# Lab: Implementing Least Privilege Governance with Custom SCCs

## Introduction: The "Golden Path" Strategy

In a regulated environment, you often need more control than the default `restricted-v2` SCC provides. You might need to ensure that specific workloads only run as a predefined User ID (UID) or within a specific SELinux compartment, regardless of what the developer requests.

This lab demonstrates how to create a **Custom Security Context Constraint (SCC)** that acts as a strict governance policy. We will implement a "Bucket" strategy where we force a workload to adopt a specific identity (`UID 1000` and `s0:c500,c600`), proving that the Platform Admin holds the ultimate authority over runtime identity.

---

## Phase 1: Environment Setup

We establish a clean project and a restricted ServiceAccount to act as our tenant.

```bash
# 1. Create the tenant project
oc new-project scc-governance-lab

# 2. Create the ServiceAccount
oc create sa governed-sa -n scc-governance-lab

# 3. Create a restricted user context for testing
oc create user user001 2>/dev/null || true
oc adm policy add-role-to-user admin user001 -n scc-governance-lab

```

---

## Phase 2: Create the Custom "Bucket" SCC

We will build an SCC based on the `restricted-v2` profile. It allows the pod to run as **UID 1000**, but it forces the SELinux identity into a specific **"Bucket" (c500,c600)**.

> **Technical Note:** In OpenShift SCCs, the `MustRunAs` strategy for SELinux acts as a validator. It requires that the Pod's request matches the SCC's level exactly.

```yaml
cat <<EOF | oc apply -f -
apiVersion: security.openshift.io/v1
kind: SecurityContextConstraints
metadata:
  name: scc-enforced-governance
allowPrivilegedContainer: false
allowPrivilegeEscalation: false
requiredDropCapabilities: ["ALL"]
runAsUser:
  type: MustRunAsRange
  uidRangeMin: 1000
  uidRangeMax: 1000
seLinuxContext:
  type: MustRunAs           # <--- THE ENFORCER: Forces a specific label
  seLinuxOptions:
    level: "s0:c500,c600"    # <--- THE BUCKET: The only allowed identity
volumes: ["configMap", "downwardAPI", "emptyDir", "secret"]
EOF

# Grant the SCC to the tenant
oc adm policy add-scc-to-user scc-enforced-governance -z governed-sa -n scc-governance-lab

```

---

## Phase 3: The "Success" Case (Explicit Compliance)

The developer requests the exact identity allowed by their governance policy. This shows the "Least Privilege" model in a functional state.

```bash
cat <<EOF | oc apply --as=user001 -n scc-governance-lab -f -
apiVersion: v1
kind: Pod
metadata: { name: pod-compliant }
spec:
  serviceAccountName: governed-sa
  securityContext:
    runAsUser: 1000
    seLinuxOptions: { level: "s0:c500,c600" } # Matches the SCC
  containers:
  - name: main
    image: registry.access.redhat.com/ubi9/ubi
    command: ["sh", "-c", "sleep infinity"]
EOF

```

**Verification:**

```bash
oc get pod pod-compliant -n scc-governance-lab -o jsonpath='{.spec.securityContext.seLinuxOptions.level}'
# Result: s0:c500,c600 (Validated and Admitted)

```

---

## Phase 4: The "Auto-Pilot" Success (Implicit Compliance)

Here we prove that the developer **doesn't even need to know** the security requirements. Because the SCC forces the identity, the Admission Controller automates the security context injection.

```bash
cat <<EOF | oc apply --as=user001 -n scc-governance-lab -f -
apiVersion: v1
kind: Pod
metadata: { name: pod-autopilot }
spec:
  serviceAccountName: governed-sa
  containers:
  - name: main
    image: registry.access.redhat.com/ubi9/ubi
    command: ["sh", "-c", "sleep infinity"]
EOF
```

**Verification:**

```bash
# Check that the SCC automatically injected the correct "Bucket" label
oc get pod pod-autopilot -n scc-governance-lab -o jsonpath='{.spec.securityContext.seLinuxOptions.level}'
# Result: s0:c500,c600 (Automatically Injected!)
```

---

## Phase 5: The "Attack" Case (Spoofing Attempt)

An attacker tries to "impersonate" a victim in another namespace by requesting the level **s0:c1,c1**. Because our SCC is set to `MustRunAs`, the Admission Controller kills the request.

```bash
cat <<EOF | oc apply --as=user001 -n scc-governance-lab -f -
apiVersion: v1
kind: Pod
metadata: { name: pod-bypass-attempt }
spec:
  serviceAccountName: governed-sa
  securityContext:
    runAsUser: 1000
    seLinuxOptions: { level: "s0:c1,c1" } # THE SPOOF: Not in the bucket
  containers:
  - name: main
    image: registry.access.redhat.com/ubi9/ubi
    command: ["sh", "-c", "sleep infinity"]
EOF

```

**Verification:**
Observe the terminal error.

> **Result:** `Forbidden`. The error message will explicitly state: `Invalid value: "s0:c1,c1": must be s0:c500,c600`.

---

# Summary Table: DAC vs. MAC vs. SCC

| Security Layer | Role in this Lab | Failure Mode (Pod C) | Success Mode (This Lab) |
| --- | --- | --- | --- |
| **SCC (API)** | **Governance** | `RunAsAny` allows spoofing. | `MustRunAs` blocks spoofing. |
| **UID (DAC)** | **Filesystem** | UID overlap permits entry. | UID range prevents root. |
| **MCS (MAC)** | **Kernel** | Matching labels permit read. | Unique labels block read. |

---

# Conclusion: The Power of Custom SCCs

By tailoring an SCC to the specific needs of a workload, you move away from **"God Mode"** configurations (`privileged`, `anyuid`) and into **"Enforced Multi-tenancy."**

1. **Identity Control:** The SCC acts as the "First Lock," ensuring a Pod cannot even *claim* to be someone else.
2. **Zero Inference:** We don't guess what the user needs; we define a bucket and force them to stay inside it.
3. **The Result:** Even if an attacker finds a way to overlap a UID, they are trapped by an SELinux label they are physically incapable of changing.
