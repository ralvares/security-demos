# Granular Governance: Custom RBAC Roles

In this demo, we move beyond generic permissions. We will create a custom role specifically for a **"Security Auditor"** who needs to inspect network policies and resource quotas but should not be allowed to see logs or application data.

## 1. Why Custom Roles?

Default roles are "bundled" permissions. For example, the `view` role allows a user to see almost everything in a namespace. A **Custom Role** allows you to follow the **Principle of Least Privilege** to the letter by selecting only the specific API "Verbs" and "Resources" required for a task.

---

## 2. Defining the Custom Role

Instead of a single command, we define a Custom Role using a YAML definition (or `oc create clusterrole`).

### Step 1: Create the Role Definition

We want a role that can *only* look at security-related configurations.

```bash
# Create a local Role for a specific namespace
oc create role security-inspector \
  --verb=get,list,watch \
  --resource=networkpolicies,resourcequotas,limitranges \
  -n payments

```

### Step 2: View the Structure

Inspect the role to see how OpenShift maps these to API Groups:

```bash
oc get role security-inspector -n payments -o yaml

```

> **Coaching Note:** Notice the `apiGroups` field. This tells OpenShift exactly which API category (like `networking.k8s.io`) the user is allowed to access.

---

## 3. Identity & Binding

Just like with default roles, we must "glue" this custom role to a subject.

### Step 1: Create the Auditor Persona

```bash
oc create user regional-auditor
oc adm groups new audit-team
oc adm groups add-users audit-team regional-auditor

```

### Step 2: Bind the Custom Role

```bash
# Bind the custom 'security-inspector' role to the audit group
oc adm policy add-role-to-group security-inspector audit-team -n payments

```

---

## 4. Verification: The "Surgical" Check

Because this is a custom role, we need to verify that the permissions are strictly limited to what we defined.

### Scenario: Testing Granularity

```bash
# 1. Can I see the Network Policies? 
# Result: YES (Explicitly allowed)
oc auth can-i get networkpolicies -n payments --as=regional-auditor

# 2. Can I see the Pods? 
# Result: NO (The 'view' role allows this, but our custom role DOES NOT)
oc auth can-i get pods -n payments --as=regional-auditor

# 3. Can I see the Resource Quotas? 
# Result: YES (Explicitly allowed)
oc auth can-i get resourcequotas -n payments --as=regional-auditor

```

---

## 5. Custom ServiceAccount Roles

Custom roles are most powerful when applied to **ServiceAccounts**. For example, a monitoring microservice (like Prometheus) only needs to "collect" metrics, not manage the cluster.

```bash
# 1. Create a SA for a monitoring tool
oc create sa metric-collector -n management

# 2. Create a Custom Role for metrics only
oc create clusterrole metric-reader \
  --verb=get,list \
  --resource=pods,nodes/metrics

# 3. Bind it
oc adm policy add-cluster-role-to-user metric-reader \
  system:serviceaccount:management:metric-collector

```

---

## 6. Pro-Tip: ClusterRole vs. Role

* **Role:** Applied to a **single namespace**. Use this for application-specific security (like our Auditor in `payments`).
* **ClusterRole:** Applied **cluster-wide**. Use this for infrastructure tools or users who need to see resources across all namespaces (like a global Admin or a Monitoring SA).