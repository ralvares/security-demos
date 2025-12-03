

# Pipeline Demo Overview

This is a simple demo pipeline that showcases:
- **Image scanning**
- **Deployment manifest checks**
- **Enforcement of security policies at deployment time**

You can use this pipeline to demonstrate how ACS enforces security controls in CI/CD workflows. To safely test enforcement without risking cluster-wide impact, you can scope your policies to only the `frontend` namespace. This allows you to create or edit policies and observe enforcement actions (such as blocking risky deployments) in a controlled environment.

---

## Setup Instructions

Follow these steps to set up and run the demo pipeline:

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




