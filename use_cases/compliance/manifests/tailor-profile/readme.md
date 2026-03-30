# OpenShift Security Compliance Policies

This folder contains an ACM **PolicyGenerator** configuration and supporting manifests that enforce security controls across an OpenShift cluster. The policies are framework-agnostic in naming and cover both **CIS OpenShift Container Platform 4 Benchmark** and **PCI DSS v4.0** requirements. They are applied via ACM and targeted at the `open-cluster-management-policies` namespace.

## Prerequisites

- OpenShift 4.20+
- OpenShift Compliance Operator installed in `openshift-compliance`
- Advanced Cluster Management (ACM) 2.x hub
- `kustomize` with the ACM `policy-generator` alpha plugin enabled

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

---

## Policy Details

### `netpol-compliance-scan`

**Manifests:** `manifests/tailored-profile.yaml`, `manifests/scan-setting-binding.yaml`
**NIST Controls:** CM-6, CM-7, SC-7 | **CIS:** 5.3.2, 5.7.x | **PCI DSS:** 1.3, 1.4
**Requires:** OpenShift Compliance Operator in `openshift-compliance`

Deploys a `TailoredProfile` extending `ocp4-cis` and a `ScanSettingBinding` that scopes compliance scanning to namespaces labelled `complience-netpol-demo: true`. The profile enables a single rule — `ocp4-configure-network-policies-namespaces` — and uses a dynamic Go template regex to exclude all unlabelled namespaces from evaluation. Results appear as `ComplianceCheckResult` objects and are surfaced in the ACM compliance dashboard.

**Demo walkthrough:**

1. Deploy the manifests — no namespaces are labelled yet, scan returns `PASS`.
2. Create a namespace and label it:
   ```bash
   oc new-project netpol-demo-app
   oc label namespace netpol-demo-app complience-netpol-demo=true
   ```
3. Re-trigger the scan — the namespace has no `NetworkPolicy`, scan returns `FAIL`.
4. Apply a default-deny `NetworkPolicy`:
   ```bash
   oc apply -f - <<EOF
   kind: NetworkPolicy
   apiVersion: networking.k8s.io/v1
   metadata:
     name: deny-by-default
     namespace: netpol-demo-app
   spec:
     podSelector: {}
     policyTypes:
     - Ingress
   EOF
   ```
5. Re-trigger the scan — returns `PASS`.

**Useful debugging commands:**
```bash
# Watch scan pods
oc get pods -n openshift-compliance -w | grep "api-checks"
# Check current regex value
oc get tailoredprofile demo-targeted-profile -n openshift-compliance \
  -o jsonpath='{.spec.setValues[0].value}'
# Check suite phase
oc get compliancesuite demo-cis-binding -n openshift-compliance
# Check results
oc get compliancecheckresults -n openshift-compliance | grep "network-policies"
```

---

### `netpol-compliance-acm`

**Manifest:** `manifests/netpol-acm-enforce.yaml`
**NIST Controls:** CM-6, CM-7, SC-7 | **CIS:** 5.3.2, 5.7.1 | **PCI DSS:** 1.3, 1.4
**Requires:** Nothing beyond ACM — no Compliance Operator needed

Same logical check as `netpol-compliance-scan` but implemented entirely as an ACM `ConfigurationPolicy` using `object-templates-raw`. At each evaluation cycle the ACM hub executes a `lookup` over all `Namespace` objects, filters to those carrying `complience-netpol-demo: true`, and generates a `musthave` check requiring at least one `NetworkPolicy` in each matching namespace.

**Comparison with the Compliance Operator variant:**

| | `netpol-compliance-scan` | `netpol-compliance-acm` |
|---|---|---|
| Mechanism | Compliance Operator + XCCDF rule | ACM ConfigurationPolicy + lookup |
| Requires Compliance Operator | Yes | No |
| Result surfaced in | ACM Compliance dashboard (ComplianceCheckResult) | ACM Policy dashboard (Policy violation) |
| Remediation | Can auto-remediate via ComplianceRemediation | `inform` only — ACM cannot create NetworkPolicies for you |
| Scan frequency | Scheduled (default: daily) | Continuous (every ACM evaluation cycle) |

