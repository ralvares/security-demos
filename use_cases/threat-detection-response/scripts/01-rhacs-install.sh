#!/usr/bin/env bash
# 01-rhacs-install.sh — install RHACS on CRC: operator → Central → CRS → SecuredCluster → API token.
#
#   scripts/01-rhacs-install.sh              install (idempotent)
#   scripts/01-rhacs-install.sh --password   copy the Central admin password to the clipboard
#   scripts/01-rhacs-install.sh --uninstall  remove RHACS (keeps CRDs)
#
# Secrets never hit the terminal: the admin password stays in the cluster, the
# API token goes to .state/rhacs.env (mode 600, git-ignored).
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"
INSTALL_DIR="$TDR_DIR/rhacs/install"
need oc jq curl roxctl

use_crc

central_host() { oc get route central -n stackrox -o jsonpath='{.spec.host}' 2>/dev/null; }
admin_pw()     { oc get secret central-htpasswd -n stackrox -o jsonpath='{.data.password}' | base64 -d; }

case "${1:-}" in
  --password)
    admin_pw | wl-copy --trim-newline 2>/dev/null && ok "admin password copied to clipboard (user: admin)" \
      || die "wl-copy failed; run: oc get secret central-htpasswd -n stackrox -o jsonpath='{.data.password}' | base64 -d"
    echo "  console: https://$(central_host)"
    exit 0 ;;
  --uninstall)
    step "Removing RHACS"
    oc delete securedcluster --all -n stackrox --ignore-not-found --wait=true
    oc delete central --all -n stackrox --ignore-not-found --wait=true
    oc delete -f "$INSTALL_DIR/operator.yaml" --ignore-not-found
    oc delete namespace stackrox --ignore-not-found
    rm -f "$RHACS_ENV" "$STATE_DIR/crs.yaml" "$HOME/.bashrc.d/rhacs.sh"
    ok "RHACS removed"; exit 0 ;;
  "") ;;
  *) die "unknown option: $1" ;;
esac

# ---------------------------------------------------------------- operator
step "RHACS operator"
# On a fresh CRC the catalog pods start before the pull secret lands, hit ImagePullBackOff
# and never retry on their own (the CSV then never appears). Kick them until the catalog is READY.
# Only redhat-operators is needed: disable the other ~1 GB catalog images so they don't share the bandwidth.
oc patch operatorhub cluster --type merge \
  -p '{"spec":{"sources":[{"name":"certified-operators","disabled":true},{"name":"community-operators","disabled":true}]}}' >/dev/null
catalog_ready() {
  [[ $(oc get catalogsource redhat-operators -n openshift-marketplace \
       -o jsonpath='{.status.connectionState.lastObservedState}') == READY ]] && return 0
  oc get pods -n openshift-marketplace -l olm.catalogSource -o json |
    jq -r '.items[] | select([.status.initContainerStatuses[]?, .status.containerStatuses[]? |
             .state.waiting.reason] | any(. == "ImagePullBackOff" or . == "ErrImagePull")) | .metadata.name' |
    xargs -r oc delete pod -n openshift-marketplace --force --grace-period=0 >/dev/null 2>&1
  return 1
}
wait_for "redhat-operators catalog READY" 900 catalog_ready
oc apply -f "$INSTALL_DIR/operator.yaml" >/dev/null
csv_ok() { oc get csv -n rhacs-operator -o json | jq -e '[.items[] | select(.metadata.name|startswith("rhacs-operator")) | select(.status.phase=="Succeeded")] | length > 0'; }
wait_for "operator CSV Succeeded" 900 csv_ok
oc wait --for condition=established --timeout=300s crd/centrals.platform.stackrox.io crd/securedclusters.platform.stackrox.io >/dev/null
ok "$(oc get csv -n rhacs-operator -o json | jq -r '.items[] | select(.metadata.name|startswith("rhacs-operator")) | .spec.displayName + " " + .spec.version')"

# ---------------------------------------------------------------- central
step "Central"
oc apply -f "$INSTALL_DIR/central.yaml" >/dev/null
wait_for "Central available" 1200 oc wait -n stackrox --for=condition=Available --timeout=10s central/stackrox-central-services
wait_for "Central route" 300 central_host
ENDPOINT="$(central_host):443"
api_up() { curl -sfk "https://$ENDPOINT/v1/ping"; }
wait_for "Central API" 600 api_up
ok "https://$(central_host)"

# ---------------------------------------------------------------- CRS + secured cluster
step "SecuredCluster '$CLUSTER_NAME' (Cluster Registration Secret)"
if oc get secret -n stackrox cluster-registration-secret >/dev/null 2>&1 || \
   oc get secret -n stackrox sensor-tls >/dev/null 2>&1; then
  ok "cluster already registered"
