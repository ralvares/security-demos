# Identity and Access Management (IAM)

This section covers the fundamental concepts of Identity and Access Management (IAM) within the context of Kubernetes and OpenShift: Authentication (Authn), Authorization (AuthZ), and Admission Control.

## Authentication (Authn)

**"Who is this?"**

Authentication is the process of verifying a user's or device's identity. It ensures that the entity requesting access is who they claim to be.

*   **Example**: A user providing a username and password, or a service account presenting a token to the API server.
*   *Note*: In this demo environment, we will primarily focus on how authenticated identities are managed and restricted.

## Authorization (AuthZ)

**"What are they allowed to do?"**

Authorization determines what a verified identity is allowed to do or access within the system. This step occurs only after successful authentication.

*   **RBAC**: Role-Based Access Control is the primary method for handling authorization in Kubernetes/OpenShift.
*   For a deep dive into RBAC, please refer to the [RBAC Session](./rbac/README.md).

## Admission Control

**"Does this request comply with policies?"**

Admission Control is an additional layer of policy enforcement that intercepts requests to the Kubernetes API server. It acts as a final gatekeeper after the request has been authenticated and authorized, but before the object is persisted to etcd.

Admission controllers can **validate** (accept/reject) or **mutate** (modify) requests.

### Default Admission Controls in OpenShift

OpenShift includes several default admission controllers to ensure cluster stability and security. Key examples include:

#### 1. Resource Quotas
Resource Quotas provide constraints that limit the aggregate resource consumption per Namespace. They can limit the quantity of objects (e.g., number of Pods, Services) or the total amount of compute resources (e.g., CPU, Memory) that can be requested in that namespace.

*   **Purpose**: Prevents a single team or project from consuming all available cluster resources.

#### 2. Limit Ranges
Limit Ranges enumerate constraints on the resource allocation (limits and requests) for individual resources (like Pods or Containers) within a Namespace.

*   **Purpose**: Enforces minimum and maximum CPU/Memory requests per pod, or ensures that users specify resource requests if they haven't done so (by applying defaults).

#### 3. Security Context Constraints (SCC)
While often discussed under security, SCCs are enforced via admission control. They control the privileges that a pod can request, such as running as a privileged container, using host networking, or accessing the host filesystem.
