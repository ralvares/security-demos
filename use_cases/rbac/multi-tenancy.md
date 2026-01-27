# Multi-tenancy on OpenShift: Projects vs. Namespaces

In an enterprise environment, a single cluster often hosts hundreds of applications across dozens of departments. **Multi-tenancy** is the strategy of allowing these "tenants" to share the same infrastructure safely. In OpenShift, the **Project** is the primary mechanism for enforcing this isolation.

However, true multi-tenancy requires looking beyond just the software layer. When hosting diverse applications, we must consider **Data Classification**. Running a highly sensitive "Restricted" application on the same worker node (and the same Kernel) as a "Public" application introduces a risk of "container breakout" attacks. To mitigate this, enterprise designs often use **Node Selectors** and **Taints/Tolerations** to create dedicated pools of hardware based on the application's sensitivity, ensuring that different classifications never share the same physical memory or CPU cycles.

## 1. Project vs. Namespace: What’s the difference?

If you are coming from standard Kubernetes, you are familiar with **Namespaces**. In OpenShift, a **Project** is essentially a "Namespace on steroids." It is a wrapper that adds enterprise-grade governance to the basic logical partition.

| Feature | Kubernetes Namespace | OpenShift Project |
| --- | --- | --- |
| **Core Object** | A simple logical partition for resources. | A Kubernetes Namespace **plus** administrative metadata. |
| **RBAC** | Requires manual setup of RoleBindings. | Automatically assigns the requester as the `admin` of that project. |
| **Security** | Minimal default isolation; relies on manual config. | Enforces **Security Context Constraints (SCCs)** and isolation immediately. |
| **Governance** | No built-in self-service workflow. | Includes a formal `ProjectRequest` provisioning workflow. |
| **Automation** | Standard, empty creation. | Can be pre-populated via **Project Templates** (Quotas, Policies). |

---

## 2. Multi-tenant Isolation: The "Boundary of Trust"

Multi-tenancy requires more than just a separate "folder" for your resources; it requires a hardened boundary that prevents cross-tenant interference.

### Administrative Isolation & Separation of Duties

OpenShift uses the Project boundary to scope RBAC and enforce a strict **Separation of Duties (SoD)**. This ensures that responsibilities are divided among different individuals to prevent fraud and error:

* **Project Admin vs. Cluster Admin:** A Project Admin can manage their own team's deployments, services, and secrets but has no permission to modify cluster-wide configurations, storage classes, or nodes.
* **Developer vs. Operator:** By using specific Roles (e.g., `edit` vs. `view`), you can ensure that developers can write code but cannot modify the underlying Project quotas or network policies.
* **Visibility:** A user with `admin` rights in the `frontend` project has zero visibility into the `payments` project. Even accidental actions are physically constrained to the user's specific project.

### Network Isolation (The "Deny-All" Standard)

A critical part of "Proper RBAC" is ensuring that network traffic is as restricted as user permissions. It is vital to understand that **by default, OpenShift (like standard Kubernetes) allows all traffic** between pods across different projects. To achieve a **Zero Trust** model, we must use the Project Template to enforce guardrails:

* **Default Deny Ingress:** By including this in a template, you ensure that every new project starts by blocking all incoming traffic from sources outside the project. Communication is only possible if a developer explicitly defines a "hole" for a specific service.
* **Default Deny Egress:** This ensures pods cannot make outgoing calls to other projects or the external internet unless specifically authorized.
* **Why this matters:** If a hacker gains access to a pod in the `frontend` project, they naturally want to move laterally. Without these guardrails, the network is wide open. With them, the hacker is "trapped" in the frontend project, unable to "hop" across the network to attack the `payments` database.

---

## 3. Resource Governance: Quotas and Limits

In a shared cluster, "Resource Exhaustion" is a major threat. A single leaky application could consume all the cluster's memory, causing a denial of service for every other team. OpenShift manages this via the Project.

### Resource Quotas (The Project Budget)

A **ResourceQuota** provides a hard ceiling on the total resource consumption for the entire Project.

* **CPU/Memory:** Limits the aggregate sum of all container requests/limits.
* **Object Counts:** Limits the number of ConfigMaps, Secrets, or Services a team can create.

### Limit Ranges (The Container Rules)

While Quotas govern the whole project, **LimitRanges** govern individual pods. They ensure that every container stays within a "sane" size range.

* **Defaults:** If a developer forgets to define memory limits, OpenShift automatically injects the default values defined in the LimitRange.
* **Enforcement:** Prevents a developer from deploying a single pod that is so large it consumes the entire Project's quota.

Would you like me to expand on the technical implementation of **Taints and Tolerations** to show exactly how to isolate those node pools for different data classifications?