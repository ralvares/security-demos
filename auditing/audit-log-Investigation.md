# Forensic Engineering: The OpenShift Audit Log Investigation

## Part 1: The Immutable Truth (Revised)

In any production cluster, observability is crucial. Metrics such as CPU usage and memory consumption provide insights into the **health** of applications. However, during a security incident, the focus shifts from **health** to **accountability** and **intent**.

Audit logs serve as the definitive record of actions within the cluster. They are the authoritative record of the Control Plane, capturing the **5 Ws** of every interaction with the API Server: **Who**, **What**, **Where**, **When**, and the **Decision** (RBAC).

## Prerequisite 1: Storage Integrity (The "Safe")

Before we start the hunt, we must address the most important rule of forensic logging: **Storage Integrity.**

Audit logs are generated on the Master nodes. If an attacker successfully escalates privileges and takes over the node (Root compromise), they can wipe the log files. Therefore, for these logs to be legally and forensically valid, they **must be forwarded** to an external system (Splunk, Elastic, Remote Syslog).

## Prerequisite 2: The Audit Profile (The "Resolution")

Secure logs are useless if they don't contain enough detail. This is defined by the **Audit Log Policy**.

By default, OpenShift uses the **Metadata** profile. This is like a phone bill: it tells you *who* called *whom* and for *how long*, but it does not record the *conversation*.

For a deep forensic investigation—where we need to see the exact commands an attacker ran (`exec`), the malicious image they pulled, or the IP address assigned to their pod—we require a higher resolution: **Request Bodies**.

