# OpenShift Security Compliance Policies

This folder contains an ACM **PolicyGenerator** configuration and supporting manifests that enforce security controls across an OpenShift cluster. The policies cover both **CIS OpenShift Container Platform 4 Benchmark** and **PCI DSS v4.0** requirements, applied via ACM and targeted at managed clusters through the `open-cluster-management-policies` namespace.

The overall approach uses **three layers of control**:

- **Preventive** — `ValidatingAdmissionPolicies` (VAP) that block insecure workloads at admission time, before they are ever scheduled.
- **Detective** — ACM `ConfigurationPolicies` and the OpenShift Compliance Operator that continuously audit configuration drift and emit violations in the ACM Governance dashboard.
- **Auditing** — The Compliance Operator produces formal `ComplianceCheckResults` backed by XCCDF rules, suitable as evidence for PCI DSS and CIS audits.

---

## Prerequisites

- OpenShift 4.20+ on managed clusters
- Advanced Cluster Management (ACM) 2.x hub with the PolicyGenerator plugin
- OpenShift Compliance Operator installed in `openshift-compliance` (required only for the `netpol-compliance-scan` policy)
- `kustomize` with the ACM `policy-generator` alpha plugin enabled on the workstation deploying the policies

## Deploying

```bash
kustomize build --enable-alpha-plugins . | oc apply -f -
```

---

## Policy Overview

| Policy | Mechanism | Remediation | Severity | CIS Controls | PCI DSS Requirements |
|---|---|---|---|---|---|
| `netpol-compliance-scan` | Compliance Operator | enforce | low | 5.3.2, 5.7.x | 1.3, 1.4 |
| `netpol-compliance-acm` | ACM ConfigurationPolicy | inform | high | 5.3.2, 5.7.1 | 1.3, 1.4 |
| `sa-least-privilege` | ACM ConfigurationPolicy | enforce | high | 5.1.5, 5.1.6 | 7.2, 8.2.2, 8.6 |
| `rbac-controls` | ACM ConfigurationPolicy | inform | high | 5.1.1, 5.1.2, 5.1.4, 5.2.10 | 7.2, 7.3 |
| `ns-workload-isolation` | ACM ConfigurationPolicy | enforce | high | 5.7.1, 5.7.2, 5.7.3, 5.7.4 | 1.3.1, 2.2.1, 6.3.3 |
| `scc-sa-isolation` | ACM ConfigurationPolicy | inform | high | 5.1.5, 5.3.2, 5.7.3 | 2.2.1, 7.2.1, 8.6.1 |
| `privileged-containers` | ACM ConfigurationPolicy | inform | critical | 5.2.1, 5.2.2 | 2.2.1, 7.2.1 |
| `rbac-privileged-bindings` | ACM ConfigurationPolicy | inform | critical | 5.1.1, 5.1.2, 5.1.4, 5.2.10 | 7.2, 7.3 |
| `block-privileged-containers` | ACM + ValidatingAdmissionPolicy | enforce | critical | 5.2.1, 5.2.2 | 2.2.1, 7.2.1 |
| `block-host-escape` | ACM + ValidatingAdmissionPolicy | enforce | critical | 5.2.4, 5.2.5, 5.2.6, 5.2.12 | 2.2.1, 7.2.1 |
| `resource-requirements` | ACM ConfigurationPolicy | inform | high | 5.7.5, 5.7.6 | 6.3.3 |

---

## Demo Delivery Flow

This section describes how to deliver the full compliance story end-to-end in front of an audience. The narrative moves from setup through four progressively deeper security layers, culminating with formal audit evidence and dashboard visibility. Each phase is self-contained — you can stop after any phase if time is limited.

### Suggested audience positioning

Before starting, frame the problem for the audience:

> "Container platforms give teams speed, but they also create noise: hundreds of namespaces, thousands of pods, RBAC bindings across multiple teams. Compliance officers ask: *are we actually enforcing our standards?* Auditors ask: *can you prove it?* Today we'll show how ACM and the Compliance Operator answer both questions continuously — not at point-in-time scan time."

---

### Phase 0 — Environment Setup

Verify that the ACM hub and the Compliance Operator are healthy before starting the demo.

```bash
# Confirm ACM hub is running
oc get mch -A

# Confirm Compliance Operator pods are Ready
oc get pods -n openshift-compliance

# Deploy all policies from this repository
kustomize build --enable-alpha-plugins . | oc apply -f -

# Verify policies landed in the governance namespace
oc get policies -n open-cluster-management-policies
```

Open the ACM web console and navigate to **Governance → Policy Sets**. You should see three tiles: `network-controls`, `access-controls`, and `workload-hardening`. At this point most will be green — the demo creates violations intentionally in later phases.

---

