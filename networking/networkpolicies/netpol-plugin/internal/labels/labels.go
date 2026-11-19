package labels

// noisyLabels are controller-managed labels stripped when building selectors.
var noisyLabels = map[string]struct{}{
	"pod-template-hash":                              {},
	"controller-revision-hash":                       {},
	"statefulset.kubernetes.io/pod-name":             {},
	"deployment.kubernetes.io/revision":              {},
	"kubectl.kubernetes.io/last-applied-configuration": {},
}

// Clean returns a copy of the label map with noisy labels removed.
func Clean(in map[string]string) map[string]string {
	out := make(map[string]string, len(in))
	for k, v := range in {
		if _, noisy := noisyLabels[k]; !noisy {
			out[k] = v
		}
	}
	return out
}
