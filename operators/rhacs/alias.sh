# Internal function to handle the clean table formatting
_rox_format_jq() {
  # We use @tsv for alignment and column -t to make it look like a real table
  # The 'cut' at the end ensures the web terminal never wraps the text
  jq -r "$1" | column -t -s $'\t' | cut -c 1-$(tput cols)
}

# 1. Image Check
rox-check() {
  ./roxctl image check --insecure-skip-tls-verify -o json -i "$1" 2>/dev/null | \
  _rox_format_jq '["POLICY", "SEVERITY", "VIOLATION"], (["-"*10,"-"*10,"-"*10]), (.alerts[]? | [.policy.name, .policy.severity, .violations[0].message]) | @tsv'
}

# 2. Image Scan (Vulnerabilities/CVEs)
rox-scan() {
  ./roxctl image scan --insecure-skip-tls-verify -o json -i "$1" 2>/dev/null | \
  _rox_format_jq '["CVE", "SEVERITY", "COMPONENT", "VERSION"], (["-"*10,"-"*10,"-"*10,"-"*10]), (.vulnerabilities[]? | [.cve, .severity, .componentName, .componentVersion]) | @tsv'
}

# 3. Deployment Check (YAML/JSON files)
rox-deploy() {
  ./roxctl deployment check --insecure-skip-tls-verify -o json -f "$1" 2>/dev/null | \
  _rox_format_jq '["POLICY", "SEVERITY", "VIOLATION"], (["-"*10,"-"*10,"-"*10]), (.results[].violatedPolicies[]? | [.name, .severity, .violation[0]]) | @tsv'
}