### Phase 1 — Network Segmentation (Two Approaches)

**Narrative:** "Network policies are required by PCI DSS 1.3 and CIS 5.7. We enforce this two ways: with the Compliance Operator for formal audit trails, and with a pure ACM check for real-time detection — no additional operators required."

#### 1a. ACM-native continuous check (`netpol-compliance-acm`)

This policy uses ACM's Go-template evaluation to iterate every namespace labelled `complience-netpol-demo: true` and checks for the presence of at least one NetworkPolicy. It runs continuously on every ACM evaluation cycle — no waiting for a scan.

```bash
# Check the current compliance status of this policy
oc get policy netpol-compliance-acm -n open-cluster-management-policies

# Create a demo namespace and mark it as in-scope
oc new-project network-demo
oc label namespace network-demo complience-netpol-demo=true

# Wait one ACM evaluation cycle (~30–60 s), then check for violations
oc get policy netpol-compliance-acm -n open-cluster-management-policies \
  -o jsonpath='{.status.compliant}'
# Expected: NonCompliant — no NetworkPolicy exists yet

# Show the violation detail
oc describe policy netpol-compliance-acm -n open-cluster-management-policies | grep -A10 "Details:"
```

Point to the ACM console: the policy tile turns red and shows the `network-demo` namespace as the offending resource.

Now remediate:

```bash
# Create a default-deny ingress NetworkPolicy in the namespace
oc create networkpolicy deny-by-default -n network-demo \
  --pod-selector="" --policy-type="Ingress"

# Confirm the policy exists
oc get networkpolicy -n network-demo

# Wait one ACM evaluation cycle, then re-check
oc get policy netpol-compliance-acm -n open-cluster-management-policies \
  -o jsonpath='{.status.compliant}'
# Expected: Compliant
```

The ACM dashboard flips back to green within one evaluation cycle — no manual intervention.

#### 1b. Compliance Operator formal audit scan (`netpol-compliance-scan`)

This policy deploys a `TailoredProfile` extending `ocp4-cis` and a `ScanSettingBinding` scoped to namespaces carrying the same label. The scan produces XCCDF-backed `ComplianceCheckResults` usable as formal audit evidence.

```bash
# Confirm the TailoredProfile and ScanSettingBinding are deployed on the managed cluster
oc get tailoredprofile -n openshift-compliance
oc get scansettingbinding -n openshift-compliance

# The namespace we already labelled in 1a is automatically in scope
# Manually re-trigger the scan to show an immediate result
oc annotate compliancescans -n openshift-compliance \
  --all compliance.openshift.io/rescan=

# Watch the scan pods appear and complete
oc get pods -n openshift-compliance -w | grep "api-checks"

# After the scan completes, view formal results
oc get compliancecheckresults -n openshift-compliance | grep "network-policies"

# Inspect the full check result to show per-namespace pass/fail detail
oc describe compliancecheckresult \
  -n openshift-compliance ocp4-configure-network-policies-namespaces
```

**Key talking point:** The Compliance Operator result surfaces in the ACM Compliance dashboard under **Governance → Compliance**, providing historical evidence for auditors. The ACM check in 1a is for operations teams; the Compliance Operator result is for auditors.

#### Comparison: ACM check vs. Compliance Operator

| Dimension | `netpol-compliance-acm` | `netpol-compliance-scan` |
|---|---|---|
| Requires Compliance Operator | No | Yes |
| Detection speed | Continuous — within one ACM cycle | Scheduled scan (default daily) |
| Remediation capability | Inform only | ComplianceRemediation objects supported |
| Audit evidence format | ACM Policy status | XCCDF ComplianceCheckResult |
| Dashboard location | ACM Governance → Policies | ACM Governance → Compliance |

---

### Phase 2 — Identity and Access Controls

**Narrative:** "The most common post-breach escalation path is a compromised workload using its automatically projected service account token to traverse the Kubernetes API. We address this at two levels: stop tokens from being mounted by default, and continuously audit who has been granted excessive permissions."

#### 2a. Service account token hardening (`sa-least-privilege`)

This policy sets `automountServiceAccountToken: false` on the `default` ServiceAccount in every user namespace. Because the remediation mode is `enforce`, ACM automatically applies the change — no human action needed.

```bash
# Create a test namespace and observe the policy acting on it
oc new-project rbac-demo

# Check the default SA before the policy reconciles
oc get sa default -n rbac-demo -o jsonpath='{.automountServiceAccountToken}'
# May be empty (undefined = true by Kubernetes default)

# Wait one reconcile cycle, then check again
oc get sa default -n rbac-demo -o jsonpath='{.automountServiceAccountToken}'
# Expected: false — ACM enforced it

# Verify the policy reports Compliant
oc get policy sa-least-privilege -n open-cluster-management-policies \
  -o jsonpath='{.status.compliant}'
```

