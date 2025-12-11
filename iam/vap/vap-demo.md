**VAP Demo – Step by step**

- **Goal:** Demonstrate how the VAP (Validating Admission Policies) created under `iam/vap/manifests/` enforce the same checks as the `compliance` CustomRules. Use example namespaces that describe real use-cases.

**Prerequisites:**
- A cluster with `kubectl` configured and `kustomize` available locally (or use `kubectl apply -k`).
- The VAP controller that supports `ValidatingAdmissionPolicy`/`ValidatingAdmissionPolicyBinding` is installed and the cluster admits these resources.

**Namespaces (example use-cases):**
- `platform-ops` — platform/system workloads (allowed wide privileges in approved list).
- `finance-app` — production-ish app namespace where registries and network policies must be enforced.
- `dev-team` — developer/test namespace, can be labeled to enforce policies for demos.

---

**1) Create example namespaces**

Apply these namespace manifests (or create them inline):

For the demo we create example Namespaces that relax the cluster PodSecurity admission
to `privileged` so tests that need `hostPath` or privileged containers can run.

The example manifests are in `iam/vap/examples/`. Apply them with:

```bash
kubectl apply -f iam/vap/examples/
```

Note: these `pod-security.kubernetes.io/*` labels increase risk and are for demo/test
only. Remove or set back to `restricted` after testing.

**2) Deploy the VAP manifests**

From the repo root run:

```bash
kubectl apply -k iam/vap/manifests/
```

This applies all `ValidatingAdmissionPolicy` and `ValidatingAdmissionPolicyBinding` resources created earlier.

**3) Test image registry enforcement (image-supply-chain)**

- Good: image from `quay.io`

```bash
cat <<EOF | kubectl -n finance-app apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: good-registry
spec:
  securityContext:
    runAsNonRoot: true
  containers:
  - name: httpd
    image: registry.redhat.io/ubi8/httpd-24
    securityContext:
      allowPrivilegeEscalation: false
      capabilities:
        drop: ["ALL"]
      runAsNonRoot: true
      seccompProfile:
        type: RuntimeDefault
EOF
```

Expected: Pod is created successfully.

- Bad: image from `docker.io` (should be denied)

```bash
cat <<EOF | kubectl -n finance-app apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: bad-registry
spec:
  securityContext:
    runAsNonRoot: true
  containers:
  - name: nginx
    image: nginx:latest
    securityContext:
      allowPrivilegeEscalation: false
      capabilities:
        drop: ["ALL"]
      runAsNonRoot: true
      seccompProfile:
        type: RuntimeDefault
EOF
```

Expected: Admission is denied with message about approved registries.

**4) Test disallowing shadow databases**

- Good: Deploy DB in `finance-app` (namespace labeled `custom.security/database=true`):

```bash
cat <<EOF | kubectl -n finance-app apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: allowed-db
spec:
  securityContext:
    runAsNonRoot: true
  containers:
  - name: postgres
    image: quay.io/hummingbird/postgresql:latest
    securityContext:
      allowPrivilegeEscalation: false
      capabilities:
        drop: ["ALL"]
      runAsNonRoot: true
      seccompProfile:
        type: RuntimeDefault
EOF
```

Expected: Allowed in `finance-app` because it's labeled for DBs.

- Bad: Deploy DB in `dev-team` (should be denied):

```bash
cat <<EOF | kubectl -n dev-team apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: shadow-db
spec:
  securityContext:
    runAsNonRoot: true
  containers:
  - name: postgres
    image: quay.io/hummingbird/postgresql:latest
    securityContext:
      allowPrivilegeEscalation: false
      capabilities:
        drop: ["ALL"]
      runAsNonRoot: true
      seccompProfile:
        type: RuntimeDefault
EOF
```

Expected: Denied with message about unapproved database images.

**5) Test NetworkPolicy — `block-risky-netpol` only**

We focus this demo on the `block-risky-netpol` policy which rejects NetworkPolicies that
effectively allow all traffic to all pods via either an empty rule (`{}`) or an ipBlock
of `0.0.0.0/0`.

Apply the network-policy manifests (includes `block-risky-netpol`) if you haven't:

```bash
kubectl apply -k iam/vap/manifests/network-policy/
```

Run the following test cases (expected results shown):

1) Empty rule (BLOCKED)

```bash
cat <<EOF | kubectl -n dev-team apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: fail-empty-rule
spec:
  podSelector: {}
  policyTypes: ["Ingress"]
  ingress:
  - {}
EOF
```

