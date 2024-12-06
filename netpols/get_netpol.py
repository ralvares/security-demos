#!/usr/bin/env python3

import os
import requests
import yaml
import sys

ROX_ENDPOINT = os.getenv("ROX_ENDPOINT")
ROX_API_TOKEN = os.getenv("ROX_API_TOKEN")
CLUSTER = os.getenv("CLUSTER")

if ROX_ENDPOINT is None:
    print("ROX_ENDPOINT must be set")
    exit(1)

if ROX_API_TOKEN is None:
    print("ROX_API_TOKEN must be set")
    exit(1)

def get_deployment():
    headers = {
        "Content-Type": "application/json",
        "Authorization": "Bearer " + ROX_API_TOKEN
    }
    response = requests.get(f"https://{ROX_ENDPOINT}/v1/deployments?query=Deployment:{deployment_name}", headers=headers)
    return response.json()

def generate_deployment_networkpolicies():
    deployment_info = get_deployment()
    deployment_id = deployment_info["deployments"][0]["id"]
    deployment_namespace = deployment_info["deployments"][0]["namespace"]
    deployment_cluster = deployment_info["deployments"][0]["cluster"]
    if deployment_namespace == namespace and deployment_cluster == CLUSTER:
        headers = {
            "Content-Type": "application/json",
            "Authorization": "Bearer " + ROX_API_TOKEN
        }
        response = requests.post(f"https://{ROX_ENDPOINT}/v1/networkpolicies/generate/baseline/{deployment_id}", headers=headers)
        return response.json()["modification"]["applyYaml"]

with open("/tmp/all.yaml") as file:
    data = yaml.load_all(file, Loader=yaml.FullLoader)
    deployments = [f"{item['metadata']['namespace']}/{item['metadata']['name']}" for item in data if item["kind"] == "Deployment"]

with open("networkpolicies.yaml", "w") as outfile:
    for deployment in deployments:
        namespace, deployment_name = deployment.split("/")
        networkpolicies = generate_deployment_networkpolicies()
        if networkpolicies:
            outfile.write(networkpolicies)
            outfile.write("\n---\n")