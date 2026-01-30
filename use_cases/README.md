# OpenShift Security Use Cases

This repository provides a comprehensive walkthrough for implementing enterprise-grade security on OpenShift. To present a logical and high-impact story, the modules follow a **Defense-in-Depth** approach, layering defenses from infrastructure to runtime.

---

## The RHACS Demo App

This repository uses a purposely vulnerable application to demonstrate real-world attacks and defenses.

* **RHACS Demo App:** [The RHACS Demo Application](demo_app.md)
* **Goal:** Understand the target application, its architecture, and how to deploy it for the hands-on labs.

---

## The CIS Framework - Small Quick Start

**Focus:** Standards and Best Practices

Adopting the Center for Internet Security (CIS) controls to build a data-driven security program and effective vulnerability management.

* **Security Program:** [The CIS-Driven Security Operations Program](cis/cis-DrivenSecurityOperationsProgram.md)
* **Vulnerability Management:** [The CIS-Driven Vulnerability Management Program](cis/cis-ContinuousVulnerabilityManagement.md)
* **Goal:** Align security operations with industry best practices and standards.

---

## Module 1: Architecture, Threats & Security Strategy

**Focus:** Foundation and Threat Modeling

Before implementing controls, we must understand the architecture we are defending and the threats we face. This module sets the strategic baseline for the entire platform.

* **Architecture & Threat Awareness:** [OpenShift Security Architecture & Threat Awareness](compliance/architecture%20and%20threat%20awareness.md)
* **Essential Controls:** [The 10 Essential Controls - A Unified Kubernetes Security Playbook](compliance/README.md)
* **Strategy:** [The 8 Pillars of a Secure Container Platform](compliance/the%208%20pillars%20of%20a%20secure%20container%20platform.md)
* **Business Context:** [The Risk-Driven Business Conversation](compliance/The%20Risk-Driven%20Business%20Conversation.md)
* **Goal:** Understand the "Why" and "What" of container security to effectively implement the "How".

---

## Module 2: Secure Multi-Tenancy & Project Governance

**Focus:** Multi-tenancy and Day-0 Governance

Before users onboard, we define the infrastructure standards. This module demonstrates how to automate the provisioning of secured environments so that security is a default property of the platform.

* **Overview:** [Multi-Tenancy](rbac/multi-tenancy.md)
* **Hands-on Demo:** [Automated Project Provisioning](rbac/project-demo.md)
* **Goal:** Automatically provision isolated namespaces with embedded security guardrails using Custom Project Templates.

---

## Module 3: Identity and Access Management

**Focus:** Authentication and Least Privilege

Once the projects exist, we define who can enter them and what they are permitted to access.

* **Overview:** [RBAC Fundamentals](rbac/rbac-intro.md)
* **Advanced Case:** [Granular Custom Roles](rbac/custom-roles.md)
* **Goal:** Use auth checks to demonstrate that a developer can manage their own applications but cannot access sensitive payment secrets or cluster-wide configurations.

---

## Module 4: Admission Control & Enforcement

**Focus:** Resource Guardrails and Pod Security

Show what happens when applications attempt to exceed their resource limits or bypass pod-level security constraints.

* **Overview:** [IAM and Admission Control Overview](admissioncontrols/README.md)
* **Quotas:** [Resource Quotas](admissioncontrols/quota.md)
* **Cluster-Wide Quotas:** [Cluster-Wide Quotas](admissioncontrols/ClusterResourceQuota.md)
* **Limits:** [LimitRanges](admissioncontrols/limits.md)
* **Security Context Constraints (SCC):**
    * [SCC Fundamentals](admissioncontrols/scc.md)
    * [SCC Defense in Depth - DAC & MAC](admissioncontrols/scc/SCC-LayersOfContainerSecurity.md)
    * [SCC Customization - Demo](admissioncontrols/scc/custom.md)
* **Privileged Containers:** [The Real Danger of Privileged Containers](admissioncontrols/ShadowAPI.md)
* **Validating Admission Policy:** [Validating Admission Policy (VAP) Overview](admissioncontrols/vap/README.md)
* **VAP Demo:** [Validating Admission Demo](admissioncontrols/vap/vap-demo.md)
* **Goal:** Prove the cluster's ability to self-enforce security by blocking privileged pods and automatically rightsizing deployments.

---

## Module 5: Network Security & Isolation

**Focus:** Microservice Isolation

Secure data in transit and prevent lateral movement between application tiers such as frontend, backend, and payments.

* **NetworkPolicies Intro:** [Network Policies Intro](networking/README.md)
* **NetworkPolicies - Demo:** [Network Policies - Demo](networking/networkpolicies/protecting-the-network-using-networkpolicies.md)
* **AdminNetworkPolicies Intro:** [Admin Network Policies Intro](networking/networkpolicies/adminnetworkpolicies.md)
* **AdminNetworkPolicies - Demo:** [AdminNetworkPolicies - Demo](networking/networkpolicies/anp-demo.md)
* **Goal:** Use AdminNetworkPolicies to enforce global rules that remain immutable even if project owners attempt to override them.

---

## Module 6: Compliance

**Focus:** Continuous Monitoring and Vulnerability Management

Verify that the cluster remains compliant over its entire lifecycle.

* **Compliance Scan:** [Compliance Operator Demo](compliance/compliance-operator-demo.md)
* **Configuration:** [Compliance Operator Variables](compliance/compliance-operator-variables.md)
* **Goal:** Scan against NIST/PCI-DSS standards and ensure continuous compliance posture.

---

## Module 7: Incident Response & Forensics

**Focus:** Post-Mortem Analysis

The final stage covers how to react and investigate when a security event occurs.

* **Audit Investigation:** [Mastering Audit Logs & Forensics](auditing/audit-log-Investigation.md)
* **Visualizing History:** [Kubectl Timemachine](auditing/kubectl-timemachine-instructions.md)
* **Goal:** Use forensic tools to search through audit logs and identify the specific actors behind unauthorized access or privilege escalation.

---

## Module 8: Sovereign

**Focus:** Data Residency and Operational Autonomy

Understanding the requirements and characteristics of Sovereign Cloud environments.

* **Overview:** [Sovereign Cloud Overview](sovereign.md)
* **Goal:** Understand data residency, operational autonomy, and compliance with local regulations.