Expected: Denied by `block-risky-netpol` (Security Violation)

2) 0.0.0.0/0 CIDR (BLOCKED)

```bash
cat <<EOF | kubectl -n dev-team apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: fail-cidr-zero
spec:
  podSelector: {}
  policyTypes: ["Ingress"]
  ingress:
  - from:
    - ipBlock:
        cidr: 0.0.0.0/0
EOF
```

Expected: Denied by `block-risky-netpol` (Security Violation)

3) Valid deny-all (PASS)

```bash
cat <<EOF | kubectl -n dev-team apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: pass-deny-all
spec:
  podSelector: {}
  policyTypes: ["Ingress"]
  ingress: []
EOF
```

Expected: Created

4) Valid specific CIDR (PASS)

```bash
cat <<EOF | kubectl -n dev-team apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: pass-specific-cidr
spec:
  podSelector: {}
  policyTypes: ["Ingress"]
  ingress:
  - from:
    - ipBlock:
        cidr: 10.0.0.0/8
EOF
```

Expected: Created

**6) Test Pod security checks (privileged, hostPath, automount)**

- Privileged container test (should be denied in enforced namespaces):

```bash
cat <<EOF | kubectl -n dev-team apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: privileged-pod
spec:
  containers:
  - name: core-runtime
    image: quay.io/hummingbird/core-runtime
    securityContext:
      privileged: true
      allowPrivilegeEscalation: true
      capabilities:
        add: ["ALL"]
    command: ["sleep", "3600"]
EOF
```

Expected: Denied for privileged container.

- Sensitive hostPath (should be denied):

```bash
cat <<EOF | kubectl -n dev-team apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: hostpath-pod
spec:
  securityContext:
    runAsNonRoot: true
  containers:
  - name: core-runtime
    image: quay.io/hummingbird/core-runtime
    securityContext:
      allowPrivilegeEscalation: false
      capabilities:
        drop: ["ALL"]
      runAsNonRoot: true
      seccompProfile:
        type: RuntimeDefault
    command: ["sleep", "3600"]
  volumes:
  - name: host
    hostPath:
      path: /etc/kubernetes
      type: Directory
EOF
```

Expected: Denied for sensitive hostPath mount.

- Automount test:
  - In `platform-ops` (has `custom.security/automount=true`) the automount exemption should allow pods with automount enabled.
  - In `dev-team`, pods must set `automountServiceAccountToken: false` or be denied.

```bash
# Should be allowed in platform-ops
cat <<EOF | kubectl -n platform-ops apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: platform-pod
spec:
  securityContext:
    runAsNonRoot: true
  containers:
  - name: core-runtime
    image: quay.io/hummingbird/core-runtime
    securityContext:
      allowPrivilegeEscalation: false
      capabilities:
        drop: ["ALL"]
      runAsNonRoot: true
      seccompProfile:
        type: RuntimeDefault
    command: ["sleep","3600"]
EOF

# Should be denied in dev-team unless automount disabled
cat <<EOF | kubectl -n dev-team apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: dev-pod
spec:
  automountServiceAccountToken: true
  securityContext:
    runAsNonRoot: true
  containers:
  - name: core-runtime
    image: quay.io/hummingbird/core-runtime
    securityContext:
      allowPrivilegeEscalation: false
      capabilities:
        drop: ["ALL"]
      runAsNonRoot: true
      seccompProfile:
        type: RuntimeDefault
    command: ["sleep","3600"]
EOF
```

**7) Test RBAC cluster-admin allow-list**

Attempt to create a `ClusterRoleBinding` that grants `cluster-admin` to an unapproved user. Expect admission denial.

```bash
cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: bad-cluster-admin
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: User
  name: evil-user@example.com
EOF
```

Expected: Denied because subject not in allow-list.

**8) Useful queries to observe policy hits / denials**

- Inspect admission webhook/validation logs (depends on controller). If using the upstream VAP controller, check its logs.

- Using `kubectl` to see why a pod was denied will show the admission error returned at create time.

**9) Cleanup**

```bash
kubectl -k iam/vap/manifests/ -n default delete --ignore-not-found=true
kubectl delete namespace dev-team finance-app platform-ops --ignore-not-found=true
```

(If you applied only specific files, delete those specific resources instead.)

---

If you want, I can also:
- Add example Namespace YAML files into `iam/vap/examples/` and commit them.
- Add small scripts under `iam/vap/scripts/` to automate the apply/test/cleanup sequence.

Tell me which you'd like next and I'll update the TODOs and create the files.
