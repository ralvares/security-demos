This guide demonstrates how to verify and test **LimitRanges** in OpenShift. A LimitRange is a "Day 0" guardrail that ensures every container has a resource request/limit, even if the developer forgets to define one.

---

# Demo: Verifying Resource Guardrails (LimitRanges)

In this demo, we will prove that our **Project Factory** successfully enforces container sizes by deploying a "naked" pod (one without any resource definitions) and watching OpenShift automatically intervene.

## 1. Verify the Governance is Active

First, ensure that the `LimitRange` we injected via our custom template is actually present in the project.

```bash
# Check the rules in your project
oc get limitrange project-limits -n secure-app-demo -o yaml

```

**What to look for:**

* **`defaultRequest`**: The "floor" (what the pod is guaranteed). We set this to **200m CPU** and **512Mi RAM**.
* **`default`**: The "ceiling" (the limit). We set this to **500m CPU** and **1Gi RAM**.

---

## 2. Deploy a "Naked" Pod

We will now deploy a standard Nginx pod. Notice that we are **not** specifying any CPU or Memory requests in the command.

```bash
# Deploy a simple pod without resource definitions
oc run naked-pod --image=nginx -n secure-app-demo

```

---

## 3. The Reveal: Inspect the Auto-Injection

Because the `LimitRange` is active, the OpenShift Admission Controller intercepted the creation of this pod and "patched" it with our corporate defaults before it was allowed to run.

```bash
# Inspect the pod's resources
oc get pod naked-pod -n secure-app-demo -o jsonpath='{.spec.containers[0].resources}' | jq

```

### Expected Output:

```json
{
  "limits": {
    "cpu": "500m",
    "memory": "1Gi"
  },
  "requests": {
    "cpu": "200m",
    "memory": "512Mi"
  }
}

```

---

## 4. Testing the "Hard Ceiling" (The Max Limit)

Our blueprint also defined a **Max Limit** (2 CPUs and 2Gi RAM). Let's see what happens if a developer tries to create a "Mega-Pod" that exceeds this.

```bash
# Attempt to create a pod that is too large (3 CPUs)
oc run greedy-pod --image=nginx --requests='cpu=3' -n secure-app-demo

```

### Expected Result:

The command will fail with an error similar to this:

> `Error from server (Forbidden): pods "greedy-pod" is forbidden: maximum cpu usage per Container is 2, but request is 3.`

---

## 5. Key Takeaways for the Audience

* **Invisible Protection:** The developer doesn't need to know the rules; the cluster enforces them silently.
* **Standardization:** Every pod in the project now has a predictable footprint, making capacity planning much easier.
* **Prevention:** We have effectively prevented a single developer from accidentally (or intentionally) consuming more resources than their project is allowed.

---

## 6. Cleanup

```bash
oc delete pod naked-pod -n secure-app-demo

```