#!/usr/bin/env bash
# up.sh — one command from "laptop just booted" to "demo armed and verified".
#
#   scripts/up.sh             start whatever is down, install whatever is missing, reset, verify
#   scripts/up.sh --verify    only run the checks (exit 1 if anything is wrong)
#   scripts/up.sh --recreate  delete the CRC cluster first and rebuild everything (~45-60 min)
#
# Every phase is idempotent and skips what's already done:
#   1. CRC        crc setup/start (scripts/00-crc-up.sh); detects a VM whose SSH keys are broken
#   2. cluster    core operators Available (API, ingress, registry, DNS, network, auth)
#   3. RHACS      operator, Central, Sensor, Collector, API token (scripts/01-rhacs-install.sh)
#   4. demo       images, policies, baselines — only if missing (scripts/02-demo-setup.sh)
#   5. scanner    Scanner V4 vulnerability DB loaded (act 1 needs "0 CVEs")
#   6. attacker   address, firewall, DNS, payload server, pool (scripts/attacker.sh up)
#   7. reset      v1, enforcement off, fresh locked baselines, violations resolved
#   8. verify     end-to-end checks, including the attacker reachable by name from the cluster
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"
S="$TDR_DIR/scripts"
T0=$SECONDS

# crc refuses to run unless libvirt is an *active* group (no re-login after install).
if ! id -nG | tr ' ' '\n' | grep -qx libvirt && getent group libvirt | grep -qw "$USER"; then
  exec sg libvirt -c "$(printf '%q ' "$0" "$@")"
fi

elapsed() { local s=$((SECONDS - T0)); printf '%dm%02ds' $((s / 60)) $((s % 60)); }
crc_running() { crc status -o json 2>/dev/null | jq -e '.openshiftStatus == "Running"' >/dev/null; }

# The failure mode that makes `crc start` retry SSH for 5 minutes and give up: the VM boots,
# sshd answers, but rejects CRC's key (authorized_keys lost/corrupted). A restart can't fix it.
ssh_keys_broken() {
  local ip key=$HOME/.crc/machines/crc/id_ed25519
  crc status -o json 2>/dev/null | jq -e '.crcStatus == "Running"' >/dev/null || return 1
  ip=$(crc ip 2>/dev/null) || return 1
  ssh -i "$key" -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=5 \
      -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
      "core@$ip" true 2>&1 | grep -q 'Permission denied'
}
die_ssh_broken() {
  die "the CRC VM is up but rejects CRC's SSH key (authorized_keys inside the VM is gone).
  A restart cannot repair this — the cluster has to be recreated:
      make recreate      (deletes the cluster, reinstalls CRC + RHACS + demo, ~45-60 min)"
}

# ---------------------------------------------------------------- verify
FAILS=0
check() { # label, command...
  local label=$1; shift
  if "$@" >/dev/null 2>&1; then ok "$label"; else printf '  %s✗%s %s\n' "$RED" "$N" "$label"; FAILS=$((FAILS + 1)); fi
}
soft() { # like check, but only warns
  local label=$1; shift
  if "$@" >/dev/null 2>&1; then ok "$label"; else warn "$label"; fi
}

