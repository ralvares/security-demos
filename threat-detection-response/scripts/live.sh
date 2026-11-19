#!/usr/bin/env bash
# live.sh — the live demo in one tmux window (make live).
#
#   ┌──────────────────────────────┬──────────────────────────────┐
#   │ 1  ATTACKER  you type curl   │ 3  RHACS   live violations   │
#   │                              ├──────────────────────────────┤
#   ├──────────────────────────────┤ 4  BLOG    oc logs -l app    │
#   │ 2  C2  nc listening :4444    ├──────────────────────────────┤
#   │                              │ 5  PODS    kill + restart    │
#   └──────────────────────────────┴──────────────────────────────┘
#
# Pane 1 starts with a cheat sheet (scripts/live.sh --cheatsheet prints it again).
# Mouse is on: click a pane to type in it. Quit: Ctrl-b d (detach) or `tmux kill-session -t tdr`.
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

SESSION=tdr
RC="$STATE_DIR/live.bashrc"

# The four panes' start commands — shared by launch and by --reset (respawn), so the layout
# only has to be described once.
ATTACKER_CMD="bash --rcfile '$RC' -i"
FEED_CMD="'$TDR_DIR/scripts/alerts-feed.sh'; read"
C2_CMD="'$TDR_DIR/scripts/attacker.sh' c2; read"
# Blog app logs: every attack arrives through /api/links/check, so the app only ever logs an
# innocent "link check" — the point of the pane (the app sees nothing wrong; RHACS does). The
# -f stream ends when the pod is killed in Act 5, so loop to re-attach to the fresh pod.
BLOG_CMD="eval \"\$(crc oc-env)\"; echo 'Blog app logs — every attack is just a \"link check\" to the app (oc logs -l app=blog)'; while true; do oc logs -f -l app=blog -n $APP_NS --tail=12 --max-log-requests=10 --prefix=false 2>/dev/null; echo '  … pod gone — re-attaching to the fresh one'; sleep 1; done"
PODS_CMD="eval \"\$(crc oc-env)\"; echo 'Pods — watch the kill + restart'; oc get pods -n $APP_NS -w -o custom-columns=POD:.metadata.name,STATUS:.status.phase,STARTED:.status.startTime; read"

# Per-pane background tints (truecolor; falls back to the nearest 256-colour on older
# terminals). Each pane gets its own dark, desaturated hue so a busy screen stays readable at
# a glance — the two attacker panes stay warm (red/amber), the three cluster panes stay cool
# (blue/green/violet). All near-black so text contrast is preserved.
BG_ATTACKER=${BG_ATTACKER:-bg=#2e1b1b}   # 1 ATTACKER — red
BG_C2=${BG_C2:-bg=#2b2318}               # 2 C2       — amber
BG_RHACS=${BG_RHACS:-bg=#16242e}         # 3 RHACS    — blue
BG_BLOG=${BG_BLOG:-bg=#142620}           # 4 BLOG     — green
BG_PODS=${BG_PODS:-bg=#201b2e}           # 5 PODS     — violet

cheatsheet() {
  cat <<EOF

${B}${RED} ☠  ATTACKER ${N}${DIM} — outside the cluster.${N}
EOF
}

# make reset-live: clean every pane and put the demo back to the start, without tearing down
# the window. Respawns the three process panes (fresh screen) and the attacker shell, then
# wipes scrollback.
if [[ ${1:-} == --reset ]]; then
  need tmux
  tmux has-session -t "$SESSION" 2>/dev/null || die "no live session '$SESSION' — run 'make live' first"
  pane_by() { tmux list-panes -t "$SESSION" -F '#{pane_id} #{pane_title}' | awk -v k="$1" 'index($0,k){print $1; exit}'; }
  pa=$(pane_by ATTACKER); pc=$(pane_by C2); pr=$(pane_by RHACS); pb=$(pane_by BLOG); pp=$(pane_by PODS)
  "$TDR_DIR/scripts/demo.sh" reset

  # Respawn every pane fresh. The catch: this command is itself running inside one of these
  # panes (usually ATTACKER), and `respawn-pane -k` on that pane kills THIS script mid-run —
  # which is why some panes weren't getting reset. So respawn the pane we're in LAST, after
  # everything else is already done ($TMUX_PANE is the pane this script runs in).
  self="${TMUX_PANE:-}"; self_cmd=""
  for pair in "$pa|$ATTACKER_CMD" "$pc|$C2_CMD" "$pr|$FEED_CMD" "$pb|$BLOG_CMD" "$pp|$PODS_CMD"; do
    id=${pair%%|*}; cmd=${pair#*|}
    [[ -z $id ]] && continue
    if [[ $id == "$self" ]]; then self_cmd=$cmd; continue; fi
    tmux respawn-pane -k -t "$id" "$cmd"
  done
  tmux select-pane -t "$pa" -P "$BG_ATTACKER"; tmux select-pane -t "$pc" -P "$BG_C2"
  tmux select-pane -t "$pr" -P "$BG_RHACS"; tmux select-pane -t "$pb" -P "$BG_BLOG"; tmux select-pane -t "$pp" -P "$BG_PODS"
  for pid in "$pa" "$pc" "$pr" "$pb" "$pp"; do [[ -n $pid ]] && tmux clear-history -t "$pid"; done
  tmux select-pane -t "$pa"
  ok "live panes cleared; demo back to the start"
  # Last: respawn the pane we're in (this kills this script — nothing left to do but exit).
  [[ -n $self && -n $self_cmd ]] && exec tmux respawn-pane -k -t "$self" "$self_cmd"
  exit 0
fi

if [[ ${1:-} == --cheatsheet ]]; then
  if [[ -z ${BLOG:-} ]]; then
    eval "$(crc oc-env 2>/dev/null)" 2>/dev/null || true
    host=$(oc get route blog -n "$APP_NS" -o jsonpath='{.spec.host}' 2>/dev/null || true)
    BLOG=https://${host:-blog-unhackable.apps-crc.testing}
  fi
  cheatsheet
  exit 0
fi

[[ ${1:-} == --pane ]] && need oc || need tmux oc
use_crc
load_rhacs
BLOG=https://$(oc get route blog -n "$APP_NS" -o jsonpath='{.spec.host}')
export BLOG

# Pane 1 starts an interactive bash with the demo environment and the cheat sheet.
cat > "$RC" <<EOF
[ -f ~/.bashrc ] && . ~/.bashrc
# make live runs under make, so MAKELEVEL/MAKEFLAGS are exported into this pane; without
# clearing them every 'make <target>' you type here prints "Entering/Leaving directory".
unset MAKELEVEL MAKEFLAGS MFLAGS
eval "\$(crc oc-env 2>/dev/null)"
export BLOG=$BLOG
cd "$TDR_DIR"
source "$TDR_DIR/scripts/lib/live-shell.sh"
PS1='\[\e[1;31m\]attacker\[\e[0m\]:\[\e[34m\]~\[\e[0m\]\$ '
clear
"$TDR_DIR/scripts/live.sh" --cheatsheet
EOF

# --pane NAME: run ONE pane's command on its own, without tmux. Used by scripts/web-terminal.sh,
# which serves each pane as its own browser terminal (ttyd) for the TALK.html deck.
if [[ ${1:-} == --pane ]]; then
  case ${2:-} in
    attacker) exec bash -c "$ATTACKER_CMD" ;;
    c2)       exec bash -c "$C2_CMD" ;;
    rhacs)    exec bash -c "$FEED_CMD" ;;
    blog)     exec bash -c "$BLOG_CMD" ;;
    pods)     exec bash -c "$PODS_CMD" ;;
    *) die "usage: live.sh --pane attacker|c2|rhacs|blog|pods" ;;
  esac
