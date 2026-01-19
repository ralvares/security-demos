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
# Attempt to run a pod as root
oc run root-pod --image=fedora --overrides='{"spec":{"securityContext":{"runAsUser":0}}}' -n secure-app-demo

```

### The Reveal: Inspect the Block

OpenShift will accept the command, but the pod will fail to enter a "Running" state.

```bash
# Check the pod status
oc get pod root-pod -n secure-app-demo

```

**Expected Result:** The pod will stay in `CreateContainerConfigError` or `CrashLoopBackOff`. If you describe the pod, you will see:

> `Error: container's runAsUser breaks non-root policy (pod has uid 0, but must have non-zero uid)`

---

## 3. The "Proper" Way: Using a ServiceAccount

We never want to grant "Root" access to a whole project or a human user. Instead, we grant it to a specific **ServiceAccount** (the pod's identity).

### Step A: Create the Identity

```bash
# Create a dedicated ServiceAccount for this specific workload
oc create sa root-service-app -n secure-app-demo

```

### Step B: Bind the SCC to the ServiceAccount

We will grant this specific identity the `anyuid` SCC, which allows the pod to choose its own User ID (including 0).

```bash
# Grant the 'anyuid' SCC to the ServiceAccount
oc adm policy add-scc-to-user anyuid -z root-service-app -n secure-app-demo

```

---

## 4. The Success: Running with the New Identity

Now, we run the same pod again, but this time we tell it to use our authorized `root-service-app` identity.

```bash
# Run the pod using the authorized ServiceAccount
oc run root-pod-fixed --image=fedora \
  --serviceaccount=root-service-app \
  --overrides='{"spec":{"securityContext":{"runAsUser":0}}}' \
  -n secure-app-demo

```

### Verification

```bash
# Check if the pod is running
oc get pod root-pod-fixed -n secure-app-demo

# Verify the user inside the container is actually root
oc exec root-pod-fixed -n secure-app-demo -- whoami

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
oc delete pod root-pod root-pod-fixed -n secure-app-demo
oc delete sa root-service-app -n secure-app-demo

```