#!/usr/bin/env bash
# install-nopasswd.sh — one root prompt, then `make up` / `make down` never ask for a password.
#
# Installs scripts/root/tdr-attacker-net to /usr/local/sbin (root-owned) and a sudoers rule that
# lets THIS user run exactly that helper without a password — nothing else.
#   scripts/install-nopasswd.sh            install (asks for root once)
#   scripts/install-nopasswd.sh --remove   uninstall
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"
U=${SUDO_USER:-${PKEXEC_UID:+$(id -nu "$PKEXEC_UID")}}; U=${U:-$USER}
if [[ $EUID -ne 0 ]]; then exec_root() { if [[ -t 0 ]]; then exec sudo "$@"; else exec pkexec "$@"; fi; }
  exec_root env SUDO_USER="$USER" "$(readlink -f "$0")" "$@"; fi

if [[ ${1:-} == --remove ]]; then
  rm -f /etc/sudoers.d/tdr-demo /usr/local/sbin/tdr-attacker-net; ok "removed"; exit 0
fi
install -m 0755 -o root -g root "$TDR_DIR/scripts/root/tdr-attacker-net" /usr/local/sbin/tdr-attacker-net
restorecon /usr/local/sbin/tdr-attacker-net 2>/dev/null || true
tmp=$(mktemp)
printf '# Threat Detection & Response demo — written by %s\n%s ALL=(root) NOPASSWD: /usr/local/sbin/tdr-attacker-net\n' "$0" "$U" > "$tmp"
visudo -cqf "$tmp" || { rm -f "$tmp"; die "sudoers rule failed validation"; }
install -m 0440 -o root -g root "$tmp" /etc/sudoers.d/tdr-demo; rm -f "$tmp"
ok "$U may run /usr/local/sbin/tdr-attacker-net without a password (nothing else)"