To demonstrate the practical impact, spin up a pod in the namespace and show that no token is auto-projected:

```bash
oc run token-test -n rbac-demo --image=busybox \
  --restart=Never -- ls /var/run/secrets/kubernetes.io/serviceaccount/
# The directory will not exist — no token mounted
```

#### 2b. RBAC audit — unauthenticated access and wildcard roles (`rbac-controls`)

This policy continuously checks two things: any `ClusterRoleBinding` that grants access to `system:unauthenticated` or `system:anonymous`, and any namespace-scoped `Role` that grants wildcard verbs over all resources.

```bash
# Check current compliance status
oc get policy rbac-controls -n open-cluster-management-policies

# Create a wildcard Role to trigger a violation
oc create role dangerous-role -n rbac-demo \
  --verb="*" --resource="*"

# Wait for ACM evaluation, then inspect the violation
oc describe policy rbac-controls -n open-cluster-management-policies | grep -A15 "Details:"

# Clean up
oc delete role dangerous-role -n rbac-demo
```

#### 2c. Privileged binding audit (`rbac-privileged-bindings`)

This policy audits three high-risk RBAC patterns: ServiceAccounts bound to `cluster-admin`, ServiceAccounts or users bound to ClusterRoles with wildcard permissions, and RoleBindings in user namespaces referencing a Role with wildcard verbs.

```bash
# Check for existing cluster-admin bindings involving user namespaces
oc get policy rbac-privileged-bindings -n open-cluster-management-policies

# Demonstrate a violation by binding the rbac-demo SA to cluster-admin
oc adm policy add-cluster-role-to-user cluster-admin \
  -z default -n rbac-demo

# ACM will flag this as a critical violation within one evaluation cycle
oc get policy rbac-privileged-bindings -n open-cluster-management-policies \
  -o jsonpath='{.status.compliant}'
# Expected: NonCompliant

# Show the violation in detail
oc describe policy rbac-privileged-bindings -n open-cluster-management-policies | grep -A10 "cluster-admin"

# Remediate
oc adm policy remove-cluster-role-from-user cluster-admin \
  -z default -n rbac-demo
```

---

### Phase 3 — Workload Hardening (Detective Layer)

**Narrative:** "Policies 1 and 2 controlled identity and networking. Now we look at what the workloads themselves are doing. The detective layer tells us about violations that already exist — crucial for compliance officers who need to know the current risk posture."

#### 3a. Keep workloads out of the default namespace (`ns-workload-isolation`)

```bash
# Check current status
oc get policy ns-workload-isolation -n open-cluster-management-policies

# Violate by deploying a workload to the default namespace
oc run accidental-pod --image=busybox -n default -- sleep 3600

# ACM flags this immediately
oc get policy ns-workload-isolation -n open-cluster-management-policies \
  -o jsonpath='{.status.compliant}'
# Expected: NonCompliant

# Show the violation detail
oc describe policy ns-workload-isolation -n open-cluster-management-policies | grep -A5 "default"

# Clean up
oc delete pod accidental-pod -n default
```

#### 3b. Pod Security Standards enforcement on namespaces

ACM automatically labels every new user namespace with `pod-security.kubernetes.io/audit: restricted` and `pod-security.kubernetes.io/warn: restricted`. This activates Kubernetes Pod Security Admission (PSA) in warn/audit mode, surfacing violations without hard-blocking existing workloads.

```bash
# Verify PSA labels on the namespaces we created
oc get namespace network-demo rbac-demo -o custom-columns="NAME:.metadata.name,AUDIT:.metadata.labels.pod-security\.kubernetes\.io/audit,WARN:.metadata.labels.pod-security\.kubernetes\.io/warn"

# Try deploying a workload that violates restricted policy — it will succeed but emit a warning
oc run root-pod -n rbac-demo --image=ubi8 \
  --overrides='{"spec":{"securityContext":{"runAsUser":0}}}' -- sleep 3600
# Warning: would violate PodSecurity "restricted:latest"

# Check the audit log for the PSA violation
oc adm node-logs --role=master --path=kube-apiserver/audit.log | \
  grep "pod-security" | grep "rbac-demo" | tail -5
```

#### 3c. SCC integrity check (`scc-sa-isolation`)

This policy verifies that the `restricted-v2` SCC — the hardened default introduced in OCP 4.11 — has not been weakened, and that no workload is explicitly referencing `serviceAccountName: default`.

