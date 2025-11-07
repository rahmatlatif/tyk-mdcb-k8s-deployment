# Tyk MDCB Kubernetes Deployment

This repository contains automated scripts to deploy Tyk Control Plane with MDCB and multiple Data Planes on Kubernetes.

## 🏗️ Architecture

- **Control Plane (`tyk-cp`)**: Dashboard, MDCB, Gateway, Pump, Redis, PostgreSQL
- **Data Plane(s) (`tyk-dp`, `tyk-dp-2`, ...)**: Gateway(s) + Redis, connected to MDCB
- **Multi-Data Plane Support**: Deploy unlimited data planes with auto-incremented ports

## 🚀 Quick Start

### Option 1: Deploy Everything at Once (Recommended)
```bash
./deploy-all.sh
```
This will:
1. Deploy dependencies (Redis, PostgreSQL)
2. Deploy control plane (Dashboard, MDCB, Gateway, Pump)
3. Port-forward Dashboard to http://localhost:3000
4. Retrieve org/user credentials and create secrets
5. Deploy first data plane

### Option 2: Deploy Step by Step
```bash
# Step 1: Deploy dependencies (Redis, PostgreSQL)
./01-deploy-dependencies.sh

# Step 2: Deploy control plane
./02-deploy-control-plane.sh

# Step 3: Port-forward Dashboard (in another terminal)
kubectl port-forward -n tyk-cp service/dashboard-svc-tyk-cp-tyk-dashboard 3000:3000

# Step 4: Deploy first data plane
./03-deploy-data-plane.sh

# Step 5: Deploy additional data planes (optional)

# Option A: Deploy additional data planes for the same org
./04-deploy-additional-data-plane.sh  # Creates tyk-dp-2 on port 8081
./04-deploy-additional-data-plane.sh  # Creates tyk-dp-3 on port 8082

# Option B: Deploy new organizations with dedicated data planes (multi-tenant)
./05-deploy-org-with-data-plane.sh "Acme Corp"                    # Uses defaults
./05-deploy-org-with-data-plane.sh "Tech Inc" admin@tech.com     # Custom email
./05-deploy-org-with-data-plane.sh "BigCo" admin@bigco.com pass123  # Custom email and password
```

## 🏢 Multi-Tenant Deployment

Deploy multiple organizations, each with their own isolated data plane:

```bash
# Ensure Dashboard is accessible
kubectl port-forward -n tyk-cp service/dashboard-svc-tyk-cp-tyk-dashboard 3000:3000

# Create organizations with dedicated data planes
./05-deploy-org-with-data-plane.sh "Acme Corp" admin@acme.com secure123
./05-deploy-org-with-data-plane.sh "Tech Startup" admin@techstartup.io password456
./05-deploy-org-with-data-plane.sh "Enterprise Co" admin@enterprise.com complex789

# Each org gets:
# - Unique namespace: tyk-dp-acme-corp, tyk-dp-tech-startup, tyk-dp-enterprise-co
# - Unique port: 8081, 8082, 8083
# - Isolated Redis and Gateway
# - Separate credentials stored in secrets
```

## 📋 Prerequisites

- Kubernetes cluster (minikube, kind, or cloud provider)
- kubectl configured
- Helm 3.x installed
- jq installed (for JSON parsing)

## 🔧 Scripts Overview

### 01-deploy-dependencies.sh
- Cleans up existing `tyk-cp` namespace
- Creates `tyk-cp` namespace
- Deploys **Redis** using Bitnami chart with **latest** image tags (workaround for Bitnami access changes)
- Deploys **PostgreSQL** using Bitnami chart with **latest** image tags
- Disables persistence for clean restarts
- Saves environment variables to `.env.tyk` file

### 02-deploy-control-plane.sh
- Loads environment variables from `.env.tyk` file
- Adds Tyk Helm repository
- Deploys Tyk Control Plane (Dashboard, MDCB, Gateway, Pump)
- Automatically detects and handles:
  - fsGroup errors
  - Bootstrap/license errors
  - Timeout errors
