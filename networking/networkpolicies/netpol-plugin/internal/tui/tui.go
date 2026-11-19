package tui

import (
	"fmt"
	"sort"
	"strings"

	"github.com/charmbracelet/bubbles/progress"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"github.com/ralvares/kubectl-netpol/internal/generator"
	"github.com/ralvares/kubectl-netpol/internal/provider"
)

// ──────────────────────────────────────────────────────────────────────────────
// Styles
// ──────────────────────────────────────────────────────────────────────────────

var (
	purple = lipgloss.Color("99")
	green  = lipgloss.Color("76")
	yellow = lipgloss.Color("220")
	gray   = lipgloss.Color("240")
	white  = lipgloss.Color("255")

	titleStyle = lipgloss.NewStyle().
			Bold(true).
			Foreground(white).
			Background(purple).
			Padding(0, 2)

	selectedStyle = lipgloss.NewStyle().Foreground(green).Bold(true)
	warnStyle     = lipgloss.NewStyle().Foreground(yellow)
	dimStyle      = lipgloss.NewStyle().Foreground(gray)

	checkOn  = selectedStyle.Render("[✓]")
	checkOff = dimStyle.Render("[ ]")
)

// ──────────────────────────────────────────────────────────────────────────────
// Data model
// ──────────────────────────────────────────────────────────────────────────────

// PortSelection represents a single discoverable port on a deployment.
type PortSelection struct {
	Protocol string
	Port     int32
	Selected bool
}

// DeploymentSelection represents a deployment inside a namespace, with its
// ports lazily loaded once the deployment is expanded.
type DeploymentSelection struct {
	Name     string
	Labels   map[string]string
	Expanded bool
	Ports    []PortSelection // nil = not yet loaded
}

// NamespaceSelection is one destination namespace in the tree.
type NamespaceSelection struct {
	Name        string
	Expanded    bool
	Deployments []DeploymentSelection // nil = not yet loaded
}

// SrcSelection is the resolved source (namespace + optional workload labels).
// Ports are always AllPorts on the source side.
type SrcSelection struct {
	Namespace string
	Workload  string
	Labels    map[string]string
}

// ──────────────────────────────────────────────────────────────────────────────
// Flat row model (what we actually render and navigate)
// ──────────────────────────────────────────────────────────────────────────────

type rowKind int

const (
	rowNamespace rowKind = iota
	rowDeployment
	rowPort
)

type flatRow struct {
	kind    rowKind
	nsIndex int
	depIdx  int // only for rowDeployment / rowPort
	portIdx int // only for rowPort
}

// ──────────────────────────────────────────────────────────────────────────────
// Screens
// ──────────────────────────────────────────────────────────────────────────────

type screen int

const (
	screenSrcNS   screen = iota // pick source namespace (simple list)
	screenSrcWL                 // pick source workload (simple list, skipPorts=true)
	screenDstTree               // hierarchical dst selection
	screenDone
)

// ──────────────────────────────────────────────────────────────────────────────
// Model
// ──────────────────────────────────────────────────────────────────────────────

// Model is the root Bubble Tea model.
type Model struct {
	prov    provider.Provider
	current screen
	prog    progress.Model
	termW   int
	termH   int

	// Source selection
	srcNS       string // set when source namespace is known up front
	srcWL       string // set when source workload is known up front
	srcLabels   map[string]string
	skipSrcWL   bool     // true when --src=<ns> is given, jump straight to dst
	srcNSList   []string // for screenSrcNS
	srcNSCursor int
	srcWLList   []srcWLEntry // for screenSrcWL
	srcWLCursor int

	// Destination tree
	DstNSHint string // optional: pre-expand this namespace
	dstItems  []NamespaceSelection
	flatRows  []flatRow
	cursor    int

	// Result
	SrcResult *SrcSelection
	DstResult []NamespaceSelection
	Err       error
}

type srcWLEntry struct {
	name   string
	labels map[string]string
}

// ──────────────────────────────────────────────────────────────────────────────
// Public constructors
// ──────────────────────────────────────────────────────────────────────────────

// New starts the full flow: source namespace → source workload → dst tree.
func New(prov provider.Provider) (*Model, error) {
	nsList, err := prov.ListNamespaces()
	if err != nil {
		return nil, fmt.Errorf("listing namespaces: %w", err)
	}
	prog := progress.New(progress.WithGradient("#5A56E0", "#9B78E8"), progress.WithoutPercentage())
	return &Model{
		prov:        prov,
		current:     screenSrcNS,
		prog:        prog,
		srcNSList:   nsList,
		srcNSCursor: 0,
		termW:       80,
		termH:       24,
	}, nil
}

