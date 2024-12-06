We have to encode the URL so space = %20 , + = %2B


List all Images

curl -k -s \
    -X GET \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${ROX_API_TOKEN}" \
    https://$ROX_ENDPOINT/v1/images | jq

List all deployments

curl -k -s \
    -X GET \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${ROX_API_TOKEN}" \
    https://$ROX_ENDPOINT/v1/deployments | jq

List all deployments with the component log4j

curl -k -s \
    -X GET \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${ROX_API_TOKEN}" \
    https://$ROX_ENDPOINT/v1/deployments\?query\=Component:log4j | jq

List all deployments in a namespace ( eg: payments)

curl -k -s \
    -X GET \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${ROX_API_TOKEN}" \
    https://$ROX_ENDPOINT/v1/deployments?query=Namespace:payments

List all deployments with the name visa-processor

curl -k -s \
    -X GET \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${ROX_API_TOKEN}" \
    https://$ROX_ENDPOINT/v1/deployments?query=Deployment:visa-processor

List all Violation category = Vulnerability Management

curl -k -s \
    -X GET \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${ROX_API_TOKEN}" \
    https://$ROX_ENDPOINT/v1/alerts\?query\=Category:Vulnerability%20Management

Get the total number of Violations for the policy Fixable Severity at least Important

curl -k -s \
    -X GET \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${ROX_API_TOKEN}" \
    https://$ROX_ENDPOINT/v1/alerts/summary/counts?query\=Policy:Fixable%20Severity%20at%20least%20Important

Get the Violations = Policy = Fixable Severity at least important

curl -k -s \
    -X GET \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${ROX_API_TOKEN}" \
    https://$ROX_ENDPOINT/v1/alerts?query\=Policy:Fixable%20Severity%20at%20least%20Important | jq

Get the Violations for the namespace payments and severity = Critical

curl -k -s \
    -X GET \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${ROX_API_TOKEN}" \
    https://$ROX_ENDPOINT/v1/alerts\?query\=Namespace:payments%2BSeverity:CRITICAL_SEVERITY | jq


List of images with Fixables

curl -k -s \
    -X GET \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${ROX_API_TOKEN}" \
    https://$ROX_ENDPOINT/v1/images\?query\=Fixable\:True | jq


List all the images with the component log4j

curl -k -s \
    -X GET \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${ROX_API_TOKEN}" \
    https://$ROX_ENDPOINT/v1/images\?query\=Component\:log4j%2BFixable\:True | jq

List all the images with the CVE CVE-2021-44228

curl -k -s \
    -X GET \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${ROX_API_TOKEN}" \
    https://$ROX_ENDPOINT/v1/images\?query\=CVE:CVE-2021-44228 | jq


Search everything that runs log4j version 2.14.x

curl -k -s \
    -X GET \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${ROX_API_TOKEN}" \
    https://$ROX_ENDPOINT/v1/search\?query\=Component:log4j%2BComponent%20Version:2.14%2BOrchestrator%20Component:false | jq

Search everything that a fixable patch exist and are pulled from quay.io

curl -k -s \
    -X GET \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${ROX_API_TOKEN}" \
    https://$ROX_ENDPOINT/v1/search\?query\=Fixable:true%2BImage%20Registry:quay.io%2BOrchestrator%20Component:false | jq

Search everything that a fixable patch exist and deployments of the payments namespace

curl -k -s \
    -X GET \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${ROX_API_TOKEN}" \
    https://$ROX_ENDPOINT/v1/search\?query\=Fixable:true%2BNamespace:payments%2BOrchestrator%20Component:false | jq

Search everything that contains a CRITICAL VULNERABILITY


curl -k -s \
    -X GET \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${ROX_API_TOKEN}" \
    https://$ROX_ENDPOINT/v1/search\?query\=Severity:CRITICAL_VULNERABILITY_SEVERITY%2BOrchestrator%20Component:false | jq



# Other Examples

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
    https://$ROX_ENDPOINT/v1/deployments/$deployment_id | jq
}

function get_deployment_risk() {
    deployment_id=$(get_deployment $1 | jq -r '.deployments[].id')
    curl -k -s \
    -X GET \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${ROX_API_TOKEN}" \
    https://$ROX_ENDPOINT/v1/deploymentswithrisk/$deployment_id | jq
}

function get_image() {
    curl -k -s \
    -X GET \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${ROX_API_TOKEN}" \
    https://$ROX_ENDPOINT/v1/images/$1 | jq
}


#####

Example - Getting the ID of all the deployments with ACTIVE Violations for the policy Fixable Severity at least Important

function get_deployment_image_id() {
    curl -k -s \
    -X GET \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${ROX_API_TOKEN}" \
    https://$ROX_ENDPOINT/v1/deploymentswithrisk/$1 | jq -r '.deployment.containers[0].image.id'
}

function get_id_fixable_Important() {
    curl -k -s \
    -X GET \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${ROX_API_TOKEN}" \
    https://$ROX_ENDPOINT/v1/alerts\?query\=Policy:Fixable%20Severity%20at%20least%20Important | jq -r '.alerts[] | select(.state == "ACTIVE") | .deployment.id'
}

function get_image() {
    curl -k -s \
    -X GET \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${ROX_API_TOKEN}" \
    https://$ROX_ENDPOINT/v1/images/$1 | jq
}

function get_image_name() {
    curl -k -s \
    -X GET \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${ROX_API_TOKEN}" \
    https://$ROX_ENDPOINT/v1/images/$1 | jq -r '.name.fullName'
}

function get_image_fixed() {
    curl -k -s \
    -X GET \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${ROX_API_TOKEN}" \
    https://$ROX_ENDPOINT/v1/images/$1 | jq -r '.scan.components[] | select(.fixedBy != null and .fixedBy != "")'
}

function get_image_fixed_name_version() {
    curl -k -s \
    -X GET \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${ROX_API_TOKEN}" \
    https://$ROX_ENDPOINT/v1/images/$1 | jq -r '.scan.components[] | select(.fixedBy != null and .fixedBy != "") | "NAME: \(.name), VERSION: \(.version), FixedBy: \(.fixedBy)"'
}


# RUN DEMO

get_id_fixable_Important

get_deployment_image_id 34bde204-b6cc-4abc-922f-9b22c9ddc40c

get_image_name sha256:c0ca37da8544a1a5b3e322482cca8146e3175dc9e55576d40ae0c81a14166f2d

get_image_fixed sha256:c0ca37da8544a1a5b3e322482cca8146e3175dc9e55576d40ae0c81a14166f2d

###

webapp log4j

get_image_fixed sha256:744199d26ddf6410538c63b5cffb9142b4e0d5f569aa674859c91f68e85920c9
