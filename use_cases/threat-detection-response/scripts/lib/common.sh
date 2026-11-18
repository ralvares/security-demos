# shellcheck shell=bash
# Shared helpers for the Threat Detection & Response demo. Source, don't run.

TDR_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
STATE_DIR="$TDR_DIR/.state"            # git-ignored: tokens, generated files
mkdir -p "$STATE_DIR" && chmod 700 "$STATE_DIR"

# demo namespaces
APP_NS=${APP_NS:-unhackable}
PAY_NS=${PAY_NS:-payments}
# The attacker = this laptop, on a real, routable PUBLIC address so RHACS classifies it as
# external. It's "spoofed" only between the CRC VM and this laptop: the VM's default gateway
# is the laptop, so packets to it never leave the machine. 1.2.3.4 is the classic stand-in
# for "some host on the internet". Override with ATTACKER_IP=... if you prefer another.
ATTACKER_IP=${ATTACKER_IP:-1.2.3.4}
CRC_BRIDGE_IP=$(ip -4 -o addr show dev crc 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | grep -v "^${ATTACKER_IP}$" | head -1 || true)
ATTACKER_ZONE=${ATTACKER_ZONE:-example.local}     # the attacker's domain, served by the attacker's own DNS
ATTACKER=${ATTACKER:-attacker.$ATTACKER_ZONE}     # the one name used in every attack step
CLUSTER_NAME=${CLUSTER_NAME:-production}
REGISTRY_SVC=image-registry.openshift-image-registry.svc:5000

if [[ -t 1 || -n ${FORCE_COLOR:-} ]]; then
  B=$'\e[1m'; DIM=$'\e[2m'; RED=$'\e[31m'; GRN=$'\e[32m'; YLW=$'\e[33m'; BLU=$'\e[34m'; MAG=$'\e[35m'; CYN=$'\e[36m'; N=$'\e[0m'
else
  B=; DIM=; RED=; GRN=; YLW=; BLU=; MAG=; CYN=; N=
fi

step() { printf '\n%s==>%s %s%s%s\n' "$BLU" "$N" "$B" "$*" "$N"; }
ok()   { printf '  %s✓%s %s\n' "$GRN" "$N" "$*"; }
info() { printf '  %s•%s %s\n' "$DIM" "$N" "$*"; }
warn() { printf '  %s!%s %s\n' "$YLW" "$N" "$*" >&2; }
die()  { printf '%s✗ %s%s\n' "$RED" "$*" "$N" >&2; exit 1; }

# Run a command as root: sudo in a terminal (fingerprint/password), KDE dialog otherwise.
as_root() {
  if [[ $EUID -eq 0 ]]; then "$@"
  elif sudo -n true 2>/dev/null; then sudo -n "$@"   # passwordless sudo (cached or NOPASSWD)
  elif [[ -t 0 ]]; then sudo "$@"
  else pkexec "$@"
  fi
}

need() { for c in "$@"; do command -v "$c" >/dev/null || die "missing command: $c"; done; }

# Wait until "$@" succeeds; label, timeout seconds.
wait_for() {
  local label=$1 timeout=$2; shift 2
  local start=$SECONDS
  printf '  %s…%s %s ' "$DIM" "$N" "$label"
  until "$@" >/dev/null 2>&1; do
    (( SECONDS - start > timeout )) && { echo; die "timed out after ${timeout}s: $label"; }
    printf '.'; sleep 5
  done
  printf ' %sready%s (%ss)\n' "$GRN" "$N" "$((SECONDS - start))"
}

# Make oc/kubectl talk to CRC.
use_crc() {
  command -v crc >/dev/null || die "crc not found — run scripts/00-crc-up.sh first"
  eval "$(crc oc-env 2>/dev/null)" || true
  oc whoami >/dev/null 2>&1 || {
    local pw; pw=$(crc console --credentials -o json 2>/dev/null | jq -r '.clusterConfig.adminCredentials.password')
    [[ -n $pw && $pw != null ]] || die "CRC is not running (crc start)"
    oc login -u kubeadmin -p "$pw" https://api.crc.testing:6443 --insecure-skip-tls-verify=true >/dev/null
  }
}

# ---------------------------------------------------------------- RHACS API
# 01-rhacs-install.sh writes ROX_ENDPOINT + ROX_API_TOKEN to $RHACS_ENV (mode 600)
# and installs ~/.bashrc.d/rhacs.sh, so roxctl works in every new shell too.
RHACS_ENV=${RHACS_ENV:-$HOME/.config/rhacs/crc.env}
load_rhacs() {
  [[ -f $RHACS_ENV ]] || die "no RHACS credentials in $RHACS_ENV — run scripts/01-rhacs-install.sh"
  # shellcheck disable=SC1090
  source "$RHACS_ENV"
  export ROX_ENDPOINT ROX_API_TOKEN ROX_INSECURE_CLIENT_SKIP_TLS_VERIFY=true
}

rox() { # rox METHOD PATH [JSON]
  local m=$1 p=$2 d=${3:-}
  if [[ -n $d ]]; then
    curl -sSk -X "$m" -H "Authorization: Bearer $ROX_API_TOKEN" -H 'Content-Type: application/json' -d "$d" "https://$ROX_ENDPOINT$p"
  else
    curl -sSk -X "$m" -H "Authorization: Bearer $ROX_API_TOKEN" "https://$ROX_ENDPOINT$p"
  fi
}

uri() { jq -rn --arg q "$1" '$q|@uri'; }

# deployment id by ns/name (empty if RHACS hasn't seen it yet)
rox_deployment_id() {
  rox GET "/v1/deployments?query=$(uri "Cluster:$CLUSTER_NAME+Namespace:$1+Deployment:$2")" |
    jq -r --arg ns "$1" --arg d "$2" '[.deployments[]? | select(.namespace==$ns and .name==$d)][0].id // empty'
}

# Recreate payments-api with an empty, locked network baseline (setup + reset).
# A fresh deployment = fresh RHACS identity, so the lateral-movement flow is "new" every run.
fresh_payments() {
  # shellcheck disable=SC1091
  source "$TDR_DIR/scripts/lib/rhacs-baselines.sh"
  oc delete -f "$TDR_DIR/deploy/app/payments.yaml" --ignore-not-found --wait=true >/dev/null 2>&1 || true
  oc apply -f "$TDR_DIR/deploy/app/payments.yaml" >/dev/null
  oc rollout status deploy/payments-api -n "$PAY_NS" --timeout=180s >/dev/null
  _seen() { [[ -n $(rox_deployment_id "$PAY_NS" payments-api) ]] && rox GET "/v1/networkbaseline/$(rox_deployment_id "$PAY_NS" payments-api)" | jq -e .deploymentId; }
  wait_for "RHACS sees the new payments-api" 300 _seen
  rhacs-nb-lock "$PAY_NS/payments-api" >/dev/null && ok "payments-api: fresh, network baseline EMPTY + LOCKED"
  _pb() { rhacs-pb-lock "$PAY_NS/payments-api"; }
  wait_for "payments-api process baseline locked" 180 _pb
}