else
  rm -f "$STATE_DIR/crs.yaml"   # leftover from a deleted cluster: roxctl refuses to overwrite it
  # env -u: a stale ROX_API_TOKEN from ~/.bashrc.d/rhacs.sh (e.g. after a rebuild) + password = roxctl refuses
  env -u ROX_API_TOKEN ROX_ADMIN_PASSWORD="$(admin_pw)" roxctl -e "$ENDPOINT" --insecure-skip-tls-verify \
    central crs generate "$CLUSTER_NAME-$(date +%Y%m%d%H%M)" --output "$STATE_DIR/crs.yaml" >/dev/null
  chmod 600 "$STATE_DIR/crs.yaml"
  oc apply -n stackrox -f "$STATE_DIR/crs.yaml" >/dev/null
  ok "CRS generated and applied"
fi
oc apply -f "$INSTALL_DIR/secured-cluster.yaml" >/dev/null
sensor_ok() { oc rollout status deploy/sensor -n stackrox --timeout=5s; }
collector_ok() { oc rollout status ds/collector -n stackrox --timeout=5s; }
wait_for "sensor" 900 sensor_ok
wait_for "collector" 900 collector_ok
cluster_healthy() { curl -sfk -u "admin:$(admin_pw)" "https://$ENDPOINT/v1/clusters" | jq -e --arg n "$CLUSTER_NAME" '.clusters[] | select(.name==$n) | .healthStatus.sensorHealthStatus=="HEALTHY"'; }
wait_for "cluster '$CLUSTER_NAME' healthy in Central" 600 cluster_healthy

# ---------------------------------------------------------------- API token + shell integration
step "API token for roxctl and the demo scripts"
mkdir -p "$(dirname "$RHACS_ENV")" && chmod 700 "$(dirname "$RHACS_ENV")"
[[ -f $STATE_DIR/rhacs.env && ! -f $RHACS_ENV ]] && mv "$STATE_DIR/rhacs.env" "$RHACS_ENV"   # migrate old location
token_ok() { [[ -f $RHACS_ENV ]] && (source "$RHACS_ENV"; [[ $ROX_ENDPOINT == "$ENDPOINT" ]] && curl -sfk -H "Authorization: Bearer $ROX_API_TOKEN" "https://$ROX_ENDPOINT/v1/auth/status" >/dev/null); }
if token_ok; then
  ok "existing token still valid"
else
  tok=$(curl -sfk -u "admin:$(admin_pw)" -X POST "https://$ENDPOINT/v1/apitokens/generate" \
        -d '{"name":"laptop-roxctl","roles":["Admin"]}' | jq -r .token)
  [[ -n $tok && $tok != null ]] || die "token generation failed"
  ( umask 077; printf '# RHACS on CRC — written by %s\nROX_ENDPOINT=%q\nROX_API_TOKEN=%q\n' "$0" "$ENDPOINT" "$tok" > "$RHACS_ENV" )
  ok "new token"
fi
chmod 600 "$RHACS_ENV"
ok "token + endpoint: $RHACS_ENV (mode 600)"

mkdir -p "$HOME/.bashrc.d"
cat > "$HOME/.bashrc.d/rhacs.sh" <<'RC'
# RHACS (CRC) — roxctl and API access from this laptop.
# Written by security-demos/use_cases/threat-detection-response/scripts/01-rhacs-install.sh
if [ -r "$HOME/.config/rhacs/crc.env" ]; then
  set -a; . "$HOME/.config/rhacs/crc.env"; set +a
  export ROX_INSECURE_CLIENT_SKIP_TLS_VERIFY=true   # CRC: self-signed Central certificate
  export ROX_CENTRAL_URL="https://${ROX_ENDPOINT%:443}"
fi
RC
# readable rox-* helpers (do NOT shadow roxctl)
printf '[ -r %q ] && . %q\n' "$TDR_DIR/scripts/lib/rhacs-aliases.sh" "$TDR_DIR/scripts/lib/rhacs-aliases.sh" >> "$HOME/.bashrc.d/rhacs.sh"
ok "~/.bashrc.d/rhacs.sh — every new shell: ROX_ENDPOINT, ROX_API_TOKEN + rox-* helpers"

cat <<EOF

${GRN}${B}RHACS is ready.${N}
  console:   https://$(central_host)   user: admin
  password:  scripts/01-rhacs-install.sh --password   (copies it to the clipboard)
  roxctl:    works in every new shell (try: roxctl central whoami)
  helpers:   rox-ui, rox-password, rox-scan, rox-check, rox-deploy, rox-violations, rox-processes, rox-baseline
  next:      scripts/02-demo-setup.sh
EOF
