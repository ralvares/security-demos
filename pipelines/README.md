
# Pipeline Setup Instructions

This guide explains how to set up and run the demo pipeline in this directory.

## Prerequisites

1. **OpenShift Pipelines** must be installed and configured on your OpenShift cluster.

2. **Red Hat Advanced Cluster Security (ACS)** must be deployed and accessible. You will need:
	- The ACS Central endpoint (e.g., `central-stackrox.apps.<cluster-domain>:443`)
	- An API token with sufficient permissions

## Setup Steps

1. **Apply the pipeline manifests:**

	```sh
	oc apply -k manifests
	```

2. **Create the `roxsecrets` secret:**

	Set your ACS Central endpoint and API token as environment variables:

	```sh
	export ROX_API_ENDPOINT=<your-central-endpoint>
	export ROX_API_TOKEN=<your-api-token>
	```

	Then create the secret in the `pipeline-demo` namespace:

	```sh
	oc create secret generic roxsecrets \
	  --from-literal=rox_central_endpoint="$ROX_API_ENDPOINT" \
	  --from-literal=rox_api_token="$ROX_API_TOKEN" \
	  -n pipeline-demo
	```

3. **Verify ACS Configuration:**

	- Ensure your ACS Central instance is reachable from the cluster.
	- The API token must be valid and have the necessary permissions for image scanning and policy evaluation.

## Troubleshooting

- If the pipeline fails due to missing secrets or ACS connectivity, double-check the endpoint, token, and that the `roxsecrets` secret exists in the correct namespace.
- Make sure OpenShift Pipelines is installed and the `pipeline-demo` namespace exists.




