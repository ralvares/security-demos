# Forensic Engineering: The OpenShift Audit Log Investigation

## Part 1: The Immutable Truth

In any production cluster, observability is crucial. Metrics such as CPU usage, memory consumption, and latency provide insights into the **health** of applications and infrastructure. However, during a security incident, the focus shifts from **health** to **accountability** and **intent**.

Audit logs become indispensable in these scenarios. They serve as the definitive record of actions within the cluster, enabling forensic analysis to uncover the **who**, **what**, **when**, **where**, and **why** of every interaction. This shift in focus underscores the importance of maintaining comprehensive and immutable audit logs to ensure clarity and accountability during critical investigations.

This is where the OpenShift Audit Log becomes the most critical tool in your arsenal. It is the authoritative record of the Control Plane, capturing the **5 Ws** of every interaction with the API Server: **Who**, **What**, **Where**, **When**, and the **Decision** (RBAC).

### The Critical Prerequisite: Log Forwarding

Before we start the hunt, we must address the most important rule of forensic logging: **Storage Integrity.**

Audit logs are generated on the Master nodes. If an attacker successfully escalates privileges and takes over the node (Root compromise), they can technically wipe the log files on that server to cover their tracks.

Therefore, for these logs to be legally and forensically valid, they **must be forwarded** to an external, system (like Splunk, Elastic, or a remote syslog server). In this architecture, even if the attacker burns the cluster to the ground, the evidence of *how* they did it remains safe in your external SIEM.

-----

## Part 2: The Incident Scenario

We are investigating a suspected breach of our "Visa Payment" application. Intelligence suggests a sophisticated Kill Chain involving two specific workloads:

  * **Frontend:** `asset-cache` (Namespace: `frontend`)
  * **Payments:** `visa-processor` (Namespace: `payments`)

**The Attack Theory:**

1.  **Application Exploit:** The attacker exploited a vulnerability in the `asset-cache` code. Because this is an application-level exploit, **the Audit Log is blind to it**.
2.  **The "Loud" Failure:** The attacker tried to talk to the API from `asset-cache` but failed because that account is locked down.
3.  **Lateral Movement:** They pivoted to the `visa-processor`, stole the token, and found it had `cluster-admin` rights due to a misconfiguration in the RoleBinding, which granted excessive privileges to the service account.
4.  **The Trigger:** The moment the attacker uses that stolen token to talk to the OpenShift API, they step out of the shadows and into our logs.

We will now switch to the terminal to reconstruct this timeline using **Behavioral Analysis**.

-----

## Part 3: The Investigation

### Step 1: Investigating the Entry Point

We begin our investigation by looking for suspicious anonymous API activity originating from within the cluster. Our first clue is a set of `403 Forbidden` audit log entries where the `user` is `system:anonymous` and the `sourceIPs` field contains an address from the pod network (e.g., `10.128.x.y`).

By focusing on these events, we can identify API requests that likely originated from a pod, rather than from a node, router, or external source. This method allows us to attribute activity to in-cluster workloads and is a common first step in forensic analysis.

Once we identify a pod IP making these anonymous requests, we can correlate it to a specific workload. 

At this stage, we search for anonymous `403 Forbidden` attempts from the pod network:

```bash
echo "--- Hunting for Anonymous API Attempts (Frontend) ---"
grep '"user":{"username":"system:anonymous"' audit.log | \
grep '"stage":"ResponseComplete"' | \
grep '"code":403' | \
grep '"sourceIPs":\["10.128.' | \
jq -r '[
  .requestReceivedTimestamp,
  .user.username,
  .verb,
  .requestURI,
  (.responseStatus.code | tostring),
  (.sourceIPs[0] // "-"),
  (.userAgent // "-")
] | @tsv' | column -t -s $'\t'
```

