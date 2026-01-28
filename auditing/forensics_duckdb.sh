#!/bin/bash

# ==============================================================================
# OPENSHIFT FORENSIC LIBRARY (DuckDB Edition) - FIXED & OPTIMIZED
# ------------------------------------------------------------------------------
# A toolkit for hunting threats in Kubernetes/OpenShift Audit Logs.
# Powered by DuckDB for high-performance SQL analysis.
#
# Features:
# - Auto-Caching (Parquet/DuckDB format) with Integrity Checks
# - Input Sanitization & SQL Injection Protection
# - Robust Schema Handling for unstructured JSON logs
# ==============================================================================

# Strict Mode (Safe execution)
set -o pipefail

# ANSI Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Dependency Check
for cmd in duckdb column; do
    if ! command -v $cmd &> /dev/null; then
        echo -e "${RED}Error:${NC} '$cmd' is not installed. Please install it to use this tool."
        return 1 2>/dev/null || exit 1
    fi
done

# ==============================================================================
# INTERNAL: Input Sanitization (Prevents SQL Syntax Errors)
# ==============================================================================
sql_escape() {
    local input="$1"
    # Replace single quote with two single quotes (SQL escaping)
    echo "${input//\'/\'\'}"
}

# ==============================================================================
# INTERNAL: Argument Resolver
# Logic: 
#   If $1 exists as a file -> FILE=$1, TERM=$2
#   Else -> FILE=audit.log, TERM=$1
# ==============================================================================
_resolve_args() {
    local arg1="$1"
    local arg2="$2"
    
    if [[ -f "$arg1" ]]; then
        RET_FILE="$arg1"
        RET_TERM="$(sql_escape "$arg2")"
    else
        RET_FILE="audit.log"
        RET_TERM="$(sql_escape "$arg1")"
    fi
}

# ==============================================================================
# INTERNAL: Run SQL against JSON (With Indexed Caching)
# ==============================================================================
run_sql() {
    local LOG_FILE="$1"
    local QUERY="$2"
    
    if [[ ! -f "$LOG_FILE" ]]; then
        echo -e "${RED}Error:${NC} Log file '$LOG_FILE' not found."
        return 1
    fi

    local BASE_NAME="${LOG_FILE##*/}"
    local CACHE_DB=".${BASE_NAME}.duckdb"
    local SIG_FILE=".${BASE_NAME}.sig"

    # 1. Calculate Robust Signature (Inode + Size + MTime)
    local CURRENT_SIG
    if stat --version &>/dev/null; then
        CURRENT_SIG=$(stat -c "%i:%s:%Y" "$LOG_FILE") # Linux
    else
        CURRENT_SIG=$(stat -f "%i:%z:%m" "$LOG_FILE") # MacOS
    fi

    local STORED_SIG=""
    [[ -f "$SIG_FILE" ]] && STORED_SIG=$(cat "$SIG_FILE")

    # 2. Check Validity & Build Cache
    if [[ ! -f "$CACHE_DB" ]] || [[ "$CURRENT_SIG" != "$STORED_SIG" ]]; then
        echo -e "${YELLOW}--- ⚡ Detected file change. Building Indexed Cache for '$LOG_FILE' ... ---${NC}" >&2
        
        rm -f "$CACHE_DB"
        
        # Build DB with memory optimization
        duckdb "$CACHE_DB" -c "
            PRAGMA memory_limit='4GB';
            PRAGMA threads=4;
            
            CREATE TABLE logs AS 
            SELECT * FROM read_json_auto('$LOG_FILE', format='newline_delimited', ignore_errors=true, union_by_name=true);
            
            -- Create Indexes for performance
            CREATE INDEX IF NOT EXISTS idx_verb ON logs(verb);
            CREATE INDEX IF NOT EXISTS idx_res ON logs((objectRef.resource));
            CREATE INDEX IF NOT EXISTS idx_name ON logs((objectRef.name));
            CREATE INDEX IF NOT EXISTS idx_user ON logs((user.username));
            CREATE INDEX IF NOT EXISTS idx_code ON logs((responseStatus.code));
        "
        
        if [[ $? -eq 0 ]]; then
            echo "$CURRENT_SIG" > "$SIG_FILE"
            echo -e "${GREEN}--- Cache build complete. ---${NC}" >&2
        else
            echo -e "${RED}--- Cache build failed! ---${NC}" >&2
            rm -f "$CACHE_DB"
            return 1
        fi
    fi

    # 3. Execute Query
    # FIX: Removed invalid '-s' flag. Passed DB file as positional argument.
    local OUTPUT
    OUTPUT=$(duckdb "$CACHE_DB" -c "COPY ($QUERY) TO STDOUT (HEADER, DELIMITER '\t');")
    
    if [[ -z "$OUTPUT" ]]; then
        echo -e "${BLUE}[INFO] No results found.${NC}"
    else
        echo "$OUTPUT" | column -t -s $'\t'
    fi
}

