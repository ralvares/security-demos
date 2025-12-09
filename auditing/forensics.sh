#!/bin/bash

# ==============================================================================
# OPENSHIFT FORENSIC LIBRARY
# ------------------------------------------------------------------------------
# A toolkit for hunting threats in Kubernetes/OpenShift Audit Logs.
# Maps directly to the "Forensic Engineering" investigation steps.
# ==============================================================================

# Check for dependencies
if ! command -v jq &> /dev/null; then
    echo "Error: 'jq' is not installed. Please install it to use this tool."
    exit 1
fi

# ==============================================================================
# 0. SETUP: Fetch Audit Logs from Masters
# ==============================================================================
# Usage: audit_fetch_logs [output_file]
audit_fetch_logs() {
    local OUTPUT_FILE="${1:-audit.log}"

    if ! command -v oc &> /dev/null; then
        echo "Error: 'oc' command is not found. Please install the OpenShift CLI."
        return 1
    fi

    echo "--- Fetching Audit Logs from Master Nodes to '$OUTPUT_FILE' ---"
    
    # Check connectivity/permissions first
    if ! oc get nodes -l node-role.kubernetes.io/master &> /dev/null; then
        echo "Error: Failed to get master nodes. Check your 'oc' login and permissions."
        return 1
    fi

    # Clear/Create file
    echo > "$OUTPUT_FILE"

    masters=$(oc get nodes -l node-role.kubernetes.io/master -o custom-columns=POD:.metadata.name --no-headers)

    # Iterate over master nodes
    for master in $(echo $masters)                                                  
    do                                                                        
      echo "Fetching logs from ${master}..."                                        
      oc adm node-logs ${master} --path=kube-apiserver/audit.log >> "$OUTPUT_FILE"
    done
    
    echo "Done. Logs are available in '$OUTPUT_FILE'."
}

# ==============================================================================
# 1. INITIAL ACCESS: Detect Anonymous Probing
# ==============================================================================
# Usage: audit_detect_anonymous_access <log_file> [ip_prefix]
audit_detect_anonymous_access() {
    local LOG_FILE="${1:-audit.log}"
    local IP_PREFIX="${2:-10.}"

    echo "--- [1] Hunting for Anonymous Probes (Denied) from pod network ---"
    (echo "TIMESTAMP VERB URI SOURCE_IP"; jq -r --arg ip "$IP_PREFIX" 'select(
      .user.username == "system:anonymous" and 
      .responseStatus.code == 403 and 
      (.sourceIPs[0] | startswith($ip))
    ) | [
      .requestReceivedTimestamp, 
      .verb, 
      .requestURI, 
      .sourceIPs[0]
    ] | @tsv' "$LOG_FILE") | column -t
}

# ==============================================================================
# 2. DISCOVERY: Detect Reconnaissance (Privilege Enumeration)
# ==============================================================================
# Usage: audit_detect_reconnaissance <log_file> [user_pattern]
audit_detect_reconnaissance() {
    local LOG_FILE="${1:-audit.log}"
    local USER_PATTERN="${2:-system:serviceaccount:}"

    echo "--- [2] Hunting for Recon (SelfSubjectAccessReview) by: $USER_PATTERN ---"
    (echo "TIMESTAMP USER DECISION REASON"; jq -r --arg user "$USER_PATTERN" 'select(
      .objectRef.resource == "selfsubjectaccessreviews" and
      (.user.username | startswith($user)) and
      (.user.username | contains("openshift") | not) and
      (.user.username | contains("stackrox") | not) and
      (.user.username | contains("kube-system") | not)
    ) | [
      .requestReceivedTimestamp, 
      .user.username, 
      .annotations["authorization.k8s.io/decision"],
      .annotations["authorization.k8s.io/reason"]
    ] | @tsv' "$LOG_FILE") | column -t
}

# ==============================================================================
# 3. CREDENTIAL ACCESS: Detect Resource Harvesting
# ==============================================================================
# Usage: audit_detect_resource_harvesting <log_file> [target_user] [ip_prefix]
audit_detect_resource_harvesting() {
    local LOG_FILE="${1:-audit.log}"
    local TARGET_USER="$2"

    if [ -z "$TARGET_USER" ]; then
        echo "Error: You must provide a target user (e.g., 'visa-processor')"
        return 1
    fi

    echo "--- [3] Hunting for Resource Harvesting by: $TARGET_USER ---"
    (echo "TIMESTAMP USER RESOURCE CODE USER_AGENT SOURCE_IP"; jq -r --arg user "$TARGET_USER" 'select(
      .verb == "list" and
      (.user.username | contains($user))    ) | [
      .requestReceivedTimestamp, 
      .user.username, 
      .objectRef.resource,
      .responseStatus.code,
      (.userAgent | split(" ")[0]),
      .sourceIPs[0]
    ] | @tsv' "$LOG_FILE") | column -t
}

