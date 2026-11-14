# Act 5 — containment. Applied by: scripts/demo.sh respond
# The blog only needs: ingress from the router, egress to DNS and to the internet
# on 80/443 (link checker). That cuts every attacker channel:
#   * reverse shell  → attacker:4444   blocked (not 80/443)
#   * payload server → attacker:8080   blocked
#   * mining pool    → attacker:3333   blocked
#   * lateral movement → payments-api, kube API: cluster CIDRs excluded
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: { name: tdr-blog-contain, namespace: unhackable, labels: { tdr-demo: response } }
spec:
  podSelector: { matchLabels: { app: blog } }
  policyTypes: [Ingress, Egress]
  ingress:
    - from:
        - namespaceSelector: { matchLabels: { network.openshift.io/policy-group: ingress } }
      ports: [{ port: 8080, protocol: TCP }]
  egress:
    - to:
        - namespaceSelector: { matchLabels: { kubernetes.io/metadata.name: openshift-dns } }
      ports: [{ port: 5353, protocol: UDP }, { port: 5353, protocol: TCP }]
    - to:
        - ipBlock:
            cidr: 0.0.0.0/0
            except: [__CLUSTER_CIDRS__]
      ports: [{ port: 80, protocol: TCP }, { port: 443, protocol: TCP }]
---
# payments-api: nothing in this demo is allowed to call it. Deny all ingress.
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: { name: tdr-payments-deny-all, namespace: payments, labels: { tdr-demo: response } }
spec:
  podSelector: {}
  policyTypes: [Ingress]
