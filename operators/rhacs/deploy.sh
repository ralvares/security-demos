#!/bin/bash

# Exit on any error
set -e

echo "----------------------------------------------------"
echo "🚀 Starting RHACS Deployment"
echo "----------------------------------------------------"

# 1. Install the Operator
echo "Step 1: Installing RHACS Operator..."
oc apply -k operator/

# 2. Wait for the CSV
echo "Waiting for Operator CSV to reach 'Succeeded' phase..."
# We use printf to avoid newline clutter during the wait loop
until oc get csv -n rhacs-operator -l operators.coreos.com/rhacs-operator.rhacs-operator -o jsonpath='{.items[0].status.phase}' 2>/dev/null | grep -q "Succeeded"; do
    printf "."
    sleep 5
done
echo ""
echo "✅ Operator is Succeeded."

# 3. Ensure CRDs are established
echo "Ensuring CRDs are established..."
oc wait --for condition=established --timeout=60s crd/centrals.platform.stackrox.io
oc wait --for condition=established --timeout=60s crd/securedclusters.platform.stackrox.io

# 4. Install Services
echo "Step 2: Deploying Central and SecuredCluster Services..."
oc apply -k service/

echo "----------------------------------------------------"
echo "📡 Monitoring CRS Automation Job..."
echo "----------------------------------------------------"

# 5. Wait for the Job to exist
echo "Waiting for Job 'create-cluster-crs' to be created..."
until oc get job create-cluster-crs -n stackrox &>/dev/null; do
    printf "."
    sleep 2
done
echo ""

# 6. Stream logs with retry logic (FIXED)
echo "Job found. Attempting to attach to logs..."

# We loop 'oc logs' inside 'until'. 
# Because it is a loop condition, 'set -e' will NOT exit the script if it fails.
# Once it succeeds, it streams logs until the job finishes, then breaks the loop.
until oc logs -f job/create-cluster-crs -n stackrox; do
    echo "⏳ Pod is initializing... retrying in 3s..."
    sleep 3
done

echo "----------------------------------------------------"
echo "🔐 RHACS ACCESS CREDENTIALS"
echo "----------------------------------------------------"

# 7. Fetch Route and Password
CENTRAL_URL=$(oc get route central -n stackrox -o jsonpath='{.spec.host}')
ADMIN_PASSWORD=$(oc get secret central-htpasswd -n stackrox -o jsonpath='{.data.password}' | base64 -d)

if [ -n "$CENTRAL_URL" ]; then
    echo "Console URL: https://$CENTRAL_URL"
    echo "Username:    admin"
    echo "Password:    $ADMIN_PASSWORD"
else
    echo "Error: Could not retrieve Central Route. Is Central deployed correctly?"
fi

echo "----------------------------------------------------"
echo "✅ Deployment and Initialization Complete!"