# Demo: Dynamic Network Policy Compliance Guardrails

This demo showcases a compliance loop using the **OpenShift Compliance Operator** and **Advanced Cluster Management (ACM)**. It dynamically targets namespaces based on a specific label and enforces the presence of at least one `NetworkPolicy`.

## Prerequisites
* OpenShift 4.x Cluster
* Compliance Operator installed in `openshift-compliance`
* `kustomize` with the `policy-generator` (ACM) plugin enabled ( OR ARGOCD )

---

## Step 1: Baseline Deployment
In this phase, we deploy the compliance infrastructure. Since no namespaces carry the target label yet, the scan should result in a **PASS**.

1.  **Build and Apply the Manifests:**
    ```bash
    kustomize build --enable-alpha-plugins . | oc apply -f -
    ```
2.  **Verify the Baseline PASS:**
    ```bash
    oc get compliancecheckresults -n openshift-compliance | grep "network-policies"
    ```
    * **Expected Result:** `PASS`

---

## Step 2: Triggering a Violation
We now create a new project and "tag" it for compliance monitoring. Since the new project won't have a `NetworkPolicy` yet, the scan will fail.

1.  **Create the Project and Label it:**
    ```bash
    oc new-project netpol-demo-app
    oc label namespace netpol-demo-app complience-netpol-demo=true
    ```
    > **Note:** We are using the specific label spelling `complience-netpol-demo` as defined in our ACM template.

2.  **Clear Old Results and Rerun:**
    ```bash
    oc delete compliancecheckresult demo-targeted-profile-configure-network-policies-namespaces -n openshift-compliance
    SCANS=$(oc get compliancescans -n openshift-compliance -o name | grep demo-targeted-profile)
    for scan in $SCANS; do
      oc annotate $scan compliance.openshift.io/rescan= -n openshift-compliance --overwrite
    done
    ```

3.  **Verify the FAIL:**
    Wait for the `api-checks-pod` to complete.
    ```bash
    oc get compliancecheckresults -n openshift-compliance | grep "network-policies"
    ```
    * **Expected Result:** `FAIL`

---

## Step 3: Remediating and Passing
Finally, we apply a "Deny-All" policy to the namespace to bring it back into compliance.

1.  **Apply a Default Deny Policy:**
    ```bash
    cat > /tmp/deny-by-default.yaml << 'YAML'
    kind: NetworkPolicy
    apiVersion: networking.k8s.io/v1
    metadata:
      name: deny-by-default
      namespace: netpol-demo-app
    spec:
      podSelector: {}
      policyTypes:
      - Ingress
    YAML
    oc apply -f /tmp/deny-by-default.yaml
    ```

2.  **Final Rerun:**
    ```bash
    oc delete compliancecheckresult demo-targeted-profile-configure-network-policies-namespaces -n openshift-compliance
    SCANS=$(oc get compliancescans -n openshift-compliance -o name | grep demo-targeted-profile)
    for scan in $SCANS; do
      oc annotate $scan compliance.openshift.io/rescan= -n openshift-compliance --overwrite
    done
    ```

3.  **Verify the Final PASS:**
    ```bash
    oc get compliancecheckresults -n openshift-compliance | grep "network-policies"
    ```
    * **Expected Result:** `PASS`

---

## Useful Debugging Commands
* **Watch Scanner Pods:** `oc get pods -n openshift-compliance -w | grep "api-checks"`
* **Check Regex State:** `oc get tailoredprofile demo-targeted-profile -n openshift-compliance -o jsonpath='{.spec.setValues[0].value}'`
* **Check Suite Phase:** `oc get compliancesuite demo-cis-binding -n openshift-compliance`

---