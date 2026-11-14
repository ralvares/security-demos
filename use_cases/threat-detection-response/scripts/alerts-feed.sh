#!/usr/bin/env bash
# alerts-feed.sh — live RHACS violations for the demo, as a plain-language security timeline.
# Used by `make live` (pane 3). Polls the RHACS API every 2 seconds.
#
#   scripts/alerts-feed.sh            watch unhackable + payments
#   NS="unhackable" scripts/alerts-feed.sh
set -uo pipefail
source "$(dirname "$0")/lib/common.sh"
load_rhacs

NS=${NS:-$APP_NS,$PAY_NS}
declare -A SEEN      # alert id -> last seen alert time
declare -A KILLS     # alert id -> enforcement count already printed

# MITRE ATT&CK tactic IDs → names (the tactics this demo exercises; falls back to the ID).
declare -A TACTIC=(
  [TA0001]="Initial Access"  [TA0002]="Execution"        [TA0003]="Persistence"
  [TA0004]="Priv. Esc."      [TA0005]="Defense Evasion"  [TA0006]="Credential Access"
  [TA0007]="Discovery"       [TA0008]="Lateral Movement" [TA0009]="Collection"
  [TA0010]="Exfiltration"    [TA0011]="Command & Control" [TA0040]="Impact"
  [TA0042]="Resource Dev."   [TA0043]="Reconnaissance"
)

# Severity badge: a coloured chip, readable at a glance from the back of the room.
# Muted severity chips: dark, desaturated backgrounds with soft text — distinguishable at a
# glance without the eye strain of full-bright red/yellow/cyan blocks.
badge() { case $1 in
  CRITICAL*) printf '\e[48;5;52;38;5;217m CRITICAL \e[0m';;
  HIGH*)     printf '\e[48;5;94;38;5;223m HIGH     \e[0m';;
  MEDIUM*)   printf '\e[48;5;24;38;5;153m MEDIUM   \e[0m';;
  *)         printf '\e[48;5;238;38;5;250m LOW      \e[0m';;
esac; }

detail() { # alert json -> short "what the attacker did"
  jq -r '
    if (.processViolation.processes // []) | length > 0 then
      (.processViolation.processes | sort_by(.signal.time) | last | .signal | "\(.execFilePath) \(.args // "")")
    elif (.violations // []) | length > 0 then
      (.violations | last | .message)
    else "" end' <<<"$1" | tr -s ' ' | cut -c1-96
}

rule=$'\e[2m──────────────────────────────────────────────────────────────\e[0m'
printf '\e[1;38;5;110m RHACS · Runtime Threat Detection \e[0m\e[2m— live, every attacker move, in seconds\e[0m\n'
printf '%s\n' "$rule"
printf '%swatching %s · waiting for the first move…%s\n' "$DIM" "$NS" "$N"

first=1
while true; do
  list=$(rox GET "/v1/alerts?query=$(uri "Namespace:$NS+Violation State:Active")&pagination.limit=100" 2>/dev/null) || { sleep 2; continue; }
  while IFS=$'\t' read -r id t; do
    [[ -z $id ]] && continue
    if [[ $first == 1 ]]; then SEEN[$id]=$t; KILLS[$id]=0; continue; fi
    [[ ${SEEN[$id]:-} == "$t" ]] && continue
    SEEN[$id]=$t
    a=$(rox GET "/v1/alerts/$id" 2>/dev/null) || continue
    sev=$(jq -r '.policy.severity | sub("_SEVERITY";"")' <<<"$a")
    pol=$(jq -r '.policy.name' <<<"$a")
    dep=$(jq -r '"\(.deployment.namespace)/\(.deployment.name)"' <<<"$a")
    tac=$(jq -r '.policy.mitreAttackVectors[0].tactic // empty' <<<"$a")
    tech=$(jq -r '.policy.mitreAttackVectors[0].techniques[0] // empty' <<<"$a")
    kills=$(jq -r '.enforcement.action // empty | select(. != "UNSET_ENFORCEMENT")' <<<"$a")
    cnt=$(jq -r '.enforcementCount // 0' <<<"$a")

    mitre=""
    [[ -n $tac ]] && mitre="${TACTIC[$tac]:-$tac}${tech:+ · $tech}"

    # Two lines per violation, no blank separator: header (badge · policy · target),
    # then one dim context line (MITRE + what the attacker did), truncated to the pane width.
    printf ' %s %s%s%s %s%s%s\n' \
      "$(badge "$sev")" "$B" "$pol" "$N" "$DIM" "$dep" "$N"
    d=$(detail "$a")
    ctx=""
    [[ -n $mitre ]] && ctx="MITRE $mitre"
    [[ -n $d ]]     && ctx="${ctx:+$ctx  ·  }↳ $d"
    if [[ -n $ctx ]]; then
      # Fit the context line to the pane so long paths truncate cleanly instead of wrapping.
      cols=$(tput cols 2>/dev/null || echo 90); avail=$((cols - 12))
      (( avail > 20 && ${#ctx} > avail )) && ctx="${ctx:0:avail-1}…"
      printf '          %s%s%s\n' "$DIM" "$ctx" "$N"
    fi
    if [[ -n $kills && $cnt -gt ${KILLS[$id]:-0} ]]; then
      printf '          \e[48;5;52;38;5;217m ✖ POD KILLED by RHACS ×%s \e[0m\n' "$cnt"
      KILLS[$id]=$cnt
    fi
  done < <(jq -r '.alerts[]? | [.id, .time] | @tsv' <<<"$list")
  first=0
  sleep 2
done
