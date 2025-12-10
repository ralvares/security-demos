➜  ~ duckdb -c "
SELECT
  json_extract_string(objectRef, '$.name') AS Namespace,
  requestReceivedTimestamp AS CreationTime,
  json_extract_string(responseObject, '$.status.phase') AS Status
FROM read_json_auto('audit.log', ignore_errors=true) 
WHERE json_extract_string(objectRef, '$.resource') = 'namespaces'
  AND verb = 'create'
ORDER BY CreationTime;
"
┌───────────┬─────────────────────────────┬─────────┐
│ Namespace │        CreationTime         │ Status  │
│  varchar  │           varchar           │ varchar │
├───────────┼─────────────────────────────┼─────────┤
│ backend   │ 2025-12-10T06:29:45.805882Z │ Active  │
│ frontend  │ 2025-12-10T06:29:46.148817Z │ Active  │
│ payments  │ 2025-12-10T06:29:46.493026Z │ Active  │
└───────────┴─────────────────────────────┴─────────┘
➜  ~ 


➜  ~ duckdb -c "
SELECT
  requestReceivedTimestamp AS Time,
  json_extract_string(objectRef, '$.resource') AS Kind,
  json_extract_string(objectRef, '$.name') AS Name,
  json_extract_string(user, '$.username') AS User,
  json_extract_string(responseStatus, '$.code') AS Code
FROM read_json_auto('audit.log', ignore_errors=true)
WHERE json_extract_string(objectRef, '$.namespace') = 'payments'
  AND verb = 'create'
