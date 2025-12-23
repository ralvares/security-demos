# The 10 Essential Controls: A Unified Kubernetes Security Playbook

A secure Kubernetes platform is not built by chasing individual checkboxes for every new regulation. It is built by layering a continuous set of controls that satisfy the *intent* of almost every major framework simultaneously.

Whether you are aligning to PCI, ISO, NIST, or CIS, the fundamentals are identical: verify what you run, harden how it runs, restrict who can do what, and prove the platform’s behavior over time. The following 10 areas represent a "write once, comply everywhere" strategy using OpenShift native capabilities.

### 1\. The Trusted Supply Chain

Security starts before the cluster even sees a workload. If you don't trust the source, you can't trust the runtime.

**The Risk:** Mitigates **Supply Chain Vulnerabilities**. Attackers often compromise third-party images or dependencies to bypass perimeter defenses, injecting malicious code before deployment even occurs.

  * **Provenance:** Every image must come from an allowed registry, pinned by digest (immutable), and signed.
  * **Vulnerability Gating:** Images with critical, fixable vulnerabilities are blocked at the pipeline level. This eliminates the "unknowns" before they ever reach deployment.

### 2\. Hardened Configuration

A trusted image configured insecurely is still a vulnerability.

**The Risk:** Prevents **Container Escape**. Misconfigured workloads (e.g., running as root or privileged) allow attackers to break out of the container boundary, gain control of the underlying node, and compromise the entire cluster.

  * **Guardrails:** OpenShift’s **Security Context Constraints (SCC)** and **Pod Security Admission** prevent dangerous configurations by default.
  * **Enforcement:** Capabilities like running as root, privilege escalation, or accessing host filesystems are blocked automatically, aligning the platform with CIS benchmarks without manual intervention.

### 3\. Identity & Least Privilege

Identity is the new perimeter.

**The Risk:** Stops **Privilege Escalation**. Attackers hunt for over-privileged accounts (like a CI/CD service account with admin rights). If they find one, they can silently elevate their access to take over the entire domain.

  * **RBAC:** Every action is tied to an explicit permission. "Cluster-admin" access is severely restricted to a break-glass role.
  * **Service Accounts:** Workload identities are scoped tightly. This removes silent privilege expansion and ensures that every administrative action is predictable and defensible.

### 4\. Network Governance

Flat networks are a gift to attackers. If one pod is compromised, the rest shouldn't be accessible.

**The Risk:** Limits **Lateral Movement**. In an unsegmented network, a breach in a minor web frontend allows an attacker to directly probe sensitive backend databases or internal management APIs.

  * **Segmentation:** **NetworkPolicy** enforces a "default deny" posture.
  * **Global Control:** **AdminNetworkPolicy** allows security teams to enforce mandatory blocking rules that developers cannot override, making segmentation code-defined, testable, and compliant.

### 5\. Resource Availability

Security includes availability. A runaway process crashing a node is a Denial of Service (DoS) event.

**The Risk:** Prevents **Denial of Service (DoS)**. Without limits, a compromised or buggy pod can consume all available CPU/RAM, starving critical security components (like logging agents) and causing nodes to crash.

  * **Stability:** **LimitRanges** and **ResourceQuotas** enforce boundaries on CPU and memory.
  * **Fairness:** These controls prevent "noisy neighbors" and ensure critical compliance workloads always have the resources they need to run.

### 6\. Vulnerability Lifecycle

Software ages like milk, not wine. Clean images eventually reveal new CVEs.

**The Risk:** Addresses **Vulnerable Application Components**. Attackers automate the scanning of public endpoints for known, unpatched vulnerabilities (like Log4j). Static software eventually becomes a "sitting duck."

  * **Continuous Scanning:** Runtime scanning detects risks that appear after deployment.
  * **SLA Enforcement:** The goal isn't zero bugs; it's consistent remediation (e.g., "Criticals fixed in 7 days") driven by automated reporting.

### 7\. Runtime Defense

Static analysis can't catch zero-days or logic flaws. You need to see what happens when code runs.

**The Risk:** Detects **Silent Persistence**. Static tools miss "fileless" attacks or zero-day exploits. Without runtime visibility, an attacker can dwell inside a running container for months, exfiltrating data without ever modifying a file.

  * **Behavioral Monitoring:** Runtime tools detect unexpected shells, crypto-mining patterns, or suspicious network calls.
  * **Incident Response:** These alerts link directly to operational workflows, proving to auditors that you are actively watching the shop.

### 8\. Secret Management

Credentials are the keys to the kingdom.

**The Risk:** Prevents **Credential Theft**. Hardcoded secrets in Git or environment variables are easily scraped. Once stolen, these keys allow attackers to bypass controls and access external sensitive data directly.

  * **Encryption:** Secrets are encrypted at rest and never embedded in container images or Git.
  * **Rotation:** Integration with external secret managers ensures credentials are short-lived, minimizing the blast radius of any leak.

