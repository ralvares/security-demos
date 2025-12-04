# OpenShift Audit Logs: Threat Detection & Incident Response Guide

Reference: [OpenShift Audit Log Documentation](https://docs.openshift.com/container-platform/4.20/security/audit-log-view.html)

## 1. Overview

Audit logs in OpenShift are the authoritative, tamper-evident record of every API request processed by the control plane. Each entry captures **who** performed the action, **what** they did, **when** it occurred, **where** in the cluster it happened, and **how** the request was evaluated.

Properly enabled and analyzed, these logs form the backbone of threat detection, incident response, compliance evidence, and continuous-monitoring programs.

### Why Audit Logs Are Critical

*   **Credential Abuse:** Attackers "log in" with stolen tokens and run standard API calls.
*   **Privilege Escalation:** Misconfigured RoleBindings that silently lift permissions.
*   **Lateral Movement:** Cross-namespace secret reads are often visible only in audit metadata.
*   **Policy Drift:** Excessive SecurityContextConstraints (SCC) exemptions.

## 2. Audit Log Structure

Audit events are emitted as JSON objects. Under the **Default** profile, only metadata is captured; request bodies are omitted.

| Field | Description | Example |
| :--- | :--- | :--- |
| `timestamp` | Time the API server received the request. | `2025-07-02T10:15:00Z` |
| `user.username` | User / service-account identity. | `system:serviceaccount:default:default` |
| `user.groups` | Groups attached to the identity. | `["system:serviceaccounts","system:authenticated"]` |
| `sourceIPs` | Source IP address(es). | `["10.128.0.45"]` |
| `verb` | API verb. | `get`, `create`, `delete`, `patch` |
| `objectRef.resource` | Target resource kind. | `secrets`, `pods`, `rolebindings` |
| `objectRef.namespace` | Namespace (project). | `production` |
| `subresource` | Subresource acted on. | `exec`, `portforward` |
| `responseStatus.code` | Result of the request. | `200` (OK), `403` (Forbidden) |
| `annotations` | RBAC decision, PodSecurity/SCC match. | `"authorization.k8s.io/decision":"allow"` |

> **Note:** Request bodies for **Secret**, **Route**, and **OAuthClient** are *never* logged in any profile.

## 3. Retrieving the Logs

Before analyzing, you often need to pull the logs from the master nodes to a local machine for analysis.

1.  **Get the list of master nodes:**

    ```bash
    masters=$(oc get nodes -l node-role.kubernetes.io/master -o custom-columns=POD:.metadata.name --no-headers)
    ```

2.  **Fetch logs from all masters:**

    ```bash
    for master in $(echo $masters)
    do
      echo "Fetching logs from ${master}..."
      oc adm node-logs ${master} --path=kube-apiserver/audit.log >> audit.log
    done
    # Logs are now available in 'audit.log' for analysis.
    ```

## 4. Demo: Tier 1 Threat Hunting (The "Testpod" Scenario)

This demo simulates a realistic attacker scenario where a pod is compromised and its ServiceAccount is used to escalate privileges.

**Context:**

*   **Namespace:** `default`
*   **Attacker Goal:** Privilege escalation, Recon, Persistence.
*   **Detection Strategy:** Focusing on Verbs and Resources (agnostic of username).

### Step 0: Attacker Foothold (Pod Creation)

The attacker spins up a pod to use as a base.

**Attacker Action:**

```bash
oc run testpod --image=bitnami/kubectl:latest -n default --restart=Never --command -- sleep infinity
```

**Defender Analysis:**

```bash
grep '"resource":"pods"' audit.log | \
grep '"verb":"create"' | jq 'select(.objectRef.namespace=="default") | {
  timestamp: .requestReceivedTimestamp,
  user: .user.username,
  verb: .verb,
  resource: .objectRef.resource,
  name: .objectRef.name,
  uri: .requestURI
} | with_entries(select(.value != null))'
```

### Step 1: Execution (Exec into Pod)

The attacker gains interactive shell access.

**Attacker Action:**

```bash
oc exec -it testpod -n default -- sh
```

**Defender Analysis:** Look for the `exec` subresource.

```bash
grep '"subresource":"exec"' audit.log | \
grep '"verb":"create"' | jq 'select(.objectRef.namespace=="default") | {
  timestamp: .requestReceivedTimestamp,
  user: .user.username,
  subresource: .objectRef.subresource,
  resource: .objectRef.resource,
  name: .objectRef.name
} | with_entries(select(.value != null))'
```

### Step 2: Privilege Escalation

The attacker (or a misguided admin) binds the pod's ServiceAccount to `cluster-admin`.

**Attacker Action:**

```bash
oc adm policy add-cluster-role-to-user cluster-admin system:serviceaccount:default:default
```

**Defender Analysis:** Detect changes to `clusterrolebindings`. This is a high-fidelity alert.

```bash
grep '"resource":"clusterrolebindings"' audit.log | \
grep -E '"verb":"(create|patch|update)"' | jq '{
  timestamp: .requestReceivedTimestamp,
  user: .user.username,
  verb: .verb,
  resource: .objectRef.resource,
  decision: .annotations["authorization.k8s.io/decision"]
} | with_entries(select(.value != null))'
```

### Step 3: Enumeration (Secret Harvesting)

Now an admin, the attacker lists all secrets in the cluster.

**Attacker Action (Inside Pod):**

```bash
kubectl get secrets -A --token=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token) \
  --server=https://kubernetes.default.svc --insecure-skip-tls-verify
```

**Defender Analysis:** Detect a ServiceAccount listing secrets. Filter out system accounts to find the anomaly.

```bash
grep '"resource":"secrets"' audit.log | \
grep '"verb":"list"' | \
grep '"user":{"username":"system:serviceaccount:' | \
grep -v '"user":{"username":"system:serviceaccount:openshift-' | \
grep -v '"user":{"username":"system:serviceaccount:kube-system:' | \
jq '{
  timestamp: .requestReceivedTimestamp,
  user: .user.username,
  verb: .verb,
  resource: .objectRef.resource,
  reason: .annotations["authorization.k8s.io/reason"]
}'
```

### Step 4: Persistence (CronJob)

The attacker creates a scheduled job to maintain access.

**Attacker Action:**

```bash
kubectl create cronjob eviljob --image=busybox --schedule="*/1 * * * *" -- echo pwned
```

**Defender Analysis:**

```bash
grep '"resource":"cronjobs"' audit.log | \
grep -E '"verb":"(create|patch|update)"' | \
jq '{
  timestamp: .requestReceivedTimestamp,
  user: .user.username,
  verb: .verb,
  resource: .objectRef.resource,
  name: .objectRef.name
}'
```

### Step 5: Lateral Movement (Port Forwarding)

Tunneling traffic into the cluster.

**Attacker Action:**

```bash
kubectl port-forward testpod 9000:80 ...
```

**Defender Analysis:**

```bash
grep '"subresource":"portforward"' audit.log | \
jq '{
  timestamp: .requestReceivedTimestamp,
  user: .user.username,
  subresource: .objectRef.subresource,
  name: .objectRef.name
}'
```

## 5. Scenario 2: The "Root Escalation" (Visa Scenario)

This scenario demonstrates an attacker creating a privileged container ("r00t") to escape to the host node.

### The Attack

```bash
# 1. Create a namespace
oc --token $(cat token) create namespace my-newns

# 2. Deploy a standard app
oc --token $(cat token) -n my-newns create deployment mastercard-v2 --image alpine --port=8080 -- sleep 50000

# 3. Run a privileged pod with hostPID access (Container Escape vector)
oc --token $(cat token) run -n my-newns r00t --restart=Never --image alpine \
--overrides '{"spec":{"hostPID": true, "containers":[{"name":"1","image":"alpine","command":["nsenter","--mount=/proc/1/ns/mnt","--","/bin/bash"],"stdin": true,"tty":true,"securityContext":{"privileged":true}}]}}'

# 4. Access the root shell
oc --token $(cat token) -n my-newns rsh r00t
```

### Analysis: Hunting for the "r00t" Pod

To investigate specifically what happened with the pod named `r00t`:

```bash
echo '"Timestamp","Username","Verb","Namespace","Resource","Name","Decision"' > report.csv

cat audit.log | jq -r 'select(.objectRef.name == "r00t") | [.requestReceivedTimestamp, .user.username, .verb, .objectRef.namespace, .objectRef.resource, .objectRef.name, .annotations."authorization.k8s.io/decision"] | @csv' >> report.csv
```

## 6. Audit Log Cheat Sheet (General Queries)

Use these snippets to generate rapid CSV reports from your `audit.log`.

### Get all actions in a specific Namespace

Replace `my-newns` with your target.

```bash
jq -r 'select(.requestURI | contains("/api/v1/namespaces/my-newns")) | select(.user.username != "system:apiserver") | [.requestReceivedTimestamp, .user.username, .verb, .objectRef.resource, .objectRef.name, .responseStatus.code] | @csv' audit.log
```

### Get all actions by a specific User/ServiceAccount

Replace with target username.

```bash
jq -r 'select(.user.username =="system:serviceaccount:payments:visa-processor") | [.requestReceivedTimestamp, .verb, .objectRef.namespace, .objectRef.resource, .objectRef.name, .responseStatus.code] | @csv' audit.log
```

### Identify all "Exec" calls (Shell access)

```bash
jq -r 'select(.objectRef.subresource == "exec") | [.requestReceivedTimestamp, .user.username, .objectRef.namespace, .objectRef.name] | @csv' audit.log
```

### Identify Deployments created in specific Namespace

```bash
jq -r 'select(.objectRef.resource == "deployments" and .verb == "create" and .objectRef.namespace == "payments") | [.requestReceivedTimestamp, .user.username, .objectRef.name] | @csv' audit.log
```

## 7. Best Practices & Detection Strategy

### 1. Establish Baselines

*   Map normal API usage by identity, resource, time, and IP.
*   Catalogue legitimate secret-read patterns (usually typically only Controllers or Operators read secrets).

### 2. Tune Alerting

**Tier 1 - Must Investigate**

*   `ClusterRoleBinding` creation or updates.
*   Cross-namespace secret reads by non-infra accounts.
*   `exec` or `port-forward` into production pods.

**Tier 2 - Needs Triage**

*   New `ServiceAccounts` created in production namespaces.
*   `403 Forbidden` spikes (indicating scanning/fuzzing).

### 3. MITRE ATT&CK Mapping

| Use Case | Example Log Condition | MITRE ID |
| :--- | :--- | :--- |
| **ClusterRoleBinding** | `verb="create" & resource="clusterrolebindings"` | T1098.006 |
| **Secret Access** | `verb="get" & resource="secrets" & user ∉ allowlist` | T1552.007 |
| **Pod Exec** | `verb="create" & subresource="exec"` | T1059 |
| **Lateral Movement** | `subresource="portforward"` | T1572 |