Explanation: Understanding `sourceIPs`
- The audit field `sourceIPs` reflects the IPs observed by the API server for the client connection. In most cases, the first element is the pod IP (e.g., `10.128.x.y`).
- For deeper enrichment, OpenShift Network Observability can link the IP to the pod/workload, namespace, and node, providing a quick pivot from IP → pod → owner.


#### About the asset-cache Pod

Through this correlation, we determined that the suspicious pod IP belonged to the `asset-cache` pod in the `frontend` namespace. The `asset-cache` application is a stateless frontend cache service, typically exposed to external traffic and designed to improve performance by storing frequently accessed data. In this scenario, it was running with minimal privileges and, crucially, did not mount a Kubernetes service account token.

This lack of a service account token meant that any API requests made from the pod would be anonymous. The attacker exploited a remote code execution (RCE) vulnerability in the `asset-cache` application, allowing them to run arbitrary commands inside the pod. Their first attempts to access the Kubernetes API were therefore made as `system:anonymous`, and were blocked by RBAC, as seen in the audit logs.

Only after linking the pod IP to the `asset-cache` workload did we realize this was the initial entry point for the attack chain. This highlights the importance of correlating network-level evidence with workload metadata during forensic investigations.

**The Finding:**
We see multiple entries. The attacker tried to `list secrets` and `get pods` from the `asset-cache` pod, but OpenShift blocked them (403).

  * **Forensic Insight:** This confirms the pod is compromised, but the attacker hit a wall. They need a valid account.

### Step 2: Detecting Reconnaissance (The "Who am I?" Check)

Exploiting the lack of NetworkPolicies, the attacker moved laterally to the `visa-processor` pod and abused a known vulnerability in its outdated Apache Struts to gain access and steal the token. Proper patching and scoped network controls would have blocked this path.

Now they have a new identity. But they don't know what permissions this token holds. Is it Read-Only? Is it Admin? To find out, they must ask the API.

A legitimate payment application is deterministic—it writes to databases, it processes transactions. It **never** asks, *"What are my admin rights?"*

We hunt for `SelfSubjectAccessReviews`. This API call is the digital equivalent of a user running `can-i`. It is a high-fidelity signal of a human manually enumerating permissions.

```bash
echo "--- Hunting for Privilege Enumeration (Any ServiceAccount) ---"
cat audit.log | \
jq -r -s '
  map(select(
    (.user.username | startswith("system:serviceaccount:")) and
    # Exclude platform/system namespaces
    (.user.username | contains(":openshift-") | not) and
    (.user.username | contains(":stackrox") | not) and
     (.user.username | contains(":kube-system") | not) and
    (.objectRef.resource == "selfsubjectaccessreviews")
  )) |
  unique_by(.auditID) |
  (["Time","Actor","Decision","Reason"] | @tsv),
  (.[] | [
    .requestReceivedTimestamp,
    .user.username,
    (.annotations["authorization.k8s.io/decision"] // "-"),
    (.annotations["authorization.k8s.io/reason"] // "-")
  ] | @tsv)
' | column -t -s $'\t'
```

**The Finding:**
We see the `visa-processor` identity querying the cluster to check its own capabilities. The "Robot" has become self-aware. This confirms the token is compromised and the attacker knows they are now Admin.

### Step 3: Detecting Harvesting (Data Exfiltration)

Now that they know they are Admin, they start looking for other secrets to establish persistence or move to other clouds (AWS keys, etc.).

A payment processor should only mount the specific secrets it needs at boot time. It should **never** attempt to list **all** secrets in the cluster.

We query for the `list` verb on the `secrets` resource performed by this account.

```bash
echo "--- Hunting for Secret Harvesting ---"
grep '"user":{"username":"system:serviceaccount:payments:visa-processor"' audit.log | \
grep '"resource":"secrets"' | \
grep '"verb":"list"' | \
jq -r -s '
  unique_by(.auditID) |
  (["Time","Actor","Status","Pod","Node","Client"] | @tsv),
  (.[] | [
    .requestReceivedTimestamp,
    .user.username,
    (.responseStatus.code | tostring),
    (.user.extra["authentication.kubernetes.io/pod-name"][0] // "-"),
    (.user.extra["authentication.kubernetes.io/node-name"][0] // "-"),
    (.userAgent | split(" ")[0])  ] | @tsv)
' | column -t -s $'\t'
```