**Demo walkthrough:**

Same label and NetworkPolicy steps as above. Violations appear immediately in the ACM policy view without waiting for a scan cycle:
```bash
# Check policy compliance status
oc get policy netpol-compliance-acm -n open-cluster-management-policies -o jsonpath='{.status.compliant}'
# See per-cluster details
oc get policy netpol-compliance-acm -n open-cluster-management-policies -o yaml | grep -A5 'status:'
```

---

### `sa-least-privilege`

**Manifest:** `manifests/cis-sa-token-restriction.yaml`
**NIST Controls:** AC-2, AC-6 | **CIS:** 5.1.5, 5.1.6 | **PCI DSS:** 7.2, 8.2.2, 8.6

**Remediation: enforce**

Sets `automountServiceAccountToken: false` on the `default` `ServiceAccount` in every user namespace (excludes `kube-*`, `openshift-*`, `open-cluster-management*`). This prevents Kubernetes from automatically projecting an API token into every pod, reducing the blast radius if a pod is compromised.

Workloads that genuinely need API access must use a dedicated `ServiceAccount` with explicit token mounting and the minimum required RBAC grants.

---

### `rbac-controls`

**Manifest:** `manifests/cis-rbac-controls.yaml`
**NIST Controls:** AC-3, AC-6, CM-7 | **CIS:** 5.1.1, 5.1.2, 5.1.4, 5.2.10 | **PCI DSS:** 7.2, 7.3

**Remediation: inform** — RBAC changes require deliberate human review before remediation.

Contains two `ConfigurationPolicy` checks:

**`rbac-no-unauth-access`** — Uses `object-templates-raw` with a Go template to iterate every `ClusterRoleBinding` at evaluation time and flag any that grant permissions to `system:unauthenticated` or `system:anonymous`. Two known OpenShift defaults are allow-listed and skipped:

| Allow-listed CRB | Purpose |
|---|---|
| `system:openshift:public-info-viewer` | Grants read access to public cluster version/health info |
| `system:public-info-viewer` | Upstream equivalent |

Any CRB outside this allow-list that binds unauthenticated/anonymous subjects will be reported as a violation.

**`rbac-no-wildcard-roles`** — Flags any `Role` in user namespaces that grants wildcard verbs (`*`) over all API groups and resources. Such roles are equivalent to cluster-admin within the namespace and violate least-privilege principles.

---

### `ns-workload-isolation`

**Manifest:** `manifests/cis-namespace-workload-isolation.yaml`
**NIST Controls:** SC-2, SC-7, CM-6 | **CIS:** 5.7.1, 5.7.2, 5.7.3, 5.7.4 | **PCI DSS:** 1.3.1, 2.2.1, 6.3.3

Contains two `ConfigurationPolicy` checks with different remediation actions:

**`no-workloads-default-ns`** *(inform)* — Flags any `Pod`, `Deployment`, `DaemonSet`, or `StatefulSet` found in the `default` namespace. This catches both rogue pods run directly (e.g. `oc run`) and controller-managed workloads. Workloads must be deployed into named namespaces to enable proper RBAC, network policy, and resource quota scoping.

**`ns-pod-security-standards`** *(enforce)* — Ensures every user namespace (excluding `kube-*`, `openshift-*`, `open-cluster-management*`, and `default`) carries the following labels:

```yaml
pod-security.kubernetes.io/audit: restricted
pod-security.kubernetes.io/warn: restricted
```

Setting these labels at `restricted` level activates Kubernetes Pod Security Admission in audit/warn mode, which enforces:
- `seccompProfile: RuntimeDefault` or `Localhost` (CIS 5.7.2 / PCI DSS 2.2.1)
- Non-root user and group (CIS 5.7.3)
- No privilege escalation
- All capabilities dropped

Using `audit` and `warn` (rather than `enforce`) avoids breaking existing workloads while surfacing violations in the audit log and via admission warnings.