# ==============================================================================
# 1. INITIAL ACCESS: Detect Anonymous Probing
# ==============================================================================
audit_detect_anonymous_access() {
    _resolve_args "$1" "$2"
    local IP_PREFIX="${RET_TERM:-10.}" 

    echo -e "${BLUE}--- [1] Hunting for Anonymous Probes (Denied) from '${IP_PREFIX}%' ---${NC}"
    run_sql "$RET_FILE" "
        SELECT 
            requestReceivedTimestamp AS timestamp,
            verb,
            requestURI,
            sourceIPs[1] AS source_ip
        FROM logs
        WHERE user.username = 'system:anonymous'
          AND responseStatus.code = 403
          AND sourceIPs[1] LIKE '${IP_PREFIX}%'
        ORDER BY timestamp DESC
    "
}

# ==============================================================================
# 2. DISCOVERY: Detect Reconnaissance
# ==============================================================================
audit_detect_reconnaissance() {
    _resolve_args "$1" "$2"
    local USER_PATTERN="${RET_TERM:-system:serviceaccount:}"

    echo -e "${BLUE}--- [2] Hunting for Recon (SelfSubjectAccessReview) by: $USER_PATTERN ---${NC}"
    run_sql "$RET_FILE" "
        SELECT 
            requestReceivedTimestamp AS timestamp,
            user.username,
            annotations['authorization.k8s.io/decision'] AS decision,
            sourceIPs[1] AS source_ip
        FROM logs
        WHERE objectRef.resource = 'selfsubjectaccessreviews'
          AND user.username LIKE '${USER_PATTERN}%'
          AND user.username NOT LIKE '%openshift%'
          AND user.username NOT LIKE '%stackrox%'
          AND user.username NOT LIKE '%kube-system%'
    "
}

# ==============================================================================
# 3. CREDENTIAL ACCESS: Detect Resource Harvesting
# ==============================================================================
audit_detect_resource_harvesting() {
    _resolve_args "$1" "$2"
    if [[ -z "$RET_TERM" ]]; then echo -e "${RED}Error: Missing target user pattern.${NC}"; return 1; fi

    echo -e "${BLUE}--- [3] Hunting for Resource Harvesting by: $RET_TERM ---${NC}"
    run_sql "$RET_FILE" "
        SELECT 
            requestReceivedTimestamp AS timestamp,
            user.username,
            objectRef.resource,
            responseStatus.code,
            split_part(userAgent, ' ', 1) AS agent
        FROM logs
        WHERE verb = 'list'
          AND user.username LIKE '%${RET_TERM}%'
          AND objectRef.resource IN ('secrets', 'configmaps', 'routes')
    "
}

# ==============================================================================
# 4. ESCALATION: Detect Container Escapes (HostPID / Privileged)
# ==============================================================================
audit_detect_privileged_pods() {
    _resolve_args "$1" "$2"
    local USER_FILTER="${RET_TERM:-%}"

    echo -e "${BLUE}--- [4] Hunting for Privileged Pods & HostPID ---${NC}"
    run_sql "$RET_FILE" "
        SELECT 
            requestReceivedTimestamp AS timestamp,
            user.username,
            objectRef.name,
            objectRef.namespace,
            CASE 
                WHEN json_extract_string(requestObject, '$.spec.hostPID') = 'true' THEN 'HostPID'
                ELSE 'Privileged' 
            END AS violation
        FROM logs
        WHERE verb = 'create' 
          AND objectRef.resource = 'pods'
          AND user.username LIKE '%${USER_FILTER}%'
          AND user.username NOT LIKE '%openshift%'
          AND user.username NOT LIKE '%kube-system%'
          AND (
            json_extract_string(requestObject, '$.spec.hostPID') = 'true'
            OR
            regexp_matches(json_extract_string(requestObject, '$.spec.containers'), '\"privileged\"\s*:\s*true')
          )
    "
}

