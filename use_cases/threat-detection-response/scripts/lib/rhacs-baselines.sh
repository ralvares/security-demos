#!/usr/bin/env bash
#
# Copied unchanged from github.com/ralvares/rhacs scripts/rhacs-baselines.sh
# rhacs-baselines.sh - manage RHACS process and network baselines from the CLI,
# without waiting for the observation/learning period.
#
# Source this file from your shell (or from ~/.bashrc / ~/.zshrc):
#
#   source examples/rhacs-baselines.sh
#
# Required environment (same as the other helpers):
#
#   export ROX_ENDPOINT=central.example.com:443
#   export ROX_API_TOKEN=<token>       # needs DeploymentExtension (write) + Deployment (read)
#
# Optional:
#
#   export ROX_CA_FILE=/path/ca.pem    # verify TLS (default: -k, verification skipped)
#
# All commands address a workload as NAMESPACE/DEPLOYMENT, e.g. payments/visa-processor.
#
# Process baselines:
#
#   rhacs-pb-export NS/DEPLOYMENT                    export baseline as JSON (all containers)
#   rhacs-pb-import NS/DEPLOYMENT FILE [--lock]      import processes from an export file,
#                                                    optionally lock right away
#   rhacs-pb-add    NS/DEPLOYMENT CONTAINER PROCESS [PROCESS...] [--lock]
#                                                    declare processes inline, no file needed
#   rhacs-pb-replace NS/DEPLOYMENT CONTAINER PROCESS [PROCESS...]
#                                                    replace the container baseline exactly
#   rhacs-pb-remove NS/DEPLOYMENT CONTAINER PROCESS [PROCESS...]
#                                                    remove processes from the baseline
#   rhacs-pb-lock   NS/DEPLOYMENT                    lock all containers of the deployment
#   rhacs-pb-unlock NS/DEPLOYMENT                    unlock again
#   rhacs-pb-audit  NS/DEPLOYMENT                    compare observed process history with
#                                                    the current baseline; fail on omissions
#
#   Export file format (hand-writable):
#     [ {"containerName": "app", "processes": ["/usr/sbin/httpd", "/bin/sh"]} ]
#
# Network baselines:
#
#   rhacs-nb-export NS/DEPLOYMENT                    export baseline as JSON (peers + lock state)
#   rhacs-nb-import NS/DEPLOYMENT FILE [--lock]      mark the peers from an export file as
#                                                    baseline flows, optionally lock
#   rhacs-nb-add    NS/DEPLOYMENT --peer NS/DEP|internet --port N [--udp] [--ingress] [--lock]
#                                                    add one flow to the baseline (flows never
#                                                    observed by RHACS are fine)
#   rhacs-nb-remove NS/DEPLOYMENT --peer NS/DEP|internet --port N [--udp] [--ingress]
#                                                    remove a flow (marks it anomalous/forbidden)
#   rhacs-nb-lock   NS/DEPLOYMENT                    lock (alerts on non-baseline flows)
#   rhacs-nb-unlock NS/DEPLOYMENT                    unlock
#
#   Note: network peers reference other entities by ID. Re-importing on the same
#   cluster (restore/relock after redeploy of the same workloads) is safe;
#   moving a baseline to a different cluster only works for INTERNET/external
#   peers, deployment-to-deployment peers would need their IDs re-resolved.
#
# Locking is what arms the runtime policies ("Unauthorized Process Execution",
# "Unauthorized Network Flow"). A baseline you declared and locked alerts
# immediately, no learning period involved.
#
# Dependencies: curl, jq

_roxb_curl() {
    local method="$1" path="$2" body="${3:-}"
    local curl_bin tls=(-k)
    [ -n "${ROX_CA_FILE:-}" ] && tls=(--cacert "$ROX_CA_FILE")
    curl_bin=$(command -v curl) || curl_bin=/usr/bin/curl

    if [ -z "${ROX_ENDPOINT:-}" ] || [ -z "${ROX_API_TOKEN:-}" ]; then
        echo "error: ROX_ENDPOINT and ROX_API_TOKEN must be set" >&2
        return 1
    fi

    if [ -n "$body" ]; then
        "$curl_bin" -sS "${tls[@]}" -X "$method" \
            -H "Authorization: Bearer $ROX_API_TOKEN" \
            -H "Content-Type: application/json" \
            -d "$body" \
            "https://${ROX_ENDPOINT}${path}"
    else
        "$curl_bin" -sS "${tls[@]}" -X "$method" \
            -H "Authorization: Bearer $ROX_API_TOKEN" \
            "https://${ROX_ENDPOINT}${path}"
    fi
}

