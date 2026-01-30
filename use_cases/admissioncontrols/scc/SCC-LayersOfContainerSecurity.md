# Defense in Depth: Understanding the Protection Layers

In a secure container platform, defense in depth is achieved through multiple independent layers of security. This lab demonstrates how OpenShift leverages Linux kernel primitives to enforce isolation.

## Core Concepts: The Three Layers

### 1. Discretionary Access Control (DAC)


**"The User's Perspective"**

This is the standard Linux permission model (`rwx`, `chown`, `chmod`) based on **UID/GID**.
- **Rule:** "Does User 1000 have permission to read this file owned by User 1000?"
- **Weakness:** If a user exploits a process and gains the right UID, they can access the data.

### 2. Mandatory Access Control (MAC) via SELinux

**"The System's Perspective"**

This is an additional security layer enforced by the kernel, based on **Labels** (Contexts).

- **Rule:** "Does a process with label `container_t:c1,c1` have permission to read a file labeled `container_file_t:c1,c1`?"
- **Strength:** Even if a process runs as the correct UID, if the SELinux labels (MCS categories) don't match, the Kernel blocks access. This is the primary defense against container breakouts.

### 3. OpenShift Security Context Constraints (SCC)

**"The Cluster's Perspective"**

While DAC and MAC are the enforcement mechanisms in the Linux Kernel, SCC is the higher-level admission controller that configures them. It governs *what* a pod is allowed to request before it ever reaches a node.

- **Role:** It authorizes (or denies) sensitive requests at the API level. This includes:

    - **Identity:** Which UIDs and SELinux labels can be used?
    - **Capabilities:** Can the pod request powerful Linux capabilities (e.g., `NET_ADMIN`, `SYS_TIME`)?
    - **Host Access:** Can the pod mount host directories or use the host network?

### 4. The Demo Scenario
In this lab, we will simulate a multi-tenant breakout scenario on a shared node. We will attempt to access a sensitive "Crown Jewels" file owned by Tenant A (UID 1000, MCS `c1,c1`) using various attack vectors.

We will prove that:

1.  **MAC Wins:** Matching UIDs (`1000`) is not enough if SELinux categories differ (**Blocked by Kernel**).
2.  **DAC Wins:** Matching SELinux categories (`c1,c1`) is not enough if UIDs differ (**Blocked by Filesystem**).
3.  **SCC Wins:** Spoofing access is impossible without a privileged Security Context Constraint (**Blocked by SCC**).

---

## Phase 1: Global Infrastructure Setup (Admin)

We establish the node, the projects, and the security context foundations.

```bash
# 1. Prepare the Node and Shared Host Directory
# This establishes the shared landing zone for the breakout simulation.
# We choose the first worker node as our target.
oc label node compute-0 type=shared-compute --overwrite

NODE_NAME=$(oc get nodes -l type=shared-compute -o jsonpath='{.items[0].metadata.name}')

oc debug node/$NODE_NAME -- chroot /host /bin/sh -c \
  "mkdir -p /mnt/shared-data && \
   chown 1000:1000 -R /mnt/shared-data && \
   chmod 700 -R /mnt/shared-data && \
   chcon -t container_file_t -l s0:c1,c1 /mnt/shared-data"

# 2. Setup Projects & Special Permissions
oc new-project tenant-a
oc new-project tenant-b
oc create user user001 2>/dev/null || true
oc adm policy add-role-to-user admin user001 -n tenant-a
oc adm policy add-role-to-user admin user001 -n tenant-b

# 3. Create 'demo-sa' and grant SCCs
# We use this SA to allow us to manually set UIDs and Labels for Pods A, B, C, and E.
for ns in tenant-a tenant-b; do
  oc create sa demo-sa -n $ns
  oc adm policy add-scc-to-user hostmount-anyuid-v2 -z demo-sa -n $ns
done

```

---

## Phase 2: Pod A — The Victim (Namespace: tenant-a)