ORDER BY Time;
"
┌──────────────────────┬──────────────────────┬────────────────────────────────────────────────┬────────────────────────────────────────────────────────────────────────────────────────┬─────────┐
│         Time         │         Kind         │                      Name                      │                                          User                                          │  Code   │
│       varchar        │       varchar        │                    varchar                     │                                        varchar                                         │ varchar │
├──────────────────────┼──────────────────────┼────────────────────────────────────────────────┼────────────────────────────────────────────────────────────────────────────────────────┼─────────┤
│ 2025-12-10T06:29:4…  │ configmaps           │ kube-root-ca.crt                               │ system:serviceaccount:kube-system:root-ca-cert-publisher                               │ 201     │
│ 2025-12-10T06:29:4…  │ serviceaccounts      │ default                                        │ system:serviceaccount:kube-system:service-account-controller                           │ 201     │
│ 2025-12-10T06:29:4…  │ configmaps           │ openshift-service-ca.crt                       │ system:serviceaccount:kube-system:service-ca-cert-publisher                            │ 201     │
│ 2025-12-10T06:29:4…  │ rolebindings         │ system:deployers                               │ system:serviceaccount:openshift-infra:default-rolebindings-controller                  │ 201     │
│ 2025-12-10T06:29:4…  │ rolebindings         │ system:image-pullers                           │ system:serviceaccount:openshift-infra:default-rolebindings-controller                  │ 201     │
│ 2025-12-10T06:29:4…  │ serviceaccounts      │ builder                                        │ system:serviceaccount:openshift-infra:serviceaccount-controller                        │ 201     │
│ 2025-12-10T06:29:4…  │ serviceaccounts      │ deployer                                       │ system:serviceaccount:openshift-infra:serviceaccount-controller                        │ 201     │
│ 2025-12-10T06:29:4…  │ rolebindings         │ system:image-builders                          │ system:serviceaccount:openshift-infra:default-rolebindings-controller                  │ 201     │
│ 2025-12-10T06:29:4…  │ serviceaccounts      │ builder                                        │ system:serviceaccount:openshift-infra:serviceaccount-pull-secrets-controller           │ 201     │
│ 2025-12-10T06:29:4…  │ serviceaccounts      │ deployer                                       │ system:serviceaccount:openshift-infra:serviceaccount-pull-secrets-controller           │ 201     │
│ 2025-12-10T06:29:4…  │ serviceaccounts      │ default                                        │ system:serviceaccount:kube-system:service-account-controller                           │ 409     │
│ 2025-12-10T06:29:4…  │ serviceaccounts      │ default                                        │ system:serviceaccount:openshift-infra:serviceaccount-pull-secrets-controller           │ 201     │
│ 2025-12-10T06:29:4…  │ clusterservicevers…  │ network-observability-operator.v1.10.1         │ system:serviceaccount:openshift-operator-lifecycle-manager:olm-operator-serviceaccount │ 201     │
│ 2025-12-10T06:29:4…  │ clusterservicevers…  │ compliance-operator.v1.8.0                     │ system:serviceaccount:openshift-operator-lifecycle-manager:olm-operator-serviceaccount │ 201     │
│ 2025-12-10T06:29:4…  │ clusterservicevers…  │ openshift-pipelines-operator-rh.v1.20.1        │ system:serviceaccount:openshift-operator-lifecycle-manager:olm-operator-serviceaccount │ 201     │
│ 2025-12-10T06:29:4…  │ clusterservicevers…  │ rhacs-operator.v4.9.1                          │ system:serviceaccount:openshift-operator-lifecycle-manager:olm-operator-serviceaccount │ 201     │
│ 2025-12-10T06:29:4…  │ serviceaccounts      │ pipeline                                       │ system:serviceaccount:openshift-operators:openshift-pipelines-operator                 │ 201     │
│ 2025-12-10T06:29:4…  │ serviceaccounts      │ pipeline                                       │ system:serviceaccount:openshift-infra:serviceaccount-pull-secrets-controller           │ 201     │
│ 2025-12-10T06:29:4…  │ rolebindings         │ pipelines-scc-rolebinding                      │ system:serviceaccount:openshift-operators:openshift-pipelines-operator                 │ 201     │
│ 2025-12-10T06:29:4…  │ serviceaccounts      │ mastercard-processor                           │ admin                                                                                  │ 201     │
│          ·           │  ·                   │          ·                                     │   ·                                                                                    │  ·      │
│          ·           │  ·                   │          ·                                     │   ·                                                                                    │  ·      │
│          ·           │  ·                   │          ·                                     │   ·                                                                                    │  ·      │
│ 2025-12-10T06:30:4…  │ pods                 │ gateway-79d69c8875-69zn9                       │ system:kube-scheduler                                                                  │ 201     │
│ 2025-12-10T06:30:4…  │ events               │ gateway-79d69c8875.187fc6df2c1d1a9e            │ system:serviceaccount:kube-system:replicaset-controller                                │ 201     │
│ 2025-12-10T06:30:4…  │ events               │ gateway-79d69c8875-69zn9.187fc6df2cbfc8ae      │ system:kube-scheduler                                                                  │ 201     │
│ 2025-12-10T06:30:4…  │ deployments          │ mastercard-processor                           │ admin                                                                                  │ 201     │
│ 2025-12-10T06:30:4…  │ events               │ gateway-79d69c8875-69zn9.187fc6df4ae6cb68      │ system:multus:master-1                                                                 │ 201     │
│ 2025-12-10T06:30:4…  │ replicasets          │ mastercard-processor-59986f994c                │ system:serviceaccount:kube-system:deployment-controller                                │ 201     │
│ 2025-12-10T06:30:4…  │ pods                 │ NULL                                           │ system:serviceaccount:kube-system:replicaset-controller                                │ 201     │
│ 2025-12-10T06:30:4…  │ events               │ mastercard-processor.187fc6e03de6b7ef          │ system:serviceaccount:kube-system:deployment-controller                                │ 201     │
│ 2025-12-10T06:30:4…  │ pods                 │ mastercard-processor-59986f994c-lmwmx          │ system:kube-scheduler                                                                  │ 201     │
│ 2025-12-10T06:30:4…  │ events               │ mastercard-processor-59986f994c.187fc6e03eb4…  │ system:serviceaccount:kube-system:replicaset-controller                                │ 201     │
│ 2025-12-10T06:30:4…  │ events               │ mastercard-processor-59986f994c-lmwmx.187fc6…  │ system:kube-scheduler                                                                  │ 201     │
│ 2025-12-10T06:30:4…  │ deployments          │ visa-processor                                 │ admin                                                                                  │ 201     │
│ 2025-12-10T06:30:4…  │ replicasets          │ visa-processor-7d57964dc8                      │ system:serviceaccount:kube-system:deployment-controller                                │ 201     │
│ 2025-12-10T06:30:4…  │ events               │ visa-processor.187fc6e05c52a0f9                │ system:serviceaccount:kube-system:deployment-controller                                │ 201     │
│ 2025-12-10T06:30:4…  │ pods                 │ NULL                                           │ system:serviceaccount:kube-system:replicaset-controller                                │ 201     │
│ 2025-12-10T06:30:4…  │ pods                 │ visa-processor-7d57964dc8-brrf7                │ system:kube-scheduler                                                                  │ 201     │
│ 2025-12-10T06:30:4…  │ events               │ visa-processor-7d57964dc8.187fc6e05f261c24     │ system:serviceaccount:kube-system:replicaset-controller                                │ 201     │
│ 2025-12-10T06:30:4…  │ events               │ visa-processor-7d57964dc8-brrf7.187fc6e05f79…  │ system:kube-scheduler                                                                  │ 201     │
│ 2025-12-10T06:30:4…  │ events               │ mastercard-processor-59986f994c-lmwmx.187fc6…  │ system:multus:master-1                                                                 │ 201     │
│ 2025-12-10T06:30:4…  │ events               │ visa-processor-7d57964dc8-brrf7.187fc6e08145…  │ system:multus:master-1                                                                 │ 201     │
├──────────────────────┴──────────────────────┴────────────────────────────────────────────────┴────────────────────────────────────────────────────────────────────────────────────────┴─────────┤
│ 63 rows (40 shown)                                                                                                                                                                    5 columns │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
➜  ~ 

