In a standard **ResourceQuota**, the limits are local to a single project. However, in an enterprise, you often want to grant a "Total Budget" to an entire department (e.g., the Finance Team) that spans across multiple projects (Development, Staging, Production).

For this, we use the **ClusterResourceQuota**.

---

# Demo: Multi-Project Governance (ClusterResourceQuota)

In this demo, we will create a global budget that follows a specific **Label**. Any project that carries the label `department: finance` will draw from this shared pool of resources.

## 1. Create the Cluster-Wide Budget

Unlike a local quota, a `ClusterResourceQuota` is a cluster-scoped object. We will define a limit of **10 CPUs** and **20GB of RAM** for the entire department.

```bash
# Create the global budget tied to a label selector
cat <<EOF > finance-global-quota.json
{
  "apiVersion": "quota.openshift.io/v1",
  "kind": "ClusterResourceQuota",
  "metadata": {
    "name": "finance-department-quota"
  },
  "spec": {
    "selector": {
      "annotations": null,
      "labels": {
        "matchLabels": {
          "department": "finance"
        }
      }
    },
    "quota": {
      "hard": {
        "cpu": "10",
        "memory": "20Gi"
      }
    }
  }
}
EOF

# Apply the global quota
oc create -f finance-global-quota.json

```

---

## 2. Tag the Projects

Now, we create two separate projects and "tag" them as belonging to Finance.

```bash
# Create Finance Project A
oc new-project finance-app-prod
oc label namespace finance-app-prod department=finance

# Create Finance Project B
oc new-project finance-app-dev
oc label namespace finance-app-dev department=finance

```

---

## 3. Verify the Shared Consumption

The power of this resource is the **aggregated view**. You can see exactly how much the entire department is using across all their projects.

```bash
# View the aggregated usage
oc describe clusterresourcequota finance-department-quota

```

### What to look for:

* **Total Used**: The sum of resources across *both* `finance-app-prod` and `finance-app-dev`.
* **Project View**: A breakdown of how much each specific project is contributing to that total.

---

## 4. The "Common Pot" Scenario (Verification)

If `finance-app-prod` consumes **18Gi** of the **20Gi** budget, `finance-app-dev` will only have **2Gi** left, regardless of what its own local quotas might say.

```bash
# Try to scale an app in the DEV project that exceeds the REMAINING department budget
oc run stress-test --image=nginx --requests='memory=5Gi' -n finance-app-dev

```

### Expected Result:

The command will fail because the **Department** budget is exhausted, even if the **Project** itself looks empty.

---

## 5. Key Takeaways for the Audience

* **Departmental Accountability:** You can give a team $10,000 worth of "cloud credits" (CPU/RAM) and let them decide how to distribute it among their different environments.
* **Simplified Governance:** Instead of managing 100 individual quotas, you manage one `ClusterResourceQuota` per department.
* **Label-Based Automation:** By simply labeling a new namespace, it is instantly brought under the umbrella of the department's financial and resource guardrails.

---

## 6. Cleanup

```bash
oc delete clusterresourcequota finance-department-quota
oc delete project finance-app-prod finance-app-dev

```