# Detect roxctl binary: prefer PATH, fall back to ./roxctl
# Resolve absolute path to avoid recursion with roxctl() wrapper
if command -v roxctl &>/dev/null; then
  _ROXCTL="$(command -v roxctl)"
elif [[ -x "./roxctl" ]]; then
  _ROXCTL="$(cd . && pwd)/roxctl"
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

# Helper: extract value for a flag from args (e.g. _rox_extract_flag -i "$@")
_rox_extract_flag() {
  local flag="$1"; shift
  while [[ $# -gt 0 ]]; do
    case "$1" in
      "$flag") echo "$2"; return 0 ;;
      "$flag"=*) echo "${1#*=}"; return 0 ;;
    esac
    shift
  done
  return 1
}

# 5. roxctl wrapper - mimics real roxctl syntax with formatted output
roxctl() {
  case "$1 $2" in
    "image check")
      shift 2
      local img; img="$(_rox_extract_flag -i "$@")" || { echo "Usage: roxctl image check -i <image>" >&2; return 1; }
      rox-check "$img"
      ;;
    "image scan")
      shift 2
      local img; img="$(_rox_extract_flag -i "$@")" || { echo "Usage: roxctl image scan -i <image>" >&2; return 1; }
      rox-scan "$img"
      ;;
    "deployment check")
      shift 2
      local file; file="$(_rox_extract_flag -f "$@")" || { echo "Usage: roxctl deployment check -f <file>" >&2; return 1; }
      rox-deploy "$file"
      ;;
    *)
      echo "Supported commands: roxctl image check -i <image>, roxctl image scan -i <image>, roxctl deployment check -f <file>" >&2
      return 1
      ;;
  esac
}