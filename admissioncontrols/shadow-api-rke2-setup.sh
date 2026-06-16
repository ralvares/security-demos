#!/usr/bin/env bash
# shadow-api-rke2-setup.sh
#
# Run ONCE before the demo. Creates:
#   - Lima VM with RKE2 (default profile)
#   - dev-space namespace
#   - dev-user with edit rights scoped to dev-space
#   - dev-user.config kubeconfig
#
# Usage: bash shadow-api-rke2-setup.sh

set -euo pipefail

echo "=== Step 1: Create Lima VM ==="
brew install lima 2>/dev/null || true
limactl start template://ubuntu --name=rke2-lab --tty=false 2>/dev/null || true

echo "=== Step 2: Install and start RKE2 (default profile) ==="
limactl shell rke2-lab -- bash -c '
set -euo pipefail

# Install RKE2
curl -sfL https://get.rke2.io | sudo sh -
sudo systemctl enable rke2-server.service
sudo systemctl start rke2-server.service

# Wait for API server
echo "Waiting for RKE2 API server..."
until sudo /var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml get nodes &>/dev/null; do
  sleep 5
done
echo "RKE2 is ready."

# Link kubectl, fix permissions
sudo ln -sf /var/lib/rancher/rke2/bin/kubectl /usr/local/bin/kubectl
sudo chmod 644 /etc/rancher/rke2/rke2.yaml
echo "export KUBECONFIG=/etc/rancher/rke2/rke2.yaml" >> ~/.bashrc
export KUBECONFIG=/etc/rancher/rke2/rke2.yaml

# --- Create namespace ---
kubectl create namespace dev-space

# --- Generate dev-user certs ---
mkdir -p ~/users && cd ~/users
openssl genrsa -out dev-user.key 2048
openssl req -new -key dev-user.key -out dev-user.csr -subj "/CN=dev-user"
sudo openssl x509 -req -in dev-user.csr \
  -CA /var/lib/rancher/rke2/server/tls/client-ca.crt \
  -CAkey /var/lib/rancher/rke2/server/tls/client-ca.key \
  -CAcreateserial -out dev-user.crt -days 365

# --- RBAC: edit role scoped to dev-space ---
kubectl create rolebinding dev-user-edit \
  --clusterrole=edit \
  --user=dev-user \
  --namespace=dev-space

# --- Build restricted kubeconfig ---
CLUSTER_CA=$(sudo cat /var/lib/rancher/rke2/server/tls/server-ca.crt | base64 -w 0)
USER_CERT=$(cat dev-user.crt | base64 -w 0)
USER_KEY=$(cat dev-user.key | base64 -w 0)

cat > dev-user.config <<KUBECONFIG
apiVersion: v1
kind: Config
clusters:
- cluster:
    certificate-authority-data: ${CLUSTER_CA}
    server: https://127.0.0.1:6443
  name: rke2-local
contexts:
- context:
    cluster: rke2-local
    namespace: dev-space
    user: dev-user
  name: dev-user-context
current-context: dev-user-context
users:
- name: dev-user
  user:
    client-certificate-data: ${USER_CERT}
    client-key-data: ${USER_KEY}
KUBECONFIG

echo ""
echo "============================================"
echo "  Setup complete. Kubeconfig: ~/users/dev-user.config"
echo "============================================"
'
