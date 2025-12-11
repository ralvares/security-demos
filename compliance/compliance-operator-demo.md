# OpenShift Compliance Operator: CustomRule Demos

This guide explains how to run and interpret the custom compliance checks available in the `security-demos` repository. These demos use the **Compliance Operator** and **CEL (Common Expression Language)** to enforce organization-specific policies without writing Go code.

## 1\. Setup

### Prerequisites

  * OpenShift Cluster with **Compliance Operator** installed.
  * **Cluster Admin** access.
  * `oc` CLI tool.
  * Target Namespace: `openshift-compliance`.

### Get the Manifests

Clone the repository containing the pre-built Rules, Profiles, and Bindings:

```bash
git clone https://github.com/ralvares/security-demos.git
cd security-demos/compliance/manifests
```

-----

## 2. Demo Flow: Apply Rules, Label Namespaces, and Observe Failures

This demo shows how CustomRules behave before and after labeling namespaces for enforcement. We'll apply the rules first (no enforcement yet), check that they pass, then label namespaces to trigger failures, and rerun the scans.

### Step 1: Apply the Rules (No Enforcement Yet)

Apply the use case manifests. Since no namespaces are labeled `custom.security/enforce=true`, the rules will pass (no resources to check).

```bash
# Apply all use cases (RBAC, Network Policy, Pod Security, Image Supply Chain)
oc apply -k rbac
oc apply -k network-policy
oc apply -k pod-security
oc apply -k image-supply-chain
```

### Step 2: Check Initial Results (Should Pass)

The Compliance Operator will run scans. Since no namespaces are enforced, all rules should pass.

```bash
# Wait for scans to complete
oc get compliancesuite -n openshift-compliance

# Check results
oc get compliancecheckresults -n openshift-compliance
```

**Expected Output:** All results should show `PASS` (e.g., `rbac-checks-cluster-admin-allow-list PASS high`).

```text
NAME                                                              STATUS   SEVERITY
image-supply-chain-checks-allowed-registries-pod-images           PASS     medium
image-supply-chain-checks-disallow-shadow-databases               PASS     high
networkpolicy-security-checks-netpol-disallow-allow-all-labeled   PASS     high
networkpolicy-security-checks-netpol-require-deny-all-labeled     PASS     high
rbac-checks-cluster-admin-allow-list                              PASS     high
sensitive-pod-security-checks-detect-privileged-pods              PASS     high
sensitive-pod-security-checks-detect-sensitive-hostpath-mounts    PASS     high
sensitive-pod-security-checks-detect-token-automount              PASS     medium
```

### Step 3: Label Namespaces for Enforcement

Label the demo namespaces (`payments` and `frontend`) to enable enforcement. This activates the rules for resources in those namespaces.

```bash
oc label namespace payments custom.security/enforce=true --overwrite
oc label namespace frontend custom.security/enforce=true --overwrite
```

Note: The pod automount rule supports a pod- or deployment-level allow label `custom.security/automount=true`.
You can either label individual pods or the owning Deployment to exempt them from the automount check.

```bash
# Label the Deployments in the frontend namespace so their pods are exempt
oc label deployment webapp -n frontend custom.security/automount=true --overwrite
oc label deployment blog -n frontend custom.security/automount=true --overwrite

# Or label a specific pod directly (if needed)
# oc label pod <pod-name> -n frontend custom.security/automount=true --overwrite
```

### Step 4: Force a Rerun (Delete ComplianceScans)

Delete the existing scans to force the Compliance Operator to re-evaluate with the new labels.

```bash
# Delete scans for each use case (adjust names if different in your cluster)
oc delete compliancescan rbac-checks -n openshift-compliance
oc delete compliancescan networkpolicy-security-checks -n openshift-compliance
oc delete compliancescan sensitive-pod-security-checks -n openshift-compliance
oc delete compliancescan image-supply-chain-checks -n openshift-compliance
```

### Step 5: Check Results After Labeling (Should Fail)

The scans will rerun. Now that namespaces are labeled, the rules will evaluate resources and fail due to violations.

```bash
# Wait for reruns to complete
oc get compliancesuite -n openshift-compliance

# Check results
oc get compliancecheckresults -n openshift-compliance
```

**Expected Output:** Several results should now show `FAIL` (e.g., `sensitive-pod-security-checks-detect-privileged-pods FAIL high`).

### Understanding the Failures

With namespaces labeled, the rules detect real issues in the demo cluster:

- **Pod Security Failures:** The `visa-processor` ServiceAccount in `payments` namespace has pods with:
  - Privileged containers (`detect-privileged-pods` fails).
  - Service account token automount enabled (`detect-token-automount` fails).
  - Additionally, `visa-processor` is bound to `cluster-admin` (RBAC failure), but this is cluster-scoped.

- **Network Policy Failures:** Neither `payments` nor `frontend` namespaces have any NetworkPolicies, so:
  - `netpol-require-deny-all-in-labeled-namespaces` fails (no deny-all policy).
  - `netpol-disallow-allow-all-in-labeled-namespaces` passes (no allow-all policies to detect).

- **Image Supply Chain Failures:** Pods in labeled namespaces may use images from unapproved registries (not `quay.io/` or `registry.redhat.io/`).

- **RBAC Failures:** Cluster-scoped checks (like `cluster-admin-allow-list`) fail if unauthorized subjects are bound to `cluster-admin` (e.g., `visa-processor` ServiceAccount).

To debug a specific failure, inspect the result:

```bash
oc get compliancecheckresult <result-name> -n openshift-compliance -o yaml
```

For example, to find which pods are privileged:

```bash
for ns in payments frontend; do
  echo "Namespace: $ns"
  oc get pods -n "$ns" -o json | jq -r '.items[] | select(.spec.containers[]?.securityContext.privileged == true) | "\(.metadata.name) has privileged container"'
done
```

### Step 6: Reset / Cleanup

To remove scans and rules:

```bash
oc delete -k rbac
oc delete -k network-policy
oc delete -k pod-security
oc delete -k image-supply-chain

# Remove labels
oc label namespace payments custom.security/enforce- || true
oc label namespace frontend custom.security/enforce- || true
```

-----

## 3\. Additional Notes

- **RBAC Checks:** Cluster-scoped (no namespace labels needed).
- **Namespace Labels:** Use `custom.security/enforce=true` to enable enforcement. Rules ignore unlabeled namespaces.
- **Forcing Reruns:** Always delete the `ComplianceScan` or `ComplianceCheckResult` to trigger re-evaluation after changes.
- **Customizing Rules:** Edit the YAMLs in [`compliance/manifests`](compliance/manifests ) to adjust allow-lists, labels, or expressions.