---

### `scc-sa-isolation`

**Manifest:** `manifests/cis-scc-sa-isolation.yaml`
**NIST Controls:** AC-2, AC-6, CM-6, SC-39 | **CIS:** 5.1.5, 5.3.2, 5.7.3 | **PCI DSS:** 2.2.1, 7.2.1, 8.6.1

**Remediation: inform** — All three checks are audit-only.

Contains three `ConfigurationPolicy` checks:

**`scc-restricted-v2-integrity`** — Verifies the `restricted-v2` SCC (introduced in OCP 4.11 as the hardened default) has not been weakened. Flags if any of these fields drift from their required values:

| Field | Required value |
|---|---|
| `allowPrivilegedContainer` | `false` |
| `allowPrivilegeEscalation` | `false` |
| `allowHostDirVolumePlugin` | `false` |
| `allowHostIPC` / `allowHostNetwork` / `allowHostPID` / `allowHostPorts` | `false` |
| `requiredDropCapabilities` | `[ALL]` |
| `seccompProfiles` | `[runtime/default]` |

**`default-sa-no-rolebindings`** — Flags any `RoleBinding` in user namespaces that lists the `default` `ServiceAccount` as a subject. The default SA should have zero RBAC grants.

**`workloads-dedicated-sa`** — Flags `Deployments`, `StatefulSets`, and `DaemonSets` that explicitly set `serviceAccountName: default`.

