# OpenShift Compliance Operator: CustomRule Automation Guide

This guide demonstrates how to extend the OpenShift Compliance Operator using `CustomRules`. It leverages **CEL (Common Expression Language)** to create organization-specific compliance checks without writing Go code.

## 1\. Prerequisites & Setup

Before applying the scenarios below, ensure you have:

  * An OpenShift cluster with the **Compliance Operator** installed and running.
  * **Cluster Admin** access.
  * The `oc` CLI tool installed.
  * **Target Namespace:** All examples assume the default `openshift-compliance` namespace.

## 2\. Core Concepts

To create a custom check, you must define three objects:

1.  **CustomRule:** Defines *what* to check (the logic/CEL expression).
2.  **TailoredProfile:** Groups one or more rules together (enables the rule).
3.  **ScanSettingBinding:** Connects the Profile to a ScanSetting (defines *how/when* to scan).

-----

## Scenario A: Auditing Cluster Admin Access

**Goal:** Ensure only specific Users, Groups, or ServiceAccounts are bound to the `cluster-admin` role.

### Step 1: Define the CustomRule

Create `cluster-admin-allow-list.yaml`. This rule checks `ClusterRoleBindings` against a hardcoded allow-list.

```yaml
apiVersion: compliance.openshift.io/v1alpha1
kind: CustomRule
metadata:
  name: cluster-admin-allow-list
  namespace: openshift-compliance
spec:
  title: Audit cluster-admin access against an allow-list
  description: Audits subjects bound to the 'cluster-admin' role against a pre-defined allow-list.
  failureReason: Found subject(s) bound to 'cluster-admin' that are NOT on the allow-list.
  severity: high
  id: cluster_admin_allow_list
  checkType: Platform
  scannerType: CEL
  inputs:
    - name: crbs
      kubernetesInputSpec:
        apiVersion: rbac.authorization.k8s.io/v1
        resource: clusterrolebindings
  expression: |
    crbs.items.filter(crb, crb.metadata.name == 'cluster-admin')[0]
      .subjects.all(subject,
        (subject.kind == 'User' && subject.name in [
          'kubeadmin',
          'system:admin',
          'alice@my-company.com'
        ]) ||
        (subject.kind == 'Group' && subject.name in [
          'system:masters',
          'ocp-sre-team'
        ]) ||
        (subject.kind == 'ServiceAccount' &&
          has(subject.namespace) &&
          (subject.namespace + '/' + subject.name) in [
            'openshift-monitoring/prometheus-k8s'
          ]
        )
      )
```

### Step 2: Create the Profile and Binding

Create `rbac-scan-config.yaml`. This combines the Profile and Binding into one file for easier application.

```yaml
---
# 1. TailoredProfile: Enables the CustomRule
apiVersion: compliance.openshift.io/v1alpha1
kind: TailoredProfile
metadata:
  name: custom-security-checks
  namespace: openshift-compliance
spec:
  title: Custom Security Profile
  description: Custom security compliance profile using CEL-based CustomRules
  enableRules:
    - name: cluster-admin-allow-list
      kind: CustomRule
      rationale: CIS 5.1.1 — audit cluster-admin bindings
---
# 2. ScanSettingBinding: Schedules the scan
apiVersion: compliance.openshift.io/v1alpha1
kind: ScanSettingBinding
metadata:
  name: custom-security-scan
  namespace: openshift-compliance
profiles:
  - name: custom-security-checks
    kind: TailoredProfile
    apiGroup: compliance.openshift.io/v1alpha1
settingsRef:
  name: default
  kind: ScanSetting
  apiGroup: compliance.openshift.io/v1alpha1
```

### Step 3: Apply Scenario A

```bash
oc apply -f cluster-admin-allow-list.yaml
oc apply -f rbac-scan-config.yaml
```

-----

## Scenario B: NetworkPolicy Enforcement

**Goal:** Enforce strict NetworkPolicy standards on namespaces containing the label `compliance/enforce-networkpolicies=true`.

### Step 1: Define the CustomRules

This scenario requires two rules. Save the following as `netpol-custom-rules.yaml`.