# Parse NAMESPACE/DEPLOYMENT and resolve it -> NS, DEP, DEPLOY_ID, CLUSTER_ID,
# CONTAINERS (container names).
_roxb_resolve() {
    local target="$1" q result
    case "$target" in
        */*) ;;
        *) echo "error: expected NAMESPACE/DEPLOYMENT, got: $target" >&2; return 1 ;;
    esac
    NS="${target%%/*}"
    DEP="${target#*/}"

    q=$(jq -rn --arg q "Namespace:$NS+Deployment:$DEP" '$q|@uri')
    result=$(_roxb_curl GET "/v1/deployments?query=$q") || return 1

    DEPLOY_ID=$(jq -r --arg ns "$NS" --arg dep "$DEP" \
        '[.deployments[] | select(.namespace == $ns and .name == $dep)] | first | .id // empty' <<<"$result")
    if [ -z "$DEPLOY_ID" ]; then
        echo "error: deployment $DEP not found in namespace $NS" >&2
        return 1
    fi

    local full
    full=$(_roxb_curl GET "/v1/deployments/$DEPLOY_ID") || return 1
    CLUSTER_ID=$(jq -r '.clusterId' <<<"$full")
    CONTAINERS=$(jq -r '[.containers[].name] | join(" ")' <<<"$full")
}

# Central creates a deployment's network baseline lazily. GET forces creation,
# which the modify-peers API requires for every deployment involved.
_roxb_nb_ensure() {
    _roxb_curl GET "/v1/networkbaseline/$1" >/dev/null
}

# ------------------------------------------------------------ process baselines