# ==============================================================================
# 4. ESCALATION: Detect Container Escapes (HostPID / Privileged)
# ==============================================================================
# Usage: audit_detect_privileged_pods <log_file>
# Note: Uses 'any' and '?' to safely handle logs where requestObject is null
audit_detect_privileged_pods() {
    local LOG_FILE="${1:-audit.log}"

    echo "--- [4] Hunting for Privileged Pods & HostPID ---"
    (echo "TIMESTAMP USER POD NAMESPACE ALERT"; jq -r 'select(
      .verb == "create" and 
      .objectRef.resource == "pods" and 
      (.user.username | contains("openshift") | not) and
      (.user.username | contains("stackrox") | not) and
      (.user.username | contains("kube-system") | not) and
      (.user.username | contains("system:node") | not) and
      (
        (.requestObject.spec.hostPID == true) or 
        (any(.requestObject.spec.containers[]?; .securityContext.privileged == true))
      )
    ) | [
      .requestReceivedTimestamp, 
      .user.username, 
      .objectRef.name, 
      .objectRef.namespace,
      "Created POD with Dangerous Specs"
    ] | @tsv' "$LOG_FILE") | column -t
}

# ==============================================================================
# 5. LATERAL MOVEMENT: Detect Exec Sessions
# ==============================================================================
# Usage: audit_detect_exec_sessions <log_file> [pod_name]
audit_detect_exec_sessions() {
    local LOG_FILE="${1:-audit.log}"
    local POD_NAME="$2"

    echo "--- [5] Hunting for Exec Sessions (Pod Filter: ${POD_NAME:-ALL}) ---"
    (echo "TIMESTAMP USER NAMESPACE POD"; jq -r --arg pod "$POD_NAME" 'select(
      .objectRef.subresource == "exec" and
      .responseStatus.code == 101 and
      ($pod == "" or .objectRef.name == $pod)
    ) | [
      .requestReceivedTimestamp, 
      .user.username, 
      .objectRef.namespace,
      .objectRef.name
    ] | @tsv' "$LOG_FILE") | column -t
}

# ==============================================================================
# 6. PAYLOAD ANALYSIS: Extract Image & Command
# ==============================================================================
# Usage: audit_extract_pod_payload <log_file> <pod_name>
# Note: Checks for 'containers != null' to prevent crashes on partial logs
audit_extract_pod_payload() {
    local LOG_FILE="${1:-audit.log}"
    local POD_NAME="$2"

    if [ -z "$POD_NAME" ]; then
        echo "Error: You must provide a pod name."
        return 1
    fi

    echo "--- [6] Extracting Payload for Pod: $POD_NAME ---"
    (echo "NAMESPACE IMAGE COMMAND"; jq -r --arg pod "$POD_NAME" 'select(
      .objectRef.resource == "pods" and 
      .objectRef.name == $pod
    ) | 
    (
      if (.responseObject.spec.containers != null) then .responseObject 
      elif (.requestObject.spec.containers != null) then .requestObject
      else empty end
    ) | 
    . as $obj |
    $obj.spec.containers[] | [
      $obj.metadata.namespace,
      .image, 
      (if .command and (.command | length > 0) then (.command | join(" ")) else "(default)" end)
    ] | @tsv' "$LOG_FILE" | sort -u) | column -t
}

