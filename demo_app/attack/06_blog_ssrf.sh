curl -k  https://$(oc -n frontend get route/blog --output jsonpath={.spec.host})/fetch?url=http://visa-processor-service.payments:8080
