#!/bin/bash

# === Tyk Complete Deployment Script ===
# This script runs all Tyk deployment scripts in sequence:
# 1. Deploy dependencies (Redis, PostgreSQL) - includes cleanup of existing resources
# 2. Deploy control plane
# 3. Deploy data plane

set -e  # Exit on any error

echo "🚀 Starting Tyk complete deployment..."
echo "======================================"
echo "Note: This will clean up any existing Tyk resources first"
echo ""

# Step 1: Deploy dependencies
echo ""
echo "📦 Step 1: Deploying dependencies (Redis, PostgreSQL)..."
echo "--------------------------------------------------------"
./01-deploy-dependencies.sh

# Step 2: Deploy control plane
echo ""
echo "🎛️  Step 2: Deploying Tyk Control Plane..."
echo "-------------------------------------------"
./02-deploy-control-plane.sh

# Step 3: Port-forward the Dashboard (in background)
echo ""
echo "🛰️  Step 3: Port-forwarding Tyk Dashboard to http://localhost:3000 ..."
echo "--------------------------------------"

# Wait for Dashboard deployment to be available
kubectl wait --for=condition=available deploy/dashboard-tyk-cp-tyk-dashboard -n tyk-cp --timeout=180s || true

# Start port-forward in background and record PID
kubectl port-forward -n tyk-cp service/dashboard-svc-tyk-cp-tyk-dashboard 3000:3000 >/dev/null 2>&1 &
PF_DASHBOARD_PID=$!
echo $PF_DASHBOARD_PID > .pf-dashboard.pid
echo "🔌 Dashboard is being forwarded on http://localhost:3000 (PID: $PF_DASHBOARD_PID)"

# Step 4: Retrieve org/user details and ensure tyk-operator-conf secret exists
echo ""
echo "🧩 Step 4: Retrieving org/user details from Dashboard and updating tyk-operator-conf..."
echo "--------------------------------------"

# Wait for Dashboard API to respond
ATTEMPTS=0
until curl -s -H "admin-auth: 12345" http://localhost:3000/admin/organisations >/dev/null 2>&1 || [ $ATTEMPTS -ge 30 ]; do
  ATTEMPTS=$((ATTEMPTS+1))
  sleep 2
done

if ! curl -s -H "admin-auth: 12345" http://localhost:3000/admin/organisations >/dev/null 2>&1; then
  echo "⚠️  Dashboard API not reachable yet. Skipping secret creation. You can rerun this step manually later."
else
  ORG_ID=$(curl -s -H "admin-auth: 12345" http://localhost:3000/admin/organisations | jq -r '.organisations[0].id // empty')
  USER_API_KEY=$(curl -s -H "admin-auth: 12345" http://localhost:3000/admin/users | jq -r '.users[0].api_key // empty')

  if [ -z "$ORG_ID" ] || [ -z "$USER_API_KEY" ]; then
    echo "⚠️  Could not retrieve ORG_ID or USER_API_KEY from Dashboard. Skipping secret creation."
  else
    kubectl create secret generic tyk-operator-conf -n tyk-cp \
      --from-literal=TYK_AUTH="$USER_API_KEY" \
      --from-literal=TYK_ORG="$ORG_ID" \
      --dry-run=client -o yaml | kubectl apply -f -
    echo "🔐 Secret tyk-operator-conf ensured in namespace tyk-cp."
  fi
fi

# Step 5: Deploy data plane
echo ""
echo "🌐 Step 5: Deploying Tyk Data Plane..."
echo "--------------------------------------"
./03-deploy-data-plane.sh

echo ""
echo "✅ Tyk deployment completed successfully!"
echo "======================================"
echo ""
echo "🎉 Your Tyk installation is now ready!"
echo ""
echo "📋 Next steps:"
echo "1. Access the Dashboard: kubectl port-forward service/dashboard-svc-tyk-cp-tyk-dashboard 3000:3000 -n tyk-cp"
echo "2. Open http://localhost:3000 in your browser"
echo "3. Test the Gateway: kubectl port-forward service/gateway-svc-tyk-data-plane-tyk-gateway 8080:8080 -n tyk-dp"
echo "4. Test with: curl localhost:8080/hello"
echo ""
echo "🔧 To clean up:"
echo "kubectl delete namespace tyk-cp tyk-dp" 