# OpenShift Audit Policy: Forensic Value vs. Splunk Costs

## Overview

This configuration is designed to solve a critical operational challenge: **Reducing log ingestion costs (e.g., Splunk license limits)** without sacrificing the **forensic data** needed to investigate security incidents.

Standard OpenShift audit logs are extremely verbose. Without tuning, infrastructure components generate terabytes of low-value data (heartbeats, leader elections) that drown out the high-value signals (user changes, application deployments).

This policy uses a **"Blocklist Strategy"**: it explicitly silences known noisy infrastructure namespaces so that we can afford to enable full detailed logging for everything else (your applications and users).

## The Configuration

> **Note:** The following configuration uses `None` for many groups to simplify lab testing and reduce log volume. In production environments, it is recommended to use `Default` for most infrastructure groups to retain essential metadata for forensics.

```yaml
spec:
  audit:
    customRules:
    - group: system:nodes
      profile: None
    - group: system:kube-proxy
      profile: None
    - group: system:kube-controller-manager
      profile: None
    - group: system:kube-scheduler
      profile: None
    - group: system:apiserver
      profile: None
    - group: system:serviceaccounts:stackrox
      profile: None
    - group: system:serviceaccounts:netobserv
      profile: None
    - group: system:serviceaccounts:openshift-cnv
      profile: None
    - group: system:serviceaccounts:kube-system
      profile: None
    - group: system:serviceaccounts:openshift-monitoring
      profile: None
    - group: system:serviceaccounts:openshift-sdn
      profile: None
    - group: system:serviceaccounts:openshift-ovn-kubernetes
      profile: None
    - group: system:serviceaccounts:openshift-console
      profile: None
    - group: system:serviceaccounts:openshift-etcd
      profile: None
    - group: system:serviceaccounts:openshift-image-registry
      profile: None
    - group: system:serviceaccounts:openshift-machine-config-operator
      profile: None
    - group: system:serviceaccounts:openshift-cluster-version
      profile: None
    - group: system:serviceaccounts:openshift-apiserver
      profile: None
    - group: system:serviceaccounts:openshift-kube-apiserver
      profile: None
    - group: system:serviceaccounts:openshift-kube-controller-manager
      profile: None
    - group: system:serviceaccounts:openshift-kube-scheduler
      profile: None
    - group: system:serviceaccounts:openshift-authentication
      profile: None
    - group: system:serviceaccounts:openshift-ingress
      profile: Default
    - group: system:serviceaccounts:openshift
      profile: None
    - group: system:authenticated:oauth
      profile: WriteRequestBodies
    - group: system:authenticated
      profile: WriteRequestBodies
    - group: system:serviceaccounts
      profile: WriteRequestBodies
    - group: system:unauthenticated
      profile: None
    profile: Default
```

-----

## Detailed Explanation of Rules

### 1\. The Silencers (Rule \#1)

  * **Target:** `system:nodes`, `kube-proxy`, etc.
  * **Action:** `profile: "None"`
  * **Why:** These components "chat" with the API server thousands of times per second just to say "I'm alive." This data has **zero forensic value** and is the primary driver of log volume. We discard it completely.

### 2\. The Infrastructure Blocklist (Rule \#2)

  * **Target:** `openshift-monitoring`, `openshift-ingress`, `kube-system`, etc.
  * **Action:** `profile: "Default"` (Metadata Only)
  * **Why:** These namespaces contain trusted OpenShift operators. They perform millions of "Lease Updates" (leader election) daily.
      * **Cost Impact:** A Lease update body is large JSON. Multiplying this by millions of events creates massive Splunk bills.
      * **Solution:** We log **Metadata Only**. We see *that* an update happened (for security tracking), but we strip out the heavy JSON body.

### 3\. The Application "Catch-All" (Rule \#3)

  * **Target:** `system:serviceaccounts` (Global Group)
  * **Action:** `profile: "WriteRequestBodies"`
  * **Why:** This is the genius of the configuration. Audit rules are processed top-to-bottom.
      * If a request comes from `openshift-monitoring`, it is caught by Rule \#2 (Quiet).
      * If a request comes from your apps (`backend`, `payments`) or **any new project you create tomorrow**, it falls through to Rule \#3.
      * **Result:** Your applications get **Full Body Logging** automatically. You capture the exact YAML of every deployment, patch, or config change without manual configuration.

### 4\. Human Accountability (Rule \#4)

  * **Target:** `system:authenticated`, `oauth`
  * **Action:** `profile: "WriteRequestBodies"`
  * **Why:** Human users (Admins, Developers) perform low-volume but high-risk actions. We always capture the full details of what a human changed.

-----

## Value Proposition

By filtering out high-volume, low-value infrastructure noise (like heartbeats and leader elections), we significantly reduce log ingestion volume. This allows us to retain full-fidelity logs for critical user actions and application changes without incurring prohibitive storage or SIEM costs.

## How to Apply

You can apply this configuration directly to your cluster using the following command:

