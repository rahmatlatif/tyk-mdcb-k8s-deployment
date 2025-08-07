#!/bin/bash

# === Tyk Data Plane Setup Script ===
# This script prepares the environment for deploying Tyk data planes with MDCB.
# It creates the required secrets and exports connection details.
#
# Prerequisites:
# 1. Tyk Control Plane must be deployed and running
# 2. Tyk Dashboard must be accessible (port-forward if needed):
#    kubectl port-forward service/dashboard-svc-tyk-cp-tyk-dashboard 3000:3000 -n tyk-cp
# 3. This script must be run from the same directory as values-dp.yaml
#
# Optional: If you manually bootstrapped the Dashboard, you can set these environment variables:
# export USER_API_KEY="your_api_key_here"
# export ORG_ID="your_org_id_here"

# Load environment variables from .env.tyk file if they exist
if [ -f ".env.tyk" ]; then
    echo "📁 Loading environment variables from .env.tyk file..."
    source .env.tyk
fi

# 1. Set your group ID (edit as needed)
export GROUP_ID=trainingdp # You can use any name for your group.

# 2. Obtain USER_API_KEY and ORG_ID
# First check if they're provided as environment variables (for manual bootstrap)
if [ -n "$USER_API_KEY" ] && [ -n "$ORG_ID" ]; then
    echo "✅ Using provided environment variables for USER_API_KEY and ORG_ID"
    echo "Retrieved USER_API_KEY: ${USER_API_KEY:0:8}..."
    echo "Retrieved ORG_ID: $ORG_ID"
else
    echo "No environment variables found. Attempting to retrieve from tyk-operator-conf secret..."
    
    # Try to get from the control plane namespace (tyk-cp)
    # Note: tyk-operator-conf secret is expected to be present in tyk-cp namespace
    export USER_API_KEY=$(kubectl get secret --namespace tyk-cp tyk-operator-conf -o jsonpath="{.data.TYK_AUTH}" | base64 --decode)
    export ORG_ID=$(kubectl get secret --namespace tyk-cp tyk-operator-conf -o jsonpath="{.data.TYK_ORG}" | base64 --decode)

    # Validate that we got the required values
    if [ -z "$USER_API_KEY" ] || [ -z "$ORG_ID" ]; then
        echo "❌ ERROR: Failed to retrieve USER_API_KEY or ORG_ID from tyk-operator-conf secret"
        echo ""
        echo "This can happen if:"
        echo "1. The Tyk Control Plane was installed with --no-hooks (manual bootstrap)"
        echo "2. The tyk-operator-conf secret doesn't exist"
        echo ""
        echo "To fix this, you can either:"
        echo "A) Set environment variables before running this script:"
        echo "   export USER_API_KEY=\"your_api_key_from_dashboard_bootstrap\""
        echo "   export ORG_ID=\"your_org_id_from_dashboard_bootstrap\""
        echo "   ./03-deploy-data-plane.sh"
        echo ""
        echo "B) Or create the secret manually:"
        echo "   kubectl create secret generic tyk-operator-conf -n tyk-cp \\"
        echo "     --from-literal=TYK_AUTH=\"your_api_key\" \\"
        echo "     --from-literal=TYK_ORG=\"your_org_id\""
        echo ""
        exit 1
    fi
    
    echo "Retrieved USER_API_KEY: ${USER_API_KEY:0:8}..."
    echo "Retrieved ORG_ID: $ORG_ID"
fi

# 3. Check and enable hybrid mode for the organization
echo "Checking hybrid mode status for organization..."

# Check if Dashboard is accessible
if ! curl -s -H "admin-auth: 12345" http://localhost:3000/admin/organisations > /dev/null 2>&1; then
    echo "❌ ERROR: Cannot access Tyk Dashboard at http://localhost:3000"
    echo "Please ensure the Dashboard is running and accessible. You may need to port-forward:"
    echo "kubectl port-forward service/dashboard-svc-tyk-cp-tyk-dashboard 3000:3000 -n tyk-cp"
    exit 1
fi

