build:
	docker build --label "app=api-server" -f Dockerfile-debian8 -t quay.io/vuln/api-server:latest .
	docker build --label "app=backend-atlas" -f Dockerfile-debian8 -t quay.io/vuln/backend-atlas:latest .
	docker build --label "app=backend-cache" -f Dockerfile-debian8 -t quay.io/vuln/backend-cache:latest .
	docker build --label "app=report-generator" -f Dockerfile_report-generator -t quay.io/vuln/report-generator:latest .
	docker build --label "app=api-server-v2" -f Dockerfile-fixed -t quay.io/vuln/api-server:v2 .
	docker build --label "app=backend-atlas-v2" -f Dockerfile-fixed -t quay.io/vuln/backend-atlas:v2 .
	docker build --label "app=backend-cache-v2" -f Dockerfile-fixed -t quay.io/vuln/backend-cache:v2 .
	docker build --label "app=report-generator-v2" -f Dockerfile-fixed -t quay.io/vuln/report-generator:v2 .
	
push:
	docker push quay.io/vuln/api-server:latest
	docker push quay.io/vuln/backend-atlas:latest
	docker push quay.io/vuln/backend-cache:latest
	docker push quay.io/vuln/report-generator:latest
	docker push quay.io/vuln/api-server:v2
	docker push quay.io/vuln/backend-atlas:v2
	docker push quay.io/vuln/backend-cache:v2
	docker push quay.io/vuln/report-generator:v2
