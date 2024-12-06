import os
import requests
import yaml
import json
import re
import argparse
import os
from urllib3.exceptions import InsecureRequestWarning

# Disable TLS warnings for self-signed certificates (useful for development only)
requests.packages.urllib3.disable_warnings(InsecureRequestWarning)

# Environment variables for StackRox endpoint and API token
ROX_ENDPOINT = os.getenv("ROX_ENDPOINT")
ROX_API_TOKEN = os.getenv("ROX_API_TOKEN")

# Hardcoded list of enabled policy names
ENABLED_POLICY_NAMES = [
    "30-Day Scan Age",
    "90-Day Image Age",
    "Alpine Linux Package Manager (apk) in Image",
    "Alpine Linux Package Manager Execution",
    "Apache Struts: CVE-2017-5638",
    "CAP_SYS_ADMIN capability added",
    "chkconfig Execution",
    "Compiler Tool Execution",
    "Container with privilege escalation allowed",
    "crontab Execution",
    "Cryptocurrency Mining Process Execution",
    "Docker CIS 4.1: Ensure That a User for the Container Has Been Created",
    "Docker CIS 4.7: Alert on Update Instruction",
    "Docker CIS 5.15: Ensure that the host's process namespace is not shared",
    "Docker CIS 5.16: Ensure that the host's IPC namespace is not shared",
    "Docker CIS 5.19: Ensure mount propagation mode is not enabled",
    "Docker CIS 5.1 Ensure that, if applicable, an AppArmor Profile is enabled",
    "Docker CIS 5.7: Ensure privileged ports are not mapped within containers",
    "Docker CIS 5.9 and 5.20: Ensure that the host's network namespace is not shared",
    "Emergency Deployment Annotation",
    "Environment Variable Contains Secret",
    "Fixable Severity at least Important",
    "Improper Usage of Orchestrator Secrets Volume",
    "Insecure specified in CMD",
    "iptables Execution",
    "Iptables or nftables Executed in Privileged Container",
    "Kubernetes Actions: Exec into Pod",
    "Kubernetes Actions: Port Forward to Pod",
    "Kubernetes Dashboard Deployed",
    "Latest tag",
    "Linux Group Add Execution",
    "Linux User Add Execution",
    "Log4Shell: log4j Remote Code Execution vulnerability",
    "Mount Container Runtime Socket",
    "Mounting Sensitive Host Directories",
    "Netcat Execution Detected",
    "Network Management Execution",
    "nmap Execution",
    "No CPU request or memory limit specified",
    "OpenShift: Central Admin Secret Accessed",
    "OpenShift: Kubeadmin Secret Accessed",
    "OpenShift: Kubernetes Secret Accessed by an Impersonated User",
    "Pod Service Account Token Automatically Mounted",
    "Privileged Container",
    "Privileged Containers with Important and Critical Fixable CVEs",
    "Process Targeting Cluster Kubelet Endpoint",
    "Process Targeting Cluster Kubernetes Docker Stats Endpoint",
    "Process Targeting Kubernetes Service Endpoint",
    "Red Hat Package Manager Execution",
    "Red Hat Package Manager in Image",
    "Remote File Copy Binary Execution",
    "Secure Shell Server (sshd) Execution",
    "Secure Shell (ssh) Port Exposed",
    "Secure Shell (ssh) Port Exposed in Image",
    "Shell Spawned by Java Application",
    "Spring4Shell (Spring Framework Remote Code Execution) and Spring Cloud Function vulnerabilities",
    "systemctl Execution",
    "systemd Execution",
    "Ubuntu Package Manager Execution",
    "Ubuntu Package Manager in Image",
    "Unauthorized Network Flow",
    "Unauthorized Process Execution"
]

if not ROX_ENDPOINT or not ROX_API_TOKEN:
    raise EnvironmentError("Both ROX_ENDPOINT and ROX_API_TOKEN environment variables must be set.")

HEADERS = {"Authorization": f"Bearer {ROX_API_TOKEN}"}