# ==============================================================================
# 7. NETWORK FORENSICS: Find Pod by IP (OVN Annotation Method)
# Best for clusters where standard Status IP logging is missing or filtered.
# Usage: audit_lookup_pod_by_ip <log_file> <ip_address>
audit_lookup_pod_by_ip() {
    local LOG_FILE="${1:-audit.log}"
    local TARGET_IP="$2"

    if [ -z "$TARGET_IP" ]; then
        echo "Error: You must provide an IP address."
        return 1
    fi

    echo "--- [7] Hunting for Pod owning IP: $TARGET_IP ---"
    (echo "TIMESTAMP POD IP"; jq -r --arg ip "$TARGET_IP" 'select(
      .objectRef.resource == "pods" and
      (.requestObject | type == "object") and
      .requestObject.metadata.annotations["k8s.ovn.org/pod-networks"] != null
    ) | 
    (.requestObject.metadata.annotations["k8s.ovn.org/pod-networks"] | fromjson | .default.ip_addresses[0] | split("/")[0]) as $pod_ip |
    select($pod_ip == $ip) |
    [
      .requestReceivedTimestamp,
      .objectRef.name,
      $pod_ip
    ] | @tsv' "$LOG_FILE") | column -t
}

# ==============================================================================
# 8. KUBEVIRT FORENSICS: Detect VM Access & Creation
# ==============================================================================
# Usage: audit_detect_kubevirt_console <log_file>
audit_detect_kubevirt_console() {
    local LOG_FILE="${1:-audit.log}"
    echo "--- [8a] Hunting for VM Console/VNC Access ---"
    (echo "TIMESTAMP USER VM_NAME ACCESS_TYPE ALERT"; jq -r 'select(
      # Check for specific KubeVirt subresources
      .objectRef.subresource == "console" or 
      .objectRef.subresource == "vnc" or 
      .objectRef.subresource == "ssh"
    ) | [
      .requestReceivedTimestamp,
      .user.username,
      .objectRef.name,
      .objectRef.subresource,
      "REMOTE_ACCESS"
    ] | @tsv' "$LOG_FILE") | column -t
}

# Usage: audit_detect_kubevirt_vm_creation <log_file>
audit_detect_kubevirt_vm_creation() {
    local LOG_FILE="${1:-audit.log}"
    echo "--- [8b] Hunting for KubeVirt VM Creations ---"
    (echo "TIMESTAMP USER RESOURCE NAME ACTION"; jq -r 'select(
      .verb == "create" and
      (.objectRef.resource == "virtualmachines" or .objectRef.resource == "virtualmachineinstances")
    ) | [
      .requestReceivedTimestamp,
      .user.username,
      .objectRef.resource,
      .objectRef.name,
      "VM_CREATED"
    ] | @tsv' "$LOG_FILE") | column -t
}

# ==============================================================================
# 9. PERSISTENCE: Detect "Time Bombs" (CronJobs/DaemonSets)
# ==============================================================================
# Usage: audit_detect_persistence <log_file> [user_pattern]
audit_detect_persistence() {
    local LOG_FILE="${1:-audit.log}"
    local USER_PATTERN="$2"
    
    echo "--- [9] Hunting for Persistence (CronJobs/DaemonSets/Deployments) ---"
    
    (echo "TIMESTAMP USER TYPE NAME IMAGE"; jq -r --arg user "$USER_PATTERN" 'select(
      .verb == "create" and
      (.objectRef.resource == "cronjobs" or .objectRef.resource == "daemonsets" or .objectRef.resource == "deployments") and
      ($user == "" or (.user.username | contains($user))) and
      (.user.username | contains("openshift-") | not) and
      (.user.username | contains("kube-system") | not)
    ) | [
      .requestReceivedTimestamp,
      .user.username,
      .objectRef.resource,
      .objectRef.name,
      # Try to extract image from the pod template inside the workload
      (.requestObject.spec.jobTemplate.spec.template.spec.containers[0].image // 
       .requestObject.spec.template.spec.containers[0].image // 
       "unknown")
    ] | @tsv' "$LOG_FILE") | column -t
}

# ==============================================================================
# 10. TAMPERING: Detect Config/Secret Modification
# ==============================================================================
# Usage: audit_detect_tampering <log_file> [user_pattern]
audit_detect_tampering() {
    local LOG_FILE="${1:-audit.log}"
    local USER_PATTERN="$2"
    
    echo "--- [10] Hunting for Config/Secret Tampering (Patch/Update) ---"
    
    (echo "TIMESTAMP USER RESOURCE NAME ACTION"; jq -r --arg user "$USER_PATTERN" 'select(
      (.verb == "patch" or .verb == "update") and
      (.objectRef.resource == "configmaps" or .objectRef.resource == "secrets") and
      ($user == "" or (.user.username | contains($user))) and
      
      # Filter out system noise (Controllers updating their own leaders/state)
      (.user.username | contains("system:") | not) and
      (.user.username | contains("openshift-") | not)
    ) | [
      .requestReceivedTimestamp,
      .user.username,
      .objectRef.resource,
      .objectRef.name,
      .verb
    ] | @tsv' "$LOG_FILE") | column -t
}

