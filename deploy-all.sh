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

# Step 3: Deploy data plane
echo ""
echo "🌐 Step 3: Deploying Tyk Data Plane..."
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