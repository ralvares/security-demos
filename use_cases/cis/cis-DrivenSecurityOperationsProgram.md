## The CIS-Driven Security Operations Program

**Framework Reference:** CIS - v8

The CIS Center for Internet Security Top 18 Critical Security Controls (v8) are a prioritized framework of best practices designed to stop the most common and pervasive cyberattacks. These 18 controls, organized into Basic, Foundational, and Organizational categories, focus on actionable, technical, and administrative safeguards for essential cyber hygiene, moving from asset management to advanced threat defense.

### The 18 CIS Critical Security Controls (v8):

1. Inventory and Control of Enterprise Assets: Actively manage all hardware devices.
2. Inventory and Control of Software Assets: Actively manage all software.
3. Data Protection: Identify, classify, and protect sensitive data.
4. Secure Configuration of Enterprise Assets and Software: Maintain hardened security settings.
5. Account Management: Manage, monitor, and restrict user accounts.
6. Access Control Management: Control access to assets and data.
7. Continuous Vulnerability Management: Assess and remediate vulnerabilities.
8. Audit Log Management: Collect and analyze logs to detect threats.
9. Email and Web Browser Protections: Secure web and email tools.
10. Malware Defenses: Prevent or detect malicious code execution.
11. Data Recovery: Implement data backup and recovery.
12. Network Infrastructure Management: Secure network devices.
13. Network Monitoring and Defense: Defend against network threats.
14. Security Awareness and Skills Training: Train personnel on security risks.
15. Service Provider Management: Manage service provider security.
16. Application Software Security: Secure internally developed or acquired software.
17. Incident Response Management: Plan and execute incident response.
18. Penetration Testing: Test effectiveness of security controls.

The controls are implemented in three Implementation Groups (IGs) to accommodate different resource levels, with IG1 representing essential cyber hygiene. 


This program is built on four "Workstreams" that turn RHACS data into a repeatable operational rhythm. These workstreams rely on the CIS Controls to focus efforts on the most critical security functions.

### 1. The Asset & Software Baseline (CIS Controls 1 & 2)

**Goal:** Define what is "Authorized" versus "Unauthorized."

* **The Rule:** No container runs without a **Technical Owner** and an **Approved Registry** source.
* **The Action:** Use RHACS to identify "Orphaned" deployments (no owner) or images from "Public/Unscanned" registries.
* **The Response:** If a deployment violates these rules, it is flagged for **Decommissioning**.

### 2. Configuration Hardening (CIS Control 4)

**Goal:** Eliminate **Misconfigurations** that increase the attack surface.

* **The Rule:** All workloads must meet the **CIS OpenShift Benchmark** (e.g., No Root, No Host IPC).
* **The Action:** Focus on the **Critical Security Violations** in the RHACS "Violations" tab.

    1. Privileged Containers.
    2. Containers running as Root.
    3. Host Mounts (Writable).
    4. Missing Network Policies.
    5. No Resource Limits.
    6. Secrets as Environment Variables.
    7. Host Network Access (`hostNetwork: true`).
    8. Privilege Escalation Allowed (`allowPrivilegeEscalation`).
    9. Dangerous Capabilities (e.g., `CAP_SYS_ADMIN`, `NET_ADMIN`).


* **The Response:** These are **not** patches; these are **YAML changes**. The SRE team must update the Deployment or use OpenShift SCCs to block these behaviors.

### 3. Continuous Vulnerability Management (CIS Control 7)

**Goal:** Prioritize **Critical Exploitable Vulnerabilities** and reduce alert fatigue.

* **The Rule:** Follow the **Risk Prioritization** logic (Critical + Exploited + Exposed + Fixable).

* **The Action (The SLA):**
    * **Critical Risk:** Fix within **3–7 Days**.
    * **High Risk:** Fix within **30 Days**.

* **The Response:** Use the **Remediation Paths**:
    * **Patch:** Update the image.
    * **Mitigate:** Apply a Network Policy to block access to the vulnerable port.
    * **Accept:** Formal sign-off for business-critical apps that can't be patched.


### 4. Network & Runtime Defense (CIS Controls 13 & 17)

**Goal:** Detect and Respond to **Anomalous Activity** in real-time.

* **The Rule:** Any process or network traffic not in the "Baseline" triggers an alert.
* **The Action:** Use the **RHACS Network Graph** to generate "Baseline" policies. Anything outside that (e.g., a pod trying to talk to an external IP) is a violation of **CIS 13**.
* **The Response:** If RHACS triggers a **Runtime Alert** (e.g., "Cryptomining process detected"), this bypasses the standard SLA and moves immediately to your **Incident Response (CIS 17)** process.

---

## Simplified Decision Matrix

When faced with a high volume of alerts, use this logic to determine the immediate course of action:

> **"Is this a CVE or a Configuration Violation?"**
> * **If CVE:** Check for **Fixability, Exploitability & Exposure**. (If yes, adhere to the 7-day remediation SLA).
> * **If Configuration:** Check if it involves **Privileged Access or Root**. (If yes, harden the deployment manifest).
> * **If neither:** Add to the backlog and **defer for future review.**
> 
> 

---