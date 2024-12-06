build:
	docker build --label "app=rce-webapp" -f Dockerfile -t quay.io/vuln/rce-webapp:latest .
	docker build --label "app=rce-webapp" -f Dockerfile-alpine -t quay.io/vuln/rce-webapp:alpine .
	docker build --label "app=rce-webapp" -f Dockerfile-ubi-micro -t quay.io/vuln/rce-webapp:ubi-micro .
	
push:
	docker push quay.io/vuln/rce-webapp:latest
	docker push quay.io/vuln/rce-webapp:alpine
	docker push quay.io/vuln/rce-webapp:ubi-micro