HYBRID_STATUS=$(curl -s -H "admin-auth: 12345" http://localhost:3000/admin/organisations | jq -r '.organisations[0].hybrid_enabled // "false"')

if [ "$HYBRID_STATUS" = "true" ]; then
    echo "✅ Hybrid mode is already enabled for organization $ORG_ID"
else
    echo "⚠️  Hybrid mode is disabled for organization $ORG_ID"
    echo "Enabling hybrid mode..."
    
    # Get the current organization data
    ORG_DATA=$(curl -s -H "admin-auth: 12345" http://localhost:3000/admin/organisations | jq '.organisations[0]')
    
    # Update the organization with hybrid_enabled: true
    UPDATE_RESPONSE=$(curl -s -X PUT -H "admin-auth: 12345" -H "Content-Type: application/json" \
        -d "$(echo "$ORG_DATA" | jq '.hybrid_enabled = true')" \
        http://localhost:3000/admin/organisations/$ORG_ID)
    
    if echo "$UPDATE_RESPONSE" | jq -e '.Status' > /dev/null 2>&1; then
        echo "✅ Successfully enabled hybrid mode for organization $ORG_ID"
    else
        echo "❌ Failed to enable hybrid mode. Response: $UPDATE_RESPONSE"
        echo "Please ensure the Tyk Dashboard is accessible and the admin credentials are correct."
        exit 1
    fi
fi

# 4. Create the data plane namespace (tyk-dp) if it doesn't exist
kubectl get namespace tyk-dp >/dev/null 2>&1 || kubectl create namespace tyk-dp

# 5. Create the Kubernetes secret for the data plane
kubectl delete secret tyk-data-plane-details -n tyk-dp --ignore-not-found
kubectl create secret generic tyk-data-plane-details \
  --from-literal "orgId=$ORG_ID" \
  --from-literal "userApiKey=$USER_API_KEY" \
  --from-literal "groupID=$GROUP_ID" \
  --namespace tyk-dp

echo "Secret 'tyk-data-plane-details' created in namespace 'tyk-dp'."

# 6. Export the MDCB connection string for same-cluster deployments
export MDCB_CONNECTIONSTRING="mdcb-svc-tyk-cp-tyk-mdcb.tyk-cp.svc:9091"
echo "MDCB_CONNECTIONSTRING: $MDCB_CONNECTIONSTRING"

# === Step 7: Deploy Redis for Data Plane ===
# Set the namespace and Redis Bitnami chart version
NAMESPACE=tyk-dp
REDIS_BITNAMI_CHART_VERSION=19.0.2

# 7.1 Deploy Redis using Helm
echo "Deploying Redis for data plane..."
helm upgrade tyk-redis oci://registry-1.docker.io/bitnamicharts/redis -n $NAMESPACE --install --version $REDIS_BITNAMI_CHART_VERSION

# 7.2 Wait for Redis to be ready
echo "Waiting for Redis to be ready..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=redis -n $NAMESPACE --timeout=300s

# 7.3 Retrieve the Redis password secret
export REDIS_PASSWORD=$(kubectl get secret tyk-redis -n $NAMESPACE -o jsonpath="{.data.redis-password}" | base64 --decode)
echo "REDIS_PASSWORD: $REDIS_PASSWORD"

# === Step 8: Install Tyk Data Plane ===
# 8.1 Add and update the Tyk Helm repo
echo "Adding Tyk Helm repository..."
helm repo add tyk-helm https://helm.tyk.io/public/helm/charts/ || true
helm repo update

# 8.2 First time deploying the data plane
echo "Installing Tyk Data Plane..."
helm install tyk-data-plane tyk-helm/tyk-data-plane -n tyk-dp -f values-dp.yaml || true

# 8.3 Apply new changes to the data plane (upgrade or install)
echo "Upgrading Tyk Data Plane..."
helm upgrade --install tyk-data-plane tyk-helm/tyk-data-plane -n tyk-dp -f values-dp.yaml

echo ""
echo "=== Tyk Data Plane Deployment Complete ==="
echo "The data plane should now be connected to the control plane via MDCB."
echo "You can verify the connection by checking the gateway health endpoint:"
echo "kubectl port-forward service/gateway-svc-tyk-data-plane-tyk-gateway 8080:8080 -n tyk-dp"
echo "curl localhost:8080/hello"
echo ""
echo "Expected response should show:"
echo '{"status":"pass","details":{"redis":{"status":"pass"},"rpc":{"status":"pass"}}}'