> **Limitation:** Workloads that *omit* `serviceAccountName` also run under the default SA at runtime. ACM `ConfigurationPolicy` cannot detect absence of a field. Full enforcement requires a validating webhook — for example a [Kyverno policy](https://kyverno.io/policies/best-practices/require-non-default-serviceaccount/) that rejects pods without an explicit non-default service account.

---

### `privileged-containers`

**Manifest:** `manifests/privileged-containers.yaml`
**NIST Controls:** CM-6, CM-7, SC-39 | **CIS:** 5.2.1, 5.2.2 | **PCI DSS:** 2.2.1, 7.2.1

**Remediation: inform** — audit-only, no pods are automatically restarted.

Contains one `ConfigurationPolicy` (`no-privileged-containers`) with two checks applied to all user namespaces (excluding `kube-*`, `openshift-*`, `open-cluster-management*`, `stackrox`):

- **Regular containers** — flags any `Pod` where at least one container has `securityContext.privileged: true`.
- **Init containers** — flags any `Pod` where at least one init container has `securityContext.privileged: true`.

Privileged containers share the host kernel namespace and effectively have root on the node. They break container isolation and violate CIS 5.2.1 / PCI DSS 2.2.1 hardening standards.

---

### `rbac-privileged-bindings`

**Manifest:** `manifests/rbac-privileged-bindings.yaml`
**NIST Controls:** AC-2, AC-3, AC-6 | **CIS:** 5.1.1, 5.1.2, 5.1.4, 5.2.10 | **PCI DSS:** 7.2, 7.3

**Remediation: inform** — RBAC binding changes require deliberate human review.

Contains three `ConfigurationPolicy` checks using `object-templates-raw`. Subjects in infra namespaces (`kube-*`, `openshift-*`, `open-cluster-management*`, `stackrox`) are excluded from all checks.

**`cluster-admin-binding`** *(severity: critical)* — Flags `ClusterRoleBindings` and `RoleBindings` that grant the `cluster-admin` `ClusterRole` to a `ServiceAccount` in a user namespace. CRBs grant cluster-wide admin; RBs grant namespace-scoped admin — both are flagged.

**`wildcard-crole-binding`** *(severity: high)* — Uses a nested `lookup` to inspect the `ClusterRole` referenced by each `ClusterRoleBinding`. Flags any CRB that binds a user-namespace `ServiceAccount` to a `ClusterRole` containing rules with wildcard verbs (`*`) or resources (`*`). `cluster-admin` is excluded (covered by `cluster-admin-binding`). The following known-legitimate platform CRBs are allow-listed:

| Allow-listed CRB | Reason |
|---|---|
| `hive-controllers` | OpenShift Hive operator |
| `hypershift-operator` | HyperShift operator |
| `open-cluster-management:cluster-proxy-addon:addon-manager` | ACM cluster proxy |
| `open-cluster-management:hive-operator:hive-operator` | ACM Hive operator |
| `multicluster-engine.*` (prefix) | MCE OLM install CRBs |
| `rhacs-operator.*` (prefix) | RHACS OLM install CRBs |

**`wildcard-role-binding`** *(severity: high)* — Iterates all user namespaces (excluding `kube-*`, `openshift-*`, `open-cluster-management*`, `stackrox`, `hypershift`, `multicluster-engine`, `local-cluster`) and their `RoleBindings`. For each `RoleBinding` referencing a `Role` with a `ServiceAccount` or `User` subject, performs a nested `lookup` on the referenced `Role` and flags the binding if any rule contains wildcard verbs or resources.

> **Note on duplicates:** If a ClusterRole/Role has multiple wildcard rules, the same binding may appear more than once in the generated template. This does not affect evaluation correctness — ACM resolves to the same pass/fail for duplicate entries.

---

### `block-privileged-containers`

**Manifest:** `manifests/block-privileged-containers.yaml`
**NIST Controls:** CM-6, CM-7, SC-39 | **CIS:** 5.2.1, 5.2.2 | **PCI DSS:** 2.2.1, 7.2.1
**Requires:** OCP 4.17+ / Kubernetes 1.30+ (VAP GA)

**Remediation: enforce** — ACM keeps the `ValidatingAdmissionPolicy` and `ValidatingAdmissionPolicyBinding` present on every managed cluster. Privileged containers are blocked at admission time (before the pod is ever scheduled).

This is the **preventive** complement to the detective `privileged-containers` policy. The two work together:

| | `privileged-containers` | `block-privileged-containers` |
|---|---|---|
| Layer | Detective (post-fact) | Preventive (admission) |
| When it fires | After the Pod exists | At `kubectl`/`oc` apply time |
| Blocks creation? | No | Yes — `Deny` |
| Scope | All user namespaces | Only labelled namespaces |
| Requires Compliance Operator | No | No |

**Activation is opt-in per namespace** — no namespace is affected until labelled. This makes it safe for demo environments where some namespaces need privileged containers (e.g. `stackrox`, infra tooling).

**Demo walkthrough:**

```bash
# 1. Label the target namespace to activate enforcement
oc label namespace demo-app enforce-no-privileged=true

# 2. Try to run a privileged pod — rejected immediately at the apiserver
oc run bad-pod -n demo-app --image=busybox \
  --overrides='{"spec":{"containers":[{"name":"bad-pod","image":"busybox","securityContext":{"privileged":true}}]}}'
# Error from server: admission webhook denied: Privileged containers are not allowed in this namespace.

# 3. A normal pod works fine
oc run good-pod -n demo-app --image=busybox -- sleep 3600

# 4. Deactivate enforcement by removing the label
oc label namespace demo-app enforce-no-privileged-
```

**Verify VAP is deployed on a managed cluster:**
```bash
oc get validatingadmissionpolicy no-privileged-containers
oc get validatingadmissionpolicybinding no-privileged-containers-binding
```

---

### `block-host-escape`

**Manifest:** `manifests/block-host-escape.yaml`
**NIST Controls:** CM-6, CM-7, SC-7, SC-39 | **CIS:** 5.2.4, 5.2.5, 5.2.6, 5.2.12 | **PCI DSS:** 2.2.1, 7.2.1
**Requires:** OCP 4.17+ / Kubernetes 1.30+ (VAP GA)

**Remediation: enforce** — ACM keeps the `ValidatingAdmissionPolicy` and `ValidatingAdmissionPolicyBinding` present on every managed cluster. Host-escape vectors are blocked at admission time.

Covers the four most common container host-escape paths in a single policy:

| Vector | Risk |
|---|---|
| `hostPath` volume | Mounts node filesystem — read `/etc/shadow`, write cron jobs, access container runtime socket |
| `hostPID: true` | Shares host process namespace — inspect or kill node processes, ptrace other containers |
| `hostIPC: true` | Shares host IPC namespace — access shared memory of other workloads including node daemons |
| `hostNetwork: true` | Shares host network stack — bypasses NetworkPolicy, sniff node traffic, bind privileged ports |

**Activation is opt-in per namespace** — identical pattern to `block-privileged-containers`:

```bash
# 1. Label the target namespace to activate enforcement
oc label namespace demo-app enforce-no-host-escape=true

# 2. Try to mount a hostPath — rejected at admission
oc apply -n demo-app -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: bad-pod
spec:
  containers:
  - name: bad-pod
    image: busybox
    volumeMounts:
    - mountPath: /host
      name: host-root
  volumes:
  - name: host-root
    hostPath:
      path: /
EOF
# Error from server: hostPath volumes expose the node filesystem and are not allowed in this namespace.

# 3. Try hostPID — also rejected
oc run pid-escape -n demo-app --image=busybox \
  --overrides='{"spec":{"hostPID":true}}' -- sleep 3600
# Error from server: hostPID shares the host process namespace...

# 4. Deactivate
oc label namespace demo-app enforce-no-host-escape-
```

**Verify VAP is deployed on a managed cluster:**
```bash
oc get validatingadmissionpolicy no-host-escape
oc get validatingadmissionpolicybinding no-host-escape-binding
```

---

## Policy Sets

Policies are grouped into three **PolicySets** visible in the ACM Governance dashboard. A compliance manager sees one aggregated status per domain rather than a flat list of 10 policies.

| PolicySet | Policies | Purpose |
|---|---|---|
| `network-controls` | `netpol-compliance-scan`, `netpol-compliance-acm` | Are my namespaces network-isolated? |
| `access-controls` | `sa-least-privilege`, `rbac-controls`, `rbac-privileged-bindings` | Are identities following least-privilege? |
| `workload-hardening` | `ns-workload-isolation`, `scc-sa-isolation`, `privileged-containers`, `block-privileged-containers`, `block-host-escape` | Are workloads hardened against privilege escalation and host escape? |

### Demo flow for a compliance manager

1. Open ACM → **Governance** → **Policy Sets** — three tiles, each Green/Red at a glance.
2. Click **workload-hardening** — see `privileged-containers` flagging existing violations (detective layer) alongside `block-privileged-containers` and `block-host-escape` showing enforce status (preventive layer).
3. Label a namespace to activate a preventive policy and show real-time transition from `Compliant` → enforcing.
4. Drill into any policy for per-cluster and per-resource violation details.

---

## Control Mapping Summary

### NIST SP 800-53

| Control | Description | Policies |
|---|---|---|
| AC-2 | Account Management | `sa-least-privilege`, `scc-sa-isolation`, `rbac-privileged-bindings` |
| AC-3 | Access Enforcement | `rbac-controls`, `rbac-privileged-bindings` |
| AC-6 | Least Privilege | `sa-least-privilege`, `rbac-controls`, `scc-sa-isolation`, `rbac-privileged-bindings` |
| CM-6 | Configuration Settings | `netpol-compliance-scan`, `netpol-compliance-acm`, `ns-workload-isolation`, `scc-sa-isolation`, `privileged-containers`, `block-privileged-containers`, `block-host-escape` |
| CM-7 | Least Functionality | `netpol-compliance-scan`, `netpol-compliance-acm`, `rbac-controls`, `privileged-containers`, `block-privileged-containers`, `block-host-escape` |
| SC-2 | Application Partitioning | `ns-workload-isolation` |
| SC-7 | Boundary Protection | `netpol-compliance-scan`, `netpol-compliance-acm`, `ns-workload-isolation`, `block-host-escape` |
| SC-39 | Process Isolation | `scc-sa-isolation`, `privileged-containers`, `block-privileged-containers`, `block-host-escape` |