#!/usr/bin/env bash
# shoot.sh SHOTS.json — take walkthrough screenshots into docs/img (Playwright in a container).
set -euo pipefail
DOCS=$(cd "$(dirname "$0")/.." && pwd)
podman image exists localhost/tdr-shoot || podman build -q -t localhost/tdr-shoot "$DOCS/tools" >/dev/null
PW=$(oc get secret central-htpasswd -n stackrox -o jsonpath='{.data.password}' | base64 -d)
podman run --rm --network host -v "$DOCS:/work:Z" -e ROX_PASSWORD="$PW" localhost/tdr-shoot \
  python /work/tools/shoot.py "/work/$(realpath --relative-to="$DOCS" "$1")" /work/img