// NewNoPort starts at source namespace selection, skipping the dst port screen
// (used when caller only needs a SrcSelection — kept for --src TUI path).
func NewNoPort(prov provider.Provider) (*Model, error) {
	m, err := New(prov)
	if err != nil {
		return nil, err
	}
	m.skipSrcWL = false
	return m, nil
}

// NewFromNamespace starts with a known source namespace, jumping to workload
// selection (skipPorts mode — only src needed).
func NewFromNamespace(prov provider.Provider, namespace string) (*Model, error) {
	m, err := New(prov)
	if err != nil {
		return nil, err
	}
	m.srcNS = namespace
	if err := m.loadSrcWorkloads(); err != nil {
		return nil, err
	}
	m.current = screenSrcWL
	return m, nil
}

// NewFromNamespaceNoPort is an alias of NewFromNamespace (both skip port screen
// since src never has ports).
func NewFromNamespaceNoPort(prov provider.Provider, namespace string) (*Model, error) {
	return NewFromNamespace(prov, namespace)
}

// NewFromWorkload is kept for backwards compatibility with cmd/root.go fast
// paths; it starts directly at the dst tree.
func NewFromWorkload(prov provider.Provider, namespace, workload string) (*Model, error) {
	m, err := New(prov)
	if err != nil {
		return nil, err
	}
	m.srcNS = namespace
	m.srcWL = workload
	lbls, err := prov.GetWorkloadLabels(namespace, workload)
	if err != nil {
		return nil, err
	}
	m.srcLabels = lbls
	m.SrcResult = &SrcSelection{Namespace: namespace, Workload: workload, Labels: lbls}
	if err := m.loadDstNamespaces(); err != nil {
		return nil, err
	}
	m.current = screenDstTree
	return m, nil
}

// NewDstOnly starts directly at the dst tree (source already resolved).
// dstNSHint is optional; when non-empty the named namespace is pre-expanded.
func NewDstOnly(prov provider.Provider, srcNS, srcWL string, srcLabels map[string]string, dstNSHint ...string) (*Model, error) {
	m, err := New(prov)
	if err != nil {
		return nil, err
	}
	m.srcNS = srcNS
	m.srcWL = srcWL
	m.srcLabels = srcLabels
	m.SrcResult = &SrcSelection{Namespace: srcNS, Workload: srcWL, Labels: srcLabels}
	if len(dstNSHint) > 0 {
		m.DstNSHint = dstNSHint[0]
	}
	if err := m.loadDstNamespaces(); err != nil {
		return nil, err
	}
	m.current = screenDstTree
	return m, nil
}

// ──────────────────────────────────────────────────────────────────────────────
// Bubble Tea interface
// ──────────────────────────────────────────────────────────────────────────────

func (m *Model) Init() tea.Cmd { return nil }

func (m *Model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.KeyMsg:
		switch m.current {
		case screenSrcNS:
			return m.updateSrcNS(msg)
		case screenSrcWL:
			return m.updateSrcWL(msg)
		case screenDstTree:
			return m.updateDstTree(msg)
		}
	case tea.WindowSizeMsg:
		m.termW = msg.Width
		m.termH = msg.Height
		m.prog.Width = msg.Width - 4
	}
	return m, nil
}

func (m *Model) View() string {
	switch m.current {
	case screenSrcNS:
		return m.viewSimpleList(
			"Select Source Namespace",
			1, 4,
			m.srcNSList, m.srcNSCursor,
			"↑/k  ↓/j  enter select  q quit",
		)
	case screenSrcWL:
		names := make([]string, len(m.srcWLList))
		for i, e := range m.srcWLList {
			names[i] = e.name
		}
		return m.viewSimpleList(
			fmt.Sprintf("Select Source Workload — %s", m.srcNS),
			2, 4,
			names, m.srcWLCursor,
			"↑/k  ↓/j  enter select  esc back  q quit",
		)
	case screenDstTree:
		return m.viewDstTree()
	case screenDone:
		return ""
	}
	return ""
}

// ──────────────────────────────────────────────────────────────────────────────
// Simple list view (src namespace + workload screens)
// ──────────────────────────────────────────────────────────────────────────────