```bash
# Verify the restricted-v2 SCC is intact
oc get policy scc-sa-isolation -n open-cluster-management-policies

# Inspect the actual SCC values on the managed cluster
oc get scc restricted-v2 -o jsonpath='{.allowPrivilegedContainer}'
oc get scc restricted-v2 -o jsonpath='{.requiredDropCapabilities}'

# Simulate a violation: explicitly set serviceAccountName: default on a deployment
oc create deployment default-sa-workload -n rbac-demo \
  --image=busybox -- sleep 3600
oc set serviceaccount deployment default-sa-workload default -n rbac-demo

# ACM detects the violation
oc get policy scc-sa-isolation -n open-cluster-management-policies \
  -o jsonpath='{.status.compliant}'

# Clean up
oc delete deployment default-sa-workload -n rbac-demo
```

#### 3d. Privileged container detection (`privileged-containers`)

```bash
# Check current status — this may already show violations if platform workloads exist
oc get policy privileged-containers -n open-cluster-management-policies

# Deploy a privileged pod to trigger the detection
oc run priv-test -n rbac-demo --image=busybox \
  --overrides='{"spec":{"containers":[{"name":"priv-test","image":"busybox","securityContext":{"privileged":true},"command":["sleep","3600"]}]}}' \
  --restart=Never

# ACM detects the privileged container within one evaluation cycle
oc get policy privileged-containers -n open-cluster-management-policies \
  -o jsonpath='{.status.compliant}'
# Expected: NonCompliant

# Show which pod triggered the violation
oc describe policy privileged-containers -n open-cluster-management-policies | grep -A5 "NonCompliant"

# Clean up
oc delete pod priv-test -n rbac-demo
```

**Key talking point here:** The detection fires *after* the pod exists. The audience can ask "why didn't you just block it?" — that is the lead-in to Phase 4.

---

### Phase 4 — Preventive Layer (ValidatingAdmissionPolicies)

**Narrative:** "Detective controls tell us what went wrong. But 'detect and alert' still means a privileged container ran on your node for some period of time. The preventive layer uses Kubernetes-native ValidatingAdmissionPolicies to reject insecure workloads at the API server — the pod never runs, not even for a second."

VAP enforcement is **opt-in per namespace via a label**. This is intentional: infra or platform-operator namespaces that legitimately need privileged access are never affected unless explicitly labelled.

#### 4a. Block privileged containers (`block-privileged-containers`)

```bash
# Verify the VAP and binding exist on the managed cluster
oc get validatingadmissionpolicy no-privileged-containers
oc get validatingadmissionpolicybinding no-privileged-containers-binding

# Activate enforcement on the demo namespace
oc label namespace rbac-demo enforce-no-privileged=true

# Confirm the label is set
oc get namespace rbac-demo --show-labels | grep enforce-no-privileged

# Attempt to run a privileged pod — it is rejected immediately at the API server
oc run blocked-priv -n rbac-demo --image=busybox \
  --overrides='{"spec":{"containers":[{"name":"blocked-priv","image":"busybox","securityContext":{"privileged":true},"command":["sleep","3600"]}]}}' \
  --restart=Never
# Expected: Error from server (Forbidden): Privileged containers are not allowed in this namespace.

# A non-privileged pod succeeds normally
oc run allowed-pod -n rbac-demo --image=busybox --restart=Never -- sleep 3600

# Show the asymmetry in the ACM dashboard:
# - privileged-containers policy: Compliant (no existing violations)
# - block-privileged-containers policy: Compliant (VAP is present)

# Show deactivation is instant — remove the label
oc label namespace rbac-demo enforce-no-privileged-
```

#### 4b. Block host namespace escape vectors (`block-host-escape`)

This policy blocks the four most dangerous host-escape vectors in a single VAP: `hostPath` volumes, `hostPID`, `hostIPC`, and `hostNetwork`.

```bash
# Verify the VAP and binding
oc get validatingadmissionpolicy no-host-escape
oc get validatingadmissionpolicybinding no-host-escape-binding

# Activate enforcement
oc label namespace rbac-demo enforce-no-host-escape=true

# Attempt hostPID — rejected at admission
oc run pid-escape -n rbac-demo --image=busybox \
  --overrides='{"spec":{"hostPID":true}}' --restart=Never -- sleep 3600
# Expected: Error from server (Forbidden): hostPID shares the host process namespace...

# Attempt hostNetwork — rejected at admission
oc run net-escape -n rbac-demo --image=busybox \
  --overrides='{"spec":{"hostNetwork":true}}' --restart=Never -- sleep 3600
# Expected: Error from server (Forbidden): hostNetwork bypasses NetworkPolicy...

# Show that both VAPs are enforcing simultaneously
oc get validatingadmissionpolicy -o custom-columns="NAME:.metadata.name,FAILURE-POLICY:.spec.failurePolicy"
```

**Key talking point:** The VAPs use CEL expressions evaluated entirely inside the Kubernetes API server. There is no webhook latency, no webhook availability concern, and no separate controller to maintain. ACM ensures these objects exist on every managed cluster.