**The Finding:**
We see a `200 OK` response. The compromised payment processor has successfully listed all secrets. The attacker has harvested credentials.

### Step 4: The "Smoking Gun" (Host Escape)


```bash
echo "--- Hunting for Pod Creation Events (Non-Platform ServiceAccounts) ---"
cat audit.log | jq -r -s '
  map(select(
    (.user.username | startswith("system:serviceaccount:")) and
    (.user.username | contains(":openshift-") | not) and
    (.user.username | contains(":stackrox") | not) and
    (.user.username | contains(":kube-system") | not) and
    (.verb == "create")
  )) |
  (["Time","Actor","Pod","Namespace"] | @tsv),
  (.[] | [
    .requestReceivedTimestamp,
    .user.username,
    (.objectRef.name // "-"),
    (.objectRef.namespace // "-")
  ] | @tsv)
' | column -t -s $'\t'
```

**The Finding:**
We match a request. The `visa-processor` identity created a pod named `visa-processor` on a namespace `payments-v2`

---

#### Forensic Hypothesis & Context

The attacker decides to escalate to the underlying Node. They need to deploy a new workload with specific security violations: `hostPID: true` or `privileged: true`.

If your audit log profile does not capture the full request body, you cannot directly see fields like `hostPID` or `privileged`. However, by hunting for pod creation events by non-platform service accounts, you can spot suspicious activity and pivot to deeper investigation (e.g., checking pod specs via `oc get pod -o yaml` if the pod still exists).

In a full forensic scenario, we would scan the JSON Request Body for `hostPID: true`, which would allow the container to see every process running on the Linux host (including Root processes). But even without the body, this query helps you identify the likely escape vector.

**About Audit Log Body Options:**
**Audit Log Profile Options:**

| Profile              | Description |
|----------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Default              | Logs only metadata for read and write requests; does not log request bodies except for OAuth access token requests. This is the default policy. |
| WriteRequestBodies   | In addition to logging metadata for all requests, logs request bodies for every write request to the API servers (create, update, patch). This profile has more resource overhead than the Default profile. |
| AllRequestBodies     | In addition to logging metadata for all requests, logs request bodies for every read and write request to the API servers (get, list, create, update, patch). This profile has the most resource overhead. |

Choose `WriteRequestBodies` or `AllRequestBodies` if you need to capture the full request body for forensic investigations. Be aware that these profiles increase resource usage and log volume.
 
This allows you to:

- Detect security-sensitive fields like `hostPID: true`, `privileged: true`, or `volumes[].hostPath` directly in the log.
- See the exact pod spec submitted at creation time, including all security context and volume mounts.
- Write precise queries to hunt for container escape vectors, privilege escalation, or suspicious mounts.

**Example query for hostPID:**
```bash
echo "--- Hunting for Pod Creations with hostPID: true ---"
cat audit.log | jq -r -s '
  map(select(
    .verb == "create" and
    .objectRef.resource == "pods" and
    (.requestObject.spec.hostPID == true)
  )) |
  (["Time","Actor","Pod","Namespace","hostPID"] | @tsv),
  (.[] | [
    .requestReceivedTimestamp,
    .user.username,
    (.objectRef.name // "-"),
    (.objectRef.namespace // "-"),
    (.requestObject.spec.hostPID | tostring)
  ] | @tsv)
' | column -t -s $'\t'
```