func (m *Model) viewSimpleList(title string, step, total int, items []string, cursor int, hint string) string {
	pct := float64(step-1) / float64(total)
	var sb strings.Builder
	sb.WriteString(titleStyle.Render(title))
	sb.WriteString("\n")
	sb.WriteString(m.prog.ViewAs(pct))
	sb.WriteString("\n")
	sb.WriteString(dimStyle.Render(fmt.Sprintf("  step %d of %d", step, total)))
	sb.WriteString("\n\n")

	visibleH := m.termH - 10
	if visibleH < 3 {
		visibleH = 3
	}
	start := 0
	if cursor >= visibleH {
		start = cursor - visibleH + 1
	}
	for i := start; i < len(items) && i < start+visibleH; i++ {
		if i == cursor {
			sb.WriteString(selectedStyle.Render("▶ " + items[i]))
		} else {
			sb.WriteString("  " + items[i])
		}
		sb.WriteString("\n")
	}
	sb.WriteString("\n")
	sb.WriteString(dimStyle.Render("  " + hint))
	return sb.String()
}

// ──────────────────────────────────────────────────────────────────────────────
// Dst tree view
// ──────────────────────────────────────────────────────────────────────────────

func (m *Model) viewDstTree() string {
	pct := float64(3) / float64(4)
	var sb strings.Builder

	srcDesc := m.srcNS
	if m.srcWL != "" {
		srcDesc = m.srcNS + "/" + m.srcWL
	}
	sb.WriteString(titleStyle.Render(fmt.Sprintf("Select Destinations — src: %s", srcDesc)))
	sb.WriteString("\n")
	sb.WriteString(m.prog.ViewAs(pct))
	sb.WriteString("\n")
	sb.WriteString(dimStyle.Render("  step 3-4 of 4  (space select  →/enter expand  ← collapse  tab confirm  q quit)"))
	sb.WriteString("\n\n")

	visibleH := m.termH - 9
	if visibleH < 3 {
		visibleH = 3
	}

	// Find viewport start so cursor is always visible
	start := 0
	if m.cursor >= visibleH {
		start = m.cursor - visibleH + 1
	}

	for rowI := start; rowI < len(m.flatRows) && rowI < start+visibleH; rowI++ {
		row := m.flatRows[rowI]
		isCursor := rowI == m.cursor
		sb.WriteString(m.renderRow(row, isCursor))
		sb.WriteString("\n")
	}

	// Legend / warnings
	sb.WriteString("\n")
	warnings := m.collectWarnings()
	for _, w := range warnings {
		sb.WriteString(warnStyle.Render("  ⚠  " + w))
		sb.WriteString("\n")
	}
	if len(warnings) == 0 {
		sb.WriteString(dimStyle.Render("  tab or enter on last item to generate policies"))
	}
	return sb.String()
}

func (m *Model) renderRow(row flatRow, isCursor bool) string {
	cursor := "  "
	if isCursor {
		cursor = selectedStyle.Render("▶ ")
	}

	switch row.kind {
	case rowNamespace:
		ns := &m.dstItems[row.nsIndex]
		exp := "▶"
		if ns.Expanded {
			exp = "▼"
		}
		check := checkOff
		if m.isNSChecked(row.nsIndex) {
			check = checkOn
		}
		line := fmt.Sprintf("%s %s %s %s", cursor, check, exp, ns.Name)
		if ns.Expanded && len(ns.Deployments) > 0 && !m.anyDepSelected(row.nsIndex) {
			line += warnStyle.Render("  (no deployments → full namespace)")
		}
		return line

	case rowDeployment:
		dep := &m.dstItems[row.nsIndex].Deployments[row.depIdx]
		exp := " "
		if dep.Expanded {
			exp = "▼"
		} else if dep.Ports != nil {
			exp = "▶"
		}
		check := checkOff
		if dep.Expanded || m.isDepChecked(row.nsIndex, row.depIdx) {
			check = checkOn
		}
		hint := ""
		if dep.Expanded || m.isDepChecked(row.nsIndex, row.depIdx) {
			if dep.Ports != nil && !m.anyPortSelected(row.nsIndex, row.depIdx) {
				hint = dimStyle.Render("  (no ports → ALL)")
			}
		}
		return fmt.Sprintf("%s   %s %s deployment/%s%s", cursor, check, exp, dep.Name, hint)

	case rowPort:
		port := &m.dstItems[row.nsIndex].Deployments[row.depIdx].Ports[row.portIdx]
		check := checkOff
		if port.Selected {
			check = checkOn
		}
		return fmt.Sprintf("%s      %s  %s/%d", cursor, check, port.Protocol, port.Port)
	}
	return ""
}

