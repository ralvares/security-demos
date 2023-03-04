# Install the openshift-pipeline operator 

I'll not cover the instalation here, just go to the operator hub and install the pipeline operator

# Create a roxsecrets
```
export ROX_ENDPOINT=central-stackrox.apps.ocp.ralvares.com:443 
ROX_API_TOKEN=$(cat ~/token)
oc create secret generic roxsecrets --from-literal=rox_central_endpoint="${ROX_ENDPOINT}" --from-literal=rox_api_token=${ROX_API_TOKEN} -n pipeline-demo
```

# Create the demo pipeline
```
oc apply -k .
```