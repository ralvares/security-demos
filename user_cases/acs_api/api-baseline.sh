#!/bin/bash

if [[ -z "${ROX_ENDPOINT}" ]]; then
  echo >&2 "ROX_ENDPOINT must be set"
  exit 1
fi

if [[ -z "${ROX_API_TOKEN}" ]]; then
  echo >&2 "ROX_API_TOKEN must be set"
  exit 1
fi


function get_deployment() {
    curl -k -s \
    -X GET \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${ROX_API_TOKEN}" \
    https://$ROX_ENDPOINT/v1/deployments?query=Deployment:$1
}

function get_deployment_extra_details() {
    deployment_id=$(get_deployment $1 | jq -r '.deployments[].id')
    curl -k -s \
    -X GET \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${ROX_API_TOKEN}" \
    https://$ROX_ENDPOINT/v1/deployments/$deployment_id
}

function get_deployment_risk() {
    deployment_id=$(get_deployment $1 | jq -r '.deployments[].id')
    curl -k -s \
    -X GET \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${ROX_API_TOKEN}" \
    https://$ROX_ENDPOINT/v1/deploymentswithrisk/$deployment_id
}

get_deployment_extra_details_processinfo() {
    curl -k -s \
    -X GET \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${ROX_API_TOKEN}" \
    https://$ROX_ENDPOINT/v1/deploymentswithprocessinfo?query=Deployment:$1
}

function get_deployment_details() {
    deployment=$(get_deployment_extra_details $1)
    export deployment_name=$(echo $deployment | jq -r '.name')
    export deployment_id=$(echo $deployment | jq -r '.id')
    export namespace=$(echo $deployment | jq -r '.namespace')
    export clusterid=$(echo $deployment | jq -r '.clusterId')
    export containerid=$(echo $deployment | jq -r '.containers[].id')
    export container_name=$(echo $deployment | jq -r '.containers[].name')
}

function get_process_baseline(){
    get_deployment_details $1
    curl  -k -s -X GET \
    -H "Authorization: Bearer ${ROX_API_TOKEN}" \
    'https://'$ROX_ENDPOINT'/v1/processbaselines/key?key.clusterId='$clusterid'&key.namespace='$namespace'&key.deploymentId='$deployment_id'&key.containerName='$container_name''
}

function lock_baseline(){
    get_deployment_details $1
    export userlocked=$(get_process_baseline $1 | jq -r 'select(.userLockedTimestamp == null)')
    if [ ! -z "$userlocked" ]
    then
    _RETURN=$(curl -k -s \
    -X PUT \
    --header "Content-Type: application/json" \
    -H "Authorization: Bearer ${ROX_API_TOKEN}" \
    -d "{\"keys\":[{\"deploymentId\":\"${deployment_id}\",\"containerName\":\"${deployment_name}\",\"clusterId\":\"${clusterid}\",\"namespace\":\"${namespace}\"}],\"locked\":true}" \
    https://$ROX_ENDPOINT/v1/processbaselines/lock)
    echo "Baseline locked - ${deployment_name}"
    else
    echo "Baseline already locked - ${deployment_name}"
    fi
}

function unlocklock_baseline(){
    get_deployment_details $1
    export userlocked=$(get_process_baseline $1 $2 | jq -r 'select(.userLockedTimestamp == null)')
    if [ -z "$userlocked" ]
    then
    _RETURN=$(curl -k -s \
    -X PUT \
    --header "Content-Type: application/json" \
    -H "Authorization: Bearer ${ROX_API_TOKEN}" \
    -d "{\"keys\":[{\"deploymentId\":\"${deployment_id}\",\"containerName\":\"${deployment_name}\",\"clusterId\":\"${clusterid}\",\"namespace\":\"${namespace}\"}],\"locked\":false}" \
    https://$ROX_ENDPOINT/v1/processbaselines/lock)
    echo "Baseline unlocked - ${deployment_name}"
    else
    echo "Baseline already unlocked - ${deployment_name}"
    fi
}

function export_process_baseline(){
    get_process_baseline $1 | jq -r '.elements[].element.processName'
}

#get_process_baseline $1

#lock_baseline $cluster_name $1

#unlocklock_baseline $1

#export_process_baseline $1

function get_image() {
    export image=$(get_deployment_risk $1 | jq -r '.deployment.containers[].image.id')
    curl -k -s \
    -X GET \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${ROX_API_TOKEN}" \
    https://$ROX_ENDPOINT/v1/images/$image
}

#get_image sha256:d4168dc4c12349802fb3f56bb9123eebd8cc1ce0682589d322b54c1563cc760a

#echo $(get_deployment_details gogs)

#get_deployment_extra_details visa-processor

#get_deployment_risk visa-processor

get_image  gateway | jq
