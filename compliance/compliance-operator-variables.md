# Using `Variables` to Simplify CEL Expressions

This guide demonstrates how to use `Variable` CRs to separate compliance data from compliance expressions, making `CustomRules` more maintainable and easier to customize.

## The Problem

When writing `CustomRules` with CEL expressions, you might need to check
specific values that change across deployments or environments. One good
example of this would be allow-lists or deny-lists. Hardcoding these lists
directly in the CEL expression makes them difficult to maintain:

```yaml
expression: |-
  resource.subjects.all(subject,
    subject.name in [
      'user1',
      'user2',
      'user3'
    ]
  )
```

Potential issues when using this approach:
- Updating the list requires modifying the `CustomRule` expression
- No separation between the compliance logic and the data being checked
- Difficult for organizations to customize without understanding CEL syntax
- Changes require re-validating the entire `CustomRule`

## Separating Data from Expressions

The Compliance Operator already has a `Variable` custom resource, which users
have leveraged in the past to tweak the behavior of SCAP/OVAL rules. The same
concept applies with `CustomRule` objects, where we need to separate the data
from the logic.

### Step 1: Create `Variable` CRs

Create separate `Variable` resources for each list of values you need to check.
In this example, the `Variable` value will be a comma-delimited list. Because
we're using a CRD inside the CEL expression, we need to keep the following in
mind:

- `Variable` `metadata.name` must follow Kubernetes RFC 1123 naming (lowercase alphanumeric, hyphens, and dots only)
- `Variable` `id` is used in CEL expressions and must be a valid CEL identifier (alphanumeric only, no hyphens)

**Example Variable:**
```yaml
apiVersion: compliance.openshift.io/v1alpha1
kind: Variable
metadata:
  name: cluster-admin-users-var
  namespace: openshift-compliance
id: cluster-admin-users-var
title: Allowed users for cluster-admin role
description: |-
  Comma-delimited list of user names that are permitted to be
  bound to the cluster-admin ClusterRoleBinding. Organizations should
  customize this list according to their security policies.
  Format: ,user1,user2,user3, (comma at start and end for exact matching)
type: string
value: ',kubeadmin,system:admin,alice@my-company.com,'
```

Notice that the value is prefixed and postfixed with commas, which allows us to
do exact matching in the expression.

### Step 2: Add `Variables` as Inputs to Your `CustomRule`

The `CustomRule` already accepts Kubernetes inputs via the
`kubernetesInputSpec`. We can use that here since a `Variable` is just a custom
resource:

```yaml
apiVersion: compliance.openshift.io/v1alpha1
kind: CustomRule
metadata:
  name: my-custom-rule
  namespace: openshift-compliance
spec:
  inputs:
    - kubernetesInputSpec:
        apiVersion: rbac.authorization.k8s.io/v1
        resource: clusterrolebindings
      name: crbs
    - kubernetesInputSpec:
        apiVersion: compliance.openshift.io/v1alpha1
        resource: variables
        resourceName: cluster-admin-users-var
        resourceNamespace: openshift-compliance
      name: allowedusers
    - kubernetesInputSpec:
        apiVersion: compliance.openshift.io/v1alpha1
        resource: variables
        resourceName: cluster-admin-groups-var
        resourceNamespace: openshift-compliance
      name: allowedgroups
```

Make sure you're looking for `Variable` instances in the `openshift-compliance`
namespace, since they're owned by the Compliance Operator.

### Step 3: Reference `Variables` in Your CEL Expression

Access the `Variable` value using `.value` and use `.contains()` for checking membership:

```yaml
expression: |-
  crbs.items.filter(crb, crb.metadata.name == 'cluster-admin')[0]
    .subjects.all(subject,
      (subject.kind == 'User' && allowedusers.value.contains(',' + subject.name + ',')) ||
      (subject.kind == 'Group' && allowedgroups.value.contains(',' + subject.name + ','))
    )
```

Make sure you're referencing the variable in the expression using the `name`
from the `kubernetesInputSpec`. You can access the value directly in the
expression using `allowedusers.value`. Using the CEL `contains()` filter with
comma wrapping provides exact matching (e.g., `admin` won't match `kubeadmin`).

### Step 4: Add `Variables` to Your Kustomization (Optional)

This gist includes a Kustomization, making it easier to apply the custom rules,
variables, tailored profiles, and bindings with a single command.

```yaml
resources:
  - cluster-admin-allowed-users-variable.yaml
  - cluster-admin-allowed-groups-variable.yaml
  - cluster-admin-allowed-serviceaccounts-variable.yaml
  - cluster-admin-allow-list.yaml
  - tailored-profile.yaml
  - scan-setting-binding.yaml
```

Apply the example in a cluster with Compliance Operator version 1.8.0 or greater:

```console
oc apply -k .
```

See the `cluster-admin-allow-list.yaml` `CustomRule` in this gist for a
complete working example that uses three `Variables`:

- `allowedusers` - allowed users
- `allowedgroups` - allowed groups
- `allowedserviceaccounts` - allowed service accounts (in `namespace/name` format)

# Summary

This example walks through how you can use the `Variable` resource in
conjunction with the new `CustomRule` resource introduced in Compliance
Operator 1.8.0 to keep compliance data and logic separate.

The primary benefits include:

1. Separation of concerns by keeping the compliance logic in the `CustomRule` and data in the `Variable`
2. Organizations can update allow-lists by editing `Variables`, not CEL expressions
3. Changing values doesn't risk introducing syntax errors in the CEL expression
4. `Variables` can potentially be referenced by multiple `CustomRules`
5. `Variable` descriptions explain what values are allowed and how to format them

## Best Practices

1. Use descriptive `Variable` names it clear what the `Variable` contains
2. Document the format and type of the variable (e.g., string) in the description of the `Variable`
3. Test your expressions by updating the `Variable` to ensure they pass and fail with various inputs
4. Keep `Variables` focused to one distinct list of values
5. Keep `Variables` in the same namespace as the `CustomRule`
6. Use functions and macros defined by the [CEL language definition](https://github.com/google/cel-spec/blob/master/doc/langdef.md)

## Common Patterns

### Allow-list Pattern
Check if a value is in an approved list:
```cel
allowedvalues.value.contains(',' + actual.value + ',')
```

### Deny-list Pattern
Check if a value is NOT in a prohibited list:
```cel
!deniedvalues.value.contains(',' + actual.value + ',')
```

### Multiple Conditions
Combine multiple `Variable` checks:
```cel
allowedusers.value.contains(',' + user.name + ',') &&
!deniedgroups.value.contains(',' + user.group + ',')
```

## Updating `Variables`

To update an allow-list, simply edit the `Variable`:

```bash
kubectl edit variable cluster-admin-users-var -n openshift-compliance
```

Change the value maintaining the comma-delimited format:
```yaml
value: ',kubeadmin,system:admin,alice@my-company.com,bob@my-company.com,'
```

The next compliance scan will automatically use the updated values without
requiring any changes to the `CustomRule`.