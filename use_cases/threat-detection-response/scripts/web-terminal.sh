#!/usr/bin/env bash
# web-terminal.sh — the live demo, in the browser (make web-terminal).
#
# Serves each `make live` pane as its OWN browser terminal (ttyd), so the docs/TALK.html deck
# can show them as windows you move, resize, minimize and maximize:
#
#   7681  1 ATTACKER   type here: pwn 'id' · link https://…
#   7682  2 C2         attacker's laptop, nc listening on :4444
#   7683  3 RHACS      live violations
#   7684  4 BLOG       app logs — every attack is just a "link check"
#   7685  5 PODS       the kill + restart
#
#   scripts/web-terminal.sh                start all five (foreground; Ctrl-C stops everything)
#   WEB_TERM_FONT=22 scripts/...           bigger font for the attacker pane (others scale)
#   WEB_TERM_FAMILY="Red Hat Mono" ...     another installed monospace font
#
# The processes survive the browser: each pane runs in its own tmux session (a private tmux
# server, -L tdrweb, one pane, no status bar). Closing or reloading the page only detaches;
# opening it again shows the same running process. The deck's ↻ button restarts a pane from
# zero (it connects with ?arg=reset, which kills that pane's session and starts it fresh).
#
# Renderer: canvas. Measures and draws the text in the same place, so the letters never spread
# apart (the DOM renderer did that in Firefox) and box lines stay solid. Tested in Firefox 160.
# The deck's A-/A+ per window changes the size live (?fontSize=N).
#
# Security: these are writable shells. They bind to the loopback interface only, and ttyd
# checks the WebSocket Origin (--check-origin), so other web pages cannot drive them. The only
# URL argument accepted is "reset". Never expose them on a network.
set -euo pipefail
TDR_DIR=$(cd "$(dirname "$0")/.." && pwd)
STATE_DIR="$TDR_DIR/.state"; mkdir -p "$STATE_DIR"
CONF="$STATE_DIR/web-tmux.conf"
T=(tmux -L tdrweb -f "$CONF")

# ---- one pane: attach to (or create) its tmux session. Called by ttyd for each browser client.
if [[ ${1:-} == --attach ]]; then
  name=${2:?pane name}
  [[ $name =~ ^(attacker|c2|rhacs|blog|pods)$ ]] || { echo "unknown pane: $name" >&2; exit 1; }
  if [[ ${3:-} == reset ]]; then "${T[@]}" kill-session -t "=$name" 2>/dev/null || true; fi
  exec "${T[@]}" new-session -A -s "$name" "'$TDR_DIR/scripts/live.sh' --pane $name"
fi

FONT=${WEB_TERM_FONT:-20}
# ONE installed terminal font. Do not give a long fallback list: xterm.js measures the cell
# width with the FIRST font, so a missing first font spreads every letter apart.
# Adwaita Mono is GNOME's terminal font (installed on Fedora). Override: WEB_TERM_FAMILY="Red Hat Mono"
FAMILY="\"${WEB_TERM_FAMILY:-Adwaita Mono}\", monospace"

command -v ttyd >/dev/null || { echo "ttyd is not installed — run: sudo dnf install ttyd" >&2; exit 1; }
command -v tmux >/dev/null || { echo "tmux is not installed — run: sudo dnf install tmux" >&2; exit 1; }

# tmux is only the process keeper here: no status bar, mouse wheel scrolls the history.
cat > "$CONF" <<'EOF'
set -g status off
set -g mouse on
set -g escape-time 0
set -g history-limit 50000
set -g window-size latest
set -g remain-on-exit on
set -g allow-rename off
set -g default-terminal "tmux-256color"
set -ga terminal-overrides ",xterm-256color:Tc"
EOF

#      name     port  font-delta  background
PANES=("attacker 7681  0 #2e1b1b"
       "c2       7682 -2 #2b2318"
       "rhacs    7683 -2 #16242e"
       "blog     7684 -4 #142620"
       "pods     7685 -4 #201b2e")

pids=()
cleanup() {
  kill "${pids[@]}" 2>/dev/null || true; wait 2>/dev/null || true
  "${T[@]}" kill-server 2>/dev/null || true      # Ctrl-C also stops the demo processes
}
trap cleanup EXIT INT TERM

for p in "${PANES[@]}"; do
  read -r name port delta bg <<<"$p"
  ttyd --writable --check-origin --interface lo --port "$port" --url-arg \
    -t rendererType=canvas -t fontSize=$((FONT + delta)) -t "fontFamily=$FAMILY" \
    -t fontWeight=500 -t fontWeightBold=700 -t lineHeight=1.1 \
    -t "theme={\"background\":\"$bg\",\"foreground\":\"#f0f0f0\",\"cursor\":\"#ffffff\",\"selectionBackground\":\"#5a5a5a\"}" \
    -t disableLeaveAlert=true -t disableResizeOverlay=true -t titleFixed="$name" \
    "$TDR_DIR/scripts/web-terminal.sh" --attach "$name" >/dev/null 2>&1 &
  pids+=($!)
done

sleep 1
for p in "${PANES[@]}"; do
  read -r name port _ _ <<<"$p"
  printf '  %-9s http://127.0.0.1:%s\n' "$name" "$port"
done
echo "Web terminals running (Ctrl-C stops them and their processes). Open docs/TALK.html → ▶ Slideshow."
wait
