export ROX_ENDPOINT=central-stackrox.apps.ocp.ralvares.com:443
export ROX_API_TOKEN=$(cat ~/token)

oc create secret generic roxsecrets --from-literal=rox_central_endpoint="${ROX_ENDPOINT}" --from-literal=rox_api_token=${ROX_API_TOKEN} -n pipeline-demo

oc patch serviceaccount pipeline -p '{"secrets": [{"name": "git-repo-auth"}]}' -n pipeline-demo