# ==============================================================================
# 5. LATERAL MOVEMENT: Detect Exec Sessions
# ==============================================================================
audit_detect_exec_sessions() {
    _resolve_args "$1" "$2"
    local POD_FILTER="${RET_TERM:-%}"

    echo -e "${BLUE}--- [5] Hunting for Exec Sessions ---${NC}"
    run_sql "$RET_FILE" "
        SELECT 
            requestReceivedTimestamp AS timestamp,
            user.username,
            objectRef.namespace,
            objectRef.name AS pod_name,
            requestURI
        FROM logs
        WHERE objectRef.subresource = 'exec'
          AND responseStatus.code = 101
          AND objectRef.name LIKE '${POD_FILTER}'
        ORDER BY timestamp
    "
}

# ==============================================================================
# 6. PAYLOAD ANALYSIS: Extract Image & Command (Fixed)
# ==============================================================================
audit_extract_pod_payload() {
    _resolve_args "$1" "$2"
    if [[ -z "$RET_TERM" ]]; then echo -e "${RED}Error: Missing pod name.${NC}"; return 1; fi

    echo -e "${BLUE}--- [6] Extracting Payload for Pod: $RET_TERM ---${NC}"
    
    # Changes:
    # 1. Added "AND verb = 'create'" to ensure we grab the event containing the Spec.
    # 2. Extract both 'command' AND 'args' to see the full execution line.
    # 3. Use concat_ws to join them cleanly.
    
    run_sql "$RET_FILE" "
        WITH pod_data AS (
            SELECT 
                COALESCE(try_cast(responseObject AS JSON), try_cast(requestObject AS JSON)) as obj
            FROM logs
            WHERE objectRef.resource = 'pods' 
              AND objectRef.name = '${RET_TERM}'
              AND verb = 'create'
            LIMIT 1
        ),
        containers AS (
            SELECT unnest(from_json(json_extract(obj, '$.spec.containers'), '[\"JSON\"]')) as container
            FROM pod_data
            WHERE obj IS NOT NULL
        )
        SELECT 
            json_extract_string(container, '$.name') as container_name,
            json_extract_string(container, '$.image') as image,
            -- Combine Command and Args into one string, handling NULLs safely
            concat_ws(' ', 
                COALESCE(array_to_string(json_extract(container, '$.command')::VARCHAR[], ' '), ''),
                COALESCE(array_to_string(json_extract(container, '$.args')::VARCHAR[], ' '), '')
            ) as full_command
        FROM containers
    "
}

# ==============================================================================
# 7. NETWORK FORENSICS: Find Pod by IP (OVN/Multus Aware)
# ==============================================================================
audit_lookup_pod_by_ip() {
    _resolve_args "$1" "$2"
    local TARGET_IP="$RET_TERM"

    if [[ -z "$TARGET_IP" ]]; then echo -e "${RED}Error: Missing IP address.${NC}"; return 1; fi

    echo -e "${BLUE}--- [7] Hunting for Pod owning IP: $TARGET_IP ---${NC}"
    run_sql "$RET_FILE" "
        WITH pod_data AS (
            SELECT 
                requestReceivedTimestamp,
                objectRef.name,
                objectRef.namespace,
                COALESCE(try_cast(responseObject AS JSON), try_cast(requestObject AS JSON)) as obj
            FROM logs
            WHERE objectRef.resource = 'pods'
              AND (responseObject IS NOT NULL OR requestObject IS NOT NULL)
        )
        SELECT 
            requestReceivedTimestamp AS timestamp,
            name AS pod_name,
            namespace
        FROM pod_data
        WHERE 
            -- 1. Standard IP
            json_extract_string(obj, '$.status.podIP') = '${TARGET_IP}'
            OR
            -- 2. OpenShift OVN Annotation
            json_extract_string(obj, '$.metadata.annotations.\"k8s.ovn.org/pod-networks\"') LIKE '%${TARGET_IP}%'
            OR
            -- 3. Multus/CNI Annotation
            json_extract_string(obj, '$.metadata.annotations.\"k8s.v1.cni.cncf.io/network-status\"') LIKE '%${TARGET_IP}%'
    "
}