# ==============================================================================
# 11. EVASION: Detect User Impersonation
# ==============================================================================
# Usage: audit_detect_impersonation <log_file>
audit_detect_impersonation() {
    local LOG_FILE="${1:-audit.log}"
    
    echo "--- [11] Hunting for User Impersonation (--as=...) ---"
    
    (echo "TIMESTAMP REAL_USER IMPERSONATED_USER VERB URI"; jq -r 'select(
      .impersonatedUser != null and
      (.user.username | contains("openshift") | not) and
      (.user.username | contains("kube-system") | not)
    ) | [
      .requestReceivedTimestamp,
      .user.username,
      .impersonatedUser.username,
      .verb,
      .requestURI
    ] | @tsv' "$LOG_FILE") | column -t
}

# ==============================================================================
# 12. INVESTIGATION: IP History & Identity Switching
# ==============================================================================
# Usage: audit_track_ip_activity <log_file> <ip_address>
audit_track_ip_activity() {
    local LOG_FILE="${1:-audit.log}"
    local TARGET_IP="$2"

    if [ -z "$TARGET_IP" ]; then
        echo "Error: You must provide an IP address."
        return 1
    fi

    # 1. Identify the Pod Owner (if possible)
    echo "--- Identifying Pod for IP: $TARGET_IP ---"
    local POD_OWNER=$(jq -r --arg ip "$TARGET_IP" 'select(
      .objectRef.resource == "pods" and
      (.requestObject | type == "object") and
      .requestObject.metadata.annotations["k8s.ovn.org/pod-networks"] != null
    ) | 
    (.requestObject.metadata.annotations["k8s.ovn.org/pod-networks"] | fromjson | .default.ip_addresses[0] | split("/")[0]) as $pod_ip |
    select($pod_ip == $ip) |
    "\(.objectRef.namespace)/\(.objectRef.name)"' "$LOG_FILE" | head -n 1)

    if [ -n "$POD_OWNER" ]; then
        echo "Pod Owner: $POD_OWNER"
    else
        echo "Pod Owner: Unknown (Creation event not found in this log)"
    fi
    echo ""

    echo "--- History of Activity for IP: $TARGET_IP ---"
    
    (echo "TIMESTAMP USER VERB RESOURCE CODE"; jq -r --arg ip "$TARGET_IP" 'select(
      # Check if the IP list contains our target
      (.sourceIPs[]? | contains($ip))
    ) | [
      .requestReceivedTimestamp,
      .user.username,
      .verb,
      .objectRef.resource,
      .responseStatus.code
    ] | @tsv' "$LOG_FILE") | column -t
}

