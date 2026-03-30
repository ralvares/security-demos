## Executive Summary: The Compliance Narrative

Maintaining compliance in a dynamic container environment requires moving beyond point-in-time audits. Our strategy utilizes three layers of defense:
1.  **Detective Controls**: Continuous monitoring for configuration drift (e.g., RBAC, resource limits).
2.  **Preventive Controls**: Using **ValidatingAdmissionPolicies (VAP)** to reject insecure workloads before they are scheduled.
3.  **Auditing Controls**: Deep-scan reporting via the **OpenShift Compliance Operator** for formal regulatory evidence.

---

## Phase 1: Foundational Resource Isolation

**Use Case**: Preventing resource exhaustion and ensuring workload accountability. Without enforced resource requests and namespace isolation, one sub-optimal deployment can cause node-level instability (OOM kills) affecting neighboring applications.

### Step 1: Enforce Namespace Hygiene
We restrict workloads from the `default` namespace and mandate **Pod Security Standards (PSS)** for all user namespaces.

```bash
# Verify the policy is enforcing 'restricted' labels on all user namespaces
oc get policy ns-workload-isolation -n open-cluster-management-policies
```

* **Reasoning**: **PCI DSS 1.3.1** and **2.2.1** require system hardening and traffic restriction. By forcing workloads into named namespaces with `restricted` PSS labels, we ensure non-root execution and seccomp profile defaults.

### Step 2: Dynamic Resource Monitoring
We use an ACM lookup to identify any container running without a CPU request or Memory limit.

```bash
# Check for containers violating resource requirement standards
oc get policy resource-requirements -n open-cluster-management-policies
```

* **Reasoning**: **CIS 5.7.5 and 5.7.6** require resource limits to prevent Denial of Service (DoS) attacks at the node level.

---

## Phase 2: Identity and Access Management (RBAC)

**Use Case**: Reducing the blast radius of a compromised container. If a workload token is stolen, the attacker's movement must be limited to the minimum necessary permissions.

### Step 3: Service Account Hardening
We disable the automatic mounting of API tokens for the `default` ServiceAccount in user namespaces.

```bash
# Verify automountServiceAccountToken is set to false
oc get sa default -n <user-namespace> -o jsonpath='{.automountServiceAccountToken}'
```

* **Reasoning**: **CIS 5.1.5 and 5.1.6** recommend restricting default token projection to prevent unauthorized API access.

### Step 4: Auditing Privileged Bindings
We continuously scan for ServiceAccounts or Users bound to `cluster-admin` or roles containing wildcard (`*`) permissions.

```bash
# Audit high-risk RBAC bindings
oc get policy rbac-privileged-bindings -n open-cluster-management-policies
```

* **Reasoning**: **PCI DSS 7.2 and 7.3** mandate least-privilege access. Wildcard permissions are high-risk vectors that must be flagged for manual security review.

---

## Phase 3: Preventive Defense-in-Depth

**Use Case**: Stopping host-escape attempts at the admission gate. While detective policies tell you a violation occurred, preventive policies stop the violation from ever entering the cluster.

### Step 5: Blocking Host Escape Vectors
We use **ValidatingAdmissionPolicies** to block `hostPath`, `hostPID`, `hostIPC`, and `hostNetwork` configurations.

```bash
# 1. Activate enforcement via namespace label
oc label namespace demo-app enforce-no-host-escape=true

# 2. Attempt to deploy a pod with hostPath (Expected: REJECTED)
oc apply -n demo-app -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: escape-attempt
spec:
  containers:
  - name: shell
    image: busybox
  volumes:
  - name: host-root
    hostPath:
      path: /
EOF
```

* **Reasoning**: **CIS 5.2.4 and 5.2.6** specifically target host-escape vectors. Blocking these at admission time prevents attackers from accessing the underlying node filesystem or process namespace.

---

## Phase 4: Native ACM Network Monitoring

**Use Case**: Ensuring network segmentation without the overhead of external operators. This provides an immediate "red/green" status for compliance officers regarding network isolation.

### Step 6: ACM-Native NetworkPolicy Check
We use `object-templates-raw` to dynamically iterate through namespaces and verify the existence of at least one `NetworkPolicy`.

```bash
# Check the compliance status of network controls
oc get policy netpol-compliance-acm -n open-cluster-management-policies
```

* **Reasoning**: **PCI DSS 1.3 and 1.4** require network access controls between trusted and untrusted networks. This ACM-native check provides continuous evaluation every cycle without waiting for a scheduled scan.

---

## Phase 5: Formal Auditing with Tailored Profiles

**Use Case**: Formal regulatory reporting. While ACM provides real-time status, the **Compliance Operator** provides the deep-inspection and historical evidence required for PCI DSS v4.0 audits.

### Step 7: The Tailored Profile Demo
We deploy a `TailoredProfile` that extends the standard CIS benchmark but is scoped specifically to our production-labeled namespaces.

```bash
# 1. Label the namespace for formal auditing
oc label namespace production-app complience-netpol-demo=true

# 2. Monitor the Compliance Operator scan pod
oc get pods -n openshift-compliance -w | grep "api-checks"

# 3. View the formal compliance results
oc get compliancecheckresults -n openshift-compliance | grep "network-policies"
```

* **Detailed Explanation**: 
    * **The Mechanism**: This policy uses a Go template to dynamically generate a regex of all namespaces *not* carrying our compliance label. 
    * **The Use Case**: It excludes infrastructure namespaces (like `openshift-*`) from the report to focus exclusively on application-layer compliance. 
    * **Reasoning**: This satisfies **CIS 5.3.2** and **PCI DSS 1.3** by providing a formal, operator-backed validation that network isolation is active where required.

---