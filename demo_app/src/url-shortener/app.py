import os
import sys
import base64
from datetime import datetime
from flask import Flask, request, redirect, render_template, render_template_string
from kubernetes import client, config
from kubernetes.client.rest import ApiException

# --- PATH CONFIGURATION ---
# Ensures templates are found regardless of where Gunicorn starts
base_dir = os.path.dirname(os.path.abspath(__file__))
template_dir = os.path.join(base_dir, 'templates')
app = Flask(__name__, template_folder=template_dir)

# --- K8S CONFIGURATION ---
try:
    config.load_incluster_config()
except Exception:
    # Fallback for local development testing
    try:
        config.load_kube_config()
    except:
        print("Warning: No K8s config found.", file=sys.stderr)

v1 = client.CoreV1Api()
PREFIX = os.getenv("SECRET_PREFIX", "s-")

def get_namespace():
    """Identifies the current namespace for secret lookups."""
    try:
        with open("/var/run/secrets/kubernetes.io/serviceaccount/namespace", "r") as f:
            return f.read().strip()
    except:
        return "shortener" # Defaulting to your created namespace

@app.route('/<short_id>', methods=['GET', 'POST'])
def redirector(short_id):
    namespace = get_namespace()
    
    # --- VULNERABILITY ENTRY POINT ---
    # We check for a 'q' field in POST data first. 
    # This allows large payloads that would crash the URL/Ingress.
    user_payload = request.form.get('q') or short_id
    
    # Standard logic for passcode verification
    user_passcode = request.form.get('passcode') or request.args.get('passcode')

    try:
        # We only use the URL's short_id for the ACTUAL secret lookup
        secret_name = f"{PREFIX}{short_id}"
        secret = v1.read_namespaced_secret(name=secret_name, namespace=namespace)
        s_data = secret.data

        # 1. EXPIRATION LOGIC
        if 'expire' in s_data:
            expire_str = base64.b64decode(s_data['expire']).decode()
            expire_date = datetime.strptime(expire_str, '%Y-%m-%d')
            
            if datetime.now() > expire_date:
                msg = f"The link '{user_payload}' expired on {expire_str}."
                with open(os.path.join(template_dir, "error.html"), "r") as f:
                    content = f.read()
                # Manual replacement ensures Jinja2 sees the raw SSTI braces
                vulnerable_content = content.replace('{{ msg | safe }}', msg)
                return render_template_string(vulnerable_content, type="Expired")

        # 2. PASSCODE LOGIC
        target_url = base64.b64decode(s_data.get('url')).decode()
        if 'passcode' in s_data:
            required = base64.b64decode(s_data['passcode']).decode()
            if user_passcode != required:
                # Render standard passcode form (Not vulnerable to SSTI)
                return render_template("form.html", id=short_id, error=(user_passcode is not None))
        
        # 3. SUCCESSFUL REDIRECT
        return redirect(target_url)

    except ApiException as e:
        # 4. NOT FOUND / SSTI LOGIC
        # If the secret doesn't exist, we reflect the 'user_payload' (GET or POST)
        msg = f"The identifier '{user_payload}' was not found."
        try:
            with open(os.path.join(template_dir, "error.html"), "r") as f:
                content = f.read()
            
            # TRIGGER: This is where the exploit happens.
            # We bypass auto-escaping by doing a string swap before the final render.
            vulnerable_content = content.replace('{{ msg | safe }}', msg)
            return render_template_string(vulnerable_content, type="Not Found")
        except Exception as ex:
            return f"Critical Template Error: {ex}", 500

if __name__ == "__main__":
    # Internal port matches your Service/Deployment containerPort
    app.run(host='0.0.0.0', port=8080)