**Goal:** Deploy the "Crown Jewels" file to the host with a specific SELinux category.

```bash
cat <<EOF | oc apply --as=user001 -f -
apiVersion: v1
kind: Pod
metadata:
  name: pod-a
  namespace: tenant-a
spec:
  nodeSelector:
    type: shared-compute
  serviceAccountName: demo-sa
  securityContext:
    runAsUser: 1000
    seLinuxOptions:
      level: "s0:c1,c1"
  containers:
  - name: main
    image: registry.access.redhat.com/ubi9/ubi
    command: ["sh", "-c", "echo 'TENANT-A-SECRET' > /data/secret.txt; sleep infinity"]
    volumeMounts:
    - name: vol
      mountPath: /data
  volumes:
  - name: vol
    hostPath:
      path: /mnt/shared-data
EOF

```

**Step-by-Step Verification for Pod A:**

```bash
# Verify the Pod is running as UID 1000
oc exec pod-a --as=user001 -n tenant-a -- id

# Verify the file exists on the host path and has the correct SELinux category
oc exec pod-a --as=user001 -n tenant-a -- ls -lZ /data/secret.txt

```

> **Explanation:** Pod A is the owner. It has successfully written a file owned by **UID 1000** with the SELinux label **`s0:c1,c1`**.

---

## Phase 3: Pod B — The Blocked Breakout (Namespace: tenant-b)

**Goal:** Show that UID collision (1000 vs 1000) is defeated by SELinux categories.

```bash
cat <<EOF | oc apply --as=user001 -f -
apiVersion: v1
kind: Pod
metadata:
  name: pod-b
  namespace: tenant-b
spec:
  nodeSelector:
    type: shared-compute
  serviceAccountName: demo-sa
  securityContext:
    runAsUser: 1000
    seLinuxOptions:
      level: "s0:c2,c2"
  containers:
  - name: main
    image: registry.access.redhat.com/ubi9/ubi
    command: ["sh", "-c", "sleep infinity"]
    volumeMounts:
    - name: vol
      mountPath: /data
  volumes:
  - name: vol
    hostPath:
      path: /mnt/shared-data
EOF

```

**Step-by-Step Verification for Pod B:**

```bash
# Confirm Pod B is also UID 1000 (Collision)
oc exec pod-b --as=user001 -n tenant-b -- id

# Attempt to read the victim's data
oc exec pod-b --as=user001 -n tenant-b -- cat /data/secret.txt

```

> **Explanation:** **PERMISSION DENIED.** Despite being the same user (UID 1000) on the same host path, the kernel prevents the read because the MCS labels do not match (**MAC Failure**). Category `c2,c2` is not authorized to read `c1,c1`.

---

## Phase 4: Pod E — DAC Block (Namespace: tenant-b)

**Goal:** Demonstrate that even if SELinux labels match, standard Linux DAC still applies.

```bash
cat <<EOF | oc apply --as=user001 -f -
apiVersion: v1
kind: Pod
metadata:
  name: pod-e
  namespace: tenant-b
spec:
  nodeSelector:
    type: shared-compute
  serviceAccountName: demo-sa
  securityContext:
    runAsUser: 2000
    seLinuxOptions:
      level: "s0:c1,c1"
  containers:
  - name: main
    image: registry.access.redhat.com/ubi9/ubi
    command: ["sh", "-c", "sleep infinity"]
    volumeMounts:
    - name: vol
      mountPath: /data
  volumes:
  - name: vol
    hostPath:
      path: /mnt/shared-data
EOF

```

**Step-by-Step Verification for Pod E:**

```bash
# Attempt to read the victim's data with matching labels but different UID
oc exec pod-e --as=user001 -n tenant-b -- id
oc exec pod-e --as=user001 -n tenant-b -- ls -la /data/
oc exec pod-e --as=user001 -n tenant-b -- cat /data/secret.txt

```