def save_policies_to_folder(policies):
    """Save each policy as a separate YAML file in the 'policies' folder."""
    # Create 'policies' directory if it doesn't exist
    folder_name = "policies"
    if not os.path.exists(folder_name):
        os.makedirs(folder_name)

    for policy in policies:
        # Generate a sanitized file name for each policy
        file_name = f"{sanitize_name(policy['name'])}.yaml"
        file_path = os.path.join(folder_name, file_name)

        # Convert policy to YAML and save to the file
        with open(file_path, "w") as yaml_file:
            yaml_file.write(convert_policy_to_yaml(policy))

    print(f"Saved {len(policies)} policies to the '{folder_name}' folder.")

def fetch_policies():
    """Fetch all policies using the /v1/policies endpoint."""
    url = f"https://{ROX_ENDPOINT}/v1/policies"
    response = requests.get(url, headers=HEADERS, verify=False)
    if response.status_code != 200:
        raise Exception(f"Failed to fetch policies: {response.status_code} {response.text}")
    return response.json().get("policies", [])


def fetch_full_policies(policy_ids):
    """Fetch detailed policies using the /v1/policies/export endpoint."""
    url = f"https://{ROX_ENDPOINT}/v1/policies/export"
    payload = {"policyIds": policy_ids}
    response = requests.post(url, headers=HEADERS, json=payload, verify=False)
    if response.status_code != 200:
        raise Exception(f"Failed to export policies: {response.status_code} {response.text}")
    return response.json().get("policies", [])


def update_policy(policy):
    """Update a single policy."""
    url = f"https://{ROX_ENDPOINT}/v1/policies/{policy['id']}"
    response = requests.put(url, headers=HEADERS, json=policy, verify=False)
    if response.status_code != 200:
        raise Exception(f"Failed to update policy {policy['id']}: {response.status_code} {response.text}")


def delete_policy(policy_id):
    """Delete a single policy."""
    url = f"https://{ROX_ENDPOINT}/v1/policies/{policy_id}"
    response = requests.delete(url, headers=HEADERS, verify=False)
    if response.status_code != 200:
        raise Exception(f"Failed to delete policy {policy_id}: {response.status_code} {response.text}")


def sanitize_name(name):
    """Sanitize a name to comply with Kubernetes naming conventions."""
    # Replace invalid characters with "-"
    sanitized = re.sub(r'[^a-z0-9.-]', '-', name.lower())
    # Collapse multiple "-" into a single "-"
    sanitized = re.sub(r'-+', '-', sanitized)
    # Ensure it starts and ends with an alphanumeric character
    sanitized = re.sub(r'^[^a-z0-9]+|[^a-z0-9]+$', '', sanitized)
    return sanitized


def convert_policy_to_yaml(policy):
    """Convert a single policy dictionary to YAML format, respecting hardcoded enabled policies."""
    is_enabled = policy["name"] in ENABLED_POLICY_NAMES  # Check if the policy should remain enabled
    yaml_policy = {
        "apiVersion": "config.stackrox.io/v1alpha1",
        "kind": "SecurityPolicy",
        "metadata": {
            "name": sanitize_name(policy["name"])
        },
        "spec": {
            "categories": policy.get("categories", ["Uncategorized"]),
            "criteriaLocked": policy.get("criteriaLocked", False),
            "description": policy.get("description", ""),
            "enforcementActions": policy.get("enforcementActions", []),
            "eventSource": policy.get("eventSource", "NOT_APPLICABLE"),
            "exclusions": policy.get("exclusions", []),
            "isDefault": False,  # Ensure custom policies are not marked as default
            "lifecycleStages": policy.get("lifecycleStages", []),
            "mitreAttackVectors": policy.get("mitreAttackVectors", []),
            "mitreVectorsLocked": policy.get("mitreVectorsLocked", False),
            "policyName": f"GitOps - {policy.get('name', '')}",
            "policySections": policy.get("policySections", []),
            "rationale": policy.get("rationale", "No rationale provided."),
            "remediation": policy.get("remediation", "No remediation provided."),
            "scope": policy.get("scope", []),
            "severity": policy.get("severity", "LOW_SEVERITY"),
            "disabled": not is_enabled  # Set `disabled` to False if the policy is in the enabled list
        }
    }
    return yaml.dump(yaml_policy, sort_keys=False)