func (m *Model) collectWarnings() []string {
	var ws []string
	for i, ns := range m.dstItems {
		if !m.isNSChecked(i) {
			continue
		}
		if !m.anyDepSelected(i) {
			ws = append(ws, fmt.Sprintf("%s: no deployments selected → full namespace access on ALL ports", ns.Name))
		}
	}
	return ws
}

// ──────────────────────────────────────────────────────────────────────────────
// Update handlers
// ──────────────────────────────────────────────────────────────────────────────

func (m *Model) updateSrcNS(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	n := len(m.srcNSList)
	switch msg.String() {
	case "up", "k":
		if m.srcNSCursor > 0 {
			m.srcNSCursor--
		}
	case "down", "j":
		if m.srcNSCursor < n-1 {
			m.srcNSCursor++
		}
	case "enter":
		m.srcNS = m.srcNSList[m.srcNSCursor]
		if err := m.loadSrcWorkloads(); err != nil {
			m.Err = err
			return m, tea.Quit
		}
		m.current = screenSrcWL
	case "ctrl+c", "q":
		m.Err = fmt.Errorf("cancelled by user")
		return m, tea.Quit
	}
	return m, nil
}

func (m *Model) updateSrcWL(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	n := len(m.srcWLList)
	switch msg.String() {
	case "up", "k":
		if m.srcWLCursor > 0 {
			m.srcWLCursor--
		}
	case "down", "j":
		if m.srcWLCursor < n-1 {
			m.srcWLCursor++
		}
	case "enter":
		entry := m.srcWLList[m.srcWLCursor]
		m.srcWL = entry.name
		m.srcLabels = entry.labels
		m.SrcResult = &SrcSelection{Namespace: m.srcNS, Workload: m.srcWL, Labels: m.srcLabels}
		if err := m.loadDstNamespaces(); err != nil {
			m.Err = err
			return m, tea.Quit
		}
		m.current = screenDstTree
	case "esc", "backspace":
		m.current = screenSrcNS
	case "ctrl+c", "q":
		m.Err = fmt.Errorf("cancelled by user")
		return m, tea.Quit
	}
	return m, nil
}

func (m *Model) updateDstTree(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	n := len(m.flatRows)
	switch msg.String() {
	case "up", "k":
		if m.cursor > 0 {
			m.cursor--
		}
	case "down", "j":
		if m.cursor < n-1 {
			m.cursor++
		}
	case " ":
		m.toggleCurrent()
		m.rebuildFlat()
	case "right", "l", "enter":
		m.expandCurrent()
		m.rebuildFlat()
	case "left", "h":
		m.collapseCurrent()
		m.rebuildFlat()
	case "tab", "ctrl+s":
		// Confirm — build DstResult and quit
		if !m.anyNSSelected() {
			// Nothing expanded yet: expand the namespace under the cursor so the
			// user gets a useful result instead of a silent no-op.
			if len(m.flatRows) > 0 {
				m.doExpand(m.flatRows[m.cursor])
				m.rebuildFlat()
			}
			return m, nil
		}
		m.buildDstResult()
		m.current = screenDone
		return m, tea.Quit
	case "ctrl+c", "q":
		m.Err = fmt.Errorf("cancelled by user")
		return m, tea.Quit
	}
	return m, nil
}

// ──────────────────────────────────────────────────────────────────────────────
// Tree operations
// ──────────────────────────────────────────────────────────────────────────────

func (m *Model) toggleCurrent() {
	if m.cursor >= len(m.flatRows) {
		return
	}
	row := m.flatRows[m.cursor]
	switch row.kind {
	case rowNamespace:
		// Toggle namespace selection (expand if not yet, also mark)
		ns := &m.dstItems[row.nsIndex]
		if !ns.Expanded {
			m.doExpand(row)
		}
		// No explicit checked state for NS — it's implied by expansion.

	case rowDeployment:
		dep := &m.dstItems[row.nsIndex].Deployments[row.depIdx]
		if !m.isDepChecked(row.nsIndex, row.depIdx) {
			// Select: expand and load ports
			if dep.Ports == nil {
				_ = m.loadDepPorts(row.nsIndex, row.depIdx)
			}
			dep.Expanded = true
		} else {
			// Deselect: collapse
			dep.Expanded = false
		}

	case rowPort:
		port := &m.dstItems[row.nsIndex].Deployments[row.depIdx].Ports[row.portIdx]
		port.Selected = !port.Selected
	}
}

