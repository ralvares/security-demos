# RBAC Governance for Microservices

This guide demonstrates how to implement a **Least Privilege** security model across a 3-tier application (`frontend`, `backend`, `payments`).

## 1\. Identity Management: Users & Groups

### Coaching Note: Where do users come from?

> In a **real production environment**, you do **not** run commands to create users manually.
>
> OpenShift typically integrates with an Identity Provider (IdP) like **Active Directory, LDAP, or OIDC** (Google, GitHub, etc.). When a real human logs in for the first time via the web console or CLI, OpenShift **automatically** creates the User object for them.
>
> However, for this **demo**, we will manually simulate these users so we can test our permissions without setting up an external authentication server.

### Step 1: Create Simulated Users

We will create three distinct personas to represent our teams.

```bash
# Simulating the identity provider process
oc create user frontend-dev
oc create user backend-dev
oc create user payment-admin
```

### Step 2: Create Groups (Best Practice)

> **Why Groups?** Never assign permissions to individual users. People change jobs; teams remain constant. If you assign roles to a **Group**, onboarding a new team member is as simple as adding them to the group.

```bash
# Create the functional teams
oc adm groups new frontend-team
oc adm groups new backend-team
oc adm groups new payment-team

# Add our users to their respective teams
oc adm groups add-users frontend-team frontend-dev
oc adm groups add-users backend-team backend-dev
oc adm groups add-users payment-team payment-admin
```

-----

## 2\. The Permission Strategy

We will apply permissions based on the specific needs of each tier.

| Team | Tier-Frontend | Tier-Backend | Tier-Payments |
| :--- | :--- | :--- | :--- |
| **Frontend** | **Edit** (Owner) | **View** (Debugger) | ⛔ No Access |
| **Backend** | **View** (Debugger) | **Edit** (Owner) | **View** (Health Check) |
| **Payment** | ⛔ No Access | ⛔ No Access | **Admin** (Owner) |

-----

## 3\. Applying Policies

### Frontend Team Configuration

They own the frontend, but need to see the backend logs to debug API issues. They must never see payment data.

```bash
# Grant 'edit' (manager) access to their own project
oc adm policy add-role-to-group edit frontend-team -n frontend

# Grant 'view' (read-only) access to the backend API they consume
oc adm policy add-role-to-group view frontend-team -n backend
```

### Backend Team Configuration

They own the backend logic. They need to see the frontend (to check integration) and the payment gateway (to check connectivity), but they cannot change payment configurations.

```bash
# Grant 'edit' (manager) access to their own project
oc adm policy add-role-to-group edit backend-team -n backend

# Grant 'view' access to upstream and downstream dependencies
oc adm policy add-role-to-group view backend-team -n frontend
oc adm policy add-role-to-group view backend-team -n payments
```

### Payment Admin Configuration (High Security)

This is a sensitive role. They have full control over the payment vault but are isolated from the application code to enforce **Segregation of Duties**.

```bash
# Grant 'admin' (full control) access to the payment vault
oc adm policy add-role-to-group admin payment-team -n payments
```

-----

## 4\. Verification (The "Can-I" Check)

We use the `--as` flag to simulate being these users without actually logging in and out.

### Scenario A: The Frontend Developer

```bash
# 1. Can I update the frontend deployment? -> YES
oc auth can-i update deployment -n frontend --as=frontend-dev

# 2. Can I view backend logs to see why my API call failed? -> YES
oc auth can-i get pods/log -n backend --as=frontend-dev

# 3. Can I accidentally delete the payment gateway? -> NO
oc auth can-i delete deployment -n payments --as=frontend-dev
```

### Scenario B: The Backend Developer

```bash
# 1. Can I restart the backend service? -> YES
oc auth can-i delete pod -n backend --as=backend-dev

# 2. Can I see if the payment gateway is running? -> YES
oc auth can-i get pods -n payments --as=backend-dev

# 3. Can I read the payment API Secrets (API Keys)? -> NO (View role prevents reading secrets)
oc auth can-i get secrets -n payments --as=backend-dev
```

### Scenario C: The Payment Admin

```bash
# 1. Can I change the credit card processor config? -> YES
oc auth can-i update deployment -n payments --as=payment-admin

# 2. Can I mess with the frontend website code? -> NO
oc auth can-i get pods -n frontend --as=payment-admin
```