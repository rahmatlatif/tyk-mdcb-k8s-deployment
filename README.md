# Tyk Control Plane Deployment

This repository contains scripts to deploy Tyk Control Plane and Data Plane on Kubernetes.

## 🚀 Quick Start

### Option 1: Deploy Everything at Once
```bash
./deploy-all.sh
```

### Option 2: Deploy Step by Step
```bash
# Step 1: Deploy dependencies (Redis, PostgreSQL)
./01-deploy-dependencies.sh

# Step 2: Deploy control plane
./02-deploy-control-plane.sh

# Step 3: Deploy data plane (after bootstrap)
./03-deploy-data-plane.sh
```

## 📋 Prerequisites

- Kubernetes cluster (minikube, kind, or cloud provider)
- kubectl configured
- Helm 3.x installed
- jq installed (for JSON parsing)

## 🔧 Scripts Overview

### 01-deploy-dependencies.sh
- **Cleans up existing Tyk resources** (namespace, Redis, PostgreSQL)
- Creates `tyk-cp` namespace
- Deploys Redis using Bitnami chart
- Deploys PostgreSQL using Bitnami chart
- **Saves environment variables to `.env.tyk` file**

### 02-deploy-control-plane.sh
- **Loads environment variables from `.env.tyk` file**
- Deploys Tyk Control Plane using Helm
- Handles fsGroup errors automatically
- Provides bootstrap instructions

### 03-deploy-data-plane.sh
- **Loads environment variables from `.env.tyk` file**
- Creates data plane namespace and secrets
- Deploys Tyk Data Plane
- Configures MDCB connection

### deploy-all.sh
- Runs all scripts in sequence
- Provides comprehensive deployment

### cleanup.sh
- Removes all Tyk resources
- Cleans up environment files

## 🔐 Environment Variables

The scripts now handle environment variables properly:

1. **Dependencies script** exports and saves passwords to `.env.tyk`
2. **Subsequent scripts** automatically load from `.env.tyk`
3. **Manual fallback** available if `.env.tyk` is missing

### Environment Variables Used
- `REDIS_PASSWORD`: Redis authentication password
- `POSTGRES_PASSWORD`: PostgreSQL authentication password
- `NAMESPACE`: Kubernetes namespace (default: tyk-cp)

## 🛠️ Troubleshooting

### Environment Variables Not Saved
**Problem**: Environment variables from `01-deploy-dependencies.sh` are not available in subsequent scripts.

**Solution**: The scripts now automatically save/load environment variables using `.env.tyk` file.

**Manual Fix**: If `.env.tyk` is missing, you can manually set the variables:
```bash
export REDIS_PASSWORD=$(kubectl get secret -n tyk-cp tyk-redis -o jsonpath='{.data.redis-password}' | base64 -d)
export POSTGRES_PASSWORD=$(kubectl get secret -n tyk-cp tyk-postgres-postgresql -o jsonpath='{.data.postgres-password}' | base64 -d)
```

### fsGroup Error
**Problem**: Installation fails with fsGroup validation error.

**Solution**: The control plane script automatically detects this and installs without hooks.

### Manual Bootstrap Required
**Problem**: Control plane installed without hooks, requiring manual bootstrap.

**Solution**: Follow the on-screen instructions to manually bootstrap the Dashboard.

## 📊 Verification

### Check Pods
```bash
kubectl get pods -n tyk-cp
kubectl get pods -n tyk-dp
```

### Access Dashboard
```bash
kubectl port-forward service/dashboard-svc-tyk-cp-tyk-dashboard 3000:3000 -n tyk-cp
# Open http://localhost:3000
```

### Test Gateway
```bash
kubectl port-forward service/gateway-svc-tyk-data-plane-tyk-gateway 8080:8080 -n tyk-dp
curl localhost:8080/hello
```

## 🧹 Cleanup

To remove all Tyk resources:
```bash
./cleanup.sh
```

Or manually:
```bash
kubectl delete namespace tyk-cp tyk-dp
rm -f .env.tyk values-temp.yaml
```

## 📝 Files

- `01-deploy-dependencies.sh`: Deploy Redis and PostgreSQL
- `02-deploy-control-plane.sh`: Deploy Tyk Control Plane
- `03-deploy-data-plane.sh`: Deploy Tyk Data Plane
- `deploy-all.sh`: Deploy everything in sequence
- `cleanup.sh`: Remove all resources
- `values.yaml`: Control plane configuration
- `values-dp.yaml`: Data plane configuration
- `.env.tyk`: Environment variables (auto-generated, gitignored)

## 🔒 Security Notes

- `.env.tyk` contains sensitive passwords and is gitignored
- Passwords are retrieved from Kubernetes secrets
- Environment variables are only stored locally 