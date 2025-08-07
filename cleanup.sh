#!/bin/bash

# === Tyk Cleanup Script ===
# This script removes all Tyk resources and cleans up the environment

echo "🧹 Starting Tyk cleanup..."
echo "=========================="

# Remove Tyk namespaces
echo "🗑️  Removing Tyk namespaces..."
kubectl delete namespace tyk-cp --ignore-not-found
kubectl delete namespace tyk-dp --ignore-not-found

# Remove environment file
echo "🗑️  Removing environment file..."
rm -f .env.tyk

# Remove temporary values file if it exists
echo "🗑️  Removing temporary files..."
rm -f values-temp.yaml

echo ""
echo "✅ Tyk cleanup completed!"
echo "All Tyk resources have been removed from your cluster." 