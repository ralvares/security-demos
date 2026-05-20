# Shadow API Takeover on RKE2

A developer with nothing more than `edit` rights in a single namespace escalates to **full cluster admin** — because RKE2 ships with Pod Security Admission set to `privileged` by default.

This is not a theoretical risk. Every step uses standard Kubernetes primitives. No CVE. No zero-day. Just a default that trusts too much.

---

## The Story

### The Setup

An RKE2 cluster runs with the **default profile**. A developer — `dev-user` — has been granted `edit` permissions scoped to `dev-space`. They can create pods, services, and configmaps in their namespace. Nothing else. RBAC is configured correctly. From an access-control perspective, everything looks right.

But there is a gap hiding in plain sight.

### Act 1 — The Box Is Small

`dev-user` proves the walls are real. They can spin up pods in `dev-space`, but every attempt to peek outside — listing nodes, reading secrets from other namespaces, touching `kube-system` — is met with `Forbidden`. RBAC works. The box is tight.

### Act 2 — The Gap

Here is where things go wrong. The namespace has **no Pod Security Admission labels**, and the global PSA policy is `privileged`. That means `dev-user` can deploy a pod that:

- Runs as **privileged**
- Mounts the **entire host filesystem**

A simple canary pod with `hostPath: /` is submitted. PSA does not blink. The pod lands, and suddenly `dev-user` can read the node's filesystem — including RKE2's TLS certificates, etcd credentials, and static pod manifests. All from inside their "restricted" namespace.

### Act 3 — Reconnaissance

With host filesystem access, the attacker does not need to guess. They read the real `kube-apiserver` static pod manifest to extract the exact container image, the node's hostname and IP, and the service CIDR. Everything needed to build a convincing replica of the API server.

### Act 4 — The Shadow API

Now comes the payload. `dev-user` deploys a **rogue kube-apiserver** inside `dev-space`. This shadow API server:

- Connects to the **real etcd** using the host-mounted TLS certs
- Sets `--authorization-mode=AlwaysAllow` — no RBAC
- Injects a backdoor token file granting `system:masters`
- Listens on port `16443` with `hostNetwork: true`

It is a fully functional Kubernetes API server — reading from and writing to the same etcd as the legitimate one — but with no authorization checks.

### Act 5 — Takeover

A client pod queries the shadow API using the backdoor token. Instantly:

- **Nodes** are visible (forbidden 30 seconds ago)
- **Every secret in every namespace** is readable
- A persistent `cluster-admin` ClusterRoleBinding is created for `dev-user`

The binding is written directly to etcd through the shadow API. Even if the shadow pods are deleted, the binding persists. `dev-user` is now cluster-admin on the **real** API server.

**Game over.**

---

## Why This Works

The entire attack chain depends on one thing: the ability to run a privileged pod with host mounts. RKE2's default profile allows this because global PSA is set to `privileged`.

| | Default Profile | CIS Profile |
|---|---|---|
| PSA Level | `privileged` | `restricted` |
| Privileged Pods | Allowed | Blocked |
| Host Mounts | Allowed | Blocked |
| Shadow API Attack | **Works** | **Blocked** |

If PSA enforced `restricted` or `baseline`, the canary pod in Act 2 would be rejected. No host mount means no cert theft. No certs means no shadow API. The entire chain collapses at step one.

---

## Running the Demo

Two scripts automate everything — setup and exploit.

### Prerequisites

- macOS with [Lima](https://lima-vm.io/) installed
- Internet access (downloads RKE2 and container images)

### Step 1 — Provision the Lab

Run from your Mac terminal:

```bash
bash shadow-api-rke2-setup.sh
```

This creates a Lima VM running RKE2 with the default profile, a `dev-space` namespace, and a `dev-user` kubeconfig scoped to that namespace.

### Step 2 — Run the Exploit

Copy the exploit script into the VM and execute it:

```bash
limactl copy shadow-api-rke2-exploit.sh rke2-lab:~/users/
limactl shell rke2-lab -- bash ~/users/shadow-api-rke2-exploit.sh
```

The script walks through all 5 acts interactively, with `[OK]`/`[FAIL]` status checks and pauses between each act.

### Cleanup

```bash
limactl stop rke2-lab && limactl delete rke2-lab
```

---

## The Fix

One line in `/etc/rancher/rke2/config.yaml`:

```yaml
profile: "cis"
```

Restart RKE2. The CIS profile enforces `restricted` PSA globally. The privileged canary pod from Act 2 is immediately rejected — and without it, the entire attack chain is dead.

> Older RKE2 versions may require `cis-1.23` or `cis-1.6`. Check with `rke2 --version`.

---

## Key Takeaway

RBAC is necessary but not sufficient. Without Pod Security Admission enforcement, a namespace-scoped user can escape their boundary through the node's filesystem and compromise the entire cluster. The default RKE2 profile leaves this door wide open. The CIS profile closes it.