### 9\. Audit & Evidence

If you didn't log it, it didn't happen.

**The Risk:** Eliminates the **Compliance Blind Spot**. If logs are missing or mutable, you cannot investigate a breach, nor can you prove to auditors that a breach *didn't* happen.

  * **Immutability:** Audit logs, event streams, and infrastructure logs are shipped to immutable external storage.
  * **Reproducibility:** You can answer "Who, What, When, and How" for every change, which is the foundation of every audit.

### 10\. Governance & Exceptions

Rigid rules break. Smart rules bend but track the variance.

**The Risk:** Controls **Policy Drift**. "Temporary" fixes often become permanent backdoors. Without a lifecycle for exceptions, the platform slowly accumulates security debt until strict policies are no longer effective.

  * **Discipline:** Exceptions (e.g., a temporary privileged pod) are formally tracked with justification and expiry dates.
  * **Findings:** When an exception expires, it becomes a finding. This prevents temporary allowances from becoming permanent, silent risks.

-----

# Automating the Audit: The Compliance Operator

Implementing these controls is step one. **Proving** them continuously is step two.

Most frameworks ask for similar things, which is why the **Compliance Operator** is essential. It automates the "boring" work of checking your cluster against standard profiles (CIS, PCI-DSS, NIST) and producing the evidence auditors expect.

However, real-world compliance is rarely just "vanilla CIS." Auditors often have unique, organization-specific demands that standard profiles miss.

## Going Beyond Standard Profiles: CustomRules

What happens when your security team requires something unique?

  * *“Show me that no developers have access to the `central-db` namespace.”*
  * *“Prove that only the SRE team has `cluster-admin` rights.”*
  * *“Ensure no application is running a 'shadow' database outside of approved areas.”*

Historically, this meant writing brittle bash scripts or manual verification. Now, with the **CustomRule** CRD (currently in Tech Preview), you can codify these bespoke policies using the Common Expression Language (CEL) and run them alongside your standard compliance scans.

### How CustomRules Work

A `CustomRule` allows you to write simple logic to check Kubernetes resources. The operator runs these rules and reports success or failure just like it does for a standard CIS check.

#### Example 1: The "Cluster-Admin" Audit

This rule enforces a strict allow-list for the `cluster-admin` role. It fails if anyone *not* on the list holds that permission.

```yaml
apiVersion: compliance.openshift.io/v1alpha1
kind: CustomRule
metadata:
  name: cluster-admin-allow-list
spec:
  title: Audit cluster-admin access against an allow-list
  severity: high
  scannerType: CEL
  inputs:
    - name: crbs
      kubernetesInputSpec:
        apiVersion: rbac.authorization.k8s.io/v1
        resource: clusterrolebindings
  expression: |-
    crbs.items.filter(crb, crb.metadata.name == 'cluster-admin')[0]
      .subjects.all(subject,
        (subject.kind == 'User' && subject.name in ['kubeadmin', 'alice@company.com']) ||
        (subject.kind == 'Group' && subject.name in ['system:masters', 'sre-team'])
      )
```

#### Example 2: The "Shadow Database" Detector

This rule scans application namespaces to ensure no one is spinning up unapproved databases (like Postgres or Mongo) outside of the dedicated database team's control.

```yaml
apiVersion: compliance.openshift.io/v1alpha1
kind: CustomRule
metadata:
  name: disallow-shadow-databases
spec:
  title: Disallow Unapproved Database Pods
  severity: high
  scannerType: CEL
  inputs:
    - name: pods
      kubernetesInputSpec:
        apiVersion: v1
        resource: pods
  expression: |
    pods.items.all(pod,
      pod.metadata.namespace in ['central-dba-prod'] ||
      pod.spec.containers.all(c, 
        !['postgres','mysql','mongo','redis'].exists(db, c.image.contains(db))
      )
    )
```

### The Workflow: From YAML to Evidence

1.  **Define:** Create your `CustomRule` manifests (like the examples above).
2.  **Bundle:** Add them to a `TailoredProfile`. This tells the operator, "Run the standard CIS checks, but *also* run my custom SQL check."
3.  **Scan:** Bind the profile to a `ScanSetting` and let it run.
4.  **Report:** Review the results via `oc get compliancecheckresults`.


### Summary

By combining the **10 Essential Controls** with the **Compliance Operator**, you move from "Compliance as a barrier" to "Compliance as code." You verify the foundation with native controls, and you prove the specific, unique requirements of your organization with CustomRules—all in one automated workflow.

---

## Further Reading & Demos

- [Compliance Operator CustomRule Demo](./compliance-operator-demo.md)