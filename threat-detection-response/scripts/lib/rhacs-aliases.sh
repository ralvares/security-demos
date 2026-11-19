# shellcheck shell=bash
# rhacs-aliases.sh — readable RHACS output for live demos.
#
# Ported from security-demos/operators/rhacs/alias.sh, with one big fix:
# it does NOT redefine `roxctl`. The real roxctl keeps working exactly as
# documented; these rox-* helpers call it with -o json and only reformat
# the output into tables that fit the terminal.
#
#   rox-password             print the Central admin password (and copy it to the clipboard)
#   rox-ui                   Central URL + user + password, ready to log in
#   rox-scan IMAGE [SEV]     CVEs of an image          (SEV default: all — e.g. IMPORTANT,CRITICAL)
#   rox-check IMAGE          build-time policy violations of an image
#   rox-deploy FILE          deploy-time policy violations of a manifest
#   rox-violations [NS]      active runtime/deploy violations (from the API), newest first
#   rox-processes NS/DEPLOY  processes RHACS observed in a deployment
#   rox-baseline NS/DEPLOY   locked process baseline of a deployment
#
# Credentials: ROX_ENDPOINT / ROX_API_TOKEN from ~/.config/rhacs/crc.env (see ~/.bashrc.d/rhacs.sh).

# table: TSV on stdin -> aligned columns, trimmed to the terminal width
_rox_table() {
  local w; w=$(tput cols 2>/dev/null || echo 200)
  column -t -s $'\t' | cut -c "1-$w"
}

_rox_api() { # GET path
  curl -sSk -H "Authorization: Bearer ${ROX_API_TOKEN:?run 01-rhacs-install.sh}" "https://${ROX_ENDPOINT:?}$1"
}

_rox_uri() { jq -rn --arg q "$1" '$q|@uri'; }

rox-password() {
  local pw
  pw=$(oc get secret central-htpasswd -n stackrox -o jsonpath='{.data.password}' | base64 -d) || return 1
  printf '%s\n' "$pw"
  printf '%s' "$pw" | wl-copy 2>/dev/null && echo "(copied to clipboard)" >&2
}

rox-ui() {
  echo "URL:      https://${ROX_ENDPOINT%:443}"
  echo "User:     admin"
  printf 'Password: '; rox-password
}

rox-scan() {
  local img=${1:?usage: rox-scan IMAGE [SEVERITIES]} sev=${2:-LOW,MODERATE,IMPORTANT,CRITICAL} out
  out=$(command roxctl image scan --image "$img" --severity "$sev" --output json 2>/dev/null) || { echo "scan failed: $img" >&2; return 1; }
  jq -r '"CVEs: \(.result.summary.TOTAL_VULNERABILITIES // 0)   critical \(.result.summary.CRITICAL // 0)  important \(.result.summary.IMPORTANT // 0)  moderate \(.result.summary.MODERATE // 0)  low \(.result.summary.LOW // 0)"' <<<"$out"
  jq -r '(["CVE","SEVERITY","COMPONENT","VERSION","FIXED IN"] | @tsv),
         (.result.vulnerabilities[]? | [.cveId, .cveSeverity, .componentName, .componentVersion, (.componentFixedVersion // "-")] | @tsv)' <<<"$out" | _rox_table
}

rox-check() {
  local img=${1:?usage: rox-check IMAGE}
  command roxctl image check --image "$img" --output json 2>/dev/null |
    jq -r '(["POLICY","SEVERITY","BREAKS BUILD","VIOLATION"] | @tsv),
           (.results[]?.violatedPolicies[]? | [.name, .severity, (.failingCheck|tostring), (.violation[0] // "")] | @tsv)' | _rox_table
}

rox-deploy() {
  local f=${1:?usage: rox-deploy FILE}
  command roxctl deployment check --file "$f" --output json 2>/dev/null |
    jq -r '(["POLICY","SEVERITY","BLOCKS DEPLOY","VIOLATION"] | @tsv),
           (.results[]?.violatedPolicies[]? | [.name, .severity, (.failingCheck|tostring), (.violation[0] // "")] | @tsv)' | _rox_table
}

rox-violations() {
  local q="Violation State:Active"; [[ -n ${1:-} ]] && q="$q+Namespace:$1"
  _rox_api "/v1/alerts?query=$(_rox_uri "$q")&pagination.limit=100&pagination.sortOption.field=Violation%20Time&pagination.sortOption.reversed=true" |
    jq -r '(["TIME","SEVERITY","POLICY","DEPLOYMENT","ENFORCED"] | @tsv),
           (.alerts[]? | [(.time|sub("\\.[0-9]+Z$";"Z")), (.policy.severity|sub("_SEVERITY";"")), .policy.name,
                          "\(.deployment.namespace // .commonEntityInfo.namespace // "")/\(.deployment.name // "")",
                          (if (.enforcementCount // 0) > 0 then "killed ×\(.enforcementCount)" else "-" end)] | @tsv)' | _rox_table
}

_rox_dep_id() { # NS/DEPLOY
  local ns=${1%%/*} d=${1#*/}
  _rox_api "/v1/deployments?query=$(_rox_uri "Namespace:$ns+Deployment:$d")" |
    jq -r --arg ns "$ns" --arg d "$d" '[.deployments[]? | select(.namespace==$ns and .name==$d)][0].id // empty'
}

rox-processes() {
  local id; id=$(_rox_dep_id "${1:?usage: rox-processes NS/DEPLOY}") || return 1
  [[ -n $id ]] || { echo "deployment not found: $1" >&2; return 1; }
  _rox_api "/v1/processes/deployment/$id" |
    jq -r '(["TIME","CONTAINER","UID","PROCESS","ARGS"] | @tsv),
           (.processes | sort_by(.signal.time) | .[] | [(.signal.time|sub("\\.[0-9]+Z$";"Z")), .containerName, (.signal.uid|tostring), .signal.execFilePath, (.signal.args // "")[0:80]] | @tsv)' | _rox_table
}

rox-baseline() {
  local id; id=$(_rox_dep_id "${1:?usage: rox-baseline NS/DEPLOY}") || return 1
  [[ -n $id ]] || { echo "deployment not found: $1" >&2; return 1; }
  local dep; dep=$(_rox_api "/v1/deployments/$id")
  local c cluster ns; cluster=$(jq -r .clusterId <<<"$dep"); ns=$(jq -r .namespace <<<"$dep")
  for c in $(jq -r '.containers[].name' <<<"$dep"); do
    _rox_api "/v1/processbaselines/key?key.deploymentId=$id&key.containerName=$c&key.clusterId=$cluster&key.namespace=$ns" |
      jq -r --arg c "$c" '"container \($c): \(if .userLockedTimestamp then "LOCKED" else "unlocked" end)",
                          (.elements[]? | "  ✓ \(.element.processName)")'
  done
}
