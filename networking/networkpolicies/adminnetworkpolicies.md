# Network Security Governance Model for Application Namespaces

This document defines the security posture, enforcement model, and operational workflow for controlling ingress and egress traffic in business-owned application namespaces on OpenShift. The goal is to provide strong guardrails while enabling developers to continue managing their own NetworkPolicies inside a controlled and predictable perimeter.

-----

## 1\. Scope

The policies in this document apply only to namespaces explicitly marked as application-owned:

> `custom.security/enforce: "true"`

Infrastructure, platform, and operator namespaces are not affected.

-----

## 2\. Security Posture

Owned namespaces follow a **closed-by-default** security model.

### Ingress

  * **External Traffic:** No external traffic may enter an application namespace by default.
  * **Namespace-to-Namespace:** Ingress between application namespaces is only allowed if explicitly passed by `AdminNetworkPolicy`; all other ingress is denied at the admin tier.
  * **Developer Control:** Application teams must use standard `NetworkPolicies` to define pod-level ingress within their namespaces.

### Egress

  * **DNS:** Allowed only to the cluster resolver (`openshift-dns`) for owned namespaces.
  * **Kube-API:** Allowed only for namespaces explicitly selected by the `kubeapi-egress-guardrail` ANP.
  * **Corporate External Networks:** Allowed only for namespaces explicitly selected by the `corporate-access-external-networks-guardrail` ANP.
  * **All Other Egress:** Denied by the final default-deny ANP at the admin tier.

### Baseline Admin Network Policy (BANP)

In addition to the AdminNetworkPolicies, a **BaselineAdminNetworkPolicy (BANP)** is enforced as a default-deny fallback for all owned namespaces. The BANP ensures that, unless explicitly allowed by a higher-tier policy, both ingress and egress traffic between owned namespaces is denied by default. This provides a strong safety net and ensures a closed-by-default posture even if no other policies are present.

### Developer NetworkPolicy Privileges

Within the boundaries enforced by AdminNetworkPolicies and the BaselineAdminNetworkPolicy (BANP), application developers have full privileges to create and manage their own Kubernetes `NetworkPolicy` objects in their namespaces. This allows teams to define pod-level ingress and egress rules for their workloads, enabling service-to-service communication and additional security controls as needed. However, these developer-created policies cannot override the cluster perimeter or default-deny posture set by the admin tier.

-----

## 3\. Administrative Enforcement – ANP Suite

In this environment, only the following AdminNetworkPolicies are present and enforced. Each policy is single-purpose, auditable, and mapped to a specific risk domain.

| File | Purpose | Priority |
| :--- | :--- | :--- |
| `corporate-external-networks-guardrail.yaml` | Allow egress to specific corporate external networks for approved namespaces | 12 |
| `kubeapi-egress-guardrail.yaml` | Permit kube-API access only for explicitly approved workloads | 13 |
| `deny-all-allow-dns-owned-namespaces.yaml` | Default deny for all, allow DNS and pass traffic between owned namespaces | 99 |

Each file has one intent, one risk domain, one owner, one approval workflow.

### 3.1 Corporate External Networks Guardrail ANP

```yaml
apiVersion: policy.networking.k8s.io/v1alpha1
kind: AdminNetworkPolicy
metadata:
  name: corporate-access-external-networks-guardrail
spec:
  priority: 12
  subject:
    namespaces:
      matchLabels:
        security.allow/networks: "true"
  egress:
    - name: allow-corporate-external-networks
      action: Allow
      to:
        - networks:
            - XX.XX.XX.0/24
      ports:
        - portNumber:
            protocol: TCP
            port: 443
```

### 3.2 Kube API Egress Guardrail ANP

```yaml
apiVersion: policy.networking.k8s.io/v1alpha1
kind: AdminNetworkPolicy
metadata:
  name: kubeapi-egress-guardrail
spec:
  priority: 13
  subject:
    namespaces:
      matchLabels:
        security.allow/kapi: "true"
  egress:
    - name: allow-kubeapi-for-approved-workloads
      action: Allow
      to:
        - nodes:
            matchExpressions:
              - key: node-role.kubernetes.io/control-plane
                operator: Exists
      ports:
        - portNumber:
            protocol: TCP
            port: 6443
```

### 3.3 Deny-All, Allow DNS & Monitoring, and Pass for Owned Namespaces ANP