---

### Phase 5 — ACM Dashboard — The Compliance Officer View

**Narrative:** "Now let's step back and look at this through the lens of a compliance officer or auditor. Everything we've done is visible in one place."

```bash
# Quick health check across all policies
oc get policies -n open-cluster-management-policies \
  -o custom-columns="NAME:.metadata.name,COMPLIANT:.status.compliant,REMEDIATION:.spec.remediationAction"
```

In the ACM console:

1. Navigate to **Governance → Policy Sets**. Show the three tiles — `network-controls`, `access-controls`, `workload-hardening`. Each rolls up multiple policies into a single compliance signal.

2. Click **workload-hardening** and walk through the policy list:
   - `privileged-containers` — detective, shows historical violations
   - `block-privileged-containers` — preventive, shows enforce status
   - `block-host-escape` — preventive, shows enforce status
   - `ns-workload-isolation` — enforces PSS labels and blocks default-ns workloads
   - `scc-sa-isolation` — detects SCC drift and misuse of the default SA

3. Click **access-controls**:
   - `sa-least-privilege` — enforces; show the `automountServiceAccountToken: false` already on all user namespaces
   - `rbac-controls` — inform; explain that RBAC changes need human review before auto-remediation
   - `rbac-privileged-bindings` — critical severity; any CRB granting cluster-admin to a user-namespace SA is a critical finding

4. Navigate to **Governance → Compliance** to show the Compliance Operator scan results from Phase 1b. Filter by cluster to show per-namespace pass/fail on the `ocp4-configure-network-policies-namespaces` rule.

```bash
# Show the full Compliance Operator scan history
oc get compliancescans -n openshift-compliance
oc get compliancesuites -n openshift-compliance

# Show all check results scoped to our labelled namespaces
oc get compliancecheckresults -n openshift-compliance \
  -o custom-columns="NAME:.metadata.name,STATUS:.status,SEVERITY:.metadata.labels.compliance\.openshift\.io/check-severity"

# Drill into a specific result
oc describe compliancecheckresult \
  -n openshift-compliance ocp4-configure-network-policies-namespaces
```

---

### Phase 6 — Resource Requirements Audit

**Narrative:** "A workload without CPU and memory limits can starve every other application on the same node — that is a denial-of-service risk inside the cluster. PCI DSS 6.3.3 and CIS 5.7.5/5.7.6 explicitly address this."

```bash
# Check current status
oc get policy resource-requirements -n open-cluster-management-policies

# Deploy a workload with no resource requests or limits to create a violation
oc create deployment unlimited-app -n rbac-demo --image=nginx

# Wait for ACM to detect the violation
oc get policy resource-requirements -n open-cluster-management-policies \
  -o jsonpath='{.status.compliant}'
# Expected: NonCompliant

# Show the specific containers flagged
oc describe policy resource-requirements -n open-cluster-management-policies | grep -A10 "NonCompliant"

# Remediate by patching the deployment with resource constraints
oc set resources deployment unlimited-app -n rbac-demo \
  --requests=cpu=100m,memory=128Mi \
  --limits=cpu=500m,memory=256Mi

# Verify ACM clears the violation on the next cycle
oc get policy resource-requirements -n open-cluster-management-policies \
  -o jsonpath='{.status.compliant}'

# Clean up
oc delete deployment unlimited-app -n rbac-demo
```

---

### Demo Teardown

```bash
# Remove the demo namespaces
oc delete project network-demo rbac-demo

# Remove all policies if needed
kustomize build --enable-alpha-plugins . | oc delete -f -
```

---

## Policy Reference

### `netpol-compliance-scan`

**Manifest:** `manifests/tailored-profile.yaml`, `manifests/scan-setting-binding.yaml`
**NIST:** CM-6, CM-7, SC-7 | **CIS:** 5.3.2, 5.7.x | **PCI DSS:** 1.3, 1.4
**Requires:** OpenShift Compliance Operator in `openshift-compliance`

Deploys a `TailoredProfile` extending `ocp4-cis` that enables a single rule — `ocp4-configure-network-policies-namespaces` — scoped to namespaces labelled `complience-netpol-demo: true`. A dynamic Go-template regex excludes all unlabelled namespaces so infrastructure namespaces never appear in results. Scan results land as `ComplianceCheckResult` objects visible in the ACM Compliance dashboard.

**Useful debugging commands:**

```bash
# Check scan pod status
oc get pods -n openshift-compliance | grep "api-checks"

# Inspect the dynamic namespace exclusion regex on the TailoredProfile
oc get tailoredprofile demo-targeted-profile -n openshift-compliance \
  -o jsonpath='{.spec.setValues[0].value}'

# Check the ScanSettingBinding phase
oc get compliancesuite demo-cis-binding -n openshift-compliance \
  -o jsonpath='{.status.phase}'

# List all results for the network-policies rule
oc get compliancecheckresults -n openshift-compliance | grep "network-policies"

# Re-trigger a scan manually
oc annotate compliancescans demo-cis-node \
  -n openshift-compliance compliance.openshift.io/rescan=
```

