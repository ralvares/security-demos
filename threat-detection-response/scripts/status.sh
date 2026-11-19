#!/usr/bin/env bash
# status.sh — where are we? A quick, read-only snapshot of every layer of the demo.
# Never changes anything and never fails: a layer that is down is reported, the rest still runs.
#
#   cluster    CRC VM + OpenShift
#   RHACS      Central API, Sensor/Collector health, Scanner V4 vulnerability DB
#   demo       blog image + pod, enforcement, response NetworkPolicies, active violations
#   attacker   address, firewall, containers
set -uo pipefail
source "$(dirname "$0")/lib/common.sh"
S="$TDR_DIR/scripts"

if ! id -nG | tr ' ' '\n' | grep -qx libvirt && getent group libvirt | grep -qw "$USER"; then
  exec sg libvirt -c "$(printf '%q ' "$0" "$@")"
fi

bad()  { printf '  %s✗%s %s\n' "$RED" "$N" "$*"; }
row()  { printf '  %s%-12s%s %s\n' "$DIM" "$1" "$N" "$2"; }

# ---------------------------------------------------------------- cluster
step "Cluster"
crc_json=$(crc status -o json 2>/dev/null || echo '{}')
crc_state=$(jq -r '.crcStatus // "not installed"' <<<"$crc_json")
oc_state=$(jq -r '.openshiftStatus // "-"' <<<"$crc_json")
if [[ $oc_state == Running ]]; then
  ok "CRC $crc_state, OpenShift $oc_state"
  cluster_up=1
else
  bad "CRC: $crc_state, OpenShift: $oc_state   → make up"
  cluster_up=""
fi

# ---------------------------------------------------------------- RHACS
rhacs_up=""
if [[ -n $cluster_up ]] && (use_crc) >/dev/null 2>&1; then
  use_crc
  step "RHACS"
  if [[ -f $RHACS_ENV ]]; then
    load_rhacs
    if curl -sfk --max-time 5 "https://$ROX_ENDPOINT/v1/ping" >/dev/null 2>&1; then
      ok "Central API  https://${ROX_ENDPOINT%:443}"; rhacs_up=1
      health=$(rox GET /v1/clusters 2>/dev/null | jq -r --arg n "$CLUSTER_NAME" \
        '.clusters[]? | select(.name==$n) | .healthStatus | "sensor \(.sensorHealthStatus // "?"), collector \(.collectorHealthStatus // "?")"' 2>/dev/null)
      if [[ $health == "sensor HEALTHY, collector HEALTHY" ]]; then ok "cluster '$CLUSTER_NAME': $health"
      else bad "cluster '$CLUSTER_NAME': ${health:-not registered}"; fi
      scan=$(timeout 30 roxctl -e "$ROX_ENDPOINT" image scan --image "$REGISTRY_SVC/$APP_NS/blog:v1" --output json 2>&1)
      if cves=$(jq -er '.result.summary.TOTAL_VULNERABILITIES // 0' <<<"$scan" 2>/dev/null); then
        if (( cves == 0 )); then ok "Scanner V4 ready — blog:v1 has 0 CVEs"; else bad "Scanner V4 ready — blog:v1 has $cves CVEs (act 1 expects 0)"; fi
      elif grep -q "matcher is not initialized" <<<"$scan"; then
        warn "Scanner V4 still loading its vulnerability DB (finishes by itself; act 1 needs it)"
      else
        warn "Scanner V4: blog:v1 scan failed"
      fi
    else
      bad "Central not answering   → make up"
    fi
  else
    bad "not installed (no $RHACS_ENV)   → make install"
  fi
fi

# ---------------------------------------------------------------- demo
if [[ -n $cluster_up ]] && oc whoami >/dev/null 2>&1; then
  step "Demo"
  img=$(oc get deploy blog -n "$APP_NS" -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null | sed 's|.*/||')
  pod=$(oc get pod -n "$APP_NS" -l app=blog --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
  row "blog"        "${img:-not deployed}${pod:+  ($pod running)}"
  host=$(oc get route blog -n "$APP_NS" -o jsonpath='{.spec.host}' 2>/dev/null)
  [[ -n $host ]] && row "url" "https://$host"
  enf=$(oc get securitypolicy tdr-unauthorized-process -n stackrox -o jsonpath='{.spec.enforcementActions}' 2>/dev/null)
  if [[ $enf =~ ^(\[\])?$ ]]; then row "enforcement" "off"; else row "enforcement" "${RED}ON${N} (Kill Pod — act 5)"; fi
  np=$(oc get networkpolicy -A -l tdr-demo=response --no-headers 2>/dev/null | awk '{print $1"/"$2}' | paste -sd' ')
  row "netpols"     "${np:-none}"
  if [[ -n $rhacs_up ]]; then
    alerts=$(rox GET "/v1/alerts?query=$(uri "Namespace:$APP_NS,$PAY_NS+Violation State:Active")&pagination.limit=200" 2>/dev/null |
      jq -r '.alerts[]? | "\(.policy.name)"' | sort | uniq -c | sort -rn)
    if [[ -z $alerts ]]; then row "violations" "none (clean slate)"
    else row "violations" "active:"; sed 's/^ */                 /' <<<"$alerts"; fi
  fi
fi

# ---------------------------------------------------------------- attacker
step "Attacker"
"$S/attacker.sh" status 2>/dev/null | sed 's/^  /  /' || bad "attacker status failed"
exit 0