# ==============================================================================
# 8. KUBEVIRT FORENSICS
# ==============================================================================
audit_detect_kubevirt_console() {
    _resolve_args "$1" "$2"
    echo -e "${BLUE}--- [8a] Hunting for VM Console/VNC Access ---${NC}"
    run_sql "$RET_FILE" "
        SELECT 
            requestReceivedTimestamp AS timestamp,
            user.username,
            objectRef.name,
            objectRef.subresource,
            'REMOTE_ACCESS' AS alert
        FROM logs
        WHERE objectRef.subresource IN ('console', 'vnc', 'ssh')
    "
}

audit_detect_kubevirt_vm_creation() {
    _resolve_args "$1" "$2"
    echo -e "${BLUE}--- [8b] Hunting for KubeVirt VM Creations ---${NC}"
    run_sql "$RET_FILE" "
        SELECT 
            requestReceivedTimestamp AS timestamp,
            user.username,
            objectRef.resource,
            objectRef.name,
            'VM_CREATED' AS action
        FROM logs
        WHERE verb = 'create'
          AND objectRef.resource IN ('virtualmachines', 'virtualmachineinstances')
    "
}

# ==============================================================================
# 9. PERSISTENCE & TAMPERING
# ==============================================================================
audit_detect_persistence() {
    _resolve_args "$1" "$2"
    local USER_FILTER="${RET_TERM:-%}"

    echo -e "${BLUE}--- [9] Hunting for Persistence (Workloads) ---${NC}"
    run_sql "$RET_FILE" "
        SELECT 
            requestReceivedTimestamp,
            user.username,
            objectRef.resource,
            objectRef.name
        FROM logs
        WHERE verb = 'create'
          AND objectRef.resource IN ('cronjobs', 'daemonsets', 'deployments', 'jobs', 'statefulsets')
          AND user.username LIKE '%${USER_FILTER}%'
          AND user.username NOT LIKE '%openshift%'
          AND user.username NOT LIKE '%kube%'
    "
}

audit_detect_tampering() {
    _resolve_args "$1" "$2"
    local USER_FILTER="${RET_TERM:-%}"

    echo -e "${BLUE}--- [10] Hunting for Config/Secret Tampering ---${NC}"
    run_sql "$RET_FILE" "
        SELECT 
            requestReceivedTimestamp,
            user.username,
            objectRef.resource,
            objectRef.name,
            verb
        FROM logs
        WHERE verb IN ('patch', 'update')
          AND objectRef.resource IN ('configmaps', 'secrets')
          AND user.username LIKE '%${USER_FILTER}%'
          AND user.username NOT LIKE 'system:%'
    "
}

# ==============================================================================
# 11. EVASION: User Impersonation (Safe Schema Check)
# ==============================================================================
audit_detect_impersonation() {
    _resolve_args "$1" "$2"
    echo -e "${BLUE}--- [11] Hunting for Impersonation (User: --as) ---${NC}"
    
    # Strictly define columns to handle missing impersonatedUser
    duckdb -c "
        COPY (
            SELECT 
                requestReceivedTimestamp AS timestamp,
                user.username AS real_user,
                impersonatedUser.username AS fake_user,
                verb,
                requestURI
            FROM read_json('$RET_FILE', columns={
                'requestReceivedTimestamp': 'VARCHAR',
                'verb': 'VARCHAR',
                'requestURI': 'VARCHAR',
                'user': 'STRUCT(username VARCHAR)', 
                'impersonatedUser': 'STRUCT(username VARCHAR)'
            }, format='newline_delimited', ignore_errors=true)
            WHERE impersonatedUser IS NOT NULL
              AND user.username NOT LIKE '%openshift%'
              AND user.username NOT LIKE '%kube-system%'
        ) TO STDOUT (HEADER, DELIMITER '	');
    " | column -t -s $'\t'
}

# ==============================================================================
# 12. INVESTIGATION: Full Activity Tracks
# ==============================================================================
audit_track_ip_activity() {
    _resolve_args "$1" "$2"
    if [[ -z "$RET_TERM" ]]; then echo -e "${RED}Error: Missing IP.${NC}"; return 1; fi

    echo -e "${BLUE}--- History of Activity for IP: $RET_TERM ---${NC}"
    run_sql "$RET_FILE" "
        SELECT 
            requestReceivedTimestamp,
            user.username,
            verb,
            objectRef.resource,
            responseStatus.code
        FROM logs
        WHERE list_contains(sourceIPs, '${RET_TERM}')
        ORDER BY requestReceivedTimestamp
    "
}

