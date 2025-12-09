# kubectl-timemachine Instructions

`kubectl-timemachine` is a Python-based forensic tool that allows you to reconstruct the state of a Kubernetes cluster at any specific point in time using the Kubernetes Audit Logs. It mimics the `kubectl get` command but queries historical data from an `audit.log` file instead of a live API server.

## Prerequisites

Ensure you have Python 3 installed along with the required dependencies:

```bash
pip install duckdb pyyaml
```

## Usage

The basic syntax is similar to `kubectl`:

```bash
./kubectl-timemachine get <resource> [name] [flags]
```

### Common Flags

- `--auditlog-file <path>`: Path to the audit log file (default: `audit.log`).
- `--time <timestamp>`: The point in time to view the cluster state (ISO8601 format, e.g., `2025-12-08T12:00:00Z`). If omitted, it shows the latest state found in the logs.
- `-n, --namespace <ns>`: Filter by a specific namespace.
- `-A, --all-namespaces`: List resources across all namespaces.
- `-o, --output <format>`: Output format. Supported values: `table` (default), `yaml`, `json`.

## Examples

### 1. List all pods in the default namespace (latest state in logs)
```bash
./kubectl-timemachine get pods
```

### 2. List pods in all namespaces
```bash
./kubectl-timemachine get pods -A
```

### 3. Time Travel: See the state of deployments at a specific time
View what deployments existed yesterday at noon:
```bash
./kubectl-timemachine get deployments -A --time "2025-12-08T12:00:00Z"
```

### 4. Recover a deleted resource manifest
If a ConfigMap was deleted, you can retrieve its last known state and output it as YAML:
```bash
./kubectl-timemachine get cm my-config -n my-app -o yaml > recovered-config.yaml
```

### 5. Specify a custom audit log file
```bash
./kubectl-timemachine get nodes --auditlog-file /path/to/custom-audit.log
```

### 6. Get All Resources
Retrieve a comprehensive overview of the cluster state (similar to `kubectl get all`):
```bash
./kubectl-timemachine get all -A
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

**Virtualization:**
- `virtualmachines` (vm)
- `virtualmachineinstances` (vmi)

**Special:**
- `all` (aggregates common resources)
