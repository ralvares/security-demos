# RHACS Automated Deployment (Kustomize)

This repository provides a zero-touch, Kustomize-based deployment for **Red Hat Advanced Cluster Security (RHACS)** on OpenShift.

It automates the installation of the Operator and Central services, and establishes trust using the **Cluster Registration Secret (CRS)** method—eliminating the need for manual "init-bundle" downloads.

## 📂 Project Structure

```text
.
├── deploy.sh                  # Main deployment orchestrator script
├── operator/                  # Operator installation (Namespace, Sub, OG)
└── service/                   # RHACS Instance & CRS Automation
    ├── central.yaml           # Central Service Custom Resource
    ├── securedcluster.yaml    # Secured Cluster Custom Resource
    ├── create-cluster-crs-sa.yaml  # RBAC for automation Job
    └── create-cluster-crs-job.yaml # Automation Job for CRS generation

```

---

## Installation

To deploy the entire stack, including the Operator, Central, and the automated CRS generation, simply run the deployment script:

```bash
chmod +x deploy.sh
./deploy.sh

```

### What the script does:

1. **Operator Deployment:** Applies the Kustomize manifests for the RHACS Operator.
2. **Health Check:** Waits for the `ClusterServiceVersion` (CSV) to reach the **Succeeded** phase.
3. **API Verification:** Ensures the `centrals` and `securedclusters` CRDs are established.
4. **Service Deployment:** Applies the Central and SecuredCluster resources.
5. **Automation Monitoring:** Automatically streams the logs from the `create-cluster-init-bundle` Job.
6. **Credential Output:** Once complete, it prints the Central URL and the `admin` password.

---

## 🔍 Manual Verification

If you need to verify components individually:

**1. Check Operator Pods:**

```bash
oc get pods -n rhacs-operator

```

**2. Check Central Status:**

```bash
oc get central -n stackrox

```

**3. Check Secured Cluster Status:**

```bash
oc get securedcluster stackrox-secured-cluster-services -n stackrox

```