package cmd

import (
	"fmt"
	"os"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/ralvares/kubectl-netpol/internal/generator"
	"github.com/ralvares/kubectl-netpol/internal/parser"
	"github.com/ralvares/kubectl-netpol/internal/provider"
	"github.com/ralvares/kubectl-netpol/internal/tui"
	"github.com/spf13/cobra"
	networkingv1 "k8s.io/api/networking/v1"
)

var (
	kubeconfig    string
	kubeContext   string
	fileDir       string
	namespace     string
	denyAll       bool
	denyIngress   bool
	denyEgress    bool
	allowInternal bool
)

// Execute runs the root command.
func Execute() error { return rootCmd().Execute() }

func rootCmd() *cobra.Command {
	root := &cobra.Command{
		Use:   "kubectl-netpol",
		Short: "Generate Kubernetes NetworkPolicy resources",
		Long: `kubectl-netpol generates Kubernetes NetworkPolicy resources.

It operates in three modes:
  1. Command-Line Direct  - fully specified flags, no interaction.
  2. Interactive TUI      - triggered when peer info is ambiguous.
  3. Filesystem Mode      - offline analysis via -f <folder>.

Resource reference format: namespace/workload[/port/protocol]
Use "+" as the wildcard token (shell-safe, no quoting needed):

Examples:
  kubectl netpol -n myapp --deny-all --allow-internal
  kubectl netpol --src=frontend/web/+ --dst=backend/api/8080/tcp
  kubectl netpol --src=frontend/+ --dst=backend/api/8080/tcp
  kubectl netpol --src=frontend --dst=backend
  kubectl netpol -f ./manifests --src=frontend/web/+ --dst=backend/api`,
		RunE: run,
	}

	f := root.Flags()
	f.StringVar(&kubeconfig, "kubeconfig", "", "Path to kubeconfig")
	f.StringVar(&kubeContext, "context", "", "Kubernetes context to use")
	f.StringVarP(&fileDir, "file", "f", "", "Directory of manifest files (offline mode)")
	f.StringVarP(&namespace, "namespace", "n", "", "Namespace for hygiene templates")
	f.BoolVar(&denyAll, "deny-all", false, "Generate a deny-all NetworkPolicy")
	f.BoolVar(&denyIngress, "deny-ingress", false, "Generate a deny-ingress NetworkPolicy")
	f.BoolVar(&denyEgress, "deny-egress", false, "Generate a deny-egress NetworkPolicy")
	f.BoolVar(&allowInternal, "allow-internal", false, "Generate an allow-internal NetworkPolicy")
	root.Flags().String("src", "", "Source resource reference")
	root.Flags().String("dst", "", "Destination resource reference")
	return root
}

func run(cmd *cobra.Command, _ []string) error {
	srcStr, _ := cmd.Flags().GetString("src")
	dstStr, _ := cmd.Flags().GetString("dst")

	// ── Hygiene-only mode ──────────────────────────────────────────────────────
	// When hygiene flags are used without any traffic selector or manifest folder,
	// emit policies for a single explicit --namespace and return.
	if (denyAll || denyIngress || denyEgress || allowInternal) && srcStr == "" && dstStr == "" && fileDir == "" {
		if namespace == "" {
			return fmt.Errorf("--namespace is required with hygiene flags when used without --src/--dst/-f")
		}
		var policies []*networkingv1.NetworkPolicy
		if denyAll {
			policies = append(policies, generator.DenyAll(namespace))
		}
		if denyIngress {
			policies = append(policies, generator.DenyIngress(namespace))
		}
		if denyEgress {
			policies = append(policies, generator.DenyEgress(namespace))
		}
		if allowInternal {
			policies = append(policies, generator.AllowInternal(namespace))
		}
		return generator.RenderYAML(os.Stdout, policies...)
	}

	// Need a source, destination, or manifest folder to proceed.
	if srcStr == "" && dstStr == "" && fileDir == "" {
		return fmt.Errorf("provide --src and/or --dst, or -f <folder>, or use hygiene flags with -n")
	}

	// ── Offline fast-path ──────────────────────────────────────────────────────
	// When both src and dst are fully specified on the CLI we can skip the TUI
	// and any cluster access.
	if srcStr != "" && dstStr != "" {
		srcRef, srcErr := parser.Parse(srcStr)
		dstRef, dstErr := parser.Parse(dstStr)
		if srcErr == nil && dstErr == nil &&
			isSrcOfflineCapable(srcRef) && isOfflineCapable(dstRef) && fileDir == "" {
			srcSel, err := resolveSrcRefOffline(srcRef)
			if err != nil {
				return fmt.Errorf("resolving --src: %w", err)
			}
			dstSel, err := resolveRefOffline(dstRef)
			if err != nil {
				return fmt.Errorf("resolving --dst: %w", err)
			}
			return renderFromLegacy(srcSel, []*tui.Selection{dstSel})
		}
	}

	// ── Slow path: TUI / filesystem ───────────────────────────────────────────
	prov, err := buildProvider()
	if err != nil {
		return err
	}

	// When src has a known workload (or is namespace-wide "+") we only need the
	// dst tree TUI. For everything else (no --src, or bare namespace as --src)
	// run the unified TUI which covers all steps in a single session.
	if srcStr != "" {
		if ref, rerr := parser.Parse(srcStr); rerr == nil && (ref.IsNamespaceWide() || ref.Workload != "") {
			srcSel, err := resolveSrcRef(prov, srcStr)
			if err != nil {
				return fmt.Errorf("resolving --src: %w", err)
			}
			dstSels, err := resolveDstRef(prov, srcSel, dstStr)
			if err != nil {
				return fmt.Errorf("resolving --dst: %w", err)
			}
			return renderFromLegacy(tui.SrcSelectionToLegacy(srcSel), dstSels)
		}
	}

	// Src is empty or a bare namespace: unified TUI (src ns → src workload → dst tree).
	return runUnifiedTUI(prov, srcStr, dstStr)
}

