# kubectl-netpol

A developer-centric `kubectl` plugin for generating Kubernetes `NetworkPolicy` resources.

## Modes

| Mode | Trigger | Use case |
|------|---------|----------|
| Command-Line Direct | All flags provided | Automation / CI |
| Interactive TUI | Ambiguous peer info | Discovery |
| Filesystem Mode | `-f <folder>` | GitOps offline analysis |

## Resource Reference Format

```
namespace/workload[/port/protocol]
```

`+` is the wildcard token — it is shell-safe and requires no quoting.

| Example | Behaviour |
|---------|-----------|
| `ns/app/+` | All ports — no TUI |
| `ns/app/80/tcp` | Port 80 TCP — no TUI |
| `ns/app` | Triggers TUI to pick ports |
| `ns/+` | Namespace-wide selector |

## Hygiene Templates

```bash
# Zero-trust baseline
kubectl netpol -n myapp --deny-all --allow-internal

# Only block ingress
kubectl netpol -n myapp --deny-ingress
```

## Traffic Allow Rules

```bash
# Allow frontend -> backend on port 8080
kubectl netpol --src=frontend/web/+ --dst=backend/api/8080/tcp

# Allow namespace-wide
kubectl netpol --src=frontend/+ --dst=backend/api/8080/tcp

# Offline (GitOps) mode
kubectl netpol -f ./manifests --src=frontend/web --dst=backend/api
```

## Building

```bash
make build
# binary: ./kubectl-netpol
```

## Installing as a kubectl plugin

```bash
make install
kubectl netpol --help
```

## Project Structure

```
.
├── main.go
├── cmd/root.go           # CLI wiring (cobra)
└── internal/
    ├── parser/           # Resource reference parser
    ├── labels/           # Label eraser (strips noisy labels)
    ├── provider/         # Provider interface, LiveProvider, FileProvider
    ├── generator/        # NetworkPolicy builders + YAML renderer
    └── tui/              # Bubble Tea interactive wizard
```
