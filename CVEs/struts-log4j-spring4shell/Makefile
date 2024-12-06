build:
	docker build --label "app=struts cve-201705638" -f Dockerfile -t quay.io/vuln/struts-cve-2017-5638:latest .
	docker build --label "app=visa processor" -f Dockerfile -t quay.io/vuln/visa-processor:latest .
	docker build --label "app=master-card processor" -f Dockerfile -t quay.io/vuln/mastercard-processor:latest .

push:
	docker push quay.io/vuln/struts-cve-2017-5638:latest
	docker push quay.io/vuln/visa-processor:latest
	docker push quay.io/vuln/mastercard-processor:latest