---

### `netpol-compliance-acm`

**Manifest:** `manifests/netpol-acm-enforce.yaml`
**NIST:** CM-6, CM-7, SC-7 | **CIS:** 5.3.2, 5.7.1 | **PCI DSS:** 1.3, 1.4
**Requires:** ACM only — no Compliance Operator

Uses `object-templates-raw` to iterate every namespace labelled `complience-netpol-demo: true` and require at least one NetworkPolicy. Violations appear in the ACM Policy dashboard within one evaluation cycle.

```bash
# Check compliance status
oc get policy netpol-compliance-acm -n open-cluster-management-policies \
  -o jsonpath='{.status.compliant}'

# List all non-compliant namespaces
oc describe policy netpol-compliance-acm -n open-cluster-management-policies \
  | grep -E "namespace|NonCompliant"
```

---

### `sa-least-privilege`

**Manifest:** `manifests/cis-sa-token-restriction.yaml`
**NIST:** AC-2, AC-6 | **CIS:** 5.1.5, 5.1.6 | **PCI DSS:** 7.2, 8.2.2, 8.6
**Remediation:** enforce

Sets `automountServiceAccountToken: false` on the `default` ServiceAccount in every user namespace (excludes `kube-*`, `openshift-*`, `open-cluster-management*`). Workloads that need API access must use a dedicated ServiceAccount with explicit token mounting.

```bash
# Verify the policy is Compliant
oc get policy sa-least-privilege -n open-cluster-management-policies \
  -o jsonpath='{.status.compliant}'

# Check the SA in any user namespace
oc get sa default -n <your-namespace> -o jsonpath='{.automountServiceAccountToken}'
```

---

### `rbac-controls`

**Manifest:** `manifests/cis-rbac-controls.yaml`
**NIST:** AC-3, AC-6, CM-7 | **CIS:** 5.1.1, 5.1.2, 5.1.4, 5.2.10 | **PCI DSS:** 7.2, 7.3
**Remediation:** inform

Two checks:

**`rbac-no-unauth-access`** — Iterates all `ClusterRoleBindings` and flags any that grant access to `system:unauthenticated` or `system:anonymous`. Two known OpenShift defaults are allow-listed (`system:openshift:public-info-viewer`, `system:public-info-viewer`).

**`rbac-no-wildcard-roles`** — Flags any namespace-scoped `Role` in user namespaces that grants wildcard verbs (`*`) over all API groups and resources.

```bash
# Check for violations
oc get policy rbac-controls -n open-cluster-management-policies

# List all ClusterRoleBindings involving unauthenticated/anonymous subjects
oc get clusterrolebindings -o json | \
  oc exec -it -n openshift-compliance -- jq '.items[] | select(.subjects[]?.name=="system:unauthenticated") | .metadata.name'

# List Roles with wildcard verbs across all user namespaces
oc get roles -A -o json | grep -B2 '"verbs": \["\*"\]'
```

---

### `ns-workload-isolation`

**Manifest:** `manifests/cis-namespace-workload-isolation.yaml`
**NIST:** SC-2, SC-7, CM-6 | **CIS:** 5.7.1–5.7.4 | **PCI DSS:** 1.3.1, 2.2.1, 6.3.3

Two checks:

**`no-workloads-default-ns`** *(inform)* — Flags Pods, Deployments, DaemonSets, and StatefulSets in the `default` namespace.

**`ns-pod-security-standards`** *(enforce)* — ACM ensures every user namespace carries `pod-security.kubernetes.io/audit: restricted` and `pod-security.kubernetes.io/warn: restricted` labels, activating PSA in audit/warn mode without hard-blocking existing workloads.

```bash
# Check compliance status
oc get policy ns-workload-isolation -n open-cluster-management-policies

# Verify PSA labels on a user namespace
oc get namespace <your-namespace> -o jsonpath='{.metadata.labels}' | grep pod-security

# Check for any workloads in the default namespace
oc get pods,deployments,daemonsets,statefulsets -n default
```

---

### `scc-sa-isolation`

**Manifest:** `manifests/cis-scc-sa-isolation.yaml`
**NIST:** AC-2, AC-6, CM-6, SC-39 | **CIS:** 5.1.5, 5.3.2, 5.7.3 | **PCI DSS:** 2.2.1, 7.2.1, 8.6.1
**Remediation:** inform (all three checks)

Three checks:

