# OpenShift Audit Log Forensics

This directory contains a complete toolkit and investigation guide for performing forensic analysis on OpenShift/Kubernetes Audit Logs. It is designed to demonstrate how to reconstruct a security incident, from initial access to node compromise, using only the immutable evidence found in the API logs.

## Contents

*   **`forensics.sh`**: A Bash library containing specialized functions to query, filter, and analyze audit logs. It turns raw JSON logs into human-readable forensic artifacts.
*   **`audit-log-Investigation.md`**: A comprehensive, step-by-step tutorial that walks through a simulated breach of a "Visa Payment" application. It uses the library to hunt for the attacker.
*   **`kubectl-timemachine-instructions.md`**: Instructions for using the kubectl-timemachine plugin.
*   **`audit.log.tar.gz`**: A sample audit log file containing the evidence of the simulated attack. Use this if you don't have a live cluster to investigate.

## Getting Started

### Prerequisites
*   **`jq`**: Required for parsing JSON logs.
*   **`column`**: (Standard in most Linux/macOS distros) for formatting output.
*   **`oc`**: OpenShift CLI (optional, only needed if fetching fresh logs from a cluster).

### Setup

1.  **Extract the sample logs:**
    ```bash
    tar -xzvf audit.log.tar.gz
    ```

2.  **Load the forensic library:**
    ```bash
    source forensics.sh
    ```

## The Forensic Toolkit

Once loaded, you have access to the following forensic capabilities:

| Function | Description |
| :--- | :--- |
| `audit_fetch_logs` | Fetch current audit logs from all master nodes. |
| `audit_detect_anonymous_access` | Hunt for `403 Forbidden` probes from unauthenticated sources. |
| `audit_detect_reconnaissance` | Detect `SelfSubjectAccessReview` calls (manual permission enumeration). |
| `audit_detect_resource_harvesting` | Find bulk `List` operations on Secrets, ConfigMaps, and Pods. |
| `audit_detect_privileged_pods` | Alert on the creation of pods with `HostPID` or `Privileged` flags. |
| `audit_detect_exec_sessions` | Identify interactive `oc exec` sessions into pods. |
| `audit_extract_pod_payload` | Extract the Container Image and Command from a pod creation event. |
| `audit_lookup_pod_by_ip` | Correlate an IP address to a Pod using OVN annotations. |
| `audit_track_ip_activity` | Show the full history of actions performed by a specific IP. |
| `audit_track_pod_lifecycle` | Reconstruct the complete timeline of a pod (Creation -> IP -> Events). |
| `audit_detect_admin_grants` | Detect creation of `ClusterRoleBinding` to `cluster-admin`. |
| `audit_detect_port_forward` | Detect usage of `oc port-forward` tunneling. |
| `audit_detect_node_debug` | Detect usage of `oc debug node` (Root Shell on Host). |
| `audit_detect_sensitive_mounts` | Detect pods mounting `/etc/kubernetes` or container sockets. |
| `audit_detect_bruteforce` | Identify top sources of `401 Unauthorized` errors. |

## The Investigation Scenario

The included guide (`audit-log-Investigation.md`) covers a "Kill Chain" scenario involving:
1.  **Initial Access:** Exploiting a vulnerability in a frontend service (`asset-cache`).
2.  **Lateral Movement:** Stealing a Service Account token.
3.  **Privilege Escalation:** Abusing `cluster-admin` rights.
4.  **Persistence/Action:** Escaping to the underlying Node using a privileged pod.

Follow the guide to learn how to use the toolkit to uncover each step of this attack.

## Kubectl Timemachine

The `kubectl-timemachine` plugin allows you to "travel back in time" and view the state of the cluster as it was recorded in the audit logs. It reconstructs resources (like Pods) from the audit events.

### Example Usage

```bash
➜  ~ kubectl timemachine --auditlog-file=audit.log get pods -n payments -o wide 
NAMESPACE  NAME                                   AGE  STATUS   IP            NODE    
payments   gateway-79d69c8875-72kpm               26m  Running  10.130.0.71   master-1
payments   mastercard-processor-59986f994c-gtpdn  26m  Running  10.128.0.215  master-2
payments   visa-processor-7d57964dc8-x45hb        26m  Running  10.130.0.72   master-1
➜  ~ kubectl timemachine --auditlog-file=audit.log get pods -n frontend -o wide 
NAMESPACE  NAME                          AGE  STATUS   IP            NODE    
frontend   asset-cache-7d548fc66f-l67rb  26m  Running  10.128.0.212  master-2
frontend   blog-7776768bf6-zq2rp         26m  Running  10.130.0.69   master-1
frontend   webapp-7f77777944-zp85r       26m  Running  10.130.0.70   master-1
➜  ~ 
```
