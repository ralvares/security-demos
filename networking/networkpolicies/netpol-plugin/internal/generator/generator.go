package generator

import (
	corev1 "k8s.io/api/core/v1"
	networkingv1 "k8s.io/api/networking/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/util/intstr"
)

// DenyAll generates a NetworkPolicy that drops all ingress and egress.
func DenyAll(namespace string) *networkingv1.NetworkPolicy {
	return &networkingv1.NetworkPolicy{
		TypeMeta:   typeMeta(),
		ObjectMeta: metav1.ObjectMeta{Name: "deny-all", Namespace: namespace},
		Spec: networkingv1.NetworkPolicySpec{
			PodSelector: metav1.LabelSelector{},
			PolicyTypes: []networkingv1.PolicyType{
				networkingv1.PolicyTypeIngress,
				networkingv1.PolicyTypeEgress,
			},
		},
	}
}

// DenyIngress generates a NetworkPolicy that blocks all ingress.
func DenyIngress(namespace string) *networkingv1.NetworkPolicy {
	return &networkingv1.NetworkPolicy{
		TypeMeta:   typeMeta(),
		ObjectMeta: metav1.ObjectMeta{Name: "deny-ingress", Namespace: namespace},
		Spec: networkingv1.NetworkPolicySpec{
			PodSelector: metav1.LabelSelector{},
			PolicyTypes: []networkingv1.PolicyType{networkingv1.PolicyTypeIngress},
		},
	}
}

// DenyEgress generates a NetworkPolicy that blocks all egress.
func DenyEgress(namespace string) *networkingv1.NetworkPolicy {
	return &networkingv1.NetworkPolicy{
		TypeMeta:   typeMeta(),
		ObjectMeta: metav1.ObjectMeta{Name: "deny-egress", Namespace: namespace},
		Spec: networkingv1.NetworkPolicySpec{
			PodSelector: metav1.LabelSelector{},
			PolicyTypes: []networkingv1.PolicyType{networkingv1.PolicyTypeEgress},
		},
	}
}

// AllowInternal generates a NetworkPolicy allowing all pods in a namespace
// to communicate with each other.
func AllowInternal(namespace string) *networkingv1.NetworkPolicy {
	return &networkingv1.NetworkPolicy{
		TypeMeta:   typeMeta(),
		ObjectMeta: metav1.ObjectMeta{Name: "allow-internal", Namespace: namespace},
		Spec: networkingv1.NetworkPolicySpec{
			PodSelector: metav1.LabelSelector{},
			PolicyTypes: []networkingv1.PolicyType{networkingv1.PolicyTypeIngress},
			Ingress: []networkingv1.NetworkPolicyIngressRule{
				{From: []networkingv1.NetworkPolicyPeer{{PodSelector: &metav1.LabelSelector{}}}},
			},
		},
	}
}

// AllowOpts contains parameters for an allow policy between two workloads.
type AllowOpts struct {
	DstNamespace string
	DstLabels    map[string]string
	SrcNamespace string
	SrcLabels    map[string]string
	Ports        []PortSpec
}

// PortSpec describes a single port + protocol.
type PortSpec struct {
	Port     int32
	Protocol string
}

// AllowIngress generates a policy that allows ingress to dst from src.
func AllowIngress(opts AllowOpts) *networkingv1.NetworkPolicy {
	peer := buildPeer(opts.SrcNamespace, opts.DstNamespace, opts.SrcLabels)
	rule := networkingv1.NetworkPolicyIngressRule{
		From:  []networkingv1.NetworkPolicyPeer{peer},
		Ports: buildPorts(opts.Ports),
	}
	return &networkingv1.NetworkPolicy{
		TypeMeta: typeMeta(),
		ObjectMeta: metav1.ObjectMeta{
			Name:      policyName("allow-ingress", opts.SrcNamespace, opts.DstNamespace),
			Namespace: opts.DstNamespace,
		},
		Spec: networkingv1.NetworkPolicySpec{
			PodSelector: metav1.LabelSelector{MatchLabels: opts.DstLabels},
			PolicyTypes: []networkingv1.PolicyType{networkingv1.PolicyTypeIngress},
			Ingress:     []networkingv1.NetworkPolicyIngressRule{rule},
		},
	}
}

// AllowEgress generates a policy that allows egress from src to dst.
func AllowEgress(opts AllowOpts) *networkingv1.NetworkPolicy {
	peer := buildPeer(opts.DstNamespace, opts.SrcNamespace, opts.DstLabels)
	rule := networkingv1.NetworkPolicyEgressRule{
		To:    []networkingv1.NetworkPolicyPeer{peer},
		Ports: buildPorts(opts.Ports),
	}
	return &networkingv1.NetworkPolicy{
		TypeMeta: typeMeta(),
		ObjectMeta: metav1.ObjectMeta{
			Name:      policyName("allow-egress", opts.SrcNamespace, opts.DstNamespace),
			Namespace: opts.SrcNamespace,
		},
		Spec: networkingv1.NetworkPolicySpec{
			PodSelector: metav1.LabelSelector{MatchLabels: opts.SrcLabels},
			PolicyTypes: []networkingv1.PolicyType{networkingv1.PolicyTypeEgress},
			Egress:      []networkingv1.NetworkPolicyEgressRule{rule},
		},
	}
}

func typeMeta() metav1.TypeMeta {
	return metav1.TypeMeta{APIVersion: "networking.k8s.io/v1", Kind: "NetworkPolicy"}
}

func buildPeer(peerNS, policyNS string, podLabels map[string]string) networkingv1.NetworkPolicyPeer {
	peer := networkingv1.NetworkPolicyPeer{}
	if podLabels != nil {
		peer.PodSelector = &metav1.LabelSelector{MatchLabels: podLabels}
	} else {
		peer.PodSelector = &metav1.LabelSelector{}
	}
	switch {
	case peerNS == "+":
		// All namespaces: empty namespaceSelector matches everything.
		peer.NamespaceSelector = &metav1.LabelSelector{}
	case peerNS != policyNS:
		peer.NamespaceSelector = &metav1.LabelSelector{
			MatchLabels: map[string]string{"kubernetes.io/metadata.name": peerNS},
		}
	}
	return peer
}

func buildPorts(specs []PortSpec) []networkingv1.NetworkPolicyPort {
	if len(specs) == 0 {
		return nil
	}
	out := make([]networkingv1.NetworkPolicyPort, len(specs))
	for i, s := range specs {
		proto := corev1.Protocol(s.Protocol)
		if proto == "" {
			proto = corev1.ProtocolTCP
		}
		port := intstr.FromInt(int(s.Port))
		out[i] = networkingv1.NetworkPolicyPort{Protocol: (*corev1.Protocol)(&proto), Port: &port}
	}
	return out
}

func policyName(prefix, srcNS, dstNS string) string {
	if srcNS == "+" {
		return prefix + "-from-any"
	}
	if dstNS == "+" {
		return prefix + "-to-any"
	}
	if srcNS == dstNS {
		return prefix
	}
	return prefix + "-from-" + srcNS
}