func (m *Model) expandCurrent() {
	if m.cursor >= len(m.flatRows) {
		return
	}
	m.doExpand(m.flatRows[m.cursor])
}

func (m *Model) doExpand(row flatRow) {
	switch row.kind {
	case rowNamespace:
		ns := &m.dstItems[row.nsIndex]
		if !ns.Expanded {
			if ns.Deployments == nil {
				_ = m.loadNSDeployments(row.nsIndex)
			}
			ns.Expanded = true
		}
	case rowDeployment:
		dep := &m.dstItems[row.nsIndex].Deployments[row.depIdx]
		if !dep.Expanded {
			if dep.Ports == nil {
				_ = m.loadDepPorts(row.nsIndex, row.depIdx)
			}
			dep.Expanded = true
		}
	}
}

func (m *Model) collapseCurrent() {
	if m.cursor >= len(m.flatRows) {
		return
	}
	row := m.flatRows[m.cursor]
	switch row.kind {
	case rowNamespace:
		m.dstItems[row.nsIndex].Expanded = false
	case rowDeployment:
		m.dstItems[row.nsIndex].Deployments[row.depIdx].Expanded = false
	case rowPort:
		// collapse the parent deployment
		m.dstItems[row.nsIndex].Deployments[row.depIdx].Expanded = false
	}
}

// rebuildFlat flattens the visible tree into m.flatRows.
func (m *Model) rebuildFlat() {
	rows := make([]flatRow, 0, 32)
	for ni, ns := range m.dstItems {
		rows = append(rows, flatRow{kind: rowNamespace, nsIndex: ni})
		if !ns.Expanded {
			continue
		}
		for di, dep := range ns.Deployments {
			rows = append(rows, flatRow{kind: rowDeployment, nsIndex: ni, depIdx: di})
			if !dep.Expanded {
				continue
			}
			for pi := range dep.Ports {
				rows = append(rows, flatRow{kind: rowPort, nsIndex: ni, depIdx: di, portIdx: pi})
			}
		}
	}
	m.flatRows = rows
	if m.cursor >= len(m.flatRows) {
		m.cursor = len(m.flatRows) - 1
	}
	if m.cursor < 0 {
		m.cursor = 0
	}
}

// ──────────────────────────────────────────────────────────────────────────────
// Selection helpers
// ──────────────────────────────────────────────────────────────────────────────

func (m *Model) isNSChecked(nsIdx int) bool {
	return m.dstItems[nsIdx].Expanded
}

func (m *Model) anyNSSelected() bool {
	for i := range m.dstItems {
		if m.isNSChecked(i) {
			return true
		}
	}
	return false
}

func (m *Model) isDepChecked(nsIdx, depIdx int) bool {
	return m.dstItems[nsIdx].Deployments[depIdx].Expanded
}

func (m *Model) anyDepSelected(nsIdx int) bool {
	for i := range m.dstItems[nsIdx].Deployments {
		if m.isDepChecked(nsIdx, i) {
			return true
		}
	}
	return false
}

func (m *Model) anyPortSelected(nsIdx, depIdx int) bool {
	for _, p := range m.dstItems[nsIdx].Deployments[depIdx].Ports {
		if p.Selected {
			return true
		}
	}
	return false
}

// ──────────────────────────────────────────────────────────────────────────────
// Data loaders
// ──────────────────────────────────────────────────────────────────────────────

func (m *Model) loadSrcWorkloads() error {
	workloads, err := m.prov.ListWorkloads(m.srcNS)
	if err != nil {
		return fmt.Errorf("listing workloads in %s: %w", m.srcNS, err)
	}
	m.srcWLList = make([]srcWLEntry, len(workloads))
	for i, w := range workloads {
		m.srcWLList[i] = srcWLEntry{name: w.Name, labels: w.Labels}
	}
	m.srcWLCursor = 0
	return nil
}

func (m *Model) loadDstNamespaces() error {
	nsList, err := m.prov.ListNamespaces()
	if err != nil {
		return fmt.Errorf("listing namespaces: %w", err)
	}
	m.dstItems = make([]NamespaceSelection, 0, len(nsList))
	for _, ns := range nsList {
		if ns == m.srcNS {
			continue // exclude source namespace from destinations
		}
		m.dstItems = append(m.dstItems, NamespaceSelection{Name: ns})
	}
	// If a dst namespace hint was given, auto-expand it and pre-load its deployments.
	if m.DstNSHint != "" {
		for i := range m.dstItems {
			if m.dstItems[i].Name == m.DstNSHint {
				_ = m.loadNSDeployments(i)
				m.dstItems[i].Expanded = true
				m.cursor = i
				break
			}
		}
	}
	m.rebuildFlat()
	return nil
}

