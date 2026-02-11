# Validating Admission Policy (VAP)

**Validating Admission Policy** offers a declarative, in-process alternative to validating admission webhooks. It uses the **Common Expression Language (CEL)** to declare the validation rules of a policy.

## Key Concepts

A policy is generally made up of three resources:

1.  **ValidatingAdmissionPolicy**: Describes the abstract logic of a policy (e.g., "this policy makes sure a particular label is set").
2.  **ValidatingAdmissionPolicyBinding**: Links the policy to specific resources or scopes (e.g., "apply this policy to all Pods in the `test` namespace").
3.  **Parameter Resource** (Optional): Provides configuration to the policy (e.g., "max replicas = 3"). This can be a native type (ConfigMap) or a CRD.

## How it Works

VAP uses CEL expressions to validate requests.
*   **`object`**: The object from the incoming request.
*   **`oldObject`**: The existing object (null for CREATE).
*   **`request`**: Attributes of the admission request.
*   **`params`**: The parameter resource (if used).

## Validation Actions

Each binding must specify one or more `validationActions`:
*   **Deny**: Validation failure results in a denied request.
*   **Warn**: Validation failure is reported to the client as a warning.
*   **Audit**: Validation failure is included in the audit event.

## Examples

### 1. Basic Policy (No Parameters)

Ensures that deployments have 5 or fewer replicas.

```yaml
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicy
metadata:
  name: "demo-policy.example.com"
spec:
  failurePolicy: Fail
  matchConstraints:
    resourceRules:
    - apiGroups:   ["apps"]
      apiVersions: ["v1"]
      operations:  ["CREATE", "UPDATE"]
      resources:   ["deployments"]
  validations:
    - expression: "object.spec.replicas <= 5"
```

**Binding:**

```yaml
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicyBinding
metadata:
  name: "demo-binding-test.example.com"
spec:
  policyName: "demo-policy.example.com"
  validationActions: [Deny]
  matchResources:
    namespaceSelector:
      matchLabels:
        environment: test
```

### 2. Policy with Parameters

Allows configuring the max replicas via a separate resource.

**Policy:**

```yaml
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicy
metadata:
  name: "replicalimit-policy.example.com"
spec:
  paramKind:
    apiVersion: rules.example.com/v1
    kind: ReplicaLimit
  validations:
    - expression: "object.spec.replicas <= params.maxReplicas"
      reason: Invalid
```

### 3. Scenario: Opt-In Restriction

This policy prevents workloads from setting `nodeSelector` or `tolerations`, but **only** for namespaces that are explicitly tagged as "restricted". This allows you to apply stricter controls to specific environments (like production) while leaving dev environments flexible.

**The Strategy:**
1.  **The Policy (Rules):** "Deny if `nodeSelector` or `tolerations` are present."
2.  **The Binding (Scope):** "Apply ONLY to namespaces with the label `env=restricted`."

**Policy Definition:**

```yaml
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicy
metadata:
  name: "block-custom-scheduling"
spec:
  failurePolicy: Fail
  matchConstraints:
    resourceRules:
      - apiGroups: [""]
        apiVersions: ["v1"]
        operations: ["CREATE", "UPDATE"]
        resources: ["pods"]
      - apiGroups: ["apps"]
        apiVersions: ["v1"]
        operations: ["CREATE", "UPDATE"]
        resources: ["deployments", "statefulsets", "daemonsets"]
  validations:
    - expression: |
        object.kind == 'Pod' ? 
        (!has(object.spec.nodeSelector) && !has(object.spec.tolerations)) : 
        (!has(object.spec.template.spec.nodeSelector) && !has(object.spec.template.spec.tolerations))
      message: "Custom scheduling (nodeSelector, tolerations) is forbidden in 'restricted' environments."
```

**Binding (The Inclusion Logic):**

```yaml
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicyBinding
metadata:
  name: "block-custom-scheduling-binding"
spec:
  policyName: "block-custom-scheduling"
  validationActions: [Deny]
  matchResources:
    # Logic: Apply ONLY to namespaces with this specific label
    namespaceSelector:
      matchLabels:
        env: restricted
```

## Advanced Features

*   **Match Conditions**: Fine-grained filtering using CEL (e.g., exclude specific users or groups).
*   **Audit Annotations**: Include custom annotations in audit events based on CEL expressions.
*   **Message Expressions**: Dynamic error messages (e.g., "replicas must be <= 3").
*   **Variables**: Extract complex logic into reusable variables within the policy.