// renderFromLegacy generates all ingress+egress policies from one src and
// one or more dst selections. When hygiene flags (--deny-all etc.) are set,
// those policies are prepended for every unique namespace in the result.
func renderFromLegacy(srcSel *tui.Selection, dstSels []*tui.Selection) error {
	var policies []*networkingv1.NetworkPolicy

	// Prepend hygiene policies for every unique namespace touched by the selection.
	if denyAll || denyIngress || denyEgress || allowInternal {
		seen := map[string]bool{}
		var nsList []string
		if srcSel.Namespace != "+" {
			seen[srcSel.Namespace] = true
			nsList = append(nsList, srcSel.Namespace)
		}
		for _, d := range dstSels {
			if d.Namespace != "+" && !seen[d.Namespace] {
				seen[d.Namespace] = true
				nsList = append(nsList, d.Namespace)
			}
		}
		for _, ns := range nsList {
			if denyAll {
				policies = append(policies, generator.DenyAll(ns))
			}
			if denyIngress {
				policies = append(policies, generator.DenyIngress(ns))
			}
			if denyEgress {
				policies = append(policies, generator.DenyEgress(ns))
			}
			if allowInternal {
				policies = append(policies, generator.AllowInternal(ns))
			}
		}
	}

	for _, dstSel := range dstSels {
		ports := dstSel.Ports
		if dstSel.AllPorts {
			ports = nil
		}
		opts := generator.AllowOpts{
			DstNamespace: dstSel.Namespace,
			DstLabels:    dstSel.Labels,
			SrcNamespace: srcSel.Namespace,
			SrcLabels:    srcSel.Labels,
			Ports:        ports,
		}
		if dstSel.Namespace != "+" {
			policies = append(policies, generator.AllowIngress(opts))
		}
		if srcSel.Namespace != "+" {
			policies = append(policies, generator.AllowEgress(opts))
		}
	}
	return generator.RenderYAML(os.Stdout, policies...)
}

// ── Offline helpers ────────────────────────────────────────────────────────────

func isOfflineCapable(ref parser.ResourceRef) bool {
	return ref.IsNamespaceWide() || (ref.Workload != "" && !ref.NeedsTUI())
}

func isSrcOfflineCapable(ref parser.ResourceRef) bool {
	return ref.IsNamespaceWide() || ref.Workload != ""
}

func resolveSrcRefOffline(ref parser.ResourceRef) (*tui.Selection, error) {
	var lbls map[string]string
	if !ref.IsNamespaceWide() && ref.Workload != "" {
		lbls = map[string]string{"app": ref.Workload}
	}
	return &tui.Selection{
		Namespace: ref.Namespace,
		Workload:  ref.Workload,
		Labels:    lbls,
		AllPorts:  true,
	}, nil
}

func resolveRefOffline(ref parser.ResourceRef) (*tui.Selection, error) {
	var lbls map[string]string
	if ref.Workload != "" && !ref.IsNamespaceWide() {
		lbls = map[string]string{"app": ref.Workload}
	}
	// A bare namespace (no workload), a namespace-wide "+", any ref with the
	// "+" all-ports token, or any workload whose port was not specified on the
	// CLI all resolve to AllPorts — no port parsing required.
	allPorts := ref.IsAllPorts() || ref.IsNamespaceWide() || ref.Workload == "" || ref.NeedsTUI()
	var ports []generator.PortSpec
	if !allPorts {
		p, err := parsePort(ref.Port, ref.Protocol)
		if err != nil {
			return nil, err
		}
		ports = []generator.PortSpec{p}
	}
	return &tui.Selection{
		Namespace: ref.Namespace,
		Workload:  ref.Workload,
		Labels:    lbls,
		Ports:     ports,
		AllPorts:  allPorts,
	}, nil
}