- Installs without hooks when needed (requires manual bootstrap via Dashboard UI)
- Uses PostgreSQL password from `values.yaml` (hardcoded for consistency)

### 03-deploy-data-plane.sh
- Retrieves credentials from `tyk-operator-conf` secret (created by `deploy-all.sh`)
- Checks Dashboard accessibility (requires port-forward)
- Enables hybrid mode for the organization
- Creates `tyk-dp` namespace
- Deploys Redis for data plane (with **latest** image tags)
- Deploys Tyk Data Plane Gateway
- Configures MDCB connection to control plane

### 04-deploy-additional-data-plane.sh
- Deploy additional data planes with auto-incremented namespaces/ports
- Detects existing data planes and creates next in sequence
- Auto-increments:
  - Namespace: `tyk-dp-2`, `tyk-dp-3`, etc.
  - Port: `8081`, `8082`, `8083`, etc.
  - Group ID: `dp-2`, `dp-3`, etc.
- Deploys dedicated Redis + Gateway for each data plane
- Generates unique `values-dp-N.yaml` for each deployment
- All data planes share the same org/user credentials

### 05-deploy-org-with-data-plane.sh
- **NEW**: Multi-tenant deployment - create new org with dedicated data plane
- Creates a new organization via Dashboard API
- Creates admin user for the organization
- Enables hybrid mode for the organization
- Deploys dedicated data plane tied to that specific org
- Each org is isolated with its own:
  - Organization ID
  - User API key
  - Namespace (`tyk-dp-<org-name>`)
  - Redis instance
  - Gateway deployment
  - Port (auto-incremented)
- Stores org credentials in Kubernetes secrets
- Generates org-specific `values-dp-<org-name>.yaml`

### deploy-all.sh
- **Automated end-to-end deployment**
- Runs all deployment scripts in sequence
- Port-forwards Dashboard to http://localhost:3000
- Waits for Dashboard API to be ready
- Retrieves org ID and user API key from Dashboard
- Creates `tyk-operator-conf` secret automatically
- Stores Dashboard port-forward PID in `.pf-dashboard.pid`

### cleanup.sh
- Removes all Tyk namespaces (`tyk-cp`, `tyk-dp*`)
- Cleans up environment files (`.env.tyk`, `values-temp.yaml`)
- Stops port-forwards (if tracked)

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

### ImagePullBackOff / Bitnami Images Not Found
**Problem**: Pods fail with `ImagePullBackOff` and error messages like:
```
Failed to pull image "docker.io/bitnami/redis:7.2.4-debian-12-r9": not found
```

**Cause**: As of September 2025, Bitnami discontinued free access to versioned container images. Only `latest` tags remain freely accessible.

**Solution**: The scripts now use `--set image.tag=latest` overrides for all Bitnami charts. If you installed before this fix:
```bash
# For control plane Redis/PostgreSQL
helm upgrade tyk-redis oci://registry-1.docker.io/bitnamicharts/redis \
  -n tyk-cp --install --version 19.0.2 --reset-values \
  --set image.tag=latest

# For data plane Redis
helm upgrade tyk-redis oci://registry-1.docker.io/bitnamicharts/redis \
  -n tyk-dp --install --version 19.0.2 --reset-values \
  --set image.tag=latest
```

### PostgreSQL Authentication Failed
**Problem**: Dashboard crashes with:
```
error="failed to connect: password authentication failed for user \"postgres\""
```

**Solution**: 
1. Ensure `values.yaml` has `global.postgres.password: trainingdemo`
2. Verify it matches the Helm chart setting in `01-deploy-dependencies.sh`
3. Redeploy control plane:
```bash
helm upgrade --install tyk-cp tyk-helm/tyk-control-plane -n tyk-cp -f values.yaml --no-hooks
```

### Dashboard Not Accessible (Data Plane Script)
**Problem**: `03-deploy-data-plane.sh` fails with "Cannot access Tyk Dashboard at http://localhost:3000"