rhacs-pb-export() {
    local target="${1:-}"
    if [ -z "$target" ]; then
        echo "usage: rhacs-pb-export NAMESPACE/DEPLOYMENT" >&2; return 1
    fi
    _roxb_resolve "$target" || return 1

    local c out="[]" baseline
    for c in $(echo "$CONTAINERS"); do
        baseline=$(_roxb_curl GET "/v1/processbaselines/key?key.deploymentId=$DEPLOY_ID&key.containerName=$c&key.clusterId=$CLUSTER_ID&key.namespace=$NS")
        out=$(jq --arg c "$c" --argjson b "$baseline" \
            '. + [{containerName: $c,
                   locked: (($b.userLockedTimestamp // null) != null),
                   processes: ([$b.elements[]?.element.processName] | unique)}]' <<<"$out")
    done
    jq . <<<"$out"
}

# Show what RHACS learned during normal execution, what setup declared
# explicitly, and what was deliberately removed. This is the CLI counterpart
# to the portal's process-baseline and running-process-history views.
rhacs-pb-history() {
    local target="${1:-}"
    if [ -z "$target" ]; then
        echo "usage: rhacs-pb-history NAMESPACE/DEPLOYMENT" >&2; return 1
    fi
    _roxb_resolve "$target" || return 1

    local c baseline
    for c in $(echo "$CONTAINERS"); do
        baseline=$(_roxb_curl GET "/v1/processbaselines/key?key.deploymentId=$DEPLOY_ID&key.containerName=$c&key.clusterId=$CLUSTER_ID&key.namespace=$NS") || return 1
        jq -r --arg c "$c" '
          "container " + $c + ": locked=" + (((.userLockedTimestamp // null) != null) | tostring),
          (.elements[]? | "  " + (if .auto then "learned  " else "declared " end) + .element.processName),
          (.elementGraveyard[]? | "  removed  " + .element.processName)
        ' <<<"$baseline"
    done
}

rhacs-pb-audit() {
    local target="${1:-}"
    if [ -z "$target" ]; then
        echo "usage: rhacs-pb-audit NAMESPACE/DEPLOYMENT" >&2; return 1
    fi
    _roxb_resolve "$target" || return 1

    local observed container baseline rows missing=0
    observed=$(_roxb_curl GET "/v1/processes/deployment/$DEPLOY_ID") || return 1
    for container in $(echo "$CONTAINERS"); do
        baseline=$(_roxb_curl GET "/v1/processbaselines/key?key.deploymentId=$DEPLOY_ID&key.containerName=$container&key.clusterId=$CLUSTER_ID&key.namespace=$NS") || return 1
        rows=$(jq -nr --arg c "$container" --argjson h "$observed" --argjson b "$baseline" '
            $h.processes
            | map(select(.containerName == $c) | .signal.execFilePath)
            | map(select(. != null and . != "")) | unique[] as $p
            | [$c, $p,
               (if ([$b.elements[]?.element.processName] | index($p))
                then "BASELINE"
                elif ([$b.elementGraveyard[]?.element.processName] | index($p))
                then "FORBIDDEN"
                else "MISSING" end)] | @tsv')
        if [ -z "$rows" ]; then
            echo "$container: no process history observed"
            continue
        fi
        printf '%s\n' "$rows"
        if grep -q $'\tMISSING$' <<<"$rows"; then missing=1; fi
    done
    [ "$missing" -eq 0 ] || {
        echo "error: observed processes are missing from $target baseline" >&2
        return 1
    }
}

rhacs-pb-import() {
    local target="${1:-}" file="${2:-}" lock=""
    case "${3:-}" in --lock) lock=1 ;; esac
    if [ -z "$target" ] || [ ! -f "$file" ]; then
        echo "usage: rhacs-pb-import NAMESPACE/DEPLOYMENT FILE [--lock]" >&2; return 1
    fi
    _roxb_resolve "$target" || return 1

    local n c procs body response
    n=$(jq 'length' "$file")
    local i=0
    while [ "$i" -lt "$n" ]; do
        c=$(jq -r ".[$i].containerName" "$file")
        procs=$(jq -c ".[$i].processes" "$file")
        body=$(jq -n --arg dep "$DEPLOY_ID" --arg c "$c" --arg cluster "$CLUSTER_ID" --arg ns "$NS" \
            --argjson procs "$procs" '{
                keys: [{deploymentId: $dep, containerName: $c, clusterId: $cluster, namespace: $ns}],
                addElements: [$procs[] | {processName: .}]
            }')
        response=$(_roxb_curl PUT "/v1/processbaselines" "$body") || return 1
        if [ -n "$(jq -r '.errors[]?.error // empty' <<<"$response")" ]; then
            echo "import failed for container $c:" >&2
            jq -r '.errors[].error' <<<"$response" >&2
            return 1
        fi
        echo "container $c: $(jq -r 'length' <<<"$procs") processes in baseline"
        i=$((i+1))
    done

    if [ -n "$lock" ]; then rhacs-pb-lock "$target"; fi
}

rhacs-pb-add() {
    local target="${1:-}" container="${2:-}" lock="" procs=()
    shift 2 2>/dev/null || { echo "usage: rhacs-pb-add NAMESPACE/DEPLOYMENT CONTAINER PROCESS [PROCESS...] [--lock]" >&2; return 1; }
    while [ $# -gt 0 ]; do
        case "$1" in --lock) lock=1 ;; *) procs+=("$1") ;; esac
        shift
    done
    if [ -z "$target" ] || [ -z "$container" ] || [ ${#procs[@]} -eq 0 ]; then
        echo "usage: rhacs-pb-add NAMESPACE/DEPLOYMENT CONTAINER PROCESS [PROCESS...] [--lock]" >&2; return 1
    fi
    _roxb_resolve "$target" || return 1

    local body response
    body=$(jq -n --arg dep "$DEPLOY_ID" --arg c "$container" --arg cluster "$CLUSTER_ID" --arg ns "$NS" \
        --args '{
            keys: [{deploymentId: $dep, containerName: $c, clusterId: $cluster, namespace: $ns}],
            addElements: [$ARGS.positional[] | {processName: .}]
        }' "${procs[@]}")
    response=$(_roxb_curl PUT "/v1/processbaselines" "$body") || return 1
    if [ -n "$(jq -r '.errors[]?.error // empty' <<<"$response")" ]; then
        echo "add failed:" >&2; jq -r '.errors[].error' <<<"$response" >&2; return 1
    fi
    echo "container $container: added ${#procs[@]} process(es)"

    if [ -n "$lock" ]; then rhacs-pb-lock "$target"; fi
}

rhacs-pb-remove() {
    local target="${1:-}" container="${2:-}" procs=()
    shift 2 2>/dev/null || { echo "usage: rhacs-pb-remove NAMESPACE/DEPLOYMENT CONTAINER PROCESS [PROCESS...]" >&2; return 1; }
    while [ $# -gt 0 ]; do procs+=("$1"); shift; done
    if [ -z "$target" ] || [ -z "$container" ] || [ ${#procs[@]} -eq 0 ]; then
        echo "usage: rhacs-pb-remove NAMESPACE/DEPLOYMENT CONTAINER PROCESS [PROCESS...]" >&2; return 1
    fi
    _roxb_resolve "$target" || return 1

    local body response
    body=$(jq -n --arg dep "$DEPLOY_ID" --arg c "$container" --arg cluster "$CLUSTER_ID" --arg ns "$NS" \
        --args '{
            keys: [{deploymentId: $dep, containerName: $c, clusterId: $cluster, namespace: $ns}],
            removeElements: [$ARGS.positional[] | {processName: .}]
        }' "${procs[@]}")
    response=$(_roxb_curl PUT "/v1/processbaselines" "$body") || return 1
    if [ -n "$(jq -r '.errors[]?.error // empty' <<<"$response")" ]; then
        echo "remove failed:" >&2; jq -r '.errors[].error' <<<"$response" >&2; return 1
    fi
    echo "container $container: removed ${#procs[@]} process(es)"
}

# Make a process baseline declarative. Unlike rhacs-pb-add, this removes stale
# learned or declared entries first, so repeated demo resets cannot grow the
# allowlist. The requested processes are then restored as explicit entries.
rhacs-pb-replace() {
    local target="${1:-}" container="${2:-}" procs=()
    shift 2 2>/dev/null || {
        echo "usage: rhacs-pb-replace NAMESPACE/DEPLOYMENT CONTAINER PROCESS [PROCESS...]" >&2
        return 1
    }
    while [ $# -gt 0 ]; do procs+=("$1"); shift; done
    if [ -z "$target" ] || [ -z "$container" ] || [ ${#procs[@]} -eq 0 ]; then
        echo "usage: rhacs-pb-replace NAMESPACE/DEPLOYMENT CONTAINER PROCESS [PROCESS...]" >&2
        return 1
    fi
    _roxb_resolve "$target" || return 1

    local baseline body response
    baseline=$(_roxb_curl GET "/v1/processbaselines/key?key.deploymentId=$DEPLOY_ID&key.containerName=$container&key.clusterId=$CLUSTER_ID&key.namespace=$NS") || return 1
    body=$(jq -n --arg dep "$DEPLOY_ID" --arg c "$container" --arg cluster "$CLUSTER_ID" --arg ns "$NS" \
        --argjson current "$(jq '[.elements[]?.element | {processName}] | unique_by(.processName)' <<<"$baseline")" '{
            keys: [{deploymentId: $dep, containerName: $c, clusterId: $cluster, namespace: $ns}],
            removeElements: $current
        }')
    if [ "$(jq '.removeElements | length' <<<"$body")" -gt 0 ]; then
        response=$(_roxb_curl PUT "/v1/processbaselines" "$body") || return 1
        if [ -n "$(jq -r '.errors[]?.error // empty' <<<"$response")" ]; then
            echo "replace cleanup failed:" >&2
            jq -r '.errors[].error' <<<"$response" >&2
            return 1
        fi
    fi
    rhacs-pb-add "$target" "$container" "${procs[@]}"
    echo "container $container: baseline replaced with ${#procs[@]} process(es)"
}

_roxb_pb_setlock() {
    local target="$1" locked="$2"
    _roxb_resolve "$target" || return 1

    local c keys="[]" baseline baseline_id skipped=""
    for c in $(echo "$CONTAINERS"); do
        baseline=$(_roxb_curl GET "/v1/processbaselines/key?key.deploymentId=$DEPLOY_ID&key.containerName=$c&key.clusterId=$CLUSTER_ID&key.namespace=$NS") || return 1
        baseline_id=$(jq -r '.id // empty' <<<"$baseline")
        if [ -z "$baseline_id" ]; then
            skipped="$skipped $c"
            continue
        fi
        keys=$(jq --arg dep "$DEPLOY_ID" --arg c "$c" --arg cluster "$CLUSTER_ID" --arg ns "$NS" \
            '. + [{deploymentId: $dep, containerName: $c, clusterId: $cluster, namespace: $ns}]' <<<"$keys")
    done

    if [ "$(jq 'length' <<<"$keys")" -eq 0 ]; then
        echo "error: RHACS has not created a process baseline for $target yet" >&2
        return 1
    fi

    local body response
    body=$(jq -n --argjson keys "$keys" --argjson locked "$locked" '{keys: $keys, locked: $locked}')
    response=$(_roxb_curl PUT "/v1/processbaselines/lock" "$body") || return 1
    if [ -n "$(jq -r '.errors[]?.error // empty' <<<"$response")" ]; then
        echo "lock update failed:" >&2; jq -r '.errors[].error' <<<"$response" >&2; return 1
    fi
    echo "process baselines of $DEP ($CONTAINERS): locked=$locked"
    [ -z "$skipped" ] || echo "  skipped containers without a RHACS baseline:$skipped"
}

rhacs-pb-lock()   { _roxb_pb_setlock "${1:?NAMESPACE/DEPLOYMENT}" true; }
rhacs-pb-unlock() { _roxb_pb_setlock "${1:?NAMESPACE/DEPLOYMENT}" false; }

# ------------------------------------------------------------ network baselines

rhacs-nb-export() {
    local target="${1:-}"
    if [ -z "$target" ]; then
        echo "usage: rhacs-nb-export NAMESPACE/DEPLOYMENT" >&2; return 1
    fi
    _roxb_resolve "$target" || return 1
    _roxb_curl GET "/v1/networkbaseline/$DEPLOY_ID" | jq .
}

rhacs-nb-import() {
    local target="${1:-}" file="${2:-}" lock=""
    case "${3:-}" in --lock) lock=1 ;; esac
    if [ -z "$target" ] || [ ! -f "$file" ]; then
        echo "usage: rhacs-nb-import NAMESPACE/DEPLOYMENT FILE [--lock]" >&2; return 1
    fi
    _roxb_resolve "$target" || return 1
    _roxb_nb_ensure "$DEPLOY_ID"

    # Every deployment peer in the file must have a baseline object too.
    local pid
    for pid in $(jq -r '[.peers[]? | select(.entity.info.type == "DEPLOYMENT") | .entity.info.id] | unique | .[]' "$file"); do
        _roxb_nb_ensure "$pid"
    done

    # Exported peers carry a properties[] array; the modify API wants one
    # entry per (peer, port, protocol, ingress) combination.
    local body response
    body=$(jq '{
        peers: [ .peers[]? as $p | $p.properties[] | {
            peer: {
                entity: {id: $p.entity.info.id, type: $p.entity.info.type},
                port: .port,
                protocol: .protocol,
                ingress: .ingress
            },
            status: "BASELINE"
        }]
    }' "$file")

    if [ "$(jq -r '.peers | length' <<<"$body")" = "0" ]; then
        echo "no peers in $file, nothing to import"
    else
        response=$(_roxb_curl PATCH "/v1/networkbaseline/$DEPLOY_ID/peers" "$body") || return 1
        if [ -n "$(jq -r '.message // empty' <<<"$response")" ]; then
            echo "import failed:" >&2; jq -r '.message' <<<"$response" >&2; return 1
        fi
        echo "marked $(jq -r '.peers | length' <<<"$body") flow(s) as baseline for $DEP"
    fi

    if [ -n "$lock" ]; then rhacs-nb-lock "$target"; fi
}

_roxb_nb_setlock() {
    local target="$1" action="$2"
    _roxb_resolve "$target" || return 1
    _roxb_nb_ensure "$DEPLOY_ID"
    local response
    response=$(_roxb_curl PATCH "/v1/networkbaseline/$DEPLOY_ID/$action" '{}') || return 1
    if [ -n "$(jq -r '.message // empty' <<<"$response")" ]; then
        echo "$action failed:" >&2; jq -r '.message' <<<"$response" >&2; return 1
    fi
    echo "network baseline of $DEP: $action done"
}

rhacs-nb-lock()   { _roxb_nb_setlock "${1:?NAMESPACE/DEPLOYMENT}" lock; }
rhacs-nb-unlock() { _roxb_nb_setlock "${1:?NAMESPACE/DEPLOYMENT}" unlock; }

# Add or remove individual network baseline flows. Flows that were never
# observed by RHACS are accepted: the baseline is a declaration.
#
#   rhacs-nb-add    NS/DEP --peer NS2/DEP2|internet|internal --port N [--udp] [--ingress] [--lock]
#   rhacs-nb-remove NS/DEP --peer NS2/DEP2|internet|internal --port N [--udp] [--ingress]
#
# Direction is from NS/DEP's point of view: default egress (it connects out),
# --ingress means the peer connects into it. Removing marks the flow
# anomalous/forbidden, so it alerts when the baseline is locked.
_roxb_network_entity_id() {
    local entity_type="${1:?RHACS network entity type}" graph entity_id entity_count
    local attempts=${RHACS_GRAPH_ATTEMPTS:-60}
    local delay=${RHACS_GRAPH_DELAY_SECONDS:-2}
    for attempt in $(seq 1 "$attempts"); do
        graph=$(_roxb_curl GET "/v1/networkgraph/cluster/$CLUSTER_ID") || return 1
        entity_count=$(jq -r --arg entity_type "$entity_type" '
            [.. | objects
             | select(.type? == $entity_type and (.id? | type == "string"))
             | .id]
            | unique | length
        ' <<<"$graph")
        if [ "$entity_count" -eq 1 ]; then
            entity_id=$(jq -r --arg entity_type "$entity_type" '
                [.. | objects
                 | select(.type? == $entity_type and (.id? | type == "string"))
                 | .id]
                | unique | .[0]
            ' <<<"$graph")
            printf '%s\n' "$entity_id"
            return 0
        fi
        # System Configuration reevaluation temporarily rebuilds the graph.
        # Retry the empty state, but never guess if RHACS returns ambiguity.
        if [ "$entity_count" -gt 1 ]; then
            echo "error: RHACS network graph exposed $entity_count $entity_type entities for cluster $CLUSTER_ID" >&2
            return 1
        fi
        [ "$attempt" -eq 1 ] && echo "waiting for RHACS $entity_type network entity after graph reevaluation..." >&2
        sleep "$delay"
    done
    echo "error: RHACS network graph exposed no $entity_type entity for cluster $CLUSTER_ID after $((attempts * delay)) seconds" >&2
    return 1
}

_roxb_nb_modify() {
    local pstatus="$1" target="$2"; shift 2
    local peer="" port="" protocol="L4_PROTOCOL_TCP" ingress=false lock=""

    while [ $# -gt 0 ]; do
        case "$1" in
            --peer)    peer="$2"; shift 2 ;;
            --port)    port="$2"; shift 2 ;;
            --udp)     protocol="L4_PROTOCOL_UDP"; shift ;;
            --ingress) ingress=true; shift ;;
            --lock)    lock=1; shift ;;
            *) echo "unknown option: $1" >&2; return 1 ;;
        esac
    done
    if [ -z "$peer" ] || [ -z "$port" ]; then
        echo "usage: rhacs-nb-add|rhacs-nb-remove NAMESPACE/DEPLOYMENT --peer NAMESPACE/DEPLOYMENT|internet|internal --port N [--udp] [--ingress] [--lock]" >&2
        return 1
    fi

    _roxb_resolve "$target" || return 1
    local target_id="$DEPLOY_ID" target_dep="$DEP"
    _roxb_nb_ensure "$target_id"

    # Resolve RHACS's synthetic graph entities from the current cluster graph.
    # Their IDs are implementation details and must not be embedded here.
    local peer_id peer_type
    if [ "$peer" = "internet" ]; then
        peer_type="INTERNET"
        peer_id=$(_roxb_network_entity_id "$peer_type") || return 1
    elif [ "$peer" = "internal" ]; then
        peer_type="INTERNAL_ENTITIES"
        peer_id=$(_roxb_network_entity_id "$peer_type") || return 1
    else
        _roxb_resolve "$peer" || return 1
        peer_id="$DEPLOY_ID"
        peer_type="DEPLOYMENT"
        _roxb_nb_ensure "$peer_id"
    fi

    local body response
    body=$(jq -n --arg id "$peer_id" --arg type "$peer_type" \
        --argjson port "$port" --arg protocol "$protocol" \
        --argjson ingress "$ingress" --arg status "$pstatus" '{
        peers: [{
            peer: {entity: {id: $id, type: $type}, port: $port, protocol: $protocol, ingress: $ingress},
            status: $status
        }]
    }')
    response=$(_roxb_curl PATCH "/v1/networkbaseline/$target_id/peers" "$body") || return 1
    if [ -n "$(jq -r '.message // empty' <<<"$response")" ]; then
        echo "update failed:" >&2; jq -r '.message' <<<"$response" >&2; return 1
    fi

    local dir="egress to"; [ "$ingress" = "true" ] && dir="ingress from"
    echo "$target_dep: $dir $peer port $port ${protocol#L4_PROTOCOL_} -> $pstatus"

    if [ -n "$lock" ]; then rhacs-nb-lock "$target"; fi
}

rhacs-nb-add()    { local t="${1:?NAMESPACE/DEPLOYMENT}"; shift; _roxb_nb_modify BASELINE  "$t" "$@"; }
rhacs-nb-remove() { local t="${1:?NAMESPACE/DEPLOYMENT}"; shift; _roxb_nb_modify ANOMALOUS "$t" "$@"; }

# Mark every directly observed EXTERNAL_SOURCE peer anomalous without relying
# on provider names or CIDRs. Workloads that need the workstation model use the
# distinct INTERNAL_ENTITIES declaration on CRC.
rhacs-nb-forbid-external() {
    local target="${1:-}"
    [ -n "$target" ] || { echo "usage: rhacs-nb-forbid-external NAMESPACE/DEPLOYMENT" >&2; return 1; }
    _roxb_resolve "$target" || return 1
    _roxb_nb_ensure "$DEPLOY_ID"

    local baseline body response count
    baseline=$(_roxb_curl GET "/v1/networkbaseline/$DEPLOY_ID") || return 1
    body=$(jq '{peers: [
        .peers[]? as $p
        | select($p.entity.info.type == "EXTERNAL_SOURCE")
        | $p.properties[]
        | {peer: {entity: {id: $p.entity.info.id, type: "EXTERNAL_SOURCE"},
                  port: .port, protocol: .protocol, ingress: .ingress},
           status: "ANOMALOUS"}
    ]}' <<<"$baseline")
    count=$(jq '.peers | length' <<<"$body")
    if [ "$count" -eq 0 ]; then
        echo "$DEP: no direct external-source flows observed"
        return 0
    fi
    response=$(_roxb_curl PATCH "/v1/networkbaseline/$DEPLOY_ID/peers" "$body") || return 1
    if [ -n "$(jq -r '.message // empty' <<<"$response")" ]; then
        echo "external-source update failed:" >&2; jq -r '.message' <<<"$response" >&2; return 1
    fi
    echo "$DEP: marked $count direct external-source flow(s) anomalous"
}

# Human-readable views.
#
#   rhacs-pb-list NS/DEPLOYMENT     processes per container + lock state
#   rhacs-nb-list NS/DEPLOYMENT     flows table + lock state (incl. forbidden flows)

rhacs-pb-list() {
    local target="${1:-}"
    if [ -z "$target" ]; then
        echo "usage: rhacs-pb-list NAMESPACE/DEPLOYMENT" >&2; return 1
    fi
    rhacs-pb-export "$target" | jq -r '
        .[] |
        "container: \(.containerName)  (locked: \(.locked))",
        (if (.processes | length) == 0 then "  (no processes)" else (.processes[] | "  " + .) end)'
}

rhacs-nb-list() {
    local target="${1:-}"
    if [ -z "$target" ]; then
        echo "usage: rhacs-nb-list NAMESPACE/DEPLOYMENT" >&2; return 1
    fi
    _roxb_resolve "$target" || return 1

    _roxb_curl GET "/v1/networkbaseline/$DEPLOY_ID" | jq -r '
        def peername(e):
            if e.info.type == "DEPLOYMENT" then (e.info.deployment.name // e.info.id)
            elif e.info.type == "INTERNET" then "internet"
            else ((e.info.externalSource.name // e.info.id) + " (" + e.info.type + ")") end;
        def rows(list; st):
            list[]? as $p | $p.properties[] |
            [ (if .ingress then "ingress from" else "egress to" end),
              peername($p.entity),
              (.port | tostring),
              (.protocol | sub("L4_PROTOCOL_"; "")),
              st ] | @tsv;
        "deployment: \(.deploymentName)   locked: \(.locked)   observation ends: \(.observationPeriodEnd // "-")"'
    _roxb_curl GET "/v1/networkbaseline/$DEPLOY_ID" | jq -r '
        def peername(e):
            if e.info.type == "DEPLOYMENT" then (e.info.deployment.name // e.info.id)
            elif e.info.type == "INTERNET" then "internet"
            else ((e.info.externalSource.name // e.info.id) + " (" + e.info.type + ")") end;
        def rows(list; st):
            list[]? as $p | $p.properties[] |
            [ (if .ingress then "ingress from" else "egress to" end),
              peername($p.entity),
              (.port | tostring),
              (.protocol | sub("L4_PROTOCOL_"; "")),
              st ] | @tsv;
        (["DIRECTION","PEER","PORT","PROTO","STATUS"] | @tsv),
        rows(.peers; "baseline"),
        rows(.forbiddenPeers; "forbidden")' | column -t -s $'\t'
}

# Generate full ingress+egress NetworkPolicies from network baselines:
# microsegmentation from what the baselines allow.
#
#   rhacs-nb-netpol NS/DEPLOYMENT [options] > policy.yaml
#   rhacs-nb-netpol NS/           [options] > policies.yaml
#
# Options:
#   --dns-port N          DNS pod port (default 5353; vanilla k8s: 53)
#   --dns-ns NS           DNS namespace (default openshift-dns; vanilla: kube-system)
#   --router-ns NS        router namespace for exposed ports (default openshift-ingress)
#   --expose DEP:PORT     add router ingress for DEP on PORT (repeatable); use when
#                         RHACS does not report the route/ingress exposure itself
#
# The second form generates one policy per deployment in the namespace.
# Output ALWAYS starts with a deny-all (ingress+egress) policy for the
# namespace, so anything without an explicit allow is blocked.
#
# Follows the StackRox generator conventions: stackrox-generated-<name>,
# network-policy-generator.stackrox.io labels, creationTimestamp, bare
# podSelector for same-namespace peers, peers grouped per port.
#
# - Every baseline peer becomes an ingress or egress rule (deployment peers
#   are pinned by pod labels, plus a namespaceSelector when cross-namespace;
#   internet/external peers become ipBlocks).
# - A minimal DNS egress rule (namespace openshift-dns, port 5353 UDP+TCP by
#   default; vanilla Kubernetes: --dns-ns kube-system --dns-port 53) is added
#   ONLY when the baseline has egress flows. No egress traffic, no DNS rule:
#   the deployment gets egress: [] and is fully sealed outbound.
# - Forbidden peers are NOT included: deny-all covers them.
# - Deployments with no flows at all get NO policy of their own: the deny-all
#   already seals them completely.
#
# Review, then apply with: kubectl apply -f policies.yaml
# Deployment lookups repeat a lot across a namespace (shared peers); cache them.
_roxb_get_deployment() {
    local id="$1" cache="${_ROXB_CACHE_DIR:-}/dep-$id.json"
    if [ -n "${_ROXB_CACHE_DIR:-}" ] && [ -s "$cache" ]; then
        cat "$cache"
        return 0
    fi
    local out
    out=$(_roxb_curl GET "/v1/deployments/$id") || return 1
    [ -n "${_ROXB_CACHE_DIR:-}" ] && printf '%s' "$out" > "$cache"
    printf '%s' "$out"
}

_roxb_netpol_json() {
    local dep_id="$1" dep_full baseline
    dep_full=$(_roxb_get_deployment "$dep_id") || return 1
    baseline=$(_roxb_curl GET "/v1/networkbaseline/$dep_id") || return 1

    # Resolve namespace + pod labels for every deployment peer.
    local pid peers_info="{}" pinfo
    for pid in $(jq -r '[.peers[]? | select(.entity.info.type == "DEPLOYMENT") | .entity.info.id] | unique | .[]' <<<"$baseline"); do
        pinfo=$(_roxb_get_deployment "$pid") || return 1
        peers_info=$(jq --arg id "$pid" --argjson p "$(jq '{namespace, podLabels: (if (.podLabels // {}) == {} then .labels else .podLabels end)}' <<<"$pinfo")" \
            '. + {($id): $p}' <<<"$peers_info")
    done

    jq -cn --argjson dep "$dep_full" --argjson baseline "$baseline" \
          --argjson peers "$peers_info" --argjson dnsport "$_ROXB_DNSPORT" \
          --arg dnsns "$_ROXB_DNSNS" --arg routerns "$_ROXB_ROUTERNS" \
          --arg expose "$_ROXB_EXPOSE" --arg now "$_ROXB_NOW" '
        def podsel: (if ($dep.podLabels // {}) == {} then $dep.labels else $dep.podLabels end);
        def protoname: sub("L4_PROTOCOL_"; "") | if . == "UDP" then "UDP" else "TCP" end;
        def peerref($e):
            if $e.info.type == "DEPLOYMENT" then
                (if $peers[$e.info.id].namespace == $dep.namespace
                 then {podSelector: {matchLabels: $peers[$e.info.id].podLabels}}
                 else {namespaceSelector: {matchLabels: {"kubernetes.io/metadata.name": $peers[$e.info.id].namespace}},
                       podSelector: {matchLabels: $peers[$e.info.id].podLabels}}
                 end)
            elif $e.info.type == "INTERNET" then
                {ipBlock: {cidr: "0.0.0.0/0"}}
            elif $e.info.type == "EXTERNAL_SOURCE" then
                {ipBlock: {cidr: ($e.info.externalSource.cidr // "0.0.0.0/0")}}
            else empty end;
        # one rule per (port, protocol), peers grouped like the GUI generator
        def rules($wantIngress):
            [ $baseline.peers[]? as $p | $p.properties[]
              | select(.ingress == $wantIngress)
              | {peer: peerref($p.entity), port: .port, proto: (.protocol | protoname)} ]
            | group_by([.port, .proto])
            | map({ (if $wantIngress then "from" else "to" end): ([.[].peer] | unique),
                    ports: [{port: .[0].port, protocol: .[0].proto}] });
        def dnsrule:
            { to: [{namespaceSelector: {matchLabels: {"kubernetes.io/metadata.name": $dnsns}}}],
              ports: [ {port: $dnsport, protocol: "UDP"}, {port: $dnsport, protocol: "TCP"} ] };
        # ports exposed via route/loadbalancer/nodeport get ingress from the router namespace
        def exposedports:
            ([ $dep.ports[]? | select(.exposure == "ROUTE" or .exposure == "EXTERNAL" or .exposure == "NODE"
                 or ([.exposureInfos[]?.level] | any(. == "ROUTE" or . == "EXTERNAL" or . == "NODE")))
               | .containerPort ]
             + [ $expose | split(" ")[] | select(length > 0)
                 | split(":") | select((.[0] == $dep.name) or (length == 1)) | last | tonumber ])
            | unique;
        def routerrules:
            [ exposedports[] |
              { from: [{namespaceSelector: {matchLabels: {"kubernetes.io/metadata.name": $routerns}}}],
                ports: [{port: ., protocol: "TCP"}] } ];
        (routerrules + rules(true)) as $ing
        | (rules(false) as $eg | (if ($eg | length) > 0 then [dnsrule] else [] end) + $eg) as $egr
        # nothing to allow: deny-all already covers this deployment, skip it
        | if ($ing | length) == 0 and ($egr | length) == 0 then empty else
        {
            apiVersion: "networking.k8s.io/v1",
            kind: "NetworkPolicy",
            metadata: {
                creationTimestamp: $now,
                labels: {
                    "network-policy-generator.stackrox.io/generated": "true",
                    "network-policy-generator.stackrox.io/from-baseline": "true"
                },
                name: ("stackrox-generated-" + $dep.name),
                namespace: $dep.namespace
            },
            spec: {
                ingress: $ing,
                egress: $egr,
                podSelector: {matchLabels: podsel},
                policyTypes: ["Ingress", "Egress"]
            }
        } end'
}

rhacs-nb-netpol() {
    local target="${1:-}"
    _ROXB_DNSPORT="5353"; _ROXB_DNSNS="openshift-dns"
    _ROXB_ROUTERNS="openshift-ingress"; _ROXB_EXPOSE=""
    _ROXB_NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    _ROXB_CACHE_DIR=$(mktemp -d)
    shift 2>/dev/null
    while [ $# -gt 0 ]; do
        case "$1" in
            --dns-port)  _ROXB_DNSPORT="$2"; shift 2 ;;
            --dns-ns)    _ROXB_DNSNS="$2"; shift 2 ;;
            --router-ns) _ROXB_ROUTERNS="$2"; shift 2 ;;
            --expose)    _ROXB_EXPOSE="$_ROXB_EXPOSE $2"; shift 2 ;;
            *) echo "unknown option: $1" >&2; return 1 ;;
        esac
    done
    if [ -z "$target" ]; then
        echo "usage: rhacs-nb-netpol NAMESPACE/[DEPLOYMENT] [--dns-port N] [--dns-ns NS] > policies.yaml" >&2
        return 1
    fi

    local ns dep ids
    ns="${target%%/*}"
    case "$target" in */*) dep="${target#*/}" ;; *) dep="" ;; esac

    if [ -n "$dep" ]; then
        _roxb_resolve "$target" || return 1
        ids="$DEPLOY_ID"
    else
        ids=$(_roxb_curl GET "/v1/deployments?query=$(jq -rn --arg q "Namespace:$ns" '$q|@uri')" |
            jq -r --arg ns "$ns" '[.deployments[] | select(.namespace == $ns) | .id] | .[]')
        if [ -z "$ids" ]; then
            echo "error: no deployments found in namespace $ns" >&2
            return 1
        fi
    fi

    {
        # deny-all first: anything without an explicit allow is blocked.
        jq -cn --arg ns "$ns" --arg now "$_ROXB_NOW" '{
            apiVersion: "networking.k8s.io/v1",
            kind: "NetworkPolicy",
            metadata: {
                creationTimestamp: $now,
                labels: {"network-policy-generator.stackrox.io/generated": "true"},
                name: "stackrox-generated-deny-all",
                namespace: $ns
            },
            spec: {podSelector: {}, policyTypes: ["Ingress", "Egress"]}
        }'
        # generate in parallel; peer lookups are cached in _ROXB_CACHE_DIR
        local id i=0
        while IFS= read -r id; do
            [ -z "$id" ] && continue
            i=$((i+1))
            _roxb_netpol_json "$id" > "$_ROXB_CACHE_DIR/out-$(printf '%04d' "$i").json" &
        done <<<"$ids"
        wait
        local f
        for f in "$_ROXB_CACHE_DIR"/out-*.json; do
            [ -s "$f" ] && cat "$f"
        done
    } | python3 -c '
import sys, json, yaml
docs = [json.loads(line) for line in sys.stdin if line.strip()]
print(yaml.safe_dump_all(docs, sort_keys=True, default_flow_style=False), end="")'
    local rc=$?
    rm -rf "$_ROXB_CACHE_DIR"; _ROXB_CACHE_DIR=""
    return $rc
}
