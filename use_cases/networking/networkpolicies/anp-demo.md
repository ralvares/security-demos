## Network Policy Troubleshooting & DNS Resolution

### 1. Initial State (Open Communication)

Before applying any restrictions, traffic flows freely between namespaces.

```bash
oc exec -n team-a default -- curl -s http://default.team-b.svc.cluster.local:8080

```

### 2. Apply Baseline Policy

Applying the `BaselineAdminNetworkPolicy` (BANP) to set a "Deny All" safety net.

```bash
oc apply -f netpols/baselinenp-deny-all.yaml 

```

> **Result:** The same `curl` command now **fails** because the baseline policy drops all traffic by default.

---

### 3. Attempting to Restore Access via Standard NetworkPolicies

We try to allow specific traffic between `team-a` and `team-b` using standard Kubernetes `NetworkPolicy` resources.

```bash
# Apply Egress in source namespace
oc apply -f netpols/team-a-egress-to-team-b.yaml

# Apply Ingress in destination namespace
oc apply -f netpols/team-b-ingress-from-team-a.yaml 

# Test connectivity again
oc exec -n team-a default -- curl -s http://default.team-b.svc.cluster.local:8080

```

**Outcome:** It **STILL FAILS**.

### 4. Root Cause Analysis: DNS vs. IP

Checking the pod IP in `team-b` to determine if the issue is the network path or name resolution.

```bash
oc get pod -n team-b default -o wide
# IP: 10.129.1.229

```

Testing via **Pod IP** instead of **DNS Name**:

```bash
oc exec -n team-a default -- curl -s http://10.129.1.229:8080

```

**Outcome:** Success!

```html
<!DOCTYPE html>
<html><body><h1>ok</h1></body></html>

```

**Conclusion:** The network path is open, but **DNS is blocked**. The baseline "Deny All" is preventing pods from talking to the `kube-dns` service in the `openshift-dns` or `kube-system` namespaces.

---

### 5. Resolution: Admin Network Policy for DNS

Instead of manually adding DNS rules to every single namespace, we use an **Admin Network Policy (ANP)** to globally allow DNS traffic for the entire cluster.

```bash
oc apply -f anp-deny-all-allow-dns.yaml 
# adminnetworkpolicy.policy.networking.k8s.io/deny-all-allow-dns created

```

### 6. External Bypass Test

Testing if external traffic (Internet) is still blocked by the baseline policy.

```bash
oc exec -n team-a default -- curl -s www.google.com

```

**Outcome:** Blocked (as expected).

### 7. Overriding the Baseline

Because `BaselineAdminNetworkPolicy` is the lowest priority, a developer can "bypass" it by applying a broad `NetworkPolicy` to their own namespace.

```bash
oc apply -f allow-all.yaml 

```

** Outcome:** Bingo! External access to Google is now working because the `NetworkPolicy` took precedence over the `BaselineAdminNetworkPolicy`.