➜  ~ duckdb -c "
SELECT
  json_extract_string(objectRef, '$.name') AS Deployment,
  json_extract_string(responseObject, '$.spec.template.spec.containers[0].image') AS Image,
  COALESCE(json_extract_string(responseObject, '$.spec.template.spec.serviceAccountName'), 'default') AS ServiceAccount
FROM read_json_auto('audit.log', ignore_errors=true)
WHERE json_extract_string(objectRef, '$.namespace') = 'payments'
  AND json_extract_string(objectRef, '$.resource') = 'deployments'
  AND verb = 'create'
ORDER BY requestReceivedTimestamp;
"
┌──────────────────────┬──────────────────────────────────────────┬──────────────────────┐
│      Deployment      │                  Image                   │    ServiceAccount    │
│       varchar        │                 varchar                  │       varchar        │
├──────────────────────┼──────────────────────────────────────────┼──────────────────────┤
│ gateway              │ quay.io/vuln/gateway:v1                  │ default              │
│ mastercard-processor │ quay.io/vuln/mastercard-processor:latest │ mastercard-processor │
│ visa-processor       │ quay.io/vuln/visa-processor:latest       │ visa-processor       │
└──────────────────────┴──────────────────────────────────────────┴──────────────────────┘
➜  ~ 

➜  ~ duckdb -c "
SELECT
  json_extract(responseObject, '$') AS FullJson
FROM read_json_auto('audit.log', ignore_errors=true)
WHERE json_extract_string(objectRef, '$.namespace') = 'payments'
  AND json_extract_string(objectRef, '$.resource') = 'deployments'
  AND json_extract_string(objectRef, '$.name') = 'gateway'
  AND verb = 'create';