def backup_policies(policies, output_file, format="json"):
    """Backup all policies to a file in the specified format (JSON or YAML)."""
    if format == "json":
        with open(output_file, "w") as json_file:
            json.dump(policies, json_file, indent=2)
        print(f"All policies backed up to {output_file} in JSON format.")
    elif format == "yaml":
        with open(output_file, "w") as yaml_file:
            for policy in policies:
                yaml_file.write("---\n")
                yaml_file.write(convert_policy_to_yaml(policy))
        print(f"All policies backed up to {output_file} in YAML format.")
    else:
        raise ValueError("Unsupported format. Use 'json' or 'yaml'.")


def disable_default_policies(policies):
    """Disable all default policies."""
    default_policies = [policy for policy in policies if policy.get("isDefault", False)]
    for policy in default_policies:
        policy["disabled"] = True
        update_policy(policy)
    print(f"Disabled {len(default_policies)} default policies.")


def delete_default_policies(policies):
    """Delete all default policies."""
    default_policy_ids = [policy["id"] for policy in policies if policy.get("isDefault", False)]
    for policy_id in default_policy_ids:
        try:
            delete_policy(policy_id)
        except Exception as e:
            print(f"Failed to delete default policy {policy_id}: {e}. Suggest disabling it instead.")

def save_policies_to_folder_with_kustomization(policies):
    """Save each policy as a separate YAML file in the 'policies' folder and create kustomization.yaml."""
    # Create 'policies' directory if it doesn't exist
    folder_name = "policies"
    if not os.path.exists(folder_name):
        os.makedirs(folder_name)

    policy_files = []  # List to store policy file names for kustomization.yaml

    for policy in policies:
        # Generate a sanitized file name for each policy
        file_name = f"{sanitize_name(policy['name'])}.yaml"
        file_path = os.path.join(folder_name, file_name)

        # Convert policy to YAML and save to the file
        with open(file_path, "w") as yaml_file:
            yaml_file.write(convert_policy_to_yaml(policy))

        # Add the file to the list for kustomization.yaml
        policy_files.append(file_name)

    # Create kustomization.yaml in the same folder
    kustomization_path = os.path.join(folder_name, "kustomization.yaml")
    with open(kustomization_path, "w") as kustomization_file:
        kustomization_content = {
            "apiVersion": "kustomize.config.k8s.io/v1beta1",
            "kind": "Kustomization",
            "namespace": "stackrox",  # Set the namespace (update as needed)
            "resources": policy_files
        }
        yaml.dump(kustomization_content, kustomization_file, sort_keys=False)

    print(f"Saved {len(policies)} policies to the '{folder_name}' folder and created kustomization.yaml.")


def main():
    parser = argparse.ArgumentParser(description="Manage StackRox policies.")
    parser.add_argument("--backup", action="store_true", help="Backup all policies to a JSON file.")
    parser.add_argument("--disable-all", action="store_true", help="Disable all default policies.")
    args = parser.parse_args()

    print("Fetching all policies...")
    policies = fetch_policies()
    print(f"Fetched {len(policies)} policies.")

    # Fetch full details for all policies
    policy_ids = [policy["id"] for policy in policies]
    full_policies = fetch_full_policies(policy_ids)

    # Backup if --backup is specified
    if args.backup:
        backup_file = "all_policies_backup.json"
        print("Backing up all policies in JSON format...")
        backup_policies(full_policies, backup_file, format="json")
        return  # Exit after backup when --backup is specified

    # Disable all default policies if --disable-all is specified
    if args.disable_all:
        disable_default_policies(full_policies)



    # Default action: Save each policy as a separate YAML file in 'policies' folder
    if not args.disable_all:
        print("No specific action provided. Saving policies to 'policies' folder...")
        save_policies_to_folder_with_kustomization(full_policies)



if __name__ == "__main__":
    main()
