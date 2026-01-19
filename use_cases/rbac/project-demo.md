# Demo: Hardening the OpenShift Project Factory

In this demo, we will automate the creation of a **Custom Project Template**. This ensures that every time a developer requests a new project, it is born with a **Resource Quota**, **LimitRange**, **Network Policy**, and **Security Labels** automatically injected.

## 1. Environment Setup (Cluster Admin)

To modify global governance, you must be logged in as a user with `cluster-admin` privileges.

```bash
# Verify your administrative access
oc auth can-i '*' '*' --all-namespaces

```

---

## 2. Generate the Security Components

We will generate our "ingredients" in JSON format so we can process them with `jq`.

### Step A: The Base Blueprint

Capture the default internal OpenShift project structure.

```bash
oc adm create-bootstrap-project-template -o json > template.json

```

### Step B: The Resource Quota (The Total Budget)

Create a quota to prevent "noisy neighbors" from consuming all cluster resources.

```bash
oc create quota project-quota --hard=cpu=4,memory=8Gi -o json --dry-run=client > quota.json

```

### Step C: The LimitRange (The Container Rules)

This ensures every container has a default size and stays within sane boundaries.

```bash
cat <<EOF > limits.json
{
  "kind": "LimitRange",
  "apiVersion": "v1",
  "metadata": {
    "name": "project-limits"
  },
  "spec": {
    "limits": [
      {
        "type": "Container",
        "default": {
          "cpu": "500m",
          "memory": "1Gi"
        },
        "defaultRequest": {
          "cpu": "200m",
          "memory": "512Mi"
        },
        "max": {
          "cpu": "2",
          "memory": "2Gi"
        }
      }
    ]
  }
}
EOF
```

### Step D: The Deny-All Ingress (The Firewall)

Note that OpenShift is "Allow-All" by default; this policy overrides that behavior.

```bash
cat <<EOF > deny-ingress.json
{
  "kind": "NetworkPolicy",
  "apiVersion": "networking.k8s.io/v1",
  "metadata": {
    "name": "default-deny-ingress"
  },
  "spec": {
    "podSelector": {},
    "policyTypes": ["Ingress"]
  }
}
EOF

```

---

## 3. The Automated Assembly (The `jq` Magic)

We will use `jq` to "glue" our custom security objects into the master template's `objects` array and **inject a custom security label** into the Namespace metadata.

```bash
# Merge Budget, Limits, and Firewall into the Blueprint
jq --slurpfile q quota.json \
   --slurpfile l limits.json \
   --slurpfile n deny-ingress.json \
   '.objects += ($q + $l + $n)' \
   template.json > final-custom-template.json

```

---

## 4. Activate Global Governance

Now we upload the blueprint and patch the cluster to enforce it.

```bash
# 1. Upload the template to the global configuration namespace
oc create -f final-custom-template.json -n openshift-config

# 2. Patch the cluster to use this blueprint for ALL new projects
oc patch project.config.openshift.io/cluster --type=merge \
  -p '{"spec":{"projectRequestTemplate":{"name":"project-template"}}}'

```

---

## 5. The Reveal: Verification

We now simulate a developer creating a project to observe the multi-layered governance in action.

```bash
# 1. Create a new team project
oc new-project secure-app-demo

# 2. Verify Metadata: Check for our custom security label
oc get namespace secure-app-demo --show-labels

# 3. Verify Ingress: This proves Zero-Trust is active Day 0
oc get networkpolicy -n secure-app-demo

# 4. Verify Admission Control: Check Quota and LimitRange
oc get quota,limitrange -n secure-app-demo

```

---

## 6. Key Takeaways for the Audience

* **Automation over Manual Effort:** Security and governance were **injected at birth** without manual intervention.
* **Granular Control:** We controlled the total budget (**Quota**), the individual container sizes (**LimitRange**), and the network entry points (**NetworkPolicy**).
* **Environment Consistency:** Every project on the cluster now adheres to the same baseline security posture, reducing the risk of human error during setup..

---

## 7. Cleanup (Resetting the Cluster)

```bash
# Remove the template pointer from the global configuration
oc patch project.config.openshift.io/cluster --type=json \
  -p '[{"op": "remove", "path": "/spec/projectRequestTemplate"}]'

# Delete the template from the config namespace
oc delete template project-template -n openshift-config

```