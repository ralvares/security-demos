#!/bin/bash

if [[ -z "${ROX_ENDPOINT}" ]]; then
  echo >&2 "ROX_ENDPOINT must be set"
  exit 1
fi

if [[ -z "${ROX_API_TOKEN}" ]]; then
  echo >&2 "ROX_API_TOKEN must be set"
  exit 1
fi

if [ $# -eq 0 ]
then
echo  "try: ./$0 visa-processor"
exit 1
fi

function get_deployment() {
    curl -k -s \
    -X GET \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${ROX_API_TOKEN}" \
    https://$ROX_ENDPOINT/v1/deployments?query=Deployment:$1 | jq
}

function get_deployment_detailed() {
    deployment_id=$(get_deployment $1 | jq -r '.deployments[].id')
    curl -k -s -X GET \
    -H "Content-type: application/json" \
    -H "Authorization: Bearer ${ROX_API_TOKEN}" \
   "https://${ROX_ENDPOINT}/v1/deployments/${deployment_id}" | jq
}

function get_deployment_with_risk() {
    deployment_id=$(get_deployment $1 | jq -r '.deployments[].id')
    curl -k -s -X GET \
    -H "Content-type: application/json" \
    -H "Authorization: Bearer ${ROX_API_TOKEN}" \
   "https://${ROX_ENDPOINT}/v1/deploymentswithrisk/${deployment_id}" | jq
}

function get_deployment_processes() {
    deployment_id=$(get_deployment $1 | jq -r '.deployments[].id')
    curl -k -s -X GET \
    -H "Content-type: application/json" \
    -H "Authorization: Bearer ${ROX_API_TOKEN}" \
   "https://${ROX_ENDPOINT}/v1/processes/deployment/${deployment_id}" | jq
}

function get_deployment_processes_grouped() {
    deployment_id=$(get_deployment $1 | jq -r '.deployments[].id')
    curl -k -s -X GET \
    -H "Content-type: application/json" \
    -H "Authorization: Bearer ${ROX_API_TOKEN}" \
   "https://${ROX_ENDPOINT}/v1/processes/deployment/${deployment_id}/grouped" | jq
}

function get_deployment_processes_grouped_container() {
    deployment_id=$(get_deployment $1 | jq -r '.deployments[].id')
    curl -k -s -X GET \
    -H "Content-type: application/json" \
    -H "Authorization: Bearer ${ROX_API_TOKEN}" \
   "https://${ROX_ENDPOINT}/v1/processes/deployment/${deployment_id}/grouped/container" | jq
}

function get_deployment_image_details() {
    image_id=$(get_deployment_detailed $1 | jq -r '.containers[].image.id')
    curl -k -s -X GET \
    -H "Content-type: application/json" \
    -H "Authorization: Bearer ${ROX_API_TOKEN}" \
     "https://${ROX_ENDPOINT}/v1/images/${image_id}" | jq
}

function get_rbac_bindinds() {
    curl -k -s -X GET \
    -H "Content-type: application/json" \
    -H "Authorization: Bearer ${ROX_API_TOKEN}" \
     "https://${ROX_ENDPOINT}/v1/rbac/bindings" | jq
}

#get_deployment $1
get_deployment_detailed $1
#get_deployment_processes $1
#get_deployment_processes_grouped $1
#get_deployment_processes_grouped_container $1
#get_deployment_image_details $1
#get_deployment_with_risk $1

#get_rbac_bindinds
