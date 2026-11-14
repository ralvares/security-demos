#!/usr/bin/env bash
# build-images.sh — rebuild blog v1/v2, push them to the CRC registry, rescan with RHACS.
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"
need oc podman roxctl
use_crc
load_rhacs
REG=$(oc get route default-route -n openshift-image-registry -o jsonpath='{.spec.host}')
podman login -u kubeadmin -p "$(oc whoami -t)" --tls-verify=false "$REG" >/dev/null
for v in v1 v2; do
  podman build -q --build-arg VARIANT=$v -t "$REG/$APP_NS/blog:$v" "$TDR_DIR/app/blog" >/dev/null
  podman push -q --tls-verify=false "$REG/$APP_NS/blog:$v"
  n=$(roxctl -e "$ROX_ENDPOINT" image scan --image "$REGISTRY_SVC/$APP_NS/blog:$v" --force --output json 2>/dev/null | jq -r '.result.summary."TOTAL-VULNERABILITIES" // "?"')
  ok "blog:$v pushed — CVEs: $n"
done
oc rollout restart deploy/blog -n "$APP_NS" >/dev/null && oc rollout status deploy/blog -n "$APP_NS" --timeout=120s >/dev/null && ok "blog restarted on the new image"