> **Explanation:** **PERMISSION DENIED.** SELinux allowed the access (labels match), but standard Linux permissions blocked it because UID 2000 does not own the directory or the file (**DAC Failure**). This shows that UID isolation is still a critical secondary layer.

---

## Phase 5: Pod C — The Privileged Thief (Namespace: tenant-b)

**Goal:** Demonstrate that theft only occurs if a user is allowed to spoof BOTH the UID and the SELinux label.

```bash
cat <<EOF | oc apply --as=user001 -f -
apiVersion: v1
kind: Pod
metadata:
  name: pod-c
  namespace: tenant-b
spec:
  nodeSelector:
    type: shared-compute
  serviceAccountName: demo-sa
  securityContext:
    runAsUser: 1000
    seLinuxOptions:
      level: "s0:c1,c1"
  containers:
  - name: main
    image: registry.access.redhat.com/ubi9/ubi
    command: ["sh", "-c", "sleep infinity"]
    volumeMounts:
    - name: vol
      mountPath: /data
  volumes:
  - name: vol
    hostPath:
      path: /mnt/shared-data
EOF
```

**Step-by-Step Verification for Pod C:**

```bash
# Attempt to read the victim's data with matching labels
oc exec pod-c --as=user001 -n tenant-b -- id
oc exec pod-c --as=user001 -n tenant-b -- cat /data/secret.txt
```

> **Explanation:** **ACCESS GRANTED.** Pod C can read the data because it was explicitly allowed (via a custom SCC set to `RunAsAny`) to assume the `c1,c1` identity. This proves SELinux is the only real barrier if UIDs are compromised.

---

## Phase 6: The Spoofing Wall — Admission Failure (Namespace: tenant-b)

**Goal:** Show that standard SCCs (restricted and anyuid) block identity theft at the API level.

```bash
# 1. Attempt using a restricted SCC
cat <<EOF | oc apply --as=user001 -n tenant-b -f -
apiVersion: v1
kind: Pod
metadata:
  name: pod-d
spec:
  nodeSelector:
    type: shared-compute
  securityContext:
    runAsUser: 1000
    seLinuxOptions:
      level: "s0:c1,c1"
  containers:
  - name: main
    image: registry.access.redhat.com/ubi9/ubi
    command: ["sh", "-c", "sleep infinity"]
EOF

# 2. Attempt using standard 'anyuid' SCC (which is MustRunAs on this cluster)
oc create sa anyuid-sa -n tenant-b
oc adm policy add-scc-to-user anyuid -z anyuid-sa -n tenant-b

cat <<EOF | oc apply --as=user001 -n tenant-b -f -
apiVersion: v1
kind: Pod
metadata:
  name: pod-f
spec:
  nodeSelector:
    type: shared-compute
  serviceAccountName: anyuid-sa
  securityContext:
    runAsUser: 1000
    seLinuxOptions:
      level: "s0:c1,c1"
  containers:
  - name: main
    image: registry.access.redhat.com/ubi9/ubi
    command: ["sh", "-c", "sleep infinity"]
EOF
```

> **Explanation:** **REJECTED.** The Admission Controller sees the user trying to "lie" about their SELinux level and blocks the pod before the kernel even sees it. This applies to both the default `restricted` SCC and the `anyuid` SCC (which often defaults to `MustRunAs` for SELinux).

---

## Phase 7: The "Root" Myth — Root User vs. SELinux Policy

**Goal:** Demonstrate that running as **Root (UID 0)** inside a container does NOT grant valid Root permissions on the host filesystem if SELinux is enforcing.

```bash
cat <<EOF | oc apply --as=user001 -f -
apiVersion: v1
kind: Pod
metadata:
  name: pod-root-fail
  namespace: tenant-b
spec:
  nodeSelector:
    type: shared-compute
  serviceAccountName: demo-sa
  securityContext:
    runAsUser: 0
  containers:
  - name: main
    image: registry.access.redhat.com/ubi9/ubi
    command: ["sh", "-c", "sleep infinity"]
    volumeMounts:
    - name: host-root
      mountPath: /host
  volumes:
  - name: host-root
    hostPath:
      path: /
EOF
```