**Example query for Privileged:**
```bash
echo "--- Hunting for Pod Creations with privileged: true ---"
cat audit.log | jq -r -s '
  map(select(
    .verb == "create" and
    .objectRef.resource == "pods" and
    (.requestObject.spec.containers[]?.securityContext.privileged == true) and
    (.objectRef.namespace | test("^(openshift|kube-system)") | not) and
    (.user.username | test("^system:node:") | not)
  )) |
  (["Time","Actor","Pod","Namespace","Privileged"] | @tsv),
  (.[] | [
    .requestReceivedTimestamp,
    .user.username,
    (.objectRef.name // "-"),
    (.objectRef.namespace // "-"),
    ([ .requestObject.spec.containers[]? | select(.securityContext.privileged == true) | .securityContext.privileged ] | map(tostring) | join(",") // "-")
  ] | @tsv)
' | column -t -s $'\t'
```

**Note:** If your audit log profile is only `Metadata`, the request body is not present, so you cannot detect these fields directly. For deep forensics.

### Step 5: The Backdoor (Interactive Tunneling)

Finally, now that the privileged `visa-processor` pod is running, the attacker needs to enter it to execute their attack on the host. **This** is where we finally see the `exec` call.


```bash
echo "--- Hunting for Exec Events (Pod, Node) ---"
grep '"subresource":"exec"' audit.log | \
jq -r -s '
  (["Time","Actor","Pod","Node"] | @tsv),
  (.[] | [
    .requestReceivedTimestamp,
    .user.username,
    (.user.extra["authentication.kubernetes.io/pod-name"][0] // .objectRef.name // "-"),
    (.user.extra["authentication.kubernetes.io/node-name"][0] // "-")
  ] | @tsv)
' | column -t -s $'\t'
```

**The Finding:**
The `visa-processor` identity is opening a shell inside the pod.

The "loop is closed" only means the attacker has established their connection. You are absolutely right—we haven't seen the *impact* yet. The pod wasn't the goal; it was the **vehicle** to get to the host.

Here is the final, critical chapter of the investigation: **The Node Compromise**.

-----

### Step 6: The Node Takeover

> **Note:** The following forensic analysis assumes that your audit log profile is set to capture request bodies (e.g., `WriteRequestBodies` or `AllRequestBodies`). Without this, you will not see the full pod spec, container image, or command in the audit log. Since pods are often short-lived, other methods (such as external SIEM, EDR, or node-level forensics) are required to reconstruct the attack if audit bodies are not available.

At this stage, the attacker has achieved a privileged foothold inside the `visa-processor` pod, which was created with both `hostPID: true` and `privileged: true`. These settings effectively remove most container boundaries, granting the attacker visibility and control over the host node's processes and resources.

The next move is inferred from the pod specification: the attacker likely attempts to escape the container namespace and access the host's filesystem and process space. While we often suspect tools like `nsenter`, the audit log does not capture what happens inside the container. Instead, we rely on forensic signals from the pod spec:

- **Pod creation with `hostPID` and `privileged`**: The audit log shows the creation of a pod with these dangerous settings, a strong indicator of an attempted container escape.
- **Suspicious or unusual commands**: If the audit log profile captures request bodies, you can see the full command array used to launch the container. Any command that attempts namespace manipulation (e.g., `nsenter`, `chroot`, `mount`, or custom binaries) is a red flag, but even generic shells (`/bin/bash`, `/bin/sh`) in privileged pods should be scrutinized.
- **Container image used**: The audit log also reveals the image specified for the pod. Unusual or minimal images (like `alpine`, `busybox`), or images not normally used in your environment, can indicate attacker activity or attempts to evade detection.
- **Sensitive hostPath mounts**: The attacker may also mount critical host directories (like `/`, `/etc`, `/var/run`, `/root`, or `/etc/kubernetes`) into the pod, providing direct access to the node's files.

By reviewing the pod spec in the audit log, you can:
* See the exact container image and command used, providing context for the attacker's intent and tooling—without needing to guess the method (e.g., `nsenter`).
* Correlate suspicious images and commands with dangerous settings (`hostPID`, `privileged`, sensitive hostPath mounts) to build a high-confidence picture of a node compromise attempt.