**Solution**: Port-forward the Dashboard before running the data plane script:
```bash
kubectl port-forward -n tyk-cp service/dashboard-svc-tyk-cp-tyk-dashboard 3000:3000
```
Or use `deploy-all.sh` which handles this automatically.

### Environment Variables Not Saved
**Problem**: Environment variables from `01-deploy-dependencies.sh` are not available in subsequent scripts.

**Solution**: The scripts now automatically save/load environment variables using `.env.tyk` file.

**Manual Fix**: If `.env.tyk` is missing:
```bash
export REDIS_PASSWORD=$(kubectl get secret -n tyk-cp tyk-redis -o jsonpath='{.data.redis-password}' | base64 -d)
export POSTGRES_PASSWORD=$(kubectl get secret -n tyk-cp tyk-postgres-postgresql -o jsonpath='{.data.postgres-password}' | base64 -d)
```

### fsGroup / Bootstrap / Timeout Errors
**Problem**: Installation fails with errors like:
- `fsGroup.*SecurityContext`
- `bootstrap.*failed`
- `timed out waiting for the condition`

**Solution**: The control plane script automatically detects these errors and installs without hooks (Helm pre/post-install jobs), which requires manual Dashboard bootstrap via the UI.

### Redis Connection Failed (Data Plane Gateway)
**Problem**: Gateway logs show Redis connection errors.

**Solution**: Ensure `values-dp.yaml` has correct Redis settings and reapply:
```bash
# values-dp.yaml should have:
# global.redis.addrs:
#   - tyk-redis-master.tyk-dp.svc.cluster.local:6379
# global.redis.passSecret:
#   name: tyk-redis
#   keyName: redis-password

helm upgrade --install tyk-data-plane tyk-helm/tyk-data-plane -n tyk-dp -f values-dp.yaml
kubectl rollout restart deploy/gateway-tyk-data-plane-tyk-gateway -n tyk-dp
```

## 📊 Verification

### Check Pods
```bash
# Control plane
kubectl get pods -n tyk-cp

# Data planes
kubectl get pods -n tyk-dp
kubectl get pods -n tyk-dp-2  # if deployed
kubectl get pods -n tyk-dp-3  # if deployed

# View all data plane namespaces
kubectl get namespaces | grep tyk-dp
```

### Access Dashboard
```bash
# If using deploy-all.sh, Dashboard is already port-forwarded
# Otherwise:
kubectl port-forward service/dashboard-svc-tyk-cp-tyk-dashboard 3000:3000 -n tyk-cp

# Open http://localhost:3000
# Default credentials (if manually bootstrapping):
# Email: default@tyk.io
# Password: 123456
```

### Test Gateways
```bash
# First data plane (tyk-dp)
kubectl port-forward service/gateway-svc-tyk-data-plane-tyk-gateway 8080:8080 -n tyk-dp
curl localhost:8080/hello

# Second data plane (tyk-dp-2)
kubectl port-forward service/gateway-svc-tyk-data-plane-2-tyk-gateway 8081:8081 -n tyk-dp-2
curl localhost:8081/hello

# Third data plane (tyk-dp-3)
kubectl port-forward service/gateway-svc-tyk-data-plane-3-tyk-gateway 8082:8082 -n tyk-dp-3
curl localhost:8082/hello

# Multi-tenant org-specific data planes
kubectl port-forward service/gateway-svc-tyk-dp-acme-corp-tyk-gateway 8081:8081 -n tyk-dp-acme-corp
curl localhost:8081/hello

kubectl port-forward service/gateway-svc-tyk-dp-tech-startup-tyk-gateway 8082:8082 -n tyk-dp-tech-startup
curl localhost:8082/hello
```