```yaml
apiVersion: policy.networking.k8s.io/v1alpha1
kind: AdminNetworkPolicy
metadata:
  name: deny-all-allow-dns-monitoring-owned-namespaces
spec:
  priority: 99
  subject:
    namespaces:
      matchLabels:
        custom.security/enforce: "true"
  ingress:
    - name: allow-openshift-monitoring
      action: Allow
      from:
        - namespaces:
            matchLabels:
              kubernetes.io/metadata.name: openshift-monitoring

    - name: allow-user-workload-monitoring
      action: Allow
      from:
        - namespaces:
            matchLabels:
              kubernetes.io/metadata.name: openshift-user-workload-monitoring

    - name: pass-from-owned-namespaces
      action: Pass
      from:
        - namespaces:
            matchLabels:
              custom.security/enforce: "true"

    - name: deny-ingress
      action: Deny
      from:
        - namespaces: {}
  egress:
    - name: allow-dns
      action: Allow
      to:
        - namespaces:
            matchLabels:
              kubernetes.io/metadata.name: openshift-dns
      ports:
        - portNumber:
            port: 53
            protocol: UDP
        - portNumber:
            port: 53
            protocol: TCP
        - portNumber:
            port: 5353
            protocol: UDP
        - portNumber:
            port: 5353
            protocol: TCP

    - name: pass-to-owned-namespaces
      action: Pass
      to:
        - namespaces:
            matchLabels:
              custom.security/enforce: "true"

    - name: deny-egress
      action: Deny
      to:
        - networks:
            - 0.0.0.0/0
```

*These are the only AdminNetworkPolicies enforced in this environment. All other references or examples have been removed for clarity and accuracy.*

-----

## 4\. How Rule Types and Priorities Behave

> **Note:** The number of AdminNetworkPolicies in a cluster is typically expected to be a maximum of 30–50, based on the use cases for which this API was designed. In OVN-Kubernetes, supported priority values for AdminNetworkPolicies range from 0 to 99.

### Allow

Traffic is permitted at the Admin tier. Lower-tier policies (BANP or developer NetworkPolicies) cannot override the decision.

  * **Used for:**
      * DNS egress (for owned namespaces, to `openshift-dns`)
      * Monitoring ingress (if included in the ANP)
      * Ingress(route) (if included in the ANP)
      * Kube-API egress (for namespaces explicitly selected by the `kubeapi-egress-guardrail` ANP)
      * Corporate external network egress (for namespaces explicitly selected by the `corporate-access-external-networks-guardrail` ANP)

### Deny

Traffic is blocked at the Admin tier and cannot be overridden.

  * **Used for:**
      * Final deny-all safety net (low-priority default-deny ANP)
      * Default-deny fallback for all owned namespaces (BANP)

### Pass

Some ANP rules may use the `Pass` action, which delegates the decision to developer-managed NetworkPolicies or the BANP. This allows teams to define pod-level communication within the boundaries set by the admin tier.

### Priority and Precedence

AdminNetworkPolicy evaluation is priority-driven:

  * **Lower number** → higher priority (evaluated earlier)
  * **Higher number** → lower priority (evaluated later)

Within a single ANP object, a deny-all rule always overrides other rules in that same object. However, a deny-all in a **lower-priority** ANP does not override allows in a higher-priority ANP.

This is why the final default-deny ANP is assigned a high numeric priority (e.g., 99):

1.  All allow ANPs (DNS, kube-API, corporate networks) run first.
2.  Any traffic explicitly allowed is permitted.
3.  Only traffic not matched by any allow is caught by the final deny-all.

The **BaselineAdminNetworkPolicy (BANP)** acts as a fallback, denying all ingress and egress between owned namespaces unless explicitly allowed by a higher-tier ANP. Developer NetworkPolicies can only further restrict traffic within the boundaries set by these admin policies.

-----

## 5\. Developer Workflow

Developers continue to own their namespace `NetworkPolicy` objects.

**Their responsibilities:**

  * Define allowed ingress/egress for workloads inside their namespace.
  * Maintain service-to-service topology.
  * Document required communication paths for review.

**Their NetworkPolicies operate inside the Admin perimeter enforced by the ANP suite:**

  * They can allow traffic only to destinations that one of the AdminNetworkPolicies has `Allow`ed or `Pass`ed.
  * **They cannot override:**
      * kube-API restrictions enforced by the kube API ANP.
      * Internet restrictions and proxy routing enforced by the proxy ANP and final default-deny ANP.
      * metadata blocks enforced by the metadata-deny ANP.
      * ingress exposure without Security labels enforced by the ingress ANP.

