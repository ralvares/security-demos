# Mastering RBAC: Governance for Microservices

Role-Based Access Control (RBAC) isn't just about permissions; it’s about **intent**. In this demo, we implement a **Least Privilege** model for a 3-tier application: `frontend`, `backend`, and `payments`.

## 1. The RBAC Trinity

Before running commands, it is essential to understand the three components that make RBAC work. Think of it as a sentence: **"This Subject can perform these Verbs on these Resources."**

* **Subject:** The "Who" (User, Group, or ServiceAccount).
* **Role / ClusterRole:** The "What" (A list of rules: get, list, watch, create, etc.).
* **RoleBinding:** The "Glue" (Connects a Subject to a Role within a specific Namespace).

---

## 2. Identity Management: The Source of Truth

### Why Groups Matter

In production, users are managed in external systems like Active Directory or Okta. We use **Groups** because they provide a layer of abstraction. If a developer leaves the company, you remove them from the AD Group, and their OpenShift access vanishes automatically—no changes to the cluster required.

### Step 1: Simulate the Identity Provider

```bash
# Create simulated users
oc create user frontend-dev
oc create user backend-dev
oc create user payment-admin

# Create functional groups
oc adm groups new frontend-team
oc adm groups new backend-team
oc adm groups new payment-team

# Map users to groups
oc adm groups add-users frontend-team frontend-dev
oc adm groups add-users backend-team backend-dev
oc adm groups add-users payment-team payment-admin

```

---

## 3. The Permission Strategy Matrix

A "proper" RBAC implementation starts with a requirements matrix. We use OpenShift’s **Default Local Roles**:

* **Admin:** Full power within the project (can grant permissions to others).
* **Edit:** Can create/modify/delete most resources (Pods, Services) but cannot manage permissions.
* **View:** Read-only access. Importantly, **cannot see Secrets.**

| Team | Namespace: `frontend` | Namespace: `backend` | Namespace: `payments` |
| --- | --- | --- | --- |
| **Frontend Team** | **Edit** (Owner) | **View** (Logs/API) | ⛔ No Access |
| **Backend Team** | **View** (Integration) | **Edit** (Owner) | **View** (Connectivity) |
| **Payment Team** | ⛔ No Access | ⛔ No Access | **Admin** (Security Owner) |

---

## 4. Applying the Glue (Role Bindings)

When we run `add-role-to-group`, OpenShift creates a **RoleBinding** object inside that namespace.

### Frontend & Backend Access

```bash
# Frontend owns 'frontend', views 'backend'
oc adm policy add-role-to-group edit frontend-team -n frontend
oc adm policy add-role-to-group view frontend-team -n backend

# Backend owns 'backend', views 'frontend' and 'payments'
oc adm policy add-role-to-group edit backend-team -n backend
oc adm policy add-role-to-group view backend-team -n frontend
oc adm policy add-role-to-group view backend-team -n payments

```

### High-Security Payment Access

```bash
# Payment Admin gets 'admin' role for full lifecycle management
oc adm policy add-role-to-group admin payment-team -n payments

```

---

## 5. Verification: The "Can-I" Audit

The `oc auth can-i` command is the most powerful tool for a security admin. It allows you to impersonate a user to verify your logic.

### Scenario: The "View" Role Security Check

A common mistake is thinking `view` can see everything. Let's test the **Backend Developer** trying to look at **Payment Secrets**:

```bash
# Can I see the pods in payments?
# Result: YES (View allows this)
oc auth can-i get pods -n payments --as=backend-dev

# Can I see the database passwords (Secrets) in payments?
# Result: NO (View role explicitly excludes Secrets for security)
oc auth can-i get secrets -n payments --as=backend-dev

```

> **Insight:** This is why we use `view` for cross-team debugging. It allows developers to see logs and statuses without exposing sensitive credentials like API keys or database passwords.

---

## 6. Pro-Tip: Inspecting the Binding

To see the "proper" technical object created by these commands, you can inspect the RoleBinding directly:

```bash
oc get rolebinding -n payments

```

This will show you exactly which group is tied to which role, providing an audit trail for your security team.

---

## 7. Machine Identities: ServiceAccounts

While Groups are for humans, **ServiceAccounts** are for your applications. If your `backend` microservice needs to query the OpenShift API to find the IP of the `payment` service, it needs its own identity.

### Step 1: Create the ServiceAccount

```bash
# Create a dedicated identity for the application
oc create sa backend-app-sa -n backend

```

### Step 2: Grant API Access

Applications should also follow the Least Privilege model. We grant the `backend` application service account the `view` role in the `payments` namespace so it can perform service discovery.

```bash
# Grant 'view' to the ServiceAccount specifically
oc adm policy add-role-to-user view \
    system:serviceaccount:backend:backend-app-sa \
    -n payments

```

### Step 3: Verification (The Machine Check)

```bash
# Can the backend microservice list pods in payments?
# Result: YES
oc auth can-i get pods -n payments \
    --as=system:serviceaccount:backend:backend-app-sa

# Can the backend microservice delete pods in payments?
# Result: NO
oc auth can-i delete pods -n payments \
    --as=system:serviceaccount:backend:backend-app-sa

```