**`scc-restricted-v2-integrity`** — Verifies the `restricted-v2` SCC has not been weakened. Flags if `allowPrivilegedContainer`, `allowPrivilegeEscalation`, any `allowHost*` field is `true`, or if `requiredDropCapabilities` no longer includes `ALL`.

**`default-sa-no-rolebindings`** — Flags any RoleBinding in user namespaces that lists the `default` ServiceAccount as a subject.

**`workloads-dedicated-sa`** — Flags Deployments, StatefulSets, and DaemonSets that explicitly set `serviceAccountName: default`.

```bash
# Check overall status
oc get policy scc-sa-isolation -n open-cluster-management-policies

# Verify restricted-v2 SCC integrity
oc get scc restricted-v2 -o jsonpath='{.allowPrivilegedContainer}'
oc get scc restricted-v2 -o jsonpath='{.allowPrivilegeEscalation}'
oc get scc restricted-v2 -o jsonpath='{.requiredDropCapabilities}'

# Find RoleBindings referencing the default SA across user namespaces
oc get rolebindings -A -o json | grep -B5 '"name": "default"' | grep namespace
```

---

### `privileged-containers`

**Manifest:** `manifests/privileged-containers.yaml`
**NIST:** CM-6, CM-7, SC-39 | **CIS:** 5.2.1, 5.2.2 | **PCI DSS:** 2.2.1, 7.2.1
**Remediation:** inform

Flags any Pod in user namespaces where at least one regular container or init container has `securityContext.privileged: true`. Excludes `kube-*`, `openshift-*`, `open-cluster-management*`, and `stackrox`.

```bash
# Check current violation count
oc get policy privileged-containers -n open-cluster-management-policies

# Find currently running privileged pods manually
oc get pods -A -o json | \
  oc exec -it -n openshift-compliance -- jq '.items[] | select(.spec.containers[].securityContext.privileged==true) | "\(.metadata.namespace)/\(.metadata.name)"'

# Shorter alternative using jsonpath
oc get pods -A -o jsonpath='{range .items[*]}{.metadata.namespace}{" "}{.metadata.name}{" "}{.spec.containers[*].securityContext.privileged}{"\n"}{end}' | grep true
```

---

### `rbac-privileged-bindings`

**Manifest:** `manifests/rbac-privileged-bindings.yaml`
**NIST:** AC-2, AC-3, AC-6 | **CIS:** 5.1.1, 5.1.2, 5.1.4, 5.2.10 | **PCI DSS:** 7.2, 7.3
**Remediation:** inform

Three checks using `object-templates-raw`. Infra namespace subjects are excluded throughout.

**`cluster-admin-binding`** *(critical)* — Flags ClusterRoleBindings and RoleBindings that grant `cluster-admin` to a ServiceAccount in a user namespace.

**`wildcard-crole-binding`** *(high)* — Flags ClusterRoleBindings where a user-namespace ServiceAccount is bound to a ClusterRole containing wildcard verbs or resources. A curated allow-list covers known-legitimate platform operators (Hive, HyperShift, MCE, RHACS OLM).

**`wildcard-role-binding`** *(high)* — Flags RoleBindings in user namespaces where the referenced Role contains wildcard verbs or resources and the subject is a ServiceAccount or User.

```bash
# Check current status
oc get policy rbac-privileged-bindings -n open-cluster-management-policies

# List all ClusterRoleBindings involving user-namespace SAs bound to cluster-admin
oc get clusterrolebindings -o json | grep -B10 '"cluster-admin"' | grep namespace

# List high-privilege RoleBindings
oc get rolebindings -A -o custom-columns="NS:.metadata.namespace,NAME:.metadata.name,ROLE:.roleRef.name,SUBJECT:.subjects[*].name"
```

---

### `block-privileged-containers`

**Manifest:** `manifests/block-privileged-containers.yaml`
**NIST:** CM-6, CM-7, SC-39 | **CIS:** 5.2.1, 5.2.2 | **PCI DSS:** 2.2.1, 7.2.1
**Requires:** OCP 4.17+ / Kubernetes 1.30+ (VAP GA)
**Remediation:** enforce — admission-time block

ACM ensures the `ValidatingAdmissionPolicy` and `ValidatingAdmissionPolicyBinding` exist on every managed cluster. Enforcement is opt-in per namespace via `enforce-no-privileged=true` label.

```bash
# Verify on the managed cluster
oc get validatingadmissionpolicy no-privileged-containers
oc get validatingadmissionpolicybinding no-privileged-containers-binding

# Check which namespaces have enforcement active
oc get namespaces -l enforce-no-privileged=true

# Activate enforcement on a namespace
oc label namespace <your-namespace> enforce-no-privileged=true

# Deactivate enforcement
oc label namespace <your-namespace> enforce-no-privileged-
```

