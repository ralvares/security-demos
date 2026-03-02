# Detect roxctl binary: prefer PATH, fall back to ./roxctl
if command -v roxctl &>/dev/null; then
  _ROXCTL="roxctl"
elif [[ -x "./roxctl" ]]; then
  _ROXCTL="./roxctl"
else
  echo "Warning: roxctl not found in PATH or current directory" >&2
  _ROXCTL="roxctl"
fi

# Internal function to handle the clean table formatting
_rox_format_jq() {
  # jq parses the data, column -t aligns it, cut -c 1- trims it to screen width
  jq -r "$1" | column -t -s $'\t' | cut -c 1-$(tput cols)
}

# 1. Image Check (Policies) - Path: .results[].violatedPolicies
rox-check() {
  $_ROXCTL image check --insecure-skip-tls-verify -o json -i "$1" 2>/dev/null | \
  _rox_format_jq '["POLICY", "SEVERITY", "ENFORCED", "VIOLATION"], (["-"*10,"-"*10,"-"*10,"-"*10]), (.results[].violatedPolicies[]? | [.name, .severity, .failingCheck, .violation[0]]) | @tsv'
}

# 2. Image Scan (CVEs) - Path: .result.vulnerabilities
rox-scan() {
  $_ROXCTL image scan --severity IMPORTANT,CRITICAL --insecure-skip-tls-verify -o json -i "$1" 2>/dev/null | \
  _rox_format_jq '["CVE", "SEVERITY", "COMPONENT", "VERSION", "FIXED"], (["-"*5,"-"*5,"-"*5,"-"*5,"-"*5]), (.result.vulnerabilities[]? | [.cveId, .cveSeverity, .componentName, .componentVersion, .componentFixedVersion]) | @tsv'
}

# 3. Deployment Check (YAMLs) - Path: .results[].violatedPolicies
rox-deploy() {
  $_ROXCTL deployment check --insecure-skip-tls-verify -o json -f "$1" 2>/dev/null | \
  _rox_format_jq '["POLICY", "SEVERITY", "ENFORCED", "VIOLATION"], (["-"*10,"-"*10,"-"*10,"-"*10]), (.results[].violatedPolicies[]? | [.name, .severity, .failingCheck, .violation[0]]) | @tsv'
}

# 4. Get RHACS admin password from central-htpasswd secret
rox-get-secret() {
  oc get secret central-htpasswd -o jsonpath='{.data.password}' -n stackrox | base64 -d
  echo
}