fi

tmux kill-session -t "$SESSION" 2>/dev/null || true
tmux new-session -d -s "$SESSION" -x 250 -y 64 -n demo "$ATTACKER_CMD"
tmux set-option -t "$SESSION" mouse on
tmux set-option -t "$SESSION" pane-border-status top
tmux set-option -t "$SESSION" pane-border-format ' #{pane_title} '
tmux set-option -t "$SESSION" pane-active-border-style 'fg=yellow,bold'
tmux set-option -t "$SESSION" status off

# Left column: ATTACKER (top) + C2 (bottom). Right column, top to bottom: RHACS violations
# (the star, biggest), the BLOG app logs (what the app itself sees — just "link checks"), and
# a short PODS watch (just enough to show the kill + restart).
P1=$(tmux display-message -p -t "$SESSION:demo.0" '#{pane_id}')
P3=$(tmux split-window -h -l 46% -t "$P1" -P -F '#{pane_id}' "$FEED_CMD")
P2=$(tmux split-window -v -l 38% -t "$P1" -P -F '#{pane_id}' "$C2_CMD")
PB=$(tmux split-window -v -l 45% -t "$P3" -P -F '#{pane_id}' "$BLOG_CMD")
P4=$(tmux split-window -v -l 32% -t "$PB" -P -F '#{pane_id}' "$PODS_CMD")

tmux select-pane -t "$P1" -T "1  ATTACKER — type here:  pwn 'id'   ·   link https://…"
tmux select-pane -t "$P2" -T "2  C2 — attacker's laptop, nc listening on attacker.example.local:4444"
tmux select-pane -t "$P3" -T "3  RHACS — live violations"
tmux select-pane -t "$PB" -T "4  BLOG — app logs (oc logs -l app=blog):  every attack is just a 'link check'"
tmux select-pane -t "$P4" -T "5  PODS — the kill + restart"

# A unique near-black tint per pane so the busy screen stays easy to read; warm = attacker
# (this laptop), cool = the live cluster. (The $BG_* values are defined up top.)
tmux select-pane -t "$P1" -P "$BG_ATTACKER"
tmux select-pane -t "$P2" -P "$BG_C2"
tmux select-pane -t "$P3" -P "$BG_RHACS"
tmux select-pane -t "$PB" -P "$BG_BLOG"
tmux select-pane -t "$P4" -P "$BG_PODS"

tmux select-pane -t "$P1"

if [[ -n ${TMUX:-} ]]; then tmux switch-client -t "$SESSION"; else exec tmux attach -t "$SESSION"; fi