---

### `block-host-escape`

**Manifest:** `manifests/block-host-escape.yaml`
**NIST:** CM-6, CM-7, SC-7, SC-39 | **CIS:** 5.2.4, 5.2.5, 5.2.6, 5.2.12 | **PCI DSS:** 2.2.1, 7.2.1
**Requires:** OCP 4.17+ / Kubernetes 1.30+ (VAP GA)
**Remediation:** enforce — admission-time block

Blocks all four major host-escape vectors in a single VAP. Enforcement is opt-in per namespace via `enforce-no-host-escape=true` label.

| Vector | Risk |
|---|---|
| `hostPath` volume | Mounts node filesystem — access to `/etc/shadow`, cron jobs, container runtime socket |
| `hostPID: true` | Shares host PID namespace — ptrace, inspect, or kill node processes |
| `hostIPC: true` | Shares host IPC namespace — access shared memory of node daemons |
| `hostNetwork: true` | Shares host network stack — bypasses NetworkPolicy, sniffs node traffic |

```bash
# Verify on the managed cluster
oc get validatingadmissionpolicy no-host-escape
oc get validatingadmissionpolicybinding no-host-escape-binding

# Check which namespaces have enforcement active
oc get namespaces -l enforce-no-host-escape=true

# Activate enforcement on a namespace
oc label namespace <your-namespace> enforce-no-host-escape=true

# Deactivate enforcement
oc label namespace <your-namespace> enforce-no-host-escape-
```

---

### `resource-requirements`

**Manifest:** `manifests/resource-requirements.yaml`
**NIST:** CM-6, SC-5 | **CIS:** 5.7.5, 5.7.6 | **PCI DSS:** 6.3.3
**Remediation:** inform

Flags containers in user namespaces that are missing either CPU requests or memory limits. Unconstrained containers can starve co-located workloads and represent a denial-of-service risk at the node level.

```bash
# Check current status
oc get policy resource-requirements -n open-cluster-management-policies

# Find containers without resource limits across all user namespaces (quick check)
oc get pods -A -o jsonpath='{range .items[*]}{.metadata.namespace}{" "}{.metadata.name}{range .spec.containers[*]}{" "}{.name}{" requests:"}{.resources.requests}{" limits:"}{.resources.limits}{"\n"}{end}{end}' | grep "limits:map\[\]"
```

---

## PolicySets and Dashboard Overview

Policies are grouped into three PolicySets visible in the ACM Governance dashboard. Compliance managers see one aggregated Green/Red status per domain.

| PolicySet | Included Policies | Question answered |
|---|---|---|
| `network-controls` | `netpol-compliance-scan`, `netpol-compliance-acm` | Are all in-scope namespaces network-isolated? |
| `access-controls` | `sa-least-privilege`, `rbac-controls`, `rbac-privileged-bindings` | Are identities following least-privilege? |
| `workload-hardening` | `ns-workload-isolation`, `scc-sa-isolation`, `privileged-containers`, `block-privileged-containers`, `block-host-escape`, `resource-requirements` | Are workloads hardened against privilege escalation and node escape? |

```bash
# View all PolicySets
oc get policysets -n open-cluster-management-policies

# Show detailed status per PolicySet
oc describe policyset network-controls -n open-cluster-management-policies
oc describe policyset access-controls -n open-cluster-management-policies
oc describe policyset workload-hardening -n open-cluster-management-policies
```

---

## NIST SP 800-53 Control Mapping

| Control | Description | Policies |
|---|---|---|
| AC-2 | Account Management | `sa-least-privilege`, `scc-sa-isolation`, `rbac-privileged-bindings` |
| AC-3 | Access Enforcement | `rbac-controls`, `rbac-privileged-bindings` |
| AC-6 | Least Privilege | `sa-least-privilege`, `rbac-controls`, `scc-sa-isolation`, `rbac-privileged-bindings` |
| CM-6 | Configuration Settings | `netpol-compliance-scan`, `netpol-compliance-acm`, `ns-workload-isolation`, `scc-sa-isolation`, `privileged-containers`, `block-privileged-containers`, `block-host-escape` |
| CM-7 | Least Functionality | `netpol-compliance-scan`, `netpol-compliance-acm`, `rbac-controls`, `privileged-containers`, `block-privileged-containers`, `block-host-escape` |
| SC-2 | Application Partitioning | `ns-workload-isolation` |
| SC-5 | Denial of Service Protection | `resource-requirements` |
| SC-7 | Boundary Protection | `netpol-compliance-scan`, `netpol-compliance-acm`, `ns-workload-isolation`, `block-host-escape` |
| SC-39 | Process Isolation | `scc-sa-isolation`, `privileged-containers`, `block-privileged-containers`, `block-host-escape` |