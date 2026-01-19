# OpenShift Zero-Trust and Governance: Master Demo Guide

This repository provides a comprehensive walkthrough for implementing enterprise-grade security on OpenShift. To present a logical and high-impact story, follow these modules in the order listed below.

---

## Module 1: Secure Multi-Tenancy & Project Governance

**Focus:** Multi-tenancy and Day-0 Governance

Before users onboard, we define the infrastructure standards. This module demonstrates how to automate the provisioning of secured environments so that security is a default property of the platform.

* **Overview:** [Multi-Tenancy Strategy](rbac/multi-tenancy.md)
* **Hands-on Demo:** [Automated Project Provisioning](rbac/project-demo.md)
* **Goal:** Automatically provision isolated namespaces with embedded security guardrails using Custom Project Templates.

---

## Module 2: Identity and Access Management

**Focus:** Authentication and Least Privilege

Once the projects exist, we define who can enter them and what they are permitted to access.

* **Overview:** [RBAC Fundamentals](rbac/rbac-intro.md)
* **Advanced Case:** [Granular Custom Roles](rbac/custom-roles.md)
* **Goal:** Use auth checks to demonstrate that a developer can manage their own applications but cannot access sensitive payment secrets or cluster-wide configurations.

---

## Module 3: Admission Control & Enforcement

**Focus:** Resource Guardrails and Pod Security

Show what happens when applications attempt to exceed their resource limits or bypass pod-level security constraints.

* **Overview:** [IAM and Admission Control Overview](admissioncontrols/README.md)
* **The Budget:** [Resource Quotas](admissioncontrols/quota.md) and [Cluster-Wide Quotas](admissioncontrols/ClusterResourceQuota.md)
* **The Rules:** [LimitRanges](admissioncontrols/limits.md) (Container rightsizing)
* **The Hardware Lock:** [Security Context Constraints (SCC)](admissioncontrols/scc.md) (Blocking Root access)
* **Goal:** Prove the cluster's ability to self-enforce security by blocking privileged pods and automatically rightsizing deployments.

---

## Module 4: Policy as Code & Supply Chain Security

**Focus:** Declarative validation and Image Supply Chain

Utilize native Kubernetes features to enforce corporate standards without requiring external agents.

* **Overview:** [Validating Admission Policy (VAP) Overview](admissioncontrols/vap/README.md)
* **Validating Admission Demo:** [Validating Admission Policies](admissioncontrols/vap/vap-demo.md)
* **Validating Admission Manifests:** [Supply Chain and Pod Security](admissioncontrols/vap/manifests/)
* **RHACS Policy:** [ACS Policy-as-Code](acs-policy-as-code/README.md)
* **Goal:** Block pods from unauthorized registries and prevent risky configurations using native API-driven policies.

---

## Module 5: Network Security & Isolation

**Focus:** Microservice Isolation

Secure data in transit and prevent lateral movement between application tiers such as frontend, backend, and payments.

* **Overview:** [Network Policies Overview](networking/README.md)
* **Network Policy - Demo:** [Protecting the Network](networking/networkpolicies/protecting-the-network-using-networkpolicies.md)
* **Admin Network Policies - Demo:** [AdminNetworkPolicies (ANP)](networking/networkpolicies/anp-demo.md)
* **Admin Network Policies Reference:** [Admin Network Policies Reference](networking/networkpolicies/adminnetworkpolicies.md)
* **Goal:** Use AdminNetworkPolicies to enforce global rules that remain immutable even if project owners attempt to override them.

---

## Module 6: Compliance & Threat Detection

**Focus:** Continuous Monitoring and Vulnerability Management

Verify that the cluster remains compliant over its entire lifecycle and detect real-world threats.

* **Overview:** [The 10 Essential Controls](compliance/README.md)
* **Compliance Scan:** [Compliance Operator Demo](compliance/compliance-operator-demo.md)
* **Configuration:** [Compliance Operator Variables](compliance/compliance-operator-variables.md)
* **Concepts:** [Architecture and Threat Awareness](compliance/architecture%20and%20threat%20awareness.md)
* **Goal:** Scan against NIST/PCI-DSS standards and detect runtime vulnerabilities like Log4shell.

---

## Module 7: Incident Response & Forensics

**Focus:** Post-Mortem Analysis

The final stage covers how to react and investigate when a security event occurs.

* **Overview:** [OpenShift Audit Log Forensics Overview](auditing/README.md)
* **Audit Investigation:** [Mastering Audit Logs](auditing/audit-log-Investigation.md)
* **Visualizing History:** [Kubectl Timemachine](auditing/kubectl-timemachine-instructions.md)
* **Goal:** Use forensic tools to search through audit logs and identify the specific actors behind unauthorized access or privilege escalation.

---