audit_track_user_activity() {
    _resolve_args "$1" "$2"
    if [[ -z "$RET_TERM" ]]; then echo -e "${RED}Error: Missing Username.${NC}"; return 1; fi

    echo -e "${BLUE}--- History of Activity for User: $RET_TERM ---${NC}"
    run_sql "$RET_FILE" "
        SELECT DISTINCT
            requestReceivedTimestamp,
            verb,
            objectRef.resource,
            objectRef.namespace,
            objectRef.name,
            responseStatus.code
        FROM logs
        WHERE user.username LIKE '%${RET_TERM}%'
        ORDER BY requestReceivedTimestamp
    "
}

# ==============================================================================
# 14. PRIVILEGE ESCALATION: Cluster Admin Grants
# ==============================================================================
audit_detect_admin_grants() {
    _resolve_args "$1" "$2"
    echo -e "${BLUE}--- [14] Hunting for 'cluster-admin' grants ---${NC}"
    run_sql "$RET_FILE" "
        SELECT 
            requestReceivedTimestamp,
            user.username AS actor,
            objectRef.name AS binding_name,
            json_extract_string(requestObject, '$.roleRef.name') as role
        FROM logs
        WHERE objectRef.resource = 'clusterrolebindings'
          AND verb IN ('create', 'update', 'patch')
          AND json_extract_string(requestObject, '$.roleRef.name') = 'cluster-admin'
    "
}

# ==============================================================================
# 15. INVESTIGATION: Pod Lifecycle
# ==============================================================================
audit_track_pod_lifecycle() {
    _resolve_args "$1" "$2"
    if [[ -z "$RET_TERM" ]]; then echo -e "${RED}Error: Missing pod name.${NC}"; return 1; fi
    local POD_NAME="$RET_TERM"

    echo -e "${BLUE}--- Lifecycle History for Pod: $POD_NAME ---${NC}"
    
    echo ">>> Metadata:"
    run_sql "$RET_FILE" "
        SELECT DISTINCT
            objectRef.namespace,
            json_extract_string(COALESCE(try_cast(responseObject AS JSON), try_cast(requestObject AS JSON)), '$.spec.serviceAccountName') AS service_account,
            json_extract_string(COALESCE(try_cast(responseObject AS JSON), try_cast(requestObject AS JSON)), '$.spec.nodeName') AS node,
            json_extract_string(COALESCE(try_cast(responseObject AS JSON), try_cast(requestObject AS JSON)), '$.status.podIP') AS ip_address
        FROM logs
        WHERE objectRef.resource = 'pods' 
          AND objectRef.name = '${POD_NAME}'
          AND (requestObject IS NOT NULL OR responseObject IS NOT NULL)
        LIMIT 1
    "

    echo ""
    echo ">>> Creation Event:"
    run_sql "$RET_FILE" "
        SELECT 
            requestReceivedTimestamp AS creation_time,
            user.username AS created_by
        FROM logs
        WHERE objectRef.resource = 'pods' 
          AND objectRef.name = '${POD_NAME}' 
          AND verb = 'create'
    "
    
    echo ""
    audit_extract_pod_payload "$RET_FILE" "$POD_NAME"
}

# ==============================================================================
# 16. LATERAL MOVEMENT: Port Forwarding
# ==============================================================================
audit_detect_port_forward() {
    _resolve_args "$1" "$2"
    echo -e "${BLUE}--- [16] Hunting for Port Forwarding Tunnels ---${NC}"
    run_sql "$RET_FILE" "
        SELECT 
            requestReceivedTimestamp AS timestamp,
            user.username,
            objectRef.namespace,
            objectRef.name AS pod_name
        FROM logs
        WHERE objectRef.subresource = 'portforward'
          AND responseStatus.code = 101
    "
}

