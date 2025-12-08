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
# Usage: audit_fetch [output_file]
audit_fetch() {
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
# Usage: audit_anon <log_file> [ip_prefix]
audit_anon() {
    local LOG_FILE="${1:-audit.log}"
    local IP_PREFIX="${2:-10.128.}"

    echo "--- [1] Hunting for Anonymous Probes from IP range: $IP_PREFIX ---"
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
# Usage: audit_recon <log_file> [user_pattern]
audit_recon() {
    local LOG_FILE="${1:-audit.log}"
    local USER_PATTERN="${2:-system:serviceaccount:}"

    echo "--- [2] Hunting for Recon (SelfSubjectAccessReview) by: $USER_PATTERN ---"
    (echo "TIMESTAMP USER NAMESPACE DECISION REASON"; jq -r --arg user "$USER_PATTERN" 'select(
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
    ] | @tsv' "$LOG_FILE") | column -t
}

# ==============================================================================
# 3. CREDENTIAL ACCESS: Detect Resource Harvesting
# ==============================================================================
# Usage: audit_harvesting <log_file> [target_user]
audit_harvesting() {
    local LOG_FILE="${1:-audit.log}"
    local TARGET_USER="$2"

    if [ -z "$TARGET_USER" ]; then
        echo "Error: You must provide a target user (e.g., 'visa-processor')"
        return 1
    fi

    echo "--- [3] Hunting for Resource Harvesting by: $TARGET_USER ---"
    (echo "TIMESTAMP USER RESOURCE CODE USER_AGENT"; jq -r --arg user "$TARGET_USER" 'select(
      .verb == "list" and
      (.objectRef.resource == "secrets" or .objectRef.resource == "configmaps" or .objectRef.resource == "pods") and
      (.user.username | contains($user))
    ) | [
      .requestReceivedTimestamp, 
      .user.username, 
      .objectRef.resource,
      .responseStatus.code,
      (.userAgent | split(" ")[0])
    ] | @tsv' "$LOG_FILE") | column -t
}

# ==============================================================================
# 4. ESCALATION: Detect Container Escapes (HostPID / Privileged)
# ==============================================================================
# Usage: audit_escape <log_file>
# Note: Uses 'any' and '?' to safely handle logs where requestObject is null
audit_escape() {
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
      "ALERT: Dangerous Pod Spec"
    ] | @tsv' "$LOG_FILE") | column -t
}

# ==============================================================================
# 5. LATERAL MOVEMENT: Detect Exec Sessions
# ==============================================================================
# Usage: audit_exec <log_file> [pod_name]
audit_exec() {
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
# Usage: audit_payload <log_file> <pod_name>
# Note: Checks for 'containers != null' to prevent crashes on partial logs
audit_payload() {
    local LOG_FILE="${1:-audit.log}"
    local POD_NAME="$2"

    if [ -z "$POD_NAME" ]; then
        echo "Error: You must provide a pod name."
        return 1
    fi

    echo "--- [6] Extracting Payload for Pod: $POD_NAME ---"
    (echo "NAMESPACE IMAGE COMMAND"; jq -r --arg pod "$POD_NAME" 'select(
      .verb == "create" and 
      .objectRef.resource == "pods" and 
      .objectRef.name == $pod and
      .requestObject.spec.containers != null
    ) | . as $parent | .requestObject.spec.containers[] | [
      $parent.objectRef.namespace,
      .image, 
      (.command | join(" "))
    ] | @tsv' "$LOG_FILE") | column -t
}

# ==============================================================================
# 7. NETWORK FORENSICS: Find Pod by IP (OVN Annotation Method)
# Best for clusters where standard Status IP logging is missing or filtered.
# Usage: audit_ovn_ips <log_file> <ip_address>
audit_ovn_ips() {
    local LOG_FILE="${1:-audit.log}"
    local TARGET_IP="$2"

    if [ -z "$TARGET_IP" ]; then
        echo "Error: You must provide an IP address."
        return 1
    fi

    echo "--- [7] Hunting for Pod owning IP: $TARGET_IP ---"
    (echo "TIMESTAMP POD IP"; jq -r --arg ip "$TARGET_IP" 'select(
      .objectRef.resource == "pods" and
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
# Usage: audit_kubevirt_console <log_file>
audit_virt_console() {
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

# Usage: audit_kubevirt_vm <log_file>
audit_virt_vm() {
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
# Usage: audit_persistence <log_file> [user_pattern]
audit_persistence() {
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
# Usage: audit_tampering <log_file> [user_pattern]
audit_tampering() {
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
# Usage: audit_impersonation <log_file>
audit_impersonation() {
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
# Usage: audit_ip_history <log_file> <ip_address>
audit_ip_history() {
    local LOG_FILE="${1:-audit.log}"
    local TARGET_IP="$2"

    if [ -z "$TARGET_IP" ]; then
        echo "Error: You must provide an IP address."
        return 1
    fi

    echo "--- History of Activity for IP: $TARGET_IP ---"
    
    (echo "TIMESTAMP USER VERB URI CODE"; jq -r --arg ip "$TARGET_IP" 'select(
      # Check if the IP list contains our target
      (.sourceIPs[]? | contains($ip))
    ) | [
      .requestReceivedTimestamp,
      .user.username,
      .verb,
      .requestURI,
      .responseStatus.code
    ] | @tsv' "$LOG_FILE") | column -t
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
    echo "  audit_fetch    [output_file]        - Fetch audit logs from all master nodes"
    echo "  audit_anon     <file> [ip_prefix]   - Find anonymous probes from pod network"
    echo "  audit_recon    <file> [user]        - Find 'SelfSubjectAccessReviews'"
    echo "  audit_harvesting <file> <user>      - Find 'List' attempts on Secrets/ConfigMaps/Pods"
    echo "  audit_escape   <file>               - Find 'HostPID' or 'Privileged' pod creation"
    echo "  audit_exec     <file> [pod]         - Find 'oc exec' sessions"
    echo "  audit_payload  <file> <pod>         - Extract Image and Command used"
    echo "  audit_ovn_ips  <file> <ip>          - Find Pod by IP using OVN annotations"
    echo "  audit_virt_console <file>       - Find VM Console/VNC/SSH access"
    echo "  audit_virt_vm      <file>       - Find VM creation events"
    echo "  audit_persistence      <file> [user] - Find suspicious CronJobs/DaemonSets"
    echo "  audit_tampering        <file> [user] - Find ConfigMap/Secret modifications"
    echo "  audit_impersonation    <file>       - Find usage of --as impersonation"
    echo "  audit_ip_history       <file> <ip>  - Show all activity for a specific IP"
    echo "  audit_ip_history       <file> <ip>   - Investigate IP history and identity switching"
    echo ""
    echo "Example: audit_escape audit.log"
}

# If the script is executed directly (not sourced), show help.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    audit_help
fi