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
    > "$OUTPUT_FILE"

    # Iterate over master nodes
    oc get nodes -l node-role.kubernetes.io/master -o custom-columns=NAME:.metadata.name --no-headers | while read -r master; do
        if [ -n "$master" ]; then
            echo "Fetching logs from ${master}..."
            oc adm node-logs "${master}" --path=kube-apiserver/audit.log >> "$OUTPUT_FILE"
        fi
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
    (echo "TIMESTAMP VERB URI NAMESPACE SOURCE_IP"; jq -r --arg ip "$IP_PREFIX" 'select(
      .user.username == "system:anonymous" and 
      .responseStatus.code == 403 and 
      (.sourceIPs[0] | startswith($ip))
    ) | [
      .requestReceivedTimestamp, 
      .verb, 
      .requestURI, 
      .objectRef.namespace,
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
# 3. CREDENTIAL ACCESS: Detect Secret Harvesting
# ==============================================================================
# Usage: audit_secrets <log_file> [target_user]
audit_secrets() {
    local LOG_FILE="${1:-audit.log}"
    local TARGET_USER="$2"

    if [ -z "$TARGET_USER" ]; then
        echo "Error: You must provide a target user (e.g., 'visa-processor')"
        return 1
    fi

    echo "--- [3] Hunting for Secret Listing by: $TARGET_USER ---"
    (echo "TIMESTAMP USER NAMESPACE CODE USER_AGENT"; jq -r --arg user "$TARGET_USER" 'select(
      .verb == "list" and
      .objectRef.resource == "secrets" and
      (.user.username | contains($user))
    ) | [
      .requestReceivedTimestamp, 
      .user.username, 
      .objectRef.namespace,
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
    (echo "TIMESTAMP USER NAMESPACE POD URI"; jq -r --arg pod "$POD_NAME" 'select(
      .objectRef.subresource == "exec" and
      .responseStatus.code == 101 and
      ($pod == "" or .objectRef.name == $pod)
    ) | [
      .requestReceivedTimestamp, 
      .user.username, 
      .objectRef.namespace,
      .objectRef.name, 
      .requestURI
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
# 7. NETWORK FORENSICS: Find Pod IP (OVN Annotation Method)
# ==============================================================================
# Best for clusters where standard Status IP logging is missing or filtered.
# Usage: audit_ovn_ips <log_file> [pod_name]
audit_ovn_ips() {
    local LOG_FILE="${1:-audit.log}"
    local POD_NAME="$2"

    echo "--- [7] Hunting for IP in OVN Annotations ---"
    (echo "TIMESTAMP NAMESPACE POD IP"; jq -r --arg pod "$POD_NAME" 'select(
      .objectRef.resource == "pods" and
      .requestObject.metadata.annotations["k8s.ovn.org/pod-networks"] != null and
      ($pod == "" or .objectRef.name == $pod)
    ) | [
      .requestReceivedTimestamp,
      .objectRef.namespace,
      .objectRef.name,
      (.requestObject.metadata.annotations["k8s.ovn.org/pod-networks"] | fromjson | .default.ip_addresses[0] | split("/")[0]) 
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
    echo "  audit_secrets  <file> <user>        - Find 'List Secrets' attempts"
    echo "  audit_escape   <file>               - Find 'HostPID' or 'Privileged' pod creation"
    echo "  audit_exec     <file> [pod]         - Find 'oc exec' sessions"
    echo "  audit_payload  <file> <pod>         - Extract Image and Command used"
    echo "  audit_ovn_ips  <file> [pod]         - Extract IP address from OVN annotations"
    echo ""
    echo "Example: audit_escape audit.log"
}

# If the script is executed directly (not sourced), show help.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    audit_help
fi