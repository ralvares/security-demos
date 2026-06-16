package generator

import (
	"fmt"
	"io"
	"strings"

	networkingv1 "k8s.io/api/networking/v1"
	"sigs.k8s.io/yaml"
)

// RenderYAML serialises NetworkPolicy objects as YAML documents.
func RenderYAML(w io.Writer, policies ...*networkingv1.NetworkPolicy) error {
	for i, p := range policies {
		if i > 0 {
			fmt.Fprintln(w, "---")
		}
		data, err := yaml.Marshal(p)
		if err != nil {
			return fmt.Errorf("marshalling policy %q: %w", p.Name, err)
		}
		fmt.Fprintln(w, strings.TrimRight(string(data), "\n"))
	}
	return nil
}
