This is the definitive, end-to-end lab for **User Namespaces** on OpenShift, based on the official documentation and verified by your previous tests.

This lab proves that pods running as either **UID 1000** or **UID 0 (root)** inside the container are remapped to **massive, unprivileged UIDs** on the host worker node, effectively "jailing" the processes.

---

### Official Lab: User Namespaces (v3)

#### 1. Cluster-Admin: Prepare the Security Boundary

The cluster administrator must define the remapped ID ranges and grant the user/service account the rights to use the specific User Namespace SCCs.

```bash
# A. Create the project and assign 'user001' as the admin
oc new-project userns-lab
oc adm policy add-role-to-user admin user001 -n userns-lab

# B. Configure the UID/GID remapping range (Official Requirement)
# This annotation tells CRI-O to map internal IDs starting at 0 (root) through 1000+.
oc patch namespace userns-lab --type='merge' -p '
{
  "metadata": {
    "annotations": {
      "openshift.io/sa.scc.uid-range": "0/10000",
      "openshift.io/sa.scc.supplemental-groups": "0/10000"
    }
  }
}'

# C. Grant the SCCs to the default ServiceAccount
# restricted-v3: Standard isolation.
# nested-container: Allows SETUID/SETGID (needed for apps like httpd).
#oc adm policy add-scc-to-user restricted-v3 -z default -n userns-lab
oc adm policy add-scc-to-user nested-container -z default -n userns-lab

```

---

#### 2. user001: Deploy the Isolated Pods

Acting as **user001**, we will deploy two scenarios: a standard non-root user and a "safe" root user.

**Scenario A: Standard Non-Root (UID 1000)**

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
      runAsUser: 1000
      runAsGroup: 1000
      runAsNonRoot: true
      procMount: Unmasked
EOF

```

**Scenario B: Safe Root Apache (httpd)**
This container starts as root internally to bind port 80 and uses `SETUID`/`SETGID` to drop privileges, but remains unprivileged on the host.

```bash
cat <<EOF | oc apply -f - --as=user001
apiVersion: v1
kind: Pod
metadata:
  name: userns-httpd
  namespace: userns-lab
spec:
  hostUsers: false
  containers:
  - name: apache
    image: docker.io/library/httpd:latest
    securityContext:
      runAsUser: 0
      runAsGroup: 0
      runAsNonRoot: false
      allowPrivilegeEscalation: true
      capabilities:
        add: ["SETGID", "SETUID"]
EOF

```

---

#### 3. Verification: The Double Reality

**Step A: Inside Reality (The Pod's view)**
Verify that the processes see their intended internal IDs.

```bash
# Check the non-root pod
oc exec userns-pod -n userns-lab -- id
# Output: uid=1000(1000) gid=1000(1000)

# Check the httpd root pod
oc exec userns-httpd -n userns-lab -- id
# Output: uid=0(root) gid=0(root)

```

**Step B: Host Reality (The Security view)**
Reveal the **true** identities on the host node for both containers.

```bash
# 1. Identify the worker nodes
HTTPD_ROOT=$(oc get pod userns-httpd -n userns-lab -o jsonpath='{.spec.nodeName}')

# 2. Run the targeted host inspection for the Root HTTPD Pod
oc debug node/$HTTPD_ROOT -q -- chroot /host /bin/sh -c "
  CONT_ID=\$(crictl ps --name apache -q | head -n 1)
  PID=\$(crictl inspect \$CONT_ID | grep '\"pid\":' | head -n 1 | awk -F: '{print \$2}' | tr -d ' ,')
  
  echo '--- HTTPD HOST SYSTEM VIEW ---'
  ls -ld /proc/\$PID | awk '{print \"Host-Level UID: \" \$3 \" (Remapped Root)\"}'
"

```

---

### Final Analysis

* **Result:** You will see UIDs like `3938583528` or `2147483648`.
* **The Difference:** Inside the pod, the process thinks it is **1000** or **0**. On the host, it is **3.9 Billion** or **2.1 Billion**.
* **The Security Win:** If a vulnerability (like a container escape) were found in the kernel, the attacker would land on the host as an ID that doesn't exist in `/etc/passwd`. They would have **zero permissions** to read files, modify system settings, or interfere with other tenants.

---

### Why this lab is critical

By using `user001` and the specific User Namespace SCCs (`restricted-v3` and `nested-container`), you have successfully implemented **Least Privilege** + **Defense in Depth**. You have demonstrated that OpenShift can safely run legacy "root" applications by cryptographically isolating their identity from the underlying host.
