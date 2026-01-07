#!/bin/bash

# Exit on any error
set -e

# Configuration
NS="netobserv"
FLOW_COLLECTOR_NAME="cluster"
SEARCH_TERM="network-observability-operator"

echo "----------------------------------------------------"
echo "🚀 NetObserv Deployment: Smart & Version Agnostic"
echo "----------------------------------------------------"

# 1. Infrastructure Check (Namespace, SA, PVC, etc.)
if oc get sa loki-sa -n "$NS" &> /dev/null; then
    echo "✅ Infrastructure (loki-sa) already exists. Skipping Kustomize."
else
    echo "📦 Applying Kustomize manifests..."
    oc apply -k .
fi

# 2. SCC Idempotency (Atomic assignment via 'oc adm')
echo "Checking SCC permissions for Loki..."
if oc get scc privileged -o jsonpath='{.users[*]}' | grep -q "system:serviceaccount:$NS:loki-sa"; then
    echo "✅ Loki SA already has privileged SCC."
else
    echo "🔐 Assigning Privileged SCC to loki-sa..."
    oc adm policy add-scc-to-user privileged -z loki-sa -n "$NS"
fi

# 3. Dynamic Operator Detection (The Grep Way)
echo "Verifying NetObserv Operator health..."
CSV_NAME=""
while [ -z "$CSV_NAME" ]; do
    # Using grep to find the specific CSV even if others exist in the namespace
    CSV_NAME=$(oc get csv -n "$NS" -o name 2>/dev/null | grep -i "$SEARCH_TERM" | head -n 1)
    
    if [ -z "$CSV_NAME" ]; then
        printf "."
        sleep 5
    fi
done

echo -e "\n🔍 Found: ${CSV_NAME#*/}"

# 4. Wait for Operator Success
PHASE=$(oc get "$CSV_NAME" -n "$NS" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Pending")
if [ "$PHASE" == "Succeeded" ]; then
    echo "✅ Operator is already Succeeded."
else
    echo "⏳ Waiting for Operator to reach Succeeded phase..."
    oc wait --for=jsonpath='{.status.phase}'=Succeeded "$CSV_NAME" -n "$NS" --timeout=300s
fi

# 5. API and Storage Readiness
echo "Ensuring CRD and Loki storage are Ready..."
oc wait --for condition=established --timeout=60s crd/flowcollectors.flows.netobserv.io

until oc get pods -n "$NS" -l app=loki 2>/dev/null | grep -q "Running"; do
    printf "."
    sleep 5
done
oc wait --for=condition=Ready pod -l app=loki -n "$NS" --timeout=300s
echo -e "\n✅ Backend storage is Ready."

# 6. Apply FlowCollector
if oc get flowcollector "$FLOW_COLLECTOR_NAME" &> /dev/null; then
    echo "✅ FlowCollector '$FLOW_COLLECTOR_NAME' already exists."
else
    echo "🚀 Applying FlowCollector configuration..."
    oc apply -f flowcollector.yaml
fi

echo "----------------------------------------------------"
echo "🎉 NetObserv is fully operational!"
echo "----------------------------------------------------"