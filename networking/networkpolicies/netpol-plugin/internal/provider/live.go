package provider

import (
	"context"
	"fmt"
	"strings"

	klabels "github.com/ralvares/kubectl-netpol/internal/labels"
	appsv1 "k8s.io/api/apps/v1"
	k8serrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/tools/clientcmd"
)

// LiveProvider queries a live Kubernetes cluster via client-go.
type LiveProvider struct {
	client kubernetes.Interface
}

// NewLiveProvider creates a LiveProvider from the default kubeconfig.
func NewLiveProvider(kubeconfig, kubeContext string) (*LiveProvider, error) {
	loadingRules := clientcmd.NewDefaultClientConfigLoadingRules()
	if kubeconfig != "" {
		loadingRules.ExplicitPath = kubeconfig
	}
	overrides := &clientcmd.ConfigOverrides{}
	if kubeContext != "" {
		overrides.CurrentContext = kubeContext
	}
	cfg, err := clientcmd.NewNonInteractiveDeferredLoadingClientConfig(
		loadingRules, overrides,
	).ClientConfig()
	if err != nil {
		return nil, fmt.Errorf("building kubeconfig: %w", err)
	}
	client, err := kubernetes.NewForConfig(cfg)
	if err != nil {
		return nil, fmt.Errorf("creating kubernetes client: %w", err)
	}
	return &LiveProvider{client: client}, nil
}

func (p *LiveProvider) ListNamespaces() ([]string, error) {
	list, err := p.client.CoreV1().Namespaces().List(context.Background(), metav1.ListOptions{})
	if err != nil {
		return nil, clusterErr(err)
	}
	names := make([]string, len(list.Items))
	for i, ns := range list.Items {
		names[i] = ns.Name
	}
	return names, nil
}

func (p *LiveProvider) ListWorkloads(namespace string) ([]WorkloadInfo, error) {
	var workloads []WorkloadInfo

	deps, err := p.client.AppsV1().Deployments(namespace).List(context.Background(), metav1.ListOptions{})
	if err != nil {
		return nil, clusterErr(err)
	}
	for _, d := range deps.Items {
		workloads = append(workloads, WorkloadInfo{
			Name:      d.Name,
			Namespace: d.Namespace,
			Labels:    klabels.Clean(d.Spec.Selector.MatchLabels),
		})
	}

	ss, err := p.client.AppsV1().StatefulSets(namespace).List(context.Background(), metav1.ListOptions{})
	if err != nil {
		return nil, clusterErr(err)
	}
	for _, s := range ss.Items {
		workloads = append(workloads, WorkloadInfo{
			Name:      s.Name,
			Namespace: s.Namespace,
			Labels:    klabels.Clean(s.Spec.Selector.MatchLabels),
		})
	}

	ds, err := p.client.AppsV1().DaemonSets(namespace).List(context.Background(), metav1.ListOptions{})
	if err != nil {
		return nil, clusterErr(err)
	}
	for _, d := range ds.Items {
		workloads = append(workloads, WorkloadInfo{
			Name:      d.Name,
			Namespace: d.Namespace,
			Labels:    klabels.Clean(d.Spec.Selector.MatchLabels),
		})
	}

	return workloads, nil
}

func (p *LiveProvider) GetWorkloadLabels(namespace, workload string) (map[string]string, error) {
	d, err := p.client.AppsV1().Deployments(namespace).Get(context.Background(), workload, metav1.GetOptions{})
	if err == nil {
		return klabels.Clean(d.Spec.Selector.MatchLabels), nil
	}
	if !k8serrors.IsNotFound(err) {
		return nil, clusterErr(err)
	}
	s, err2 := p.client.AppsV1().StatefulSets(namespace).Get(context.Background(), workload, metav1.GetOptions{})
	if err2 == nil {
		return klabels.Clean(s.Spec.Selector.MatchLabels), nil
	}
	if !k8serrors.IsNotFound(err2) {
		return nil, clusterErr(err2)
	}
	ds, err3 := p.client.AppsV1().DaemonSets(namespace).Get(context.Background(), workload, metav1.GetOptions{})
	if err3 == nil {
		return klabels.Clean(ds.Spec.Selector.MatchLabels), nil
	}
	if !k8serrors.IsNotFound(err3) {
		return nil, clusterErr(err3)
	}
	return nil, fmt.Errorf("workload %q not found in namespace %q", workload, namespace)
}

// clusterErr enriches an API error with a login hint when appropriate.
func clusterErr(err error) error {
	if err == nil {
		return nil
	}
	if k8serrors.IsUnauthorized(err) || k8serrors.IsForbidden(err) {
		return fmt.Errorf("%w\n\nHint: you are not authenticated — run `oc login` or `kubectl config use-context <ctx>`", err)
	}
	msg := err.Error()
	if strings.Contains(msg, "connection refused") || strings.Contains(msg, "no such host") || strings.Contains(msg, "dial") {
		return fmt.Errorf("%w\n\nHint: cannot reach the cluster — run `oc login` or check your kubeconfig", err)
	}
	return err
}

func (p *LiveProvider) GetWorkloadPorts(namespace, workload string) ([]PortInfo, error) {
	wlLabels, err := p.GetWorkloadLabels(namespace, workload)
	if err != nil {
		return nil, err
	}
	svcs, err := p.client.CoreV1().Services(namespace).List(context.Background(), metav1.ListOptions{})
	if err != nil {
		return nil, err
	}
	var ports []PortInfo
	for _, svc := range svcs.Items {
		if !selectorMatchesLabels(svc.Spec.Selector, wlLabels) {
			continue
		}
		for _, sp := range svc.Spec.Ports {
			proto := string(sp.Protocol)
			if proto == "" {
				proto = "TCP"
			}
			port := sp.TargetPort.IntVal
			if port == 0 {
				port = sp.Port
			}
			ports = append(ports, PortInfo{
				Port:     port,
				Protocol: proto,
				Source:   fmt.Sprintf("Service '%s'", svc.Name),
			})
		}
	}
	return ports, nil
}

func selectorMatchesLabels(selector, labels map[string]string) bool {
	if len(selector) == 0 {
		return false
	}
	for k, v := range selector {
		if labels[k] != v {
			return false
		}
	}
	return true
}

var _ = appsv1.Deployment{}
