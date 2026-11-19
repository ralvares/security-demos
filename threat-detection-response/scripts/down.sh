#!/usr/bin/env bash
# down.sh — stop EVERYTHING the demo runs, delete NOTHING. `make up` brings it all back.
#
#   1. live views     tmux session 'tdr' (make live) + web terminals (make web-terminal)
#   2. attacker       containers stopped, attacker address + firewall rules removed
#   3. CRC            VM stopped (graceful, forced only if that fails) — cluster, RHACS,
#                     images and baselines stay on disk; frees ~20 GiB RAM
#   4. CRC services   user daemon + sockets stopped
set -uo pipefail          # no -e: every step runs even if an earlier one fails
source "$(dirname "$0")/lib/common.sh"
S="$TDR_DIR/scripts"

if ! id -nG | tr ' ' '\n' | grep -qx libvirt && getent group libvirt | grep -qw "$USER"; then
  exec sg libvirt -c "$(printf '%q ' "$0" "$@")"
fi

step "Live views"
tmux kill-session -t tdr 2>/dev/null && ok "tmux session 'tdr' closed" || info "no tmux session"
pkill -f 'ttyd .*web-terminal.sh --attach' 2>/dev/null && ok "web terminals stopped" || info "no web terminals"
tmux -L tdrweb kill-server 2>/dev/null || true

"$S/attacker.sh" down || warn "attacker teardown incomplete (see above)"

step "CRC"
if crc status -o json 2>/dev/null | jq -e '.crcStatus == "Stopped"' >/dev/null; then
  ok "already stopped"
else
  crc stop || { warn "graceful stop failed — forcing"; crc stop -f; }
fi
systemctl --user stop crc-http.socket crc-vsock.socket crc-daemon.service 2>/dev/null || true
ok "CRC daemon + sockets stopped"

echo
crc status 2>/dev/null | head -2
printf '%s%sEverything stopped.%s Nothing deleted — %smake up%s brings it back.\n' "$GRN" "$B" "$N" "$B" "$N"