Once on the node, the attacker can:
* Read or modify sensitive files.
* Create or alter static pod manifests for persistence.
* Access container runtime sockets to control other containers or escalate further.
* etc..

**Forensic Implications:**
While the actual use of escape tools and subsequent host actions are not visible in Kubernetes audit logs, the combination of these pod creation events, dangerous settings, suspicious commands, unusual images, and sensitive mounts is a high-fidelity signal of node compromise. The queries below help you spot these behaviors.

```bash
PODNAME="visa-processor"
echo "--- Hunting for Pod Creations by Name ---"
cat audit.log | jq -r -s --arg pod "$PODNAME" '
  map(select(
    .verb == "create" and
    .objectRef.resource == "pods" and
    (.objectRef.name == $pod)
  )) |
  map({
    time: .requestReceivedTimestamp,
    actor: .user.username,
    pod: (.objectRef.name // "-"),
    ns: (.objectRef.namespace // "-"),
    image: ([.requestObject.spec.containers[]?.image] | join(" | ")),
    command: ([.requestObject.spec.containers[]?.command | join(" ")] | join(" | "))
  })
  | map(select(.image != ""))
  | (["Time","Actor","Pod","Namespace","Image","Command"] | @tsv),
    (.[] | [.time, .actor, .pod, .ns, .image, .command] | @tsv)
' | column -t -s $'\t'
```

**The Finding:**
We see the pod created with a command that explicitly invokes `nsenter`, confirming the attacker's intent to escape the container and access the host.

-----

## Forensic Timeline

We have now reconstructed the *entire* Kill Chain, from the first failed probe to total infrastructure compromise.

```mermaid
flowchart TD
    %% Define Styles
    classDef frontend fill:#ffebee,stroke:#c62828,stroke-width:2px;
    classDef lateral fill:#fff3e0,stroke:#ef6c00,stroke-width:2px;
    classDef escalation fill:#e8f5e9,stroke:#2e7d32,stroke-width:2px;
    classDef takeover fill:#212121,stroke:#000,stroke-width:2px,color:#fff;

    subgraph Phase1 ["Phase 1: The Noisy Neighbor"]
        A["Log: asset-cache gets 403 Forbidden"]:::frontend
        Note1["Attacker has RCE but no permissions"]
    end

    subgraph Phase2 ["Phase 2: Lateral Movement"]
        B["Log: visa-processor checks SelfPermissions"]:::lateral
        C["Log: visa-processor Lists Secrets"]:::lateral
        Note2["Token stolen & credential harvesting"]
    end

    subgraph Phase3 ["Phase 3: Escalation"]
        D["Log: visa-processor creates pod fake visa-processor (HostPID)"]:::escalation
        E["Log: visa-processor execs into fake visa-processor"]:::escalation
        Note3["Container Escape & Privileged Access"]
    end

    subgraph Phase4 ["Phase 4: Impact"]
        F["Log: Fake visa-processor access Host Namespace"]:::takeover
        Note4["Physical Node Compromised"]
    end

    A --> B --> C --> D --> E --> F
```

## Conclusion

We have reconstructed the crime scene using only the Audit Logs, mapping the attack to the **MITRE ATT\&CK** framework:

1.  **Asset-Cache (Frontend):** `403 Forbidden` on API calls. *Conclusion: Compromised, but contained by RBAC.*
2.  **Visa-Processor (Lateral Move):** `SelfSubjectAccessReview`. *Conclusion: Token stolen, Reconnaissance detected.*
3.  **Visa-Processor (Exfiltration):** `List Secrets`. *Conclusion: Credential Harvesting.*
4.  **Visa-Processor (Escalation):** Deployed `fake visa-processor` with `HostPID`. *Conclusion: Container Escape.*
5.  **Visa-Processor (Action):** Executed shell in `fake visa-processor`. *Conclusion: Node Takeover.*