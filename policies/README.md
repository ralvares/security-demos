roxctl deployment --insecure-skip-tls-verify check -f deployment.yaml -o table

roxctl image scan --insecure-skip-tls-verify -o csv --image quay.io/vuln/asset-cache:v1 --severity IMPORTANT,CRITICAL
roxctl image check --insecure-skip-tls-verify -o table --image quay.io/vuln/asset-cache:v1