```bash
cat <<EOF | oc patch apiserver cluster --type=merge --patch-file /dev/stdin
spec:
  audit:
    customRules:
    - group: system:nodes
      profile: None
    - group: system:kube-proxy
      profile: None
    - group: system:kube-controller-manager
      profile: None
    - group: system:kube-scheduler
      profile: None
    - group: system:apiserver
      profile: None
    - group: system:serviceaccounts:stackrox
      profile: None
    - group: system:serviceaccounts:netobserv
      profile: None
    - group: system:serviceaccounts:openshift-cnv
      profile: None
    - group: system:serviceaccounts:kube-system
      profile: None
    - group: system:serviceaccounts:openshift-monitoring
      profile: None
    - group: system:serviceaccounts:openshift-sdn
      profile: None
    - group: system:serviceaccounts:openshift-ovn-kubernetes
      profile: None
    - group: system:serviceaccounts:openshift-console
      profile: None
    - group: system:serviceaccounts:openshift-etcd
      profile: None
    - group: system:serviceaccounts:openshift-image-registry
      profile: None
    - group: system:serviceaccounts:openshift-machine-config-operator
      profile: None
    - group: system:serviceaccounts:openshift-cluster-version
      profile: None
    - group: system:serviceaccounts:openshift-apiserver
      profile: None
    - group: system:serviceaccounts:openshift-kube-apiserver
      profile: None
    - group: system:serviceaccounts:openshift-kube-controller-manager
      profile: None
    - group: system:serviceaccounts:openshift-kube-scheduler
      profile: None
    - group: system:serviceaccounts:openshift-authentication
      profile: None
    - group: system:serviceaccounts:openshift-ingress
      profile: Default
    - group: system:serviceaccounts:openshift
      profile: None
    - group: system:authenticated:oauth
      profile: WriteRequestBodies
    - group: system:authenticated
      profile: WriteRequestBodies
    - group: system:serviceaccounts
      profile: WriteRequestBodies
    - group: system:unauthenticated
      profile: None
    profile: Default
EOF
```

## Next Steps: Log Forwarding

This configuration is the **first line of defense** (at the source).

To further optimize costs, we can configure the OpenShift **Log Forwarder** to drop specific events before they leave the cluster.

  * **Example:** "If the event is from `openshift-monitoring` AND the resource is `leases`, drop it entirely."

This dual-layer approach (Source Tuning + Collector Filtering) ensures you pay only for the data that has real security value.

## Advanced Filtering with ClusterLogForwarder

To extract specific user events or filter out noise before forwarding logs to your SIEM (like Splunk), you can use the `ClusterLogForwarder` API. This allows you to define granular rules based on users, verbs, resources, and more.

### Example 1: Targeting Specific Users and Actions

This configuration captures actions by specific users (e.g., `user1`), successful logins (OAuth token creation), and failed login attempts, while filtering out everything else.

```yaml
apiVersion: logging.openshift.io/v1
kind: ClusterLogForwarder
metadata:
  name: instance
  namespace: openshift-logging
spec:
  filters:
  - kubeAPIAudit:
      omitStages:
      - RequestReceived
      rules:
      - level: Request # Track "create", "patch", "delete" for user1.
        users:
        - user1
        verbs: ["create", "patch", "delete"]
      - level: Request # Track successful logins (oauthaccesstokens creation)
        users:
        - "system:serviceaccount:openshift-authentication:oauth-openshift"
        verbs: ["create"]
        resources:
        - group: "oauth.openshift.io"
          resources: ["oauthaccesstokens"]
      - level: Request # Track failed login attempts
        users: ["system:anonymous"]
        nonResourceURLs:
        - "/oauth/authorize*"
        verbs: ["get"]
      - level: None # Filter out everything else
    name: my-policy
    type: kubeAPIAudit
  inputs:
  - name: selected-audit-logs
    audit:
      sources:
      - kubeAPI
      - openshiftAPI
  pipelines:
  - filterRefs:
    - my-policy
    inputRefs:
    - selected-audit-logs
    name: enable-logstore
    outputRefs:
    - default
```

### Example 2: Excluding System Users

If you prefer to capture all user activity but exclude system accounts (service accounts, etc.), use this approach:

```yaml
apiVersion: logging.openshift.io/v1
kind: ClusterLogForwarder
metadata:
  name: instance
  namespace: openshift-logging
spec:
  filters:
  - kubeAPIAudit:
      omitStages:
      - RequestReceived
      rules:
      - level: Request # Track failed login attempts
        users: ["system:anonymous"]
        nonResourceURLs:
        - "/oauth/authorize*"
        verbs: ["get"]
      - level: None # Exclude all system users
        users:
        - "system:*"
      - level: Request # Track "create", "patch", "delete" for any other user
        verbs: ["create", "patch", "delete"]
      - level: Request # Track successful logins
        users:
        - "system:serviceaccount:openshift-authentication:oauth-openshift"
        verbs: ["create"]
        resources:
        - group: "oauth.openshift.io"
          resources: ["oauthaccesstokens"]
      - level: None # Filter out everything else
    name: my-policy
    type: kubeAPIAudit
  inputs:
  - name: selected-audit-logs
    audit:
      sources:
      - kubeAPI
      - openshiftAPI
  pipelines:
  - filterRefs:
    - my-policy
    inputRefs:
    - selected-audit-logs
    name: enable-logstore
    outputRefs: 
    - default
```