verify() {
  step "Verify"
  FAILS=0
  crc_running || die "CRC is not running — run: make up"
  ok "CRC: OpenShift running"
  use_crc
  load_rhacs
  # shellcheck disable=SC1091
  source "$S/lib/rhacs-baselines.sh"
  local blog; blog=https://$(oc get route blog -n "$APP_NS" -o jsonpath='{.spec.host}' 2>/dev/null)

  _blog_v1()   { oc get deploy blog -n "$APP_NS" -o jsonpath='{.spec.template.spec.containers[0].image}' | grep -q ':v1$' &&
                 oc rollout status deploy/blog -n "$APP_NS" --timeout=5s; }
  _pay()       { oc rollout status deploy/payments-api -n "$PAY_NS" --timeout=5s; }
  _home()      { [[ $(curl -sk -o /dev/null -w '%{http_code}' --max-time 10 "$blog/") == 200 ]]; }
  _feature()   { curl -sk --max-time 20 "$blog/api/links/check" --data-urlencode "url=https://www.redhat.com/en" | grep -qi alive; }
  _central()   { curl -sfk --max-time 5 "https://$ROX_ENDPOINT/v1/ping"; }
  _token()     { rox GET /v1/auth/status | jq -e .userId; }
  _health()    { rox GET /v1/clusters | jq -e --arg n "$CLUSTER_NAME" '.clusters[] | select(.name==$n) | .healthStatus |
                   .sensorHealthStatus=="HEALTHY" and .collectorHealthStatus=="HEALTHY"'; }
  _policies()  { local n; n=$(oc get securitypolicy -n stackrox -o json | jq '[.items[] | select(.metadata.name|startswith("tdr-")) |
                   select(any(.status.conditions[]?; .type=="AcceptedByCentral" and .status=="True"))] | length');
                 (( n == $(ls "$TDR_DIR"/rhacs/policies/*.yaml | wc -l) )); }
  _enf_off()   { [[ $(oc get securitypolicy tdr-unauthorized-process -n stackrox -o jsonpath='{.spec.enforcementActions}') =~ ^(\[\])?$ ]]; }
  _no_np()     { [[ -z $(oc get networkpolicy -A -l tdr-demo=response -o name) ]]; }
  _pb_blog()   { rhacs-pb-export "$APP_NS/blog" | jq -e 'length > 0 and all(.locked)'; }
  _nb_blog()   { rhacs-nb-export "$APP_NS/blog" | jq -e .locked; }
  _pb_pay()    { rhacs-pb-export "$PAY_NS/payments-api" | jq -e 'length > 0 and all(.locked)'; }
  _nb_pay()    { rhacs-nb-export "$PAY_NS/payments-api" | jq -e '.locked and (.peers | length == 0)'; }
  _scanner()   { roxctl -e "$ROX_ENDPOINT" image scan --image "$REGISTRY_SVC/$APP_NS/blog:v1" --output json |
                   jq -e '(.result.summary.TOTAL_VULNERABILITIES // 0) == 0'; }
  _quiet()     { [[ -z $(rox GET "/v1/alerts?query=$(uri "Namespace:$APP_NS,$PAY_NS+Violation State:Active")&pagination.limit=1" | jq -r '.alerts[]?.id') ]]; }

  check "blog v1 running"                                   _blog_v1
  check "payments-api running"                              _pay
  check "blog reachable: $blog"                             _home
  soft  "link checker works (needs internet from the VM)"   _feature
  check "RHACS Central API"                                 _central
  check "RHACS API token valid"                             _token
  check "cluster '$CLUSTER_NAME': Sensor + Collector HEALTHY" _health
  check "TDR policies accepted by Central"                  _policies
  check "enforcement off (act 5 turns it on)"               _enf_off
  check "no response NetworkPolicies"                       _no_np
  check "blog: process + network baselines LOCKED"          eval '_pb_blog && _nb_blog'
  check "payments-api: process baseline LOCKED, network baseline empty + LOCKED" eval '_pb_pay && _nb_pay'
  check "Scanner V4 ready, blog:v1 has 0 CVEs"              _scanner
  check "no active violations (clean slate)"                _quiet
  check "attacker: containers, firewall, $ATTACKER resolvable + reachable from the cluster" "$S/attacker.sh" check

  echo
  if (( FAILS )); then
    die "$FAILS check(s) failed — fix them, or re-run: make up"
  fi
  printf '%s%sDemo is up and armed.%s  (%s)\n' "$GRN" "$B" "$N" "$(elapsed)"
  cat <<EOF
  blog:      $blog
  RHACS:     https://${ROX_ENDPOINT%:443}   (make password)
  attacker:  $ATTACKER → $ATTACKER_IP (this laptop)
  next:      make live      or  make act1 … act6
EOF
}

RECREATE=""
case "${1:-}" in
  --verify)   verify; exit ;;
  --recreate) RECREATE=1 ;;
  "") ;;
  *) sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac

need crc oc jq curl podman roxctl
systemctl --user start crc-http.socket crc-vsock.socket 2>/dev/null || true

# ---------------------------------------------------------------- 1. CRC
if [[ -n $RECREATE ]]; then
  step "RECREATE: deleting the CRC cluster"
  if [[ -t 0 ]]; then
    read -rp "  Delete the CRC cluster and everything in it, then rebuild (~45-60 min)? [y/N] " a
    [[ $a == y ]] || die "aborted"
  fi
  podman rm -f tdr-dns tdr-payload tdr-pool tdr-c2 >/dev/null 2>&1 || true
  crc delete -f || true
  ok "cluster deleted"
fi

step "CRC"
if crc_running; then
  ok "already running"
else
  ssh_keys_broken && die_ssh_broken
  if ! "$S/00-crc-up.sh"; then
    ssh_keys_broken || tail -n 400 "$HOME/.crc/crc.log" 2>/dev/null | grep -q 'unable to authenticate' && die_ssh_broken
    die "crc start failed — details: ~/.crc/crc.log"
  fi
fi
use_crc

# ---------------------------------------------------------------- 2. cluster
step "Cluster operators"
CORE_COS=(kube-apiserver openshift-apiserver authentication ingress image-registry dns network)
cos_ok() {
  oc get co "${CORE_COS[@]}" -o json | jq -e '[.items[] | .status.conditions[] | select(.type=="Available") | .status] |
    length == '"${#CORE_COS[@]}"' and all(. == "True")'
}
wait_for "${CORE_COS[*]}" 900 cos_ok
oc get route default-route -n openshift-image-registry >/dev/null 2>&1 ||
  oc patch configs.imageregistry.operator.openshift.io/cluster --type merge -p '{"spec":{"defaultRoute":true}}' >/dev/null

# ---------------------------------------------------------------- 3. RHACS (idempotent: waits, or installs what's missing)
"$S/01-rhacs-install.sh"
load_rhacs
collector_ok() { rox GET /v1/clusters | jq -e --arg n "$CLUSTER_NAME" '.clusters[] | select(.name==$n) | .healthStatus.collectorHealthStatus=="HEALTHY"'; }
wait_for "collector HEALTHY in Central" 600 collector_ok

# ---------------------------------------------------------------- 4. demo
step "Demo deployment"
demo_ran=""
have_images()   { oc get istag blog:v1 blog:v2 -n "$APP_NS"; }
have_policies() { local n; n=$(oc get securitypolicy -n stackrox -o name 2>/dev/null | grep -c '/tdr-'); (( n == $(ls "$TDR_DIR"/rhacs/policies/*.yaml | wc -l) )); }
have_integ()    { rox GET /v1/imageintegrations | jq -e '.integrations[]? | select(.name=="CRC internal registry (tdr-demo)")'; }
have_workloads(){ oc get deploy blog -n "$APP_NS" && oc get deploy payments-api -n "$PAY_NS"; }
if ! have_images >/dev/null 2>&1; then
  info "blog images missing — full setup (build + deploy + baselines)"
  "$S/02-demo-setup.sh"; demo_ran=1
elif ! { have_policies && have_integ && have_workloads; } >/dev/null 2>&1; then
  info "images present, setup incomplete — re-running setup without rebuilding"
  SKIP_BUILD=1 "$S/02-demo-setup.sh"; demo_ran=1
else
  ok "images, policies, registry integration and workloads present"
fi
podman image exists localhost/attacker-kit:latest || podman build -q -t localhost/attacker-kit:latest "$TDR_DIR/app/attacker-kit" >/dev/null

# ---------------------------------------------------------------- 5. scanner
step "Scanner V4"
scan_ok() { roxctl -e "$ROX_ENDPOINT" image scan --image "$REGISTRY_SVC/$APP_NS/blog:v1" --output json >/dev/null 2>&1; }
wait_for "vulnerability database loaded (after a restart: a few minutes)" 2400 scan_ok

# ---------------------------------------------------------------- 6+7. attacker + reset
if [[ -z $demo_ran ]]; then           # 02-demo-setup.sh already did both
  "$S/attacker.sh" up
  "$S/demo.sh" reset
fi

# ---------------------------------------------------------------- 8. verify
verify