// ── Src resolution (workload or + already known) ──────────────────────────────
// Only called when srcStr contains a workload name or "+". Never runs TUI.

func resolveSrcRef(prov provider.Provider, refStr string) (*tui.SrcSelection, error) {
	ref, err := parser.Parse(refStr)
	if err != nil {
		return nil, err
	}
	if ref.IsNamespaceWide() {
		return &tui.SrcSelection{Namespace: ref.Namespace, Workload: "+"}, nil
	}
	lbls, err := prov.GetWorkloadLabels(ref.Namespace, ref.Workload)
	if err != nil {
		return nil, err
	}
	return &tui.SrcSelection{Namespace: ref.Namespace, Workload: ref.Workload, Labels: lbls}, nil
}

// runUnifiedTUI runs the complete src namespace → src workload → dst tree TUI
// in a single session. Used when --src is absent or is a bare namespace.
// srcHint may be a bare namespace to skip the namespace-selection screen.
// dstHint, when non-empty, names a namespace to pre-expand in the dst tree.
func runUnifiedTUI(prov provider.Provider, srcHint string, dstHint string) error {
	var m *tui.Model
	var err error
	if srcHint != "" {
		if ref, rerr := parser.Parse(srcHint); rerr == nil && ref.Workload == "" {
			m, err = tui.NewFromNamespace(prov, ref.Namespace)
		} else {
			m, err = tui.New(prov)
		}
	} else {
		m, err = tui.New(prov)
	}
	if err != nil {
		return err
	}
	// Store the dst namespace hint so loadDstNamespaces can pre-expand it.
	if dstHint != "" {
		if ref, rerr := parser.Parse(dstHint); rerr == nil {
			m.DstNSHint = ref.Namespace
		}
	}
	p := tea.NewProgram(m)
	final, ferr := p.Run()
	if ferr != nil {
		return fmt.Errorf("TUI error: %w", ferr)
	}
	result := final.(*tui.Model)
	if result.Err != nil {
		return result.Err
	}
	if result.SrcResult == nil {
		return fmt.Errorf("no source selected")
	}
	if len(result.DstResult) == 0 {
		return fmt.Errorf("no destinations selected")
	}
	srcLeg := tui.SrcSelectionToLegacy(result.SrcResult)
	dstSels := tui.DstNSToLegacySelections(result.DstResult)
	return renderFromLegacy(srcLeg, dstSels)
}

// ── Dst resolution via tree TUI ────────────────────────────────────────────────

func resolveDstRef(prov provider.Provider, srcSel *tui.SrcSelection, dstStr string) ([]*tui.Selection, error) {
	// If dst is fully specified on CLI, resolve offline.
	if dstStr != "" {
		ref, err := parser.Parse(dstStr)
		if err != nil {
			return nil, err
		}
		sel, err := resolveRefOffline(ref)
		if err != nil {
			return nil, err
		}
		return []*tui.Selection{sel}, nil
	}

	// No --dst flag: launch tree TUI.
	var srcNS, srcWL string
	var srcLabels map[string]string
	if srcSel != nil {
		srcNS = srcSel.Namespace
		srcWL = srcSel.Workload
		srcLabels = srcSel.Labels
	}

	m, err := tui.NewDstOnly(prov, srcNS, srcWL, srcLabels)
	if err != nil {
		return nil, err
	}

	p := tea.NewProgram(m)
	final, err := p.Run()
	if err != nil {
		return nil, fmt.Errorf("TUI error: %w", err)
	}
	result := final.(*tui.Model)
	if result.Err != nil {
		return nil, result.Err
	}
	if len(result.DstResult) == 0 {
		return nil, fmt.Errorf("no destinations selected")
	}
	return tui.DstNSToLegacySelections(result.DstResult), nil
}

// ── Infrastructure ─────────────────────────────────────────────────────────────

func buildProvider() (provider.Provider, error) {
	if fileDir != "" {
		return provider.NewFileProvider(fileDir)
	}
	return provider.NewLiveProvider(kubeconfig, kubeContext)
}

func parsePort(portStr, proto string) (generator.PortSpec, error) {
	var port int
	if _, err := fmt.Sscanf(portStr, "%d", &port); err != nil {
		return generator.PortSpec{}, fmt.Errorf("invalid port %q", portStr)
	}
	if proto == "" {
		proto = "TCP"
	}
	return generator.PortSpec{Port: int32(port), Protocol: proto}, nil
}