func (m *Model) loadNSDeployments(nsIdx int) error {
	ns := &m.dstItems[nsIdx]
	workloads, err := m.prov.ListWorkloads(ns.Name)
	if err != nil {
		return fmt.Errorf("listing workloads in %s: %w", ns.Name, err)
	}
	ns.Deployments = make([]DeploymentSelection, len(workloads))
	for i, w := range workloads {
		ns.Deployments[i] = DeploymentSelection{Name: w.Name, Labels: w.Labels}
	}
	return nil
}

func (m *Model) loadDepPorts(nsIdx, depIdx int) error {
	ns := &m.dstItems[nsIdx]
	dep := &ns.Deployments[depIdx]
	ports, err := m.prov.GetWorkloadPorts(ns.Name, dep.Name)
	if err != nil {
		// Non-fatal — leave Ports as empty slice so we just show "all ports"
		dep.Ports = []PortSelection{}
		return nil
	}
	dep.Ports = make([]PortSelection, len(ports))
	for i, p := range ports {
		dep.Ports[i] = PortSelection{Protocol: p.Protocol, Port: p.Port}
	}
	return nil
}

// ──────────────────────────────────────────────────────────────────────────────
// Build final result
// ──────────────────────────────────────────────────────────────────────────────

func (m *Model) buildDstResult() {
	result := make([]NamespaceSelection, 0)
	for _, ns := range m.dstItems {
		if !ns.Expanded {
			continue
		}
		selected := NamespaceSelection{Name: ns.Name}
		for _, dep := range ns.Deployments {
			if !dep.Expanded {
				continue
			}
			selectedDep := DeploymentSelection{
				Name:   dep.Name,
				Labels: dep.Labels,
				Ports:  dep.Ports,
			}
			selected.Deployments = append(selected.Deployments, selectedDep)
		}
		result = append(result, selected)
	}
	m.DstResult = result
}

// ──────────────────────────────────────────────────────────────────────────────
// Legacy Selection adapter (used by offline fast-paths in cmd/root.go)
// ──────────────────────────────────────────────────────────────────────────────

// Selection is a flattened single-target view, kept for backwards compatibility
// with the offline fast-path and hygiene commands.
type Selection struct {
	Namespace string
	Workload  string
	Labels    map[string]string
	Ports     []generator.PortSpec
	AllPorts  bool
}

// SrcSelectionToLegacy converts a SrcSelection to the legacy Selection type.
func SrcSelectionToLegacy(s *SrcSelection) *Selection {
	if s == nil {
		return nil
	}
	return &Selection{
		Namespace: s.Namespace,
		Workload:  s.Workload,
		Labels:    s.Labels,
		AllPorts:  true,
	}
}

// DstNSToLegacySelections converts a slice of NamespaceSelection (from the
// tree TUI) into one legacy Selection per deployment (or one per namespace if
// no deployments were selected).
func DstNSToLegacySelections(nss []NamespaceSelection) []*Selection {
	var out []*Selection
	for _, ns := range nss {
		if len(ns.Deployments) == 0 {
			// Whole namespace, all ports
			out = append(out, &Selection{
				Namespace: ns.Name,
				AllPorts:  true,
			})
			continue
		}
		for _, dep := range ns.Deployments {
			sel := &Selection{
				Namespace: ns.Name,
				Workload:  dep.Name,
				Labels:    dep.Labels,
			}
			var ports []generator.PortSpec
			for _, p := range dep.Ports {
				if p.Selected {
					ports = append(ports, generator.PortSpec{Port: p.Port, Protocol: p.Protocol})
				}
			}
			if len(ports) == 0 {
				sel.AllPorts = true
			} else {
				sel.Ports = ports
			}
			out = append(out, sel)
		}
	}
	return out
}

// LabelsSorted returns a stable label string for display.
func LabelsSorted(m map[string]string) string {
	if len(m) == 0 {
		return ""
	}
	keys := make([]string, 0, len(m))
	for k := range m {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	parts := make([]string, len(keys))
	for i, k := range keys {
		parts[i] = k + "=" + m[k]
	}
	return strings.Join(parts, "  ")
}
