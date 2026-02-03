This is the definitive, end-to-end lab for **User Namespaces** on OpenShift, based on the official documentation and verified by your previous tests.

This lab proves that a pod running as **UID 1000** inside the container is remapped to a **massive, unprivileged UID** on the host worker node, effectively "jailing" the process.

---

### Official Lab: Non-Root User Namespaces (v3)

#### 1. Cluster-Admin: Prepare the Security Boundary

The cluster administrator must define the remapping range and grant the user permission to operate in a high-security namespace.

```bash
# A. Create the project and assign 'user001' as the admin
oc new-project userns-lab
oc adm policy add-role-to-user admin user001 -n userns-lab

# B. Configure the UID/GID remapping range (Official Requirement)
# This annotation tells CRI-O to map internal IDs starting at 1000.
oc patch namespace userns-lab --type='merge' -p '
{
  "metadata": {
    "annotations": {
      "openshift.io/sa.scc.uid-range": "1000/10000",
      "openshift.io/sa.scc.supplemental-groups": "1000/10000"
    }
  }
}'

# C. Grant 'restricted-v3' to the default ServiceAccount
# This allows the pod to pass the admission controller while using hostUsers: false.
oc adm policy add-scc-to-user restricted-v3 -z default -n userns-lab

```

---

#### 2. user001: Deploy the Isolated Pod

Now, acting as **user001**, deploy the manifest. We strip the blocked capabilities (`SETUID`/`SETGID`) to satisfy the `restricted-v3` policy.

```bash
cat <<EOF | oc apply -f - --as=user001
apiVersion: v1
kind: Pod
metadata:
  name: userns-pod
  namespace: userns-lab
spec:
  hostUsers: false  # <--- THE MAGIC SWITCH: Triggers User Namespace
  securityContext:
    runAsNonRoot: true
    seccompProfile:
      type: RuntimeDefault
  containers:
  - name: userns-container
    image: registry.access.redhat.com/ubi9:latest
    command: ["sleep", "infinity"]
    securityContext:
      runAsUser: 1000   # Must match the namespace annotation range
      runAsGroup: 1000
      runAsNonRoot: true
      procMount: Unmasked
EOF

```

---

#### 3. Verification: The Double Reality

**Step A: Inside Reality (The Pod's view)**
Verify that the process believes it is a standard non-root user.

```bash
oc exec userns-pod -n userns-lab -- id

```

> **Output:** `uid=1000(1000) gid=1000(1000) groups=1000(1000)`

**Step B: Host Reality (The Security view)**
We will find the exact process on the worker node and reveal its **true** identity on the host.

```bash
# 1. Identify the worker node
NODE=$(oc get pod userns-pod -n userns-lab -o jsonpath='{.spec.nodeName}')

# 2. Run the targeted host inspection
oc debug node/$NODE -q -- chroot /host /bin/sh -c "
  # Find the specific container ID
  CONT_ID=\$(crictl ps --name userns-container -q | head -n 1)
  
  # Extract the Host PID
  PID=\$(crictl inspect \$CONT_ID | grep '\"pid\":' | head -n 1 | awk -F: '{print \$2}' | tr -d ' ,')
  
  echo '--- HOST SYSTEM VIEW ---'
  # We check the owner of the /proc entry to avoid 'ps' integer overflow issues
  ls -ld /proc/\$PID | awk '{print \"Host-Level UID: \" \$3 \" | Host-Level GID: \" \$4}'
"

```

---

### Final Analysis

* **Result:** You will see a UID like `3938583528`.
* **The Difference:** Inside the pod, the process thinks it is **1000**. On the host, it is **3.9 Billion**.
* **The Security Win:** If a vulnerability (like a container escape) were found in the kernel, the attacker would land on the host as an ID that doesn't exist in `/etc/passwd`. They would have **zero permissions** to read files, modify system settings, or interfere with other tenants.

---

### Why this lab is critical

By using `user001` and `restricted-v3`, you have successfully implemented **Least Privilege** + **Defense in Depth**. You didn't just run a container; you created a cryptographically isolated sandbox that the host doesn't even "recognize" as a valid system user.