# ==============================================================================
# 13. INVESTIGATION: Pod Lifecycle & History
# ==============================================================================
# Usage: audit_track_pod_lifecycle <log_file> <pod_name>
audit_track_pod_lifecycle() {
    local LOG_FILE="${1:-audit.log}"
    local POD_NAME="$2"

    if [ -z "$POD_NAME" ]; then
        echo "Error: You must provide a pod name."
        return 1
    fi

    echo "--- Lifecycle History for Pod: $POD_NAME ---"

    # 1. Extract Pod Metadata (Namespace, ServiceAccount, Node, IP, SCC)
    # Priority: Object with OVN annotation (has IP) -> Object with Spec (has NS/SA)
    local POD_META=$(jq -r --arg pod "$POD_NAME" 'select(
      .objectRef.resource == "pods" and
      .objectRef.name == $pod and
      (.requestObject.spec != null or .responseObject.spec != null) and
      ((.responseObject // .requestObject) | .metadata.annotations["k8s.ovn.org/pod-networks"] != null)
    ) | 
    (.responseObject // .requestObject) | 
    [
      (.metadata.namespace // "Unknown"),
      (.spec.serviceAccountName // "Unknown"),
      (.spec.nodeName // "Pending"),
      (.metadata.annotations["k8s.ovn.org/pod-networks"] | fromjson | .default.ip_addresses[0] | split("/")[0]),
      (.metadata.annotations["openshift.io/scc"] // "Unknown")
    ] | @tsv' "$LOG_FILE" | head -n 1)

    # Fallback if no IP found (e.g. pod failed to schedule or just created)
    if [ -z "$POD_META" ]; then
         POD_META=$(jq -r --arg pod "$POD_NAME" 'select(
          .objectRef.resource == "pods" and
          .objectRef.name == $pod and
          (.requestObject.spec != null or .responseObject.spec != null)
        ) | 
        (.responseObject // .requestObject) | 
        [
          (.metadata.namespace // "Unknown"),
          (.spec.serviceAccountName // "Unknown"),
          (.spec.nodeName // "Pending"),
          "Unknown",
          (.metadata.annotations["openshift.io/scc"] // "Unknown")
        ] | @tsv' "$LOG_FILE" | head -n 1)
    fi

    if [ -n "$POD_META" ]; then
        read -r P_NS P_SA P_NODE P_IP P_SCC <<< "$POD_META"
        echo "Namespace:       $P_NS"
        echo "Service Account: $P_SA"
        echo "Node:            $P_NODE"
        echo "IP Address:      $P_IP"
        echo "SCC:             $P_SCC"
    else
        echo "Metadata:        Unknown (Full Pod Object not found in logs)"
    fi
    echo ""
    
    # 2. Find Creation Timestamp
    # We look for 'create' on the pod itself (true creation) or 'create binding' (scheduling)
    local CREATION_INFO=$(jq -r --arg pod "$POD_NAME" 'select(
      .objectRef.resource == "pods" and
      .objectRef.name == $pod and
      .verb == "create"
    ) | [
      .requestReceivedTimestamp,
      .user.username,
      (.objectRef.subresource // "pod")
    ] | @tsv' "$LOG_FILE" | sort | head -n 1)

    if [ -n "$CREATION_INFO" ]; then
        read -r C_TIME C_USER C_RES <<< "$CREATION_INFO"
        echo "Creation Time:   $C_TIME"
    else
        echo "Creation Time:   Unknown (No 'create' event found)"
    fi
    echo ""

    # 3. Extract Payload (Image & Command)
    audit_extract_pod_payload "$LOG_FILE" "$POD_NAME"
}

# ==============================================================================
# 14. PRIVILEGE ESCALATION: Detect Cluster-Admin Grants
# ==============================================================================
# Usage: audit_detect_admin_grants <log_file>
audit_detect_admin_grants() {
    local LOG_FILE="${1:-audit.log}"
    
    echo "--- [14] Hunting for Grants of 'cluster-admin' privileges ---"
    (echo "TIMESTAMP ACTOR BINDING TARGET_USER/GROUP"; jq -r 'select(
      (.objectRef.resource == "clusterrolebindings") and
      (.verb == "create" or .verb == "update" or .verb == "patch") and
      (.requestObject.roleRef.name == "cluster-admin")
    ) | [
      .requestReceivedTimestamp,
      .user.username,
      .objectRef.name,
      (.requestObject.subjects[]? | .name)
    ] | @tsv' "$LOG_FILE") | column -t
}

# ==============================================================================
# 15. LATERAL MOVEMENT: Detect Port Forwarding
# ==============================================================================
# Usage: audit_detect_port_forward <log_file>
audit_detect_port_forward() {
    local LOG_FILE="${1:-audit.log}"
    
    echo "--- [15] Hunting for Port Forwarding Tunnels ---"
    (echo "TIMESTAMP USER NAMESPACE POD"; jq -r 'select(
      .objectRef.subresource == "portforward" and
      .responseStatus.code == 101
    ) | [
      .requestReceivedTimestamp,
      .user.username,
      .objectRef.namespace,
      .objectRef.name
    ] | @tsv' "$LOG_FILE") | column -t
}

# ==============================================================================
# 16. PRIVILEGE ESCALATION: Detect Node Debugging (Root Shell)
# ==============================================================================
# Usage: audit_detect_node_debug <log_file>
audit_detect_node_debug() {
    local LOG_FILE="${1:-audit.log}"
    
    echo "--- [16] Hunting for 'oc debug node' usage ---"
    (echo "TIMESTAMP USER POD NODE"; jq -r 'select(
      .verb == "create" and
      .objectRef.resource == "pods" and
      (.objectRef.name // "" | endswith("-debug")) and
      (.requestObject.spec.containers[0].securityContext.privileged == true)
    ) | [
      .requestReceivedTimestamp,
      .user.username,
      .objectRef.name,
      .requestObject.spec.nodeName
    ] | @tsv' "$LOG_FILE") | column -t
}

# ==============================================================================
# 17. PERSISTENCE: Detect Sensitive Host Mounts
# ==============================================================================
# Usage: audit_detect_sensitive_mounts <log_file>
audit_detect_sensitive_mounts() {
    local LOG_FILE="${1:-audit.log}"
    
    echo "--- [17] Hunting for Sensitive Host Paths (/etc/kubernetes, /var/lib/etcd) ---"
    (echo "TIMESTAMP USER POD MOUNT_PATH"; jq -r 'select(
      .verb == "create" and
      .objectRef.resource == "pods" and
      .requestObject.spec.volumes != null
    ) | . as $parent | .requestObject.spec.volumes[] | select(
      .hostPath != null and
      (
        (.hostPath.path // "" | startswith("/etc/kubernetes")) or
        (.hostPath.path // "" | startswith("/var/lib/etcd")) or
        (.hostPath.path // "" | contains("docker.sock")) or
        (.hostPath.path // "" | contains("crio.sock"))
      )
    ) | [
      $parent.requestReceivedTimestamp,
      $parent.user.username,
      $parent.objectRef.name,
      .hostPath.path
    ] | @tsv' "$LOG_FILE") | column -t
}

# ==============================================================================
# 18. CREDENTIAL ACCESS: Detect Brute Force Attacks
# ==============================================================================
# Usage: audit_detect_bruteforce <log_file>
audit_detect_bruteforce() {
    local LOG_FILE="${1:-audit.log}"
    
    echo "--- [18] Hunting for Brute Force (Top 401 Unauthorized Sources) ---"
    echo "COUNT SOURCE_IP"
    jq -r 'select(.responseStatus.code == 401) | .sourceIPs[0]' "$LOG_FILE" | sort | uniq -c | sort -nr | head -n 10
}

# ==============================================================================
# HELP MENU
# ==============================================================================
audit_help() {
    echo "OpenShift Forensic Library - Usage Guide"
    echo "----------------------------------------"
    echo "Usage: source forensics.sh"
    echo "Then run any of the following functions:"
    echo ""
    echo "  audit_fetch_logs                 [output_file]        - Fetch audit logs from all master nodes"
    echo "  audit_detect_anonymous_access    <file> [ip_prefix]   - Find anonymous probes from pod network"
    echo "  audit_detect_reconnaissance      <file> [user]        - Find 'SelfSubjectAccessReviews'"
    echo "  audit_detect_resource_harvesting <file> <user> [ip]   - Find 'List' attempts on Secrets/ConfigMaps/Pods"
    echo "  audit_detect_privileged_pods     <file>               - Find 'HostPID' or 'Privileged' pod creation"
    echo "  audit_detect_exec_sessions       <file> [pod]         - Find 'oc exec' sessions"
    echo "  audit_extract_pod_payload        <file> <pod>         - Extract Image and Command used"
    echo "  audit_lookup_pod_by_ip           <file> <ip>          - Find Pod by IP using OVN annotations"
    echo "  audit_detect_kubevirt_console    <file>               - Find VM Console/VNC/SSH access"
    echo "  audit_detect_kubevirt_vm_creation <file>              - Find VM creation events"
    echo "  audit_detect_persistence         <file> [user]        - Find suspicious CronJobs/DaemonSets"
    echo "  audit_detect_tampering           <file> [user]        - Find ConfigMap/Secret modifications"
    echo "  audit_detect_impersonation       <file>               - Find usage of --as impersonation"
    echo "  audit_track_ip_activity          <file> <ip>          - Investigate IP history and identity switching"
    echo "  audit_track_pod_lifecycle        <file> <pod>         - Show full lifecycle history of a pod"
    echo "  audit_detect_admin_grants        <file>               - Find creation of 'cluster-admin' bindings"
    echo "  audit_detect_port_forward        <file>               - Find 'port-forward' usage"
    echo "  audit_detect_node_debug          <file>               - Find 'oc debug node' usage"
    echo "  audit_detect_sensitive_mounts    <file>               - Find pods mounting /etc/kubernetes etc"
    echo "  audit_detect_bruteforce          <file>               - Find top sources of 401 Unauthorized"
    echo ""
    echo "Example: audit_detect_privileged_pods audit.log"
}

# If the script is executed directly (not sourced), show help.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    audit_help
fi