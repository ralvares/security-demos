package provider

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"

	klabels "github.com/ralvares/kubectl-netpol/internal/labels"
	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/runtime/serializer"
	"k8s.io/client-go/kubernetes/scheme"
)

// FileProvider reads Kubernetes manifests from the local filesystem.
type FileProvider struct {
	deployments  map[string]*appsv1.Deployment
	statefulsets map[string]*appsv1.StatefulSet
	daemonsets   map[string]*appsv1.DaemonSet
	services     map[string]*corev1.Service
	namespaces   map[string]struct{}
}

var decoder runtime.Decoder

func init() {
	decoder = serializer.NewCodecFactory(scheme.Scheme).UniversalDeserializer()
}

// NewFileProvider scans .yaml/.yml files under root and builds in-memory representation.
func NewFileProvider(root string) (*FileProvider, error) {
	p := &FileProvider{
		deployments:  make(map[string]*appsv1.Deployment),
		statefulsets: make(map[string]*appsv1.StatefulSet),
		daemonsets:   make(map[string]*appsv1.DaemonSet),
		services:     make(map[string]*corev1.Service),
		namespaces:   make(map[string]struct{}),
	}
	err := filepath.WalkDir(root, func(path string, d os.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if d.IsDir() {
			return nil
		}
		ext := strings.ToLower(filepath.Ext(path))
		if ext != ".yaml" && ext != ".yml" {
			return nil
		}
		return p.loadFile(path)
	})
	if err != nil {
		return nil, fmt.Errorf("scanning directory %q: %w", root, err)
	}
	return p, nil
}

func (p *FileProvider) loadFile(path string) error {
	data, err := os.ReadFile(path)
	if err != nil {
		return err
	}
	docs := strings.Split(string(data), "\n---")
	for _, doc := range docs {
		doc = strings.TrimSpace(doc)
		if doc == "" {
			continue
		}
		obj, gvk, err := decoder.Decode([]byte(doc), nil, nil)
		if err != nil {
			continue
		}
		switch gvk.Kind {
		case "Deployment":
			d := obj.(*appsv1.Deployment)
			p.deployments[nskey(d.Namespace, d.Name)] = d
			p.namespaces[d.Namespace] = struct{}{}
		case "StatefulSet":
			s := obj.(*appsv1.StatefulSet)
			p.statefulsets[nskey(s.Namespace, s.Name)] = s
			p.namespaces[s.Namespace] = struct{}{}
		case "DaemonSet":
			ds := obj.(*appsv1.DaemonSet)
			p.daemonsets[nskey(ds.Namespace, ds.Name)] = ds
			p.namespaces[ds.Namespace] = struct{}{}
		case "Service":
			svc := obj.(*corev1.Service)
			p.services[nskey(svc.Namespace, svc.Name)] = svc
			p.namespaces[svc.Namespace] = struct{}{}
		}
	}
	return nil
}

func (p *FileProvider) ListNamespaces() ([]string, error) {
	out := make([]string, 0, len(p.namespaces))
	for ns := range p.namespaces {
		out = append(out, ns)
	}
	return out, nil
}

func (p *FileProvider) ListWorkloads(namespace string) ([]WorkloadInfo, error) {
	var out []WorkloadInfo
	for _, d := range p.deployments {
		if d.Namespace == namespace {
			out = append(out, WorkloadInfo{Name: d.Name, Namespace: d.Namespace, Labels: klabels.Clean(d.Spec.Selector.MatchLabels)})
		}
	}
	for _, s := range p.statefulsets {
		if s.Namespace == namespace {
			out = append(out, WorkloadInfo{Name: s.Name, Namespace: s.Namespace, Labels: klabels.Clean(s.Spec.Selector.MatchLabels)})
		}
	}
	for _, ds := range p.daemonsets {
		if ds.Namespace == namespace {
			out = append(out, WorkloadInfo{Name: ds.Name, Namespace: ds.Namespace, Labels: klabels.Clean(ds.Spec.Selector.MatchLabels)})
		}
	}
	return out, nil
}

func (p *FileProvider) GetWorkloadLabels(namespace, workload string) (map[string]string, error) {
	if d, ok := p.deployments[nskey(namespace, workload)]; ok {
		return klabels.Clean(d.Spec.Selector.MatchLabels), nil
	}
	if s, ok := p.statefulsets[nskey(namespace, workload)]; ok {
		return klabels.Clean(s.Spec.Selector.MatchLabels), nil
	}
	if ds, ok := p.daemonsets[nskey(namespace, workload)]; ok {
		return klabels.Clean(ds.Spec.Selector.MatchLabels), nil
	}
	return nil, fmt.Errorf("workload %q not found in namespace %q", workload, namespace)
}

func (p *FileProvider) GetWorkloadPorts(namespace, workload string) ([]PortInfo, error) {
	wlLabels, err := p.GetWorkloadLabels(namespace, workload)
	if err != nil {
		return nil, err
	}
	var ports []PortInfo
	for _, svc := range p.services {
		if svc.Namespace != namespace {
			continue
		}
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
			ports = append(ports, PortInfo{Port: port, Protocol: proto, Source: fmt.Sprintf("Service '%s'", svc.Name)})
		}
	}
	return ports, nil
}

func nskey(namespace, name string) string {
	return namespace + "/" + name
}