In this final phase, we act as an attacker who has successfully deployed a Pod as **Root (UID 0)** with the entire **Host Filesystem** mounted at `/host`. We will now attempt to leverage this position to compromise the node by modifying system files and stealing data from other tenants.

```bash
# 1. Verify we are UID 0 (Root)
oc exec pod-root-fail --as=user001 -n tenant-b -- id
# Output: uid=0(root) gid=0(root) groups=0(root)

# 2. Verify we see the Host Filesystem
oc exec pod-root-fail --as=user001 -n tenant-b -- ls -la /host/root/

# 3. Attempt to exploit: Write a file to the host's /etc directory
oc exec pod-root-fail --as=user001 -n tenant-b -- touch /host/tmp/hacked

# 4. Attempted Confidentiality Breach: THE DYNAMIC HEIST
# -------------------------------------------------------------------------
# A. Create a "Hidden" file inside Pod-A (Tenant-A)
oc exec pod-a -n tenant-a -- sh -c "echo 'password' > /tmp/tenant-a-secret.txt"

# B. DYNAMIC DISCOVERY: Find the physical 'diff' path of Pod-A from Tenant-B
# We talk to the CRI socket (mounted in our pod) to find the victim's disk location.
# We first identify the node where the lab is running.
NODE_NAME=$(oc get nodes -l type=shared-compute -o jsonpath='{.items[0].metadata.name}')

VICTIM_DIFF=$(oc debug node/$NODE_NAME -q -- chroot /host /bin/sh -c "crictl inspect \$(crictl ps --label io.kubernetes.pod.name=pod-a -q)" 2>/dev/null | grep -oP '/var/lib/containers/storage/overlay/[a-z0-9]+/merged' | head -n 1 | sed 's/merged/diff/')

# We check the file from the NODE (Admin Access - Should Work)
oc debug node/$NODE_NAME -q -- cat /host/${VICTIM_DIFF}/tmp/tenant-a-secret.txt 2>/dev/null 

# C. THE EXTRACTION: Read the file from the Host Root mount (Tenant Access - Should Fail)
oc exec pod-root-fail --as=user001 -n tenant-b -- cat /host${VICTIM_DIFF}/tmp/tenant-a-secret.txt
```

> **Explanation:** **PERMISSION DENIED (FULL PROTECTION).**

> *   **Host Admin (Successful):** The `oc debug node` command (Step B) succeeded because it runs as a **Privileged** container, which disables SELinux.
> *   **Malicious Tenant (Blocked):** The `pod-root-fail` (Step C) **FAILED** to read the secret. Even though it is UID 0 and has `hostPath` access, the SELinux label `container_t` is blocked from reading the `container_var_lib_t` storage layer.
>
> **Conclusion:** SELinux successfully neutralizes the "Root" user. Even with `hostPath` and `runAsUser: 0`, the attacker cannot compromise the host OS vs other tenants.

---

# Conclusion: Why SCCs are Powerful

SCCs are the **Platform Trust Boundary** that turns Kubernetes into a secure, multi-tenant platform.

1. **Prevention of Identity Spoofing:** Unlike standard Kubernetes, SCCs prevent a pod from "impersonating" another tenant by validating every UID and SELinux label request.
2. **The Two-Key Lock:** OpenShift security relies on a two-key lock. The **SCC** prevents identity spoofing at the API level (Governance), and **SELinux** prevents data access at the Kernel level (Enforcement).
3. **The Default Win:** By using **Restricted SCCs**, OpenShift ensures that even if a container is compromised, it cannot assume the identity needed to bypass the Kernel-level MAC barriers.