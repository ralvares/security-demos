package parser

import (
	"fmt"
	"strings"
)

// ResourceRef represents a parsed traffic peer reference.
// Format: namespace/workload[/port/protocol]
// Use "+" as the wildcard token (shell-safe alternative to "*"):
//
//	ns/+         namespace-wide selector
//	ns/app/+     all ports
type ResourceRef struct {
	Namespace string
	Workload  string
	Port      string // "80", "+" (all ports), or "" (empty triggers TUI)
	Protocol  string // "TCP", "UDP", "SCTP"
}

// NeedsTUI returns true when the port is unspecified and the workload is not
// a wildcard. A namespace-wide ref (workload="+") always means all ports.
func (r ResourceRef) NeedsTUI() bool { return r.Port == "" && !r.IsNamespaceWide() }

// IsNamespaceWide returns true when the workload is "+".
func (r ResourceRef) IsNamespaceWide() bool { return r.Workload == "+" }

// IsAllPorts returns true when port is "+".
func (r ResourceRef) IsAllPorts() bool { return r.Port == "+" }

// Parse parses a resource reference string into a ResourceRef.
// A bare "+" means all-namespaces / all-pods / all-ports.
func Parse(s string) (ResourceRef, error) {
	if s == "" {
		return ResourceRef{}, fmt.Errorf("resource reference must not be empty")
	}
	// Bare "+" = everything wildcard.
	if s == "+" {
		return ResourceRef{Namespace: "+", Workload: "+"}, nil
	}
	parts := strings.SplitN(s, "/", 4)
	ref := ResourceRef{}
	switch len(parts) {
	case 1:
		ref.Namespace = parts[0]
	case 2:
		ref.Namespace = parts[0]
		ref.Workload = parts[1]
	case 3:
		ref.Namespace = parts[0]
		ref.Workload = parts[1]
		ref.Port = parts[2]
	case 4:
		ref.Namespace = parts[0]
		ref.Workload = parts[1]
		ref.Port = parts[2]
		ref.Protocol = strings.ToUpper(parts[3])
	default:
		return ResourceRef{}, fmt.Errorf("invalid resource reference %q: too many segments", s)
	}
	if err := validate(ref); err != nil {
		return ResourceRef{}, fmt.Errorf("invalid resource reference %q: %w", s, err)
	}
	return ref, nil
}

func validate(r ResourceRef) error {
	if r.Namespace == "" {
		return fmt.Errorf("namespace must not be empty")
	}
	if r.Protocol != "" && r.Protocol != "TCP" && r.Protocol != "UDP" && r.Protocol != "SCTP" {
		return fmt.Errorf("protocol must be TCP, UDP, or SCTP; got %q", r.Protocol)
	}
	return nil
}