### View Organizations and Credentials
```bash
# List all organizations
curl -s -H "admin-auth: 12345" http://localhost:3000/admin/organisations | jq '.organisations[] | {name: .owner_name, id: .id, hybrid: .hybrid_enabled}'

# View specific org's credentials (stored in secret)
kubectl get secret tyk-org-details -n tyk-dp-acme-corp -o jsonpath='{.data}' | jq -r 'to_entries | .[] | "\(.key): \(.value | @base64d)"'

# List all org-specific data plane namespaces
kubectl get namespaces | grep tyk-dp
```

### Expected Gateway Response
```json
{
  "status": "pass",
  "version": "v5.8.1",
  "description": "Tyk GW",
  "details": {
    "redis": {
      "status": "pass",
      "componentType": "datastore",
      "time": "..."
    },
    "rpc": {
      "status": "pass",
      "componentType": "system",
      "time": "..."
    }
  }
}
```

## 🧹 Cleanup

### Remove All Tyk Resources
```bash
./cleanup.sh
```

### Stop Dashboard Port-Forward
```bash
kill $(cat .pf-dashboard.pid) 2>/dev/null || true
rm -f .pf-dashboard.pid
```

### Manual Cleanup
```bash
# Delete all Tyk namespaces
kubectl delete namespace tyk-cp
kubectl delete namespace $(kubectl get namespaces -o name | grep tyk-dp | cut -d/ -f2)

# Remove local files
rm -f .env.tyk values-temp.yaml values-dp-*.yaml .pf-dashboard.pid
```

## 📝 Files

### Deployment Scripts
- `01-deploy-dependencies.sh`: Deploy Redis and PostgreSQL (with latest Bitnami images)
- `02-deploy-control-plane.sh`: Deploy Tyk Control Plane (Dashboard, MDCB, Gateway, Pump)
- `03-deploy-data-plane.sh`: Deploy first data plane
- `04-deploy-additional-data-plane.sh`: Deploy additional data planes for the same org (auto-increments)
- `05-deploy-org-with-data-plane.sh`: Create new organization with dedicated data plane (multi-tenant)
- `deploy-all.sh`: Automated end-to-end deployment
- `cleanup.sh`: Remove all Tyk resources

### Configuration Files
- `values.yaml`: Control plane Helm values
- `values-dp.yaml`: Data plane template Helm values
- `values-dp-N.yaml`: Auto-generated values for additional data planes (N = 2, 3, ...)
- `values-dp-<org-name>.yaml`: Auto-generated values for org-specific data planes (e.g., `values-dp-acme-corp.yaml`)

### Auto-Generated Files (gitignored)
- `.env.tyk`: Environment variables (Redis/PostgreSQL passwords)
- `values-temp.yaml`: Rendered control plane values with substituted variables
- `.pf-dashboard.pid`: Dashboard port-forward process ID

## 🔒 Security Notes

- `.env.tyk` contains sensitive passwords and is gitignored
- PostgreSQL password is hardcoded in `values.yaml` as `trainingdemo` for consistency
- Redis passwords are auto-generated by Bitnami charts
- Passwords are retrieved from Kubernetes secrets
- `tyk-operator-conf` secret stores org ID and user API key
- Environment variables are only stored locally
- Default admin credentials:
  - Email: `default@tyk.io`
  - Password: `123456` (change in production!)
  - Admin secret: `12345` (change in production!)

## ⚠️ Important Notes

### Bitnami Image Changes
- As of September 2025, Bitnami requires paid subscriptions for versioned images
- Scripts use `image.tag=latest` overrides as a workaround
- Consider migrating to alternative charts or self-hosting images for production

### Production Readiness
This deployment is configured for **development/testing**:
- Passwords are hardcoded or predictable
- PostgreSQL persistence is disabled
- Using `latest` image tags (not recommended for production)
- No TLS/SSL encryption configured
- Default admin credentials

For production:
1. Use proper secret management (Vault, Sealed Secrets, etc.)
2. Enable persistence for databases
3. Pin specific image versions
4. Configure TLS/SSL
5. Change all default passwords and secrets
6. Use resource limits and requests
7. Configure proper backup/restore procedures 