Security Context Constraints (SCCs) are one of the most powerful security features in OpenShift. While RBAC defines **who** can do something, SCCs define **what** a pod can actually do (e.g., can it run as root? can it access the host network?).

This demo shows how OpenShift protects the cluster by blocking a "privileged" container and how we safely grant permission using a **ServiceAccount**.

---

# Demo: Hardening Pod Privileges (SCCs)

In this demo, we will attempt to run a pod that requires "Root" privileges. We will see OpenShift block it by default and then walk through the **Proper** way to allow it using a dedicated ServiceAccount.

## 1. The "Standard" Security Posture

By default, OpenShift uses the `restricted-v2` SCC. This policy:

* Prevents pods from running as the **root** user.
* Forces pods to use a unique, non-privileged User ID (UID).
* Prevents access to the host's file system or network.

---

## 2. The Failure: Attempting to Run as Root

We will try to run a standard `fedora` image and force it to run as the root user (UID 0).

```bash
oc new-project scc-governance-lab
oc adm policy add-role-to-user admin user001 -n scc-governance-lab    
# Attempt to run a pod as root
oc run --as=user001 root-pod --image=registry.access.redhat.com/ubi9/ubi --overrides='{"spec":{"securityContext":{"runAsUser":0}}}' -n scc-governance-lab -- sleep infinity

```

### The Reveal: Admission Control Blocks the Request

OpenShift **rejects the request immediately** — the pod is never created. SCC enforcement happens at the admission control layer, before any scheduling or container runtime is involved.

**Expected Result:** The `oc run` command itself returns a `Forbidden` error:

```
Error from server (Forbidden): pods "root-pod" is forbidden: unable to validate against any security context constraint: [provider "anyuid": Forbidden: not usable by user or serviceaccount, provider restricted-v2: .containers[0].runAsUser: Invalid value: 0: must be in the ranges: [1000660000, 1000669999], ...]
```

No pod object is created in the cluster. There is nothing to `oc get` — the API server denied the request before any pod was scheduled.

---

## 3. The "Proper" Way: Using a ServiceAccount

We never want to grant "Root" access to a whole project or a human user. Instead, we grant it to a specific **ServiceAccount** (the pod's identity).

### Step A: Create the Identity

```bash
# Create a dedicated ServiceAccount for this specific workload
oc create sa root-service-app -n scc-governance-lab

```

### Step B: Verify the Default SCC Permissions

Before granting anything, we can confirm that the `default` ServiceAccount can only use `restricted-v2` and **cannot** use `anyuid`:

```bash
# This should return "yes" — restricted-v2 is allowed by default
oc auth can-i use scc/restricted-v2 --as=system:serviceaccount:scc-governance-lab:default

# This should return "no" — anyuid is NOT allowed yet
oc auth can-i use scc/anyuid --as=system:serviceaccount:scc-governance-lab:default

```

**Expected Output:**
```
yes
no
```

This confirms that, out of the box, a ServiceAccount is locked to the `restricted-v2` policy and cannot escalate privileges on its own.

### Step C: Bind the SCC to the ServiceAccount

We will grant this specific identity the `anyuid` SCC, which allows the pod to choose its own User ID (including 0).

```bash
# Grant the 'anyuid' SCC to the ServiceAccount
oc adm policy add-scc-to-user anyuid -z default -n scc-governance-lab

# Confirm the permission has been granted
oc auth can-i use scc/anyuid --as=system:serviceaccount:scc-governance-lab:default

```

**Expected Output:** `yes`

---

## 4. The Success: Running with the New Identity

Now, we run the same pod again, but this time we tell it to use our authorized `default` identity.

```bash
# Run the pod using the authorized ServiceAccount
oc run --as=user001 root-pod-fixed --image=registry.access.redhat.com/ubi9/ubi \
  --overrides='{"spec":{"securityContext":{"runAsUser":0}}}' \
  -n scc-governance-lab -- sleep infinity

```

### Verification

```bash
# Check if the pod is running
oc get pod root-pod-fixed -n scc-governance-lab  --as=user001

# Verify the user inside the container is actually root
oc exec root-pod-fixed -n scc-governance-lab -- whoami  --as=user001

```

**Expected Output:** `root`

---

## 5. Key Takeaways for the Audience

* **Default Deny:** OpenShift is secure by default. Even if a developer pushes a "root-required" image, the cluster will block it unless explicitly authorized.
* **Least Privilege:** We didn't make the developer an admin. We gave a **ServiceAccount** just enough permission to run that one specific workload.
* **Audit Trail:** By using ServiceAccounts, security teams can run a single command to see exactly which applications have elevated privileges:
```bash
oc get scc anyuid -o yaml

```

---

## 6. Cleanup

```bash
oc delete pod root-pod-fixed -n scc-governance-lab
oc delete sa root-service-app -n scc-governance-lab

```