# ==============================================================================
# 17. PRIVILEGE ESCALATION: Node Debug
# ==============================================================================
audit_detect_node_debug() {
    _resolve_args "$1" "$2"
    echo -e "${BLUE}--- [17] Hunting for 'oc debug node' usage ---${NC}"
    run_sql "$RET_FILE" "
        SELECT 
            requestReceivedTimestamp AS timestamp,
            user.username,
            objectRef.name AS pod_name,
            json_extract_string(requestObject, '$.spec.nodeName') AS target_node
        FROM logs
        WHERE verb = 'create'
          AND objectRef.resource = 'pods'
          AND objectRef.name LIKE '%-debug'
          AND regexp_matches(json_extract_string(requestObject, '$.spec.containers'), '\"privileged\"\s*:\s*true')
    "
}

# ==============================================================================
# 18. PERSISTENCE: Sensitive Host Mounts
# ==============================================================================
audit_detect_sensitive_mounts() {
    _resolve_args "$1" "$2"
    echo -e "${BLUE}--- [18] Hunting for Sensitive Host Paths (/etc/kubernetes, etc) ---${NC}"
    run_sql "$RET_FILE" "
        SELECT 
            requestReceivedTimestamp AS timestamp,
            user.username,
            objectRef.name,
            'HostPath Mount' AS type
        FROM logs
        WHERE verb = 'create'
          AND objectRef.resource = 'pods'
          AND json_extract_string(requestObject, '$.spec.volumes') IS NOT NULL
          AND regexp_matches(
                json_extract_string(requestObject, '$.spec.volumes'), 
                'hostPath.*path.*(/etc/kubernetes|/var/lib/etcd|docker.sock|crio.sock)'
          )
    "
}

# ==============================================================================
# 19. CREDENTIAL ACCESS: Brute Force
# ==============================================================================
audit_detect_bruteforce() {
    _resolve_args "$1" "$2"
    echo -e "${BLUE}--- [19] Hunting for Brute Force (Top 401 Sources) ---${NC}"
    run_sql "$RET_FILE" "
        SELECT 
            sourceIPs[1] AS source_ip,
            COUNT(*) as count
        FROM logs
        WHERE responseStatus.code = 401
        GROUP BY source_ip
        ORDER BY count DESC
        LIMIT 10
    "
}


audit_help() {
    echo -e "${GREEN}OpenShift Forensic Library (DuckDB Edition) - Complete${NC}"
    echo "Usage: source forensics_duckdb.sh"
    echo ""
    echo "Core Syntax:"
    echo "  function_name [optional_file] [search_term]"
    echo "  * If file is omitted, defaults to 'audit.log'"
    echo ""
    echo "Functions:"
    echo "  audit_detect_anonymous_access    [file] [ip_prefix]   - Find 403s from anonymous users"
    echo "  audit_detect_reconnaissance      [file] [user]        - Find SelfSubjectAccessReviews"
    echo "  audit_detect_resource_harvesting [file] <user>        - Find suspicious List verbs"
    echo "  audit_detect_privileged_pods     [file] [user]        - Find HostPID/Privileged pods"
    echo "  audit_detect_exec_sessions       [file] [pod]         - Find 'oc exec' usage"
    echo "  audit_extract_pod_payload        [file] <pod>         - Extract image/cmd from pod spec"
    echo "  audit_lookup_pod_by_ip           [file] <ip>          - Resolve IP to Pod (OVN/Multus aware)"
    echo "  audit_detect_kubevirt_console    [file]               - Find VM Console/VNC access"
    echo "  audit_detect_kubevirt_vm_creation [file]              - Find VM Creation events"
    echo "  audit_detect_persistence         [file] [user]        - Find suspicious workload creation"
    echo "  audit_detect_tampering           [file] [user]        - Find Config/Secret modification"
    echo "  audit_detect_impersonation       [file]               - Find '--as' user impersonation"
    echo "  audit_detect_admin_grants        [file]               - Find cluster-admin role bindings"
    echo "  audit_track_pod_lifecycle        [file] <pod>         - Full metadata & event history of a pod"
    echo "  audit_detect_port_forward        [file]               - Find port-forwarding usage"
    echo "  audit_detect_node_debug          [file]               - Find 'oc debug node' usage"
    echo "  audit_detect_sensitive_mounts    [file]               - Find mounts of /etc/kubernetes, etc."
    echo "  audit_detect_bruteforce          [file]               - Find top sources of 401s"
    echo "  audit_track_user_activity        [file] <user>        - Full event timeline for a user"
    echo "  audit_track_ip_activity          [file] <ip>          - Full event timeline for an IP"
    echo ""
}

# Allow execution as a script or sourcing
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    audit_help
fi