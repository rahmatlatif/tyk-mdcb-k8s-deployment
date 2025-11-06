#!/bin/bash

# === Tyk Control Plane Setup Script ===
# This script deploys the Tyk Control Plane using environment variables for passwords.

NAMESPACE=tyk-cp

# Load environment variables from .env.tyk file if they exist and are not already set
if [ -f ".env.tyk" ]; then
    echo "📁 Loading environment variables from .env.tyk file..."
    source .env.tyk
fi

# Check if environment variables are set (from 01-deploy-dependencies.sh)
if [ -z "$REDIS_PASSWORD" ] || [ -z "$POSTGRES_PASSWORD" ]; then
    echo "❌ ERROR: REDIS_PASSWORD and POSTGRES_PASSWORD environment variables are not set."
    echo "Please run 01-deploy-dependencies.sh first to set up Redis and PostgreSQL with their passwords."
    echo ""
    echo "Alternatively, you can set them manually:"
    echo "export REDIS_PASSWORD=\$(kubectl get secret -n $NAMESPACE tyk-redis -o jsonpath='{.data.redis-password}' | base64 -d)"
    echo "export POSTGRES_PASSWORD=\$(kubectl get secret -n $NAMESPACE tyk-postgres-postgresql -o jsonpath='{.data.postgres-password}' | base64 -d)"
    exit 1
fi

echo "Using Redis password: ${REDIS_PASSWORD:0:8}..."
echo "Using PostgreSQL password: ${POSTGRES_PASSWORD:0:8}..."

# Add Tyk Helm repository
helm repo add tyk-helm https://helm.tyk.io/public/helm/charts/ || true
helm repo update

# Create a temporary values file with environment variables substituted
echo "Creating temporary values file with environment variables..."
envsubst < values.yaml > values-temp.yaml

# CONTROL PLANE
echo "Installing Tyk Control Plane..."

# Always uninstall existing release if it exists
if helm list -n $NAMESPACE | grep -q "^tyk-cp[[:space:]]"; then
    echo "⚠️  Existing tyk-cp release found. Uninstalling..."
    helm uninstall tyk-cp -n $NAMESPACE --no-hooks
fi

# Try to install normally first
INSTALL_OUTPUT=$(helm install tyk-cp tyk-helm/tyk-control-plane -n $NAMESPACE -f values-temp.yaml 2>&1)
INSTALL_EXIT_CODE=$?

if [ $INSTALL_EXIT_CODE -eq 0 ]; then
    echo "✅ Tyk Control Plane installed successfully with automatic bootstrap."
    echo ""
    echo "=== NEXT STEPS ==="
    echo "The control plane has been deployed with automatic bootstrap."
            echo "You can now proceed with the data plane deployment:"
        echo "./03-deploy-data-plane.sh"
else
    echo "⚠️  Installation failed. Checking error type..."
    echo "$INSTALL_OUTPUT"
    
    # Check if it's a fsGroup error, bootstrap/license error, or timeout error
    if echo "$INSTALL_OUTPUT" | grep -q "fsGroup.*SecurityContext" || \
       echo "$INSTALL_OUTPUT" | grep -q "bootstrap.*failed\|BackoffLimitExceeded\|failed to parse license" || \
       echo "$INSTALL_OUTPUT" | grep -q "timed out waiting for the condition\|failed post-install"; then
        echo "⚠️  Detected error (fsGroup or bootstrap/license issue). Installing without hooks..."
        
        # Uninstall if it exists
        helm uninstall tyk-cp -n $NAMESPACE --no-hooks 2>/dev/null || true
        
        # Install without hooks
        helm install tyk-cp tyk-helm/tyk-control-plane -n $NAMESPACE -f values-temp.yaml --no-hooks
        
        echo ""
        echo "✅ Tyk Control Plane installed successfully without hooks."
        echo ""
        echo "=== MANUAL BOOTSTRAP REQUIRED ==="
        echo "Since the installation was done without hooks, you need to manually bootstrap the Dashboard:"
        echo ""
        echo "1. Port-forward the Dashboard:"
        echo "   kubectl port-forward service/dashboard-svc-tyk-cp-tyk-dashboard 3000:3000 -n $NAMESPACE"
        echo ""
        echo "2. Open your browser and go to: http://localhost:3000"
        echo ""
        echo "3. Follow the on-screen bootstrap instructions to create your admin user."
        echo ""
        echo "4. After bootstrap is complete, note down the API key and Org ID shown on screen."
        echo ""
        echo "5. Set environment variables for the data plane script:"
        echo "   export USER_API_KEY=\"your_api_key_from_bootstrap\""
        echo "   export ORG_ID=\"your_org_id_from_bootstrap\""
        echo ""
        echo "6. Then run the data plane script:"
        echo "   ./03-deploy-data-plane.sh"
        echo ""
        echo "⚠️  IMPORTANT: Do not proceed with ./03-deploy-data-plane.sh until bootstrap is complete!"
    else
        echo "❌ Installation failed with unknown error. Please check the logs above."
        exit 1
    fi
fi

# Clean up temporary file
rm -f values-temp.yaml

echo ""
echo "=== Tyk Control Plane Deployment Complete ==="
echo "The control plane should now be running with Redis and PostgreSQL configured."
echo "You can verify the deployment by checking the pods:"
echo "kubectl get pods -n $NAMESPACE"
