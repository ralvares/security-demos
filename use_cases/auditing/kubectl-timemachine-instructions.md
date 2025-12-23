# kubectl-timemachine Instructions

`kubectl-timemachine` is a Python-based forensic tool that allows you to reconstruct the state of a Kubernetes cluster at any specific point in time using the Kubernetes Audit Logs. It mimics the `kubectl get` command but queries historical data from an `audit.log` file instead of a live API server.

## Prerequisites

Ensure you have Python 3 installed along with the required dependencies:

```bash
pip install duckdb pyyaml
```

## Installation as a kubectl Plugin

You can use this tool as a native `kubectl` plugin.

1. Rename the script to `kubectl-timemachine`.
2. Make it executable: `chmod +x kubectl-timemachine`.
3. Move it to a directory in your `$PATH` (e.g., `/usr/local/bin`).

Once installed, you can invoke it directly via `kubectl`:

```bash
oc timemachine --auditlog-file=logs/timemachine-demo-audit.log get deployment -n payments-v2 --show-labels
```

## Usage

The basic syntax is similar to `kubectl`:

```bash
oc timemachine get <resource> [name] [flags]
```

### Common Flags

- `--auditlog-file <path>`: Path to the audit log file (default: `audit.log`).
- `--time <timestamp>`: Snapshot time (e.g., `2025-12-08T16:00:00`). Automatically detects local timezone and converts to UTC.
- `-n, --namespace <ns>`: Filter by a specific namespace.
- `-A, --all-namespaces`: List resources across all namespaces.
- `-o, --output <format>`: Output format. Supported values: `table` (default), `yaml`, `json`, `wide`.
- `-l, --selector <selector>`: Filter by label selector (e.g., `app=visa,tier=backend`).
- `--show-labels`: Show all labels as the last column in the output.
- `--history`: Trace the full lineage of a resource (e.g., Pod -> ReplicaSet -> Deployment) and show a merged event history.

## Examples

### 1. List all pods in the default namespace (latest state in logs)
```bash
oc timemachine --auditlog-file=logs/timemachine-demo-audit.log get pods
```

### 2. List pods in all namespaces
```bash
oc timemachine --auditlog-file=logs/timemachine-demo-audit.log get pods -A
```

### 3. Time Travel: See the state of deployments at a specific time
View what deployments existed yesterday at 4:00 PM (Local Time). The tool automatically detects your timezone and converts it to UTC.

```bash
oc timemachine --auditlog-file=logs/timemachine-demo-audit.log get deployments -A --time "2025-12-08T16:00:00"
```

*Output:*
`--- 🕒 Snapshot: 2025-12-08 16:00:00 (Local) → 2025-12-08 12:00:00Z (UTC) ---`

### 4. Recover a deleted resource manifest
If a ConfigMap was deleted, you can retrieve its last known state and output it as YAML:
```bash
oc timemachine --auditlog-file=logs/timemachine-demo-audit.log get cm my-config -n my-app -o yaml > recovered-config.yaml
```

### 5. Specify a custom audit log file
```bash
oc timemachine --auditlog-file=logs/timemachine-demo-audit.log get nodes
```

### 6. Get All Resources
Retrieve a comprehensive overview of the cluster state (similar to `kubectl get all`):
```bash
oc timemachine --auditlog-file=logs/timemachine-demo-audit.log get all -A
```

### 7. Advanced Filtering and Output
List pods with extra details (IP, Node) matching a specific label:
```bash
oc timemachine --auditlog-file=logs/timemachine-demo-audit.log get pods -n payments -l app=visa -o wide
```

### 8. Show Labels
Display labels alongside resource information:
```bash
oc timemachine --auditlog-file=logs/timemachine-demo-audit.log get pods --show-labels
```

### 9. Trace Resource History & Lineage
Recursively trace the ownership of a resource (e.g., Pod -> ReplicaSet -> Deployment) and view a merged timeline of all events. This is useful for understanding the lifecycle of a workload.

```bash
oc timemachine --auditlog-file=logs/timemachine-demo-audit.log get pods -n payments-v2 visa-processor --history
```

*Output:*
```text
--- 🔍 Analyzing Lineage (this may take a moment) ---

--- HISTORY & LINEAGE: pods/visa-processor ---
TIMESTAMP                    VERB      OBJECT                                         USER                            STATUS      
2025-12-09T12:57:37.324537Z  CREATE    pods/visa-processor                            sa:visa-processor               Created     
2025-12-09T12:57:46.770676Z  CREATE    pods/visa-processor/exec                       sa:visa-processor               Exec        
2025-12-09T12:57:46.770676Z  CREATE    pods/visa-processor/exec                       sa:visa-processor               Exec        
```

## Supported Resources

The tool currently supports the following resources (and their short aliases):

**Core:**
- `pods` (po)
- `services` (svc)
- `configmaps` (cm)
- `serviceaccounts` (sa)
- `namespaces` (ns)
- `nodes` (no)
- `secrets` (se)
- `persistentvolumes` (pv)
- `persistentvolumeclaims` (pvc)
- `clusterrolebindings` (crb)

**Workloads:**
- `deployments` (deploy)
- `daemonsets` (ds)
- `statefulsets` (sts)
- `replicasets` (rs)
- `jobs`
- `cronjobs` (cj)

**Network:**
- `ingresses` (ing)
- `routes` (rt)
- `networkpolicies` (netpol)

**Virtualization:**
- `virtualmachines` (vm)
- `virtualmachineinstances` (vmi)

**Special:**
- `all` (aggregates common resources)
