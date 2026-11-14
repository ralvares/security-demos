#!/usr/bin/env bash
# 00-crc-up.sh — install, configure and start OpenShift Local (CRC) sized for RHACS.
#
#   scripts/00-crc-up.sh            idempotent: safe to re-run, skips what's done
#
# Tunables (env):  CRC_CPUS=8  CRC_MEMORY=20480 (MiB)  CRC_DISK=100 (GiB)
#                  PULL_SECRET=~/pull-secret.txt  CRC_TARBALL=~/Downloads/crc-linux-amd64.tar.xz
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

CRC_CPUS=${CRC_CPUS:-8}
CRC_MEMORY=${CRC_MEMORY:-20480}
CRC_DISK=${CRC_DISK:-100}
PULL_SECRET=${PULL_SECRET:-$HOME/pull-secret.txt}
CRC_TARBALL=${CRC_TARBALL:-$HOME/Downloads/crc-linux-amd64.tar.xz}

need jq curl
[[ -s $PULL_SECRET ]] || die "pull secret not found at $PULL_SECRET (download: https://console.redhat.com/openshift/create/local)"
jq -e '.auths["registry.redhat.io"]' "$PULL_SECRET" >/dev/null || die "$PULL_SECRET is not a valid pull secret"
chmod 600 "$PULL_SECRET"

# ---------------------------------------------------------------- 1. crc binary
step "CRC binary"
if ! command -v crc >/dev/null; then
  [[ -f $CRC_TARBALL ]] || die "crc not installed and $CRC_TARBALL not found"
  tmp=$(mktemp -d); tar -xJf "$CRC_TARBALL" -C "$tmp"
  install -D -m 0755 "$tmp"/crc-linux-*/crc "$HOME/.local/bin/crc"; rm -rf "$tmp"
  export PATH="$HOME/.local/bin:$PATH"
fi
ok "$(crc version | head -1)  ($(crc version | sed -n 2p))"

# ---------------------------------------------------------------- 2. host prerequisites (one root prompt)
step "Host prerequisites (libvirt/KVM)"
[[ -c /dev/kvm ]] || die "/dev/kvm missing: enable virtualization (VT-x) in the BIOS"
pkgs=(libvirt-daemon-kvm libvirt-daemon-config-network qemu-kvm-core)
missing=(); for p in "${pkgs[@]}"; do rpm -q "$p" >/dev/null 2>&1 || missing+=("$p"); done
in_group=false; id -nG "$USER" | tr ' ' '\n' | grep -qx libvirt && in_group=true
if (( ${#missing[@]} )) || ! $in_group || ! systemctl is-active -q virtqemud.socket; then
  info "needs root once: ${missing[*]:-no packages} + libvirt group + libvirt sockets"
  as_root bash -c "
    set -e
    [ -n '${missing[*]}' ] && dnf install -y ${missing[*]}
    usermod -aG libvirt '$USER'
    systemctl enable --now virtqemud.socket virtnetworkd.socket virtstoraged.socket virtnodedevd.socket virtsecretd.socket virtproxyd.socket 2>/dev/null || true
  "
fi
ok "libvirt + KVM ready"

# crc refuses to run unless libvirt is an *active* group of this process.
# 'sg' activates it without logging out (no password: we're a listed member).
if ! id -nG | tr ' ' '\n' | grep -qx libvirt; then
  info "activating libvirt group for this run (no re-login needed)"
  exec sg libvirt -c "$(printf '%q ' "$0" "$@")"
fi

# ---------------------------------------------------------------- 3. crc config
step "CRC configuration: ${CRC_CPUS} vCPU, ${CRC_MEMORY} MiB, ${CRC_DISK} GiB"
crc config set consent-telemetry no >/dev/null
crc config set cpus "$CRC_CPUS" >/dev/null
crc config set memory "$CRC_MEMORY" >/dev/null
crc config set disk-size "$CRC_DISK" >/dev/null
crc config set pull-secret-file "$PULL_SECRET" >/dev/null
crc config set network-mode system >/dev/null
crc config set enable-cluster-monitoring false >/dev/null
ok "$(crc config view | tr '\n' ' ' | sed 's/- //g')"

# ---------------------------------------------------------------- 4. crc setup
step "crc setup (preflight + bundle download, ~10 min the first time)"
if crc setup --check-only >/dev/null 2>&1; then
  ok "already set up"
else
  shim=""
  if [[ ! -t 0 ]]; then
    # No terminal: route crc's internal sudo calls to the desktop password dialog.
    shim=$(mktemp -d)
    cat > "$shim/sudo" <<'EOF'
#!/bin/sh
while [ $# -gt 0 ]; do case "$1" in -u|-g) shift 2;; --) shift; break;; -*) shift;; *) break;; esac; done
exec pkexec "$@"
EOF
    chmod +x "$shim/sudo"
  fi
  PATH="${shim:+$shim:}$PATH" crc setup
  [[ -n $shim ]] && rm -rf "$shim"
  ok "crc setup done"
fi

# ---------------------------------------------------------------- 5. start
step "crc start (~10-15 min)"
if crc status -o json 2>/dev/null | jq -e '.openshiftStatus == "Running"' >/dev/null; then
  ok "cluster already running"
else
  crc start
fi

# ---------------------------------------------------------------- 6. login + registry route
step "Cluster access"
use_crc
ok "logged in as $(oc whoami) — $(oc version -o json | jq -r .openshiftVersion)"

oc patch configs.imageregistry.operator.openshift.io/cluster --type merge \
  -p '{"spec":{"defaultRoute":true}}' >/dev/null
wait_for "image registry route" 300 oc get route default-route -n openshift-image-registry
ok "registry: $(oc get route default-route -n openshift-image-registry -o jsonpath='{.spec.host}')"

cat <<EOF

${GRN}${B}CRC is up.${N}
  console:   https://console-openshift-console.apps-crc.testing   (crc console --credentials)
  next:      scripts/01-rhacs-install.sh
EOF
