This guide demonstrates how to verify and test **Resource Quotas** in OpenShift. While a LimitRange controls individual containers, a **ResourceQuota** acts as the "Total Budget" for the entire project, preventing one team from consuming all the physical resources of the cluster.

---

# Demo: Verifying the Project Budget (Resource Quotas)

In this demo, we will simulate a "Resource Exhaustion" scenario. We will attempt to deploy multiple applications until we hit the project's hard ceiling (4 CPUs / 8Gi RAM), proving that OpenShift will block any requests that exceed the allocated budget.

## 1. Verify the Active Budget

Before we start, let's check the current consumption of our project.

```bash
# Check the quota status in your project
oc get quota project-quota -n secure-app-demo

```

**What to look for:**

* **`Used`**: How much the team is currently consuming.
* **`Hard`**: The maximum allowed (4 CPUs and 8Gi RAM).

---

## 2. Trigger the "Noisy Neighbor" Scenario

We will use a deployment to quickly scale up our resource usage. We will create a deployment where each pod is forced to use a specific amount of memory.

```bash
# Create a deployment with 3 replicas, each requesting 2Gi of RAM
# Total request: 6Gi (This fits within our 8Gi budget)
oc create deployment heavy-app --image=nginx -n secure-app-demo
oc set resources deployment heavy-app --requests='memory=2Gi,cpu=1' -n secure-app-demo
oc scale deployment heavy-app --replicas=3 -n secure-app-demo

```

---

## 3. The "Budget Breach" Attempt

Now, we will try to scale the deployment to 5 replicas.

* Total requested memory: **10Gi** (5 pods x 2Gi).
* Our Project Limit: **8Gi**.

```bash
# Attempt to scale beyond the project budget
oc scale deployment heavy-app --replicas=5 -n secure-app-demo

```

---

## 4. The Reveal: Inspecting the Admission Failure

OpenShift will accept the scale command, but the **ResourceQuota Admission Controller** will prevent the additional pods from actually being created.

```bash
# Check the Deployment status
oc describe deployment heavy-app -n secure-app-demo

```

### Expected Result:

You will see a "FailedCreate" warning in the events:

> `Error creating: pods "heavy-app-..." is forbidden: exceeded quota: project-quota, requested: memory=2Gi, used: memory=6Gi, limited: memory=8Gi`

---

## 5. Key Takeaways for the Audience

* **Financial/Operational Safety:** Quotas ensure that a "leaky" app or a runaway script in one project cannot impact the stability of other teams' projects.
* **Deterministic Behavior:** The cluster remains stable because it refuses to "overcommit" physical resources beyond what was promised to the project.
* **Self-Service with Guardrails:** Developers have the freedom to scale their apps, but only within the boundaries of their pre-approved "Resource Budget."

---

## 6. Cleanup

```bash
# Delete the deployment to free up the quota
oc delete deployment heavy-app -n secure-app-demo

```

Would you like me to show you how to create a **ClusterResourceQuota**, which allows you to set a single budget that is shared across multiple projects (e.g., all projects belonging to the "Finance" team)?