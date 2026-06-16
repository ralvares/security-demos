package provider

// WorkloadInfo holds resolved information about a workload.
type WorkloadInfo struct {
	Name      string
	Namespace string
	Labels    map[string]string
}

// PortInfo describes a port exposed by a workload.
type PortInfo struct {
	Port     int32
	Protocol string
	Source   string
}

// Provider abstracts Kubernetes data retrieval.
type Provider interface {
	ListNamespaces() ([]string, error)
	ListWorkloads(namespace string) ([]WorkloadInfo, error)
	GetWorkloadLabels(namespace, workload string) (map[string]string, error)
	GetWorkloadPorts(namespace, workload string) ([]PortInfo, error)
}