| Profile | Forensic Visibility | What you see | What you miss |
| :--- | :--- | :--- | :--- |
| **Default** | Low | Metadata (User, Verb, Resource, Response Code). | **The Payload.** You cannot see the pod spec (hostPID), the specific command arguments, or the IP assignment in status updates. |
| **WriteRequestBodies** | **High (Recommended)** | All Metadata + **The Full Payload** for "Write" actions (Create, Update, Patch). | Read payloads (e.g., you can't see *which* secret specifically was read if looking at the body, but you know a read happened). |
| **AllRequestBodies** | Maximum | Everything. | Nothing. (Extremely high storage cost). |

> **Forensic Note:** For this investigation, we assume the cluster was configured with **`WriteRequestBodies`**. This allows us to see the "Smoking Gun" evidence: the malicious `hostPID` flag in the pod creation request and the exact IP address assigned by the Node.

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
(echo "TIMESTAMP VERB URI NAMESPACE SOURCE_IP"; jq -r --arg ip "10.128." 'select(
  .user.username == "system:anonymous" and 
  .responseStatus.code == 403 and 
  (.sourceIPs[0] | startswith($ip))
) | [
  .requestReceivedTimestamp, 
  .verb, 
  .requestURI, 
  .objectRef.namespace,
  .sourceIPs[0]
] | @tsv' audit.log) | column -t
```

Explanation: Understanding `sourceIPs`
- The audit field `sourceIPs` reflects the IPs observed by the API server for the client connection. In most cases, the first element is the pod IP (e.g., `10.128.x.y`).
- For deeper enrichment, OpenShift Network Observability can link the IP to the pod/workload, namespace, and node, providing a quick pivot from IP → pod → owner.


#### Network Identity

Finally, to correlate network flows with these events, we need to know the IP address assigned to the malicious pod at the time of creation. In OpenShift/OVN, this is stored in the `k8s.ovn.org/pod-networks` annotation.

**The Query:**
```bash
(echo "TIMESTAMP NAMESPACE POD IP"; jq -r --arg pod "$POD_NAME" 'select(
  .objectRef.resource == "pods" and
  .requestObject.metadata.annotations["k8s.ovn.org/pod-networks"] != null and
  ($pod == "" or .objectRef.name == $pod)
) | [
  .requestReceivedTimestamp,
  .objectRef.namespace,
  .objectRef.name,
  (.requestObject.metadata.annotations["k8s.ovn.org/pod-networks"] | fromjson | .default.ip_addresses[0] | split("/")[0]) 
] | @tsv' audit.log) | column -t
```

**The Finding:**
This reveals the ephemeral IP address assigned to the asset-cache pod.

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
(echo "TIMESTAMP USER NAMESPACE DECISION REASON"; jq -r --arg user "system:serviceaccount:" 'select(
  .objectRef.resource == "selfsubjectaccessreviews" and
  (.user.username | startswith($user)) and
  (.user.username | contains("openshift") | not) and
  (.user.username | contains("stackrox") | not) and
  (.user.username | contains("kube-system") | not)
) | [
  .requestReceivedTimestamp, 
  .user.username, 
  .objectRef.namespace,
  .annotations["authorization.k8s.io/decision"],
  .annotations["authorization.k8s.io/reason"]
] | @tsv' audit.log) | column -t
```

**The Finding:**
We see the `visa-processor` identity querying the cluster to check its own capabilities. The "Robot" has become self-aware. This confirms the token is compromised and the attacker knows they are now Admin.

### Step 3: Detecting Harvesting (Data Exfiltration)

Now that they know they are Admin, they start looking for other secrets to establish persistence or move to other clouds (AWS keys, etc.).

A payment processor should only mount the specific secrets it needs at boot time. It should **never** attempt to list **all** secrets in the cluster.

We query for the `list` verb on the `secrets` resource performed by this account.

```bash
echo "--- Hunting for Secret Harvesting ---"
(echo "TIMESTAMP USER NAMESPACE CODE USER_AGENT"; jq -r --arg user "visa-processor" 'select(
  .verb == "list" and
  .objectRef.resource == "secrets" and
  (.user.username | contains($user))
) | [
  .requestReceivedTimestamp, 
  .user.username, 
  .objectRef.namespace,
  .responseStatus.code,
  (.userAgent | split(" ")[0])
] | @tsv' audit.log) | column -t
```

**The Finding:**
We see a `200 OK` response. The compromised payment processor has successfully listed all secrets. The attacker has harvested credentials.

### Step 4: The "Smoking Gun" (Host Escape)


```bash
echo "--- Hunting for Privileged Pods & HostPID ---"
(echo "TIMESTAMP USER POD NAMESPACE ALERT"; jq -r 'select(
  .verb == "create" and 
  .objectRef.resource == "pods" and 
  (
    (.requestObject.spec.hostPID == true) or 
    (any(.requestObject.spec.containers[]?; .securityContext.privileged == true))
  )
) | [
  .requestReceivedTimestamp, 
  .user.username, 
  .objectRef.name, 
  .objectRef.namespace,
  "ALERT: Dangerous Pod Spec"
] | @tsv' audit.log) | column -t
```

**The Finding:**
We match a request. The `visa-processor` identity created a pod named `visa-processor` on a namespace `payments-v2`

---

#### Forensic Context: The Container Escape

The attacker decided to escalate to the underlying Node. To do this, they deployed a new workload with specific security violations: `hostPID: true` or `privileged: true`.

Because our audit log profile (`WriteRequestBodies`) captures the full request payload, we were able to directly detect these dangerous fields in the `create` request.

### Step 5: The Backdoor (Interactive Tunneling)

Finally, with the privileged `visa-processor` pod running, the attacker needed to enter it to execute their attack on the host. To establish this interactive session, attackers typically use `exec` (to get a shell) or `port-forward` (to tunnel traffic). **In this incident**, we observed the `exec` call.


```bash
echo "--- Hunting for Exec Sessions ---"
(echo "TIMESTAMP USER NAMESPACE POD URI"; jq -r 'select(
  .objectRef.subresource == "exec" and
  .responseStatus.code == 101
) | [
  .requestReceivedTimestamp, 
  .user.username, 
  .objectRef.namespace,
  .objectRef.name, 
  .requestURI
] | @tsv' audit.log) | column -t
```

**The Finding:**
The `visa-processor` identity opened a shell inside the pod.

The "loop was closed," meaning the attacker had established their connection. However, we hadn't seen the *impact* yet. The pod wasn't the goal; it was the **vehicle** to get to the host.

This led to the final, critical chapter of the investigation: **The Node Compromise**.

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
POD_NAME="visa-processor"
echo "--- Extracting Payload for Pod: $POD_NAME ---"
(echo "NAMESPACE IMAGE COMMAND"; jq -r --arg pod "$POD_NAME" 'select(
  .verb == "create" and 
  .objectRef.resource == "pods" and 
  .objectRef.name == $pod and
  .requestObject.spec.containers != null
) | . as $parent | .requestObject.spec.containers[] | [
  $parent.objectRef.namespace,
  .image, 
  (.command | join(" "))
] | @tsv' audit.log) | column -t
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