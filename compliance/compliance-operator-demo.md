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

## 2\. How to Run a Scan

We use **Kustomize** to apply the configuration for each scenario. Each folder contains the necessary *CustomRule*, *TailoredProfile*, and *ScanSettingBinding*.

### Scenario A: RBAC Audit

**Goal:** strict auditing of the `cluster-admin` role.

  * **The Logic:**
    The rule inspects all `ClusterRoleBindings`. It filters for the `cluster-admin` role and verifies that the bound Subjects (Users, Groups, or ServiceAccounts) match a hardcoded "Allow List" (e.g., `kubeadmin`, `system:masters`).
  * **Execute:**
    ```bash
    oc apply -k rbac
    ```

### Scenario B: Network Policy Enforcement

**Goal:** Ensure strictly secure network defaults in namespaces labeled with `compliance/enforce-networkpolicies=true`.

  * **The Logic:**
    1.  **Disallow Allow-All:** Scans for any NetworkPolicy in labeled namespaces that effectively opens all traffic (`podSelector: {}` with empty ingress/egress rules).
    2.  **Require Deny-All:** Verifies that a "Deny All" policy exists in every labeled namespace to ensure a default-deny posture.
  * **Execute:**
    ```bash
    oc apply -k network-policy
    ```

### Other Available Scenarios

You can run these additional checks using the same pattern:

  * **Pod Security:** Checks for privileged containers or root user usage.
    ```bash
    oc apply -k pod-security
    ```
  * **Image Supply Chain:** Checks image registries or signatures.
    ```bash
    oc apply -k image-supply-chain
    ```

-----

## 3\. Verifying Results

Once you apply a manifest (e.g., `oc apply -k rbac`), the Compliance Operator automatically schedules the scan.

### 1\. Check Scan Progress

Wait for the suite to reach the `DONE` phase.

```bash
oc get compliancesuite -n openshift-compliance
```

### 2\. Review Pass/Fail Status

List the results to see which specific rules succeeded or failed.

```bash
oc get compliancecheckresults -n openshift-compliance
```

**Example Output:**

```text
NAME                                                                          STATUS   SEVERITY
custom-security-scan-cluster-admin-allow-list                                 FAIL     high
networkpolicy-security-scan-netpol-disallow-allow-all-in-labeled-namespaces   PASS     high
networkpolicy-security-scan-netpol-require-deny-all-in-labeled-namespaces     FAIL     high
```

### 3\. Debugging a Failure

If a check fails, inspect the result object to see the specific rationale or error details provided by the rule description.

```bash
# syntax: oc get compliancecheckresult <scan-name> -n openshift-compliance -o yaml
oc get compliancecheckresult custom-security-scan-cluster-admin-allow-list -n openshift-compliance -o yaml
```

-----

## 4\. Reset / Cleanup

To remove a specific scan and its rules, use `delete -k`:

```bash
oc delete -k rbac
oc delete -k network-policy
```