"
┌─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                                                                                            FullJson                                                                                             │
│                                                                                              json                                                                                               │
├─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ {"kind":"Deployment","apiVersion":"apps/v1","metadata":{"name":"gateway","namespace":"payments","uid":"ccd7ab4c-b4f9-4c05-ac24-bacbbf13fa90","resourceVersion":"11632574","creationTimestamp"…  │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
➜  ~ duckdb -c "
SELECT
  json_extract(responseObject, '$.metadata') AS Metadata
FROM read_json_auto('audit.log', ignore_errors=true)
WHERE json_extract_string(objectRef, '$.namespace') = 'payments'
  AND json_extract_string(objectRef, '$.resource') = 'deployments'
  AND json_extract_string(objectRef, '$.name') = 'gateway'
  AND verb = 'create';
"
┌─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                                                                                            Metadata                                                                                             │
│                                                                                              json                                                                                               │
├─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ {"name":"gateway","namespace":"payments","uid":"ccd7ab4c-b4f9-4c05-ac24-bacbbf13fa90","resourceVersion":"11632574","creationTimestamp":"2025-12-10 06:30:37","labels":{"app":"gateway","app.k…  │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
➜  ~ duckdb -c "
SELECT
  json_extract_string(objectRef, '$.name') AS Deployment,
  json_extract_string(responseObject, '$.spec.template.spec.containers[0].image') AS Image,
  COALESCE(json_extract_string(responseObject, '$.spec.template.spec.serviceAccountName'), 'default') AS ServiceAccount
FROM read_json_auto('audit.log', ignore_errors=true)
WHERE json_extract_string(objectRef, '$.namespace') = 'payments'
  AND json_extract_string(objectRef, '$.resource') = 'deployments'
  AND verb = 'create'
ORDER BY requestReceivedTimestamp;
"
┌──────────────────────┬──────────────────────────────────────────┬──────────────────────┐
│      Deployment      │                  Image                   │    ServiceAccount    │
│       varchar        │                 varchar                  │       varchar        │
├──────────────────────┼──────────────────────────────────────────┼──────────────────────┤
│ gateway              │ quay.io/vuln/gateway:v1                  │ default              │
│ mastercard-processor │ quay.io/vuln/mastercard-processor:latest │ mastercard-processor │
│ visa-processor       │ quay.io/vuln/visa-processor:latest       │ visa-processor       │
└──────────────────────┴──────────────────────────────────────────┴──────────────────────┘
➜  ~ 

-----

➜  ~ duckdb -c "
WITH history AS (
    SELECT
        requestReceivedTimestamp as ts,
        verb,
        json_extract_string(objectRef, '$.namespace') as ns,
        json_extract_string(objectRef, '$.resource') as kind,
        json_extract_string(objectRef, '$.name') as name,
        -- Find the latest event for every unique object (Namespace + Kind + Name)
        ROW_NUMBER() OVER (
            PARTITION BY
                json_extract_string(objectRef, '$.namespace'),
                json_extract_string(objectRef, '$.resource'),
                json_extract_string(objectRef, '$.name')
            ORDER BY requestReceivedTimestamp DESC
        ) as rn
    FROM read_json_auto('audit.log', ignore_errors=true)
    WHERE json_extract_string(objectRef, '$.resource') IN (
          'pods', 'services', 'configmaps', 'serviceaccounts', 'namespaces', 'nodes', 'secrets',
          'persistentvolumes', 'persistentvolumeclaims', 'deployments', 'daemonsets', 'statefulsets',
          'replicasets', 'jobs', 'cronjobs', 'ingresses', 'routes', 'networkpolicies',
          'virtualmachines', 'virtualmachineinstances'
          )
      AND verb IN ('create', 'update', 'patch', 'delete')
)
SELECT
    ns AS Namespace,
    kind AS Kind,
    name AS Name,
    ts AS LastUpdated
FROM history
WHERE rn = 1
  AND verb != 'delete'  -- Exclude objects that were deleted
  AND Name IS NOT NULL  -- Exclude malformed log entries
ORDER BY ns, kind, name;
"
┌────────────────┬─────────────────┬─────────────────────────────────────┬─────────────────────────────┐
│   Namespace    │      Kind       │                Name                 │         LastUpdated         │
│    varchar     │     varchar     │               varchar               │           varchar           │
├────────────────┼─────────────────┼─────────────────────────────────────┼─────────────────────────────┤
│ backend        │ configmaps      │ checkout-endpoint-config            │ 2025-12-10T06:29:50.888226Z │
│ backend        │ configmaps      │ config-service-cabundle             │ 2025-12-10T06:29:46.435614Z │
│ backend        │ configmaps      │ config-trusted-cabundle             │ 2025-12-10T06:29:46.430860Z │
│ backend        │ configmaps      │ kube-root-ca.crt                    │ 2025-12-10T06:29:45.852862Z │
│ backend        │ configmaps      │ openshift-service-ca.crt            │ 2025-12-10T06:29:45.889466Z │
│ backend        │ configmaps      │ recommendation-endpoint-config      │ 2025-12-10T06:29:51.377209Z │
│ backend        │ configmaps      │ reports-endpoint-config             │ 2025-12-10T06:29:51.876048Z │
│ backend        │ deployments     │ catalog                             │ 2025-12-10T06:30:07.439014Z │
│ backend        │ deployments     │ checkout                            │ 2025-12-10T06:30:12.510642Z │
│ backend        │ deployments     │ notification                        │ 2025-12-10T06:30:15.516189Z │
│ backend        │ deployments     │ recommendation                      │ 2025-12-10T06:30:18.543918Z │
│ backend        │ deployments     │ reports                             │ 2025-12-10T06:30:21.564426Z │
│ backend        │ deployments     │ shipping                            │ 2025-12-10T06:30:25.615086Z │
│ backend        │ namespaces      │ backend                             │ 2025-12-10T06:29:46.437041Z │
│ backend        │ pods            │ catalog-6f458f4787-gvv42            │ 2025-12-10T06:30:05.280742Z │
│ backend        │ pods            │ checkout-d4f598d84-57pwx            │ 2025-12-10T06:30:08.971804Z │
│ backend        │ pods            │ notification-77477dc7ff-4kr6n       │ 2025-12-10T06:30:12.730477Z │
│ backend        │ pods            │ recommendation-7fb9bc97dc-k66tj     │ 2025-12-10T06:30:16.467920Z │
│ backend        │ pods            │ reports-5c477c86b7-cg947            │ 2025-12-10T06:30:19.672406Z │
│ backend        │ pods            │ shipping-56c9c9dd4f-26xzw           │ 2025-12-10T06:30:23.839068Z │
│    ·           │  ·              │          ·                          │              ·              │
│    ·           │  ·              │          ·                          │              ·              │
│    ·           │  ·              │          ·                          │              ·              │
│ payments       │ serviceaccounts │ mastercard-processor                │ 2025-12-10T06:29:47.526509Z │
│ payments       │ serviceaccounts │ pipeline                            │ 2025-12-10T06:29:47.450458Z │
│ payments       │ serviceaccounts │ visa-processor                      │ 2025-12-10T06:29:48.084534Z │
│ payments       │ services        │ gateway-service                     │ 2025-12-10T06:29:58.028051Z │
│ payments       │ services        │ mastercard-processor-service        │ 2025-12-10T06:29:58.538021Z │
│ payments       │ services        │ visa-processor-service              │ 2025-12-10T06:29:59.053820Z │
│ rhacs-operator │ secrets         │ pipeline-dockercfg-66qz4            │ 2025-12-10T06:28:11.023468Z │
│ rhacs-operator │ serviceaccounts │ pipeline                            │ 2025-12-10T06:28:11.001486Z │
│ stackrox       │ deployments     │ scanner-v4-matcher                  │ 2025-12-10T06:31:07.119432Z │
│ stackrox       │ pods            │ scanner-v4-matcher-6d5bdd4dc8-zckqv │ 2025-12-10T06:31:04.024169Z │
│ stackrox       │ replicasets     │ scanner-v4-matcher-6d5bdd4dc8       │ 2025-12-10T06:31:07.102478Z │
│ stackrox       │ secrets         │ pipeline-dockercfg-4tbwh            │ 2025-12-10T06:28:13.023658Z │
│ stackrox       │ serviceaccounts │ pipeline                            │ 2025-12-10T06:28:13.002409Z │
│ NULL           │ ingresses       │ cluster                             │ 2025-12-10T06:30:32.899432Z │
│ NULL           │ namespaces      │ backend                             │ 2025-12-10T06:29:45.805882Z │
│ NULL           │ namespaces      │ frontend                            │ 2025-12-10T06:29:46.148817Z │
│ NULL           │ namespaces      │ payments                            │ 2025-12-10T06:29:46.493026Z │
│ NULL           │ nodes           │ master-0                            │ 2025-12-10T06:31:29.260508Z │
│ NULL           │ nodes           │ master-1                            │ 2025-12-10T06:31:32.322597Z │
│ NULL           │ nodes           │ master-2                            │ 2025-12-10T06:31:15.271081Z │
├────────────────┴─────────────────┴─────────────────────────────────────┴─────────────────────────────┤
│ 248 rows (40 shown)                                                                        4 columns │
└──────────────────────────────────────────────────────────────────────────────────────────────────────┘
➜  ~ duckdb -c "
WITH history AS (
    SELECT
        requestReceivedTimestamp as ts,
        verb,
        json_extract_string(objectRef, '$.namespace') as ns,
        json_extract_string(objectRef, '$.resource') as kind,
        json_extract_string(objectRef, '$.name') as name,
        -- Find the latest event for every unique object (Namespace + Kind + Name)
        ROW_NUMBER() OVER (
            PARTITION BY
                json_extract_string(objectRef, '$.namespace'),
                json_extract_string(objectRef, '$.resource'),
                json_extract_string(objectRef, '$.name')
            ORDER BY requestReceivedTimestamp DESC
        ) as rn
    FROM read_json_auto('audit.log', ignore_errors=true)
    WHERE json_extract_string(objectRef, '$.resource') IN (
          'pods', 'services', 'configmaps', 'serviceaccounts', 'namespaces', 'nodes', 'secrets',
          'persistentvolumes', 'persistentvolumeclaims', 'deployments', 'daemonsets', 'statefulsets',
          'replicasets', 'jobs', 'cronjobs', 'ingresses', 'routes', 'networkpolicies',
          'virtualmachines', 'virtualmachineinstances'
          )
      AND verb IN ('create', 'update', 'patch', 'delete')
)
SELECT
    ns AS Namespace,
    kind AS Kind,
    name AS Name,
    ts AS LastUpdated
FROM history
WHERE rn = 1
  AND verb != 'delete'  -- Exclude objects that were deleted
  AND Name IS NOT NULL  -- Exclude malformed log entries
ORDER BY ns, kind, name;
"