**The result is:**

  * Security controls the perimeter.
  * Developers control workload communication inside that perimeter.
  * Reduced risk of accidental broad exposure through permissive NetworkPolicies.

-----

## 6\. Best Practices and Improvements for AdminNetworkPolicies

AdminNetworkPolicies (ANPs) are powerful tools for enforcing cluster-wide network security. To maximize their effectiveness and avoid common pitfalls, follow these best practices:

  * **Priority Management:**
      * Use the supported priority range (0–99) in OVN-Kubernetes. Avoid priorities above 99.
      * Plan priorities with gaps (e.g., 10, 20, 30) to allow future policies to be inserted.
      * Limit the number of ANPs to 30–50 per cluster for manageability and performance.
  * **Policy Design:**
      * Prefer label-based selectors over empty selectors (`{}`) to avoid unintentionally selecting all namespaces, including system ones.
      * Use `Deny` for strict perimeter enforcement and `Pass` to delegate to namespace NetworkPolicies.
      * Avoid overlapping selectors at the same priority to prevent unpredictable results.
  * **Operational Safety:**
      * Always define high-priority `Allow` rules for essential services (DNS, kube-API) before applying a default-deny.
      * Use `Pass` to let developers control specific flows via NetworkPolicies.
  * **Performance:**
      * Minimize use of `namedPorts` in large clusters.
      * Keep address sets small and non-overlapping to avoid scale bottlenecks.
  * **Monitoring and Troubleshooting:**
      * Enable ACL logging for observability.
      * Use metrics and tracing tools (e.g., `ovn-trace`) to validate policy behavior.
  * **Documentation and Review:**
      * Document the intent and effect of each ANP.
      * Regularly review ANPs for unnecessary complexity and update as requirements evolve.

-----

## 7\. Example AdminNetworkPolicies in This Environment

The following AdminNetworkPolicies are present in this environment and define the security posture:

### corporate-external-networks-guardrail.yaml

```yaml
apiVersion: policy.networking.k8s.io/v1alpha1
kind: AdminNetworkPolicy
metadata:
  name: corporate-access-external-networks-guardrail
spec:
  priority: 12
  subject:
    namespaces:
      matchLabels:
        security.allow/networks: "true"
  egress:
    - name: allow-corporate-external-networks
      action: Allow
      to:
        - networks:
            - XX.XX.XX.0/24
      ports:
        - portNumber:
            protocol: TCP
            port: 443
```

### deny-all-allow-dns-monitoring-owned-namespaces.yaml

```yaml
apiVersion: policy.networking.k8s.io/v1alpha1
kind: AdminNetworkPolicy
metadata:
  name: deny-all-allow-dns-monitoring-owned-namespaces
spec:
  priority: 99
  subject:
    namespaces:
      matchLabels:
        custom.security/enforce: "true"
  ingress:
    - name: allow-openshift-monitoring
      action: Allow
      from:
        - namespaces:
            matchLabels:
              kubernetes.io/metadata.name: openshift-monitoring

    - name: allow-user-workload-monitoring
      action: Allow
      from:
        - namespaces:
            matchLabels:
              kubernetes.io/metadata.name: openshift-user-workload-monitoring

    - name: pass-from-owned-namespaces
      action: Pass
      from:
        - namespaces:
            matchLabels:
              custom.security/enforce: "true"

    - name: deny-ingress
      action: Deny
      from:
        - namespaces: {}
  egress:
    - name: allow-dns
      action: Allow
      to:
        - namespaces:
            matchLabels:
              kubernetes.io/metadata.name: openshift-dns
      ports:
        - portNumber:
            port: 53
            protocol: UDP
        - portNumber:
            port: 53
            protocol: TCP
        - portNumber:
            port: 5353
            protocol: UDP
        - portNumber:
            port: 5353
            protocol: TCP

    - name: pass-to-owned-namespaces
      action: Pass
      to:
        - namespaces:
            matchLabels:
              custom.security/enforce: "true"

    - name: deny-egress
      action: Deny
      to:
        - networks:
            - 0.0.0.0/0
```

These policies are the only AdminNetworkPolicies present and should be referenced for implementation and troubleshooting.