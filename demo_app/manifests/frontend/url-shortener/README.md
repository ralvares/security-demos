# url-shortener

The **url-shortener** is a lightweight, Kubernetes-native application designed to handle URL redirects using **Kubernetes Secrets** as a backend. Instead of a traditional database, the application leverages the Kubernetes API to store and retrieve mapping data, allowing for a decentralized and cloud-native approach to link management.

## Application Logic

The application interprets the URL path as a `short_id`. It then attempts to locate a Secret in the current namespace prefixed with `s-`.

* **Standard Redirects:** If the secret exists, the application decodes the `url` value and redirects the user.
* **Access Control:** Supports a `passcode` attribute. If present, the user must provide the correct passcode before the redirect occurs.
* **Lifecycle Management:** Supports an `expire` attribute. If the current date is past the expiration date, the link is deactivated.
* **Error Handling:** If no matching secret is found, the application serves a custom "Link Not Found" page.

---

## The Vulnerability: Risks of "Vibe Coding"

This application serves as a primary example of what can happen during **vibe coding**—where a developer writes code that satisfies functional requirements and "feels" correct, but ignores the underlying security implications of the chosen framework.

### Technical Root Cause: Server-Side Template Injection (SSTI)

The flaw exists in the error handling logic within `app.py`. When a requested identifier is not found, the application creates an error message containing the user-supplied input and renders it using a template string.

```python
# VULNERABLE LOGIC
msg = f"The identifier '{short_id}' was not found."
vulnerable_content = content.replace('{{ msg | safe }}', msg)
return render_template_string(vulnerable_content, type="Not Found")

```

Because `render_template_string` is called on a string that now contains raw user input, the Jinja2 engine evaluates anything inside `{{ ... }}` as Python code. This transforms a simple 404 error into an **Arbitrary Code Execution** vulnerability.

---

## Configuration Examples

To populate the application with data, create secrets in the `shortener` namespace. Note that all values in Kubernetes secrets must be Base64 encoded.

### 1. Valid Link (No passcode, not expired)

```bash
oc create secret generic s-google \
  --from-literal=url=$(echo -n "https://google.com" | base64) \
  -n shortener

```

### 2. Protected Link (Requires passcode '1234')

```bash
oc create secret generic s-locked \
  --from-literal=url=$(echo -n "https://redhat.com" | base64) \
  --from-literal=passcode=$(echo -n "1234" | base64) \
  -n shortener

```

### 3. Expired Link (Expired in 2024)

```bash
oc create secret generic s-expired \
  --from-literal=url=$(echo -n "https://bing.com" | base64) \
  --from-literal=expire=$(echo -n "2024-01-01" | base64) \
  -n shortener

```

---

## Forensic Significance

From a forensic perspective, this application highlights the importance of monitoring **Error Paths**. Traditional security monitoring often focuses on successful transactions, but in this case, the vulnerability is only triggered when a "Not Found" event occurs.

The use of `render_template_string` with user-controlled input allows an attacker to bypass standard file-system restrictions and interact directly with the Python runtime, the environment variables, and the mounted Kubernetes Service Account token.