```yaml
---
# Rule 1: Disallow "Allow-All" policies
apiVersion: compliance.openshift.io/v1alpha1
kind: CustomRule
metadata:
  name: netpol-disallow-allow-all-in-labeled-namespaces
  namespace: openshift-compliance
spec:
  title: Disallow allow-all NetworkPolicies in labeled namespaces
  description: Detects allow-all NetworkPolicies in namespaces labeled compliance/enforce-networkpolicies=true.
  failureReason: Allow-all NetworkPolicies found in enforced namespaces.
  severity: high
  id: netpol_disallow_allow_all_labeled
  checkType: Platform
  scannerType: CEL
  inputs:
    - name: netpols
      kubernetesInputSpec:
        apiVersion: networking.k8s.io/v1
        resource: networkpolicies
    - name: namespaces
      kubernetesInputSpec:
        apiVersion: v1
        resource: namespaces
  expression: |
    !netpols.items.exists(np,
      namespaces.items.exists(ns,
        ns.metadata.name == np.metadata.namespace &&
        has(ns.metadata.labels) &&
        ns.metadata.labels.exists(k, k == 'compliance/enforce-networkpolicies') &&
        ns.metadata.labels['compliance/enforce-networkpolicies'] == 'true'
      ) &&
      np.spec.podSelector == {} &&
      (
        (has(np.spec.ingress) && size(np.spec.ingress) == 1 && np.spec.ingress[0] == {}) ||
        (has(np.spec.egress)  && size(np.spec.egress) == 1 && np.spec.egress[0]  == {})
      )
    )
---
# Rule 2: Require "Deny-All" policy presence
apiVersion: compliance.openshift.io/v1alpha1
kind: CustomRule
metadata:
  name: netpol-require-deny-all-in-labeled-namespaces
  namespace: openshift-compliance
spec:
  title: Require deny-all NetworkPolicy in labeled namespaces
  description: Ensures namespaces with compliance/enforce-networkpolicies=true have a deny-all NetworkPolicy.
  failureReason: One or more enforced namespaces lack a deny-all NetworkPolicy.
  severity: high
  id: netpol_require_deny_all_labeled
  checkType: Platform
  scannerType: CEL
  inputs:
    - name: netpols
      kubernetesInputSpec:
        apiVersion: networking.k8s.io/v1
        resource: networkpolicies
    - name: namespaces
      kubernetesInputSpec:
        apiVersion: v1
        resource: namespaces
  expression: |
    namespaces.items.all(ns,
      !(
        has(ns.metadata.labels) &&
        ns.metadata.labels.exists(k, k == 'compliance/enforce-networkpolicies') &&
        ns.metadata.labels['compliance/enforce-networkpolicies'] == 'true'
      ) ||
      netpols.items.exists(np,
        np.metadata.namespace == ns.metadata.name &&
        np.spec.podSelector == {} &&
        (!has(np.spec.ingress) || size(np.spec.ingress) == 0) &&
        (!has(np.spec.egress)  || size(np.spec.egress)  == 0)
      )
    )
```

### Step 2: Create the Profile and Binding

Create `netpol-scan-config.yaml`.

```yaml
---
apiVersion: compliance.openshift.io/v1alpha1
kind: TailoredProfile
metadata:
  name: networkpolicy-security-checks
  namespace: openshift-compliance
spec:
  title: NetworkPolicy Security Checks
  description: Custom checks enforcing NetworkPolicy standards for labeled namespaces
  enableRules:
    - name: netpol-disallow-allow-all-in-labeled-namespaces
      kind: CustomRule
      rationale: Detect allow-all NetworkPolicies in enforced namespaces
    - name: netpol-require-deny-all-in-labeled-namespaces
      kind: CustomRule
      rationale: Ensure deny-all NetworkPolicies exist in enforced namespaces
---
apiVersion: compliance.openshift.io/v1alpha1
kind: ScanSettingBinding
metadata:
  name: networkpolicy-security-scan
  namespace: openshift-compliance
profiles:
  - name: networkpolicy-security-checks
    kind: TailoredProfile
    apiGroup: compliance.openshift.io/v1alpha1
settingsRef:
  name: default
  kind: ScanSetting
  apiGroup: compliance.openshift.io/v1alpha1
```

### Step 3: Apply Scenario B

```bash
oc apply -f netpol-custom-rules.yaml
oc apply -f netpol-scan-config.yaml
```

-----

## 3\. Verifying Results

Once you have applied a Scenario, the Compliance Operator will trigger a scan.

1.  **Check the Scan Status:**
    Wait for the `ComplianceSuite` (created automatically by the Binding) to reach the `DONE` phase.

    ```bash
    oc get compliancesuite -n openshift-compliance
    ```

2.  **View Detailed Results:**
    List the individual check results to see pass/fail status.

    ```bash
    oc get compliancecheckresults -n openshift-compliance
    ```

    **Sample Output:**

    ```text
    NAME                                                                          STATUS   SEVERITY
    custom-security-scan-cluster-admin-allow-list                                 FAIL     high
    networkpolicy-security-scan-netpol-disallow-allow-all-in-labeled-namespaces   PASS     high
    networkpolicy-security-scan-netpol-require-deny-all-in-labeled-namespaces     FAIL     high
    ```

3.  **Investigate Failures:**
    To see exactly why a rule failed (if supported by the rule description), inspect the YAML of the result:

    ```bash
    oc get compliancecheckresult <result-name> -n openshift-compliance -o yaml
    ```

-----

## References

  * [Compliance Operator CustomRule Examples (GitHub)](https://github.com/ComplianceAsCode/compliance-operator/tree/master/config/samples/custom-rules)
  * [Red Hat Documentation: Compliance Operator](https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/html/security_and_compliance/compliance-operator)