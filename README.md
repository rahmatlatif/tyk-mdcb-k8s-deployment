# Tyk Control Plane and Data Plane Deployment

This repository contains scripts to deploy Tyk Control Plane and Data Plane components on Kubernetes using Helm charts with zero hardcoding of credentials.

## Overview

Tyk is an API Gateway and Management Platform. This deployment includes:

- **Control Plane**: Dashboard, Gateway, MDCB (Multi Data Center Bridge), Pump
- **Data Plane**: Gateway connected to Control Plane via MDCB
- **Dependencies**: Redis and PostgreSQL

## Prerequisites

- Kubernetes cluster (tested with Docker Desktop)
- `kubectl` configured and accessible
- `helm` v3.x installed
- `jq` installed for JSON processing
- `envsubst` available (usually pre-installed)

## Quick Start

### 1. Deploy Dependencies

```bash
./01-deploy-dependencies.sh
```

This script deploys:
- Redis (Bitnami chart v19.0.2)
- PostgreSQL (Bitnami chart v12.12.10)
- Sets environment variables for passwords

### 2. Deploy Control Plane

```bash
./02-deploy-control-plane.sh
```

This script:
- Deploys Tyk Control Plane using environment variables for passwords
- Automatically handles fsGroup errors by using `--no-hooks` if needed
- Provides clear instructions for manual bootstrap if required

### 3. Bootstrap Dashboard (if manual bootstrap required)

If the control plane was installed with `--no-hooks`, you'll need to manually bootstrap:

```bash
# Port-forward the dashboard
kubectl port-forward service/dashboard-svc-tyk-cp-tyk-dashboard 3000:3000 -n tyk-cp

# Open browser to http://localhost:3000
# Follow on-screen instructions to create admin user
# Note down the API key and Org ID
```

### 4. Deploy Data Plane

#### Option A: Automatic (if tyk-operator-conf secret exists)
```bash
./03-deploy-data-plane.sh
```

#### Option B: Manual (if you bootstrapped manually)
```bash
# Set environment variables with your bootstrap credentials
export USER_API_KEY="your_api_key_from_bootstrap"
export ORG_ID="your_org_id_from_bootstrap"

# Run the data plane script
./03-deploy-data-plane.sh
```

## Script Details

### 01-deploy-dependencies.sh
- Creates `tyk-cp` namespace
- Deploys Redis with auto-generated password
- Deploys PostgreSQL with password `trainingdemo`
- Exports `REDIS_PASSWORD` and `POSTGRES_PASSWORD` environment variables

### 02-deploy-control-plane.sh
- Uses environment variables for database passwords (zero hardcoding)
- Automatically detects and handles fsGroup errors
- Deploys Tyk Control Plane components
- Provides clear instructions for manual bootstrap if needed

### 03-deploy-data-plane.sh
- Supports both automatic and manual credential retrieval
- Automatically enables hybrid mode for the organization
- Creates data plane namespace and secrets
- Deploys Redis and Tyk Data Plane
- Connects to Control Plane via MDCB

## Configuration Files

- `values.yaml` - Control Plane configuration with environment variable substitution
- `values-dp.yaml` - Data Plane configuration using Kubernetes secrets

## Verification

### Check Control Plane
```bash
kubectl get pods -n tyk-cp
```

### Check Data Plane
```bash
kubectl get pods -n tyk-dp
```

### Test Data Plane Connection
```bash
kubectl port-forward service/gateway-svc-tyk-data-plane-tyk-gateway 8080:8080 -n tyk-dp
curl localhost:8080/hello
```

Expected response:
```json
{
  "status": "pass",
  "version": "5.8.1",
  "description": "Tyk GW",
  "details": {
    "redis": {"status": "pass"},
    "rpc": {"status": "pass"}
  }
}
```

## Troubleshooting

### fsGroup Errors
The scripts automatically handle fsGroup validation errors by using `--no-hooks` when detected.

### Manual Bootstrap Required
If you see "MANUAL BOOTSTRAP REQUIRED", follow the on-screen instructions to bootstrap the Dashboard manually.

### Missing Credentials
If the data plane script can't find credentials, either:
1. Set environment variables: `export USER_API_KEY="..." && export ORG_ID="..."`
2. Create the secret manually: `kubectl create secret generic tyk-operator-conf -n tyk-cp --from-literal=TYK_AUTH="..." --from-literal=TYK_ORG="..."`

### Port Forward Issues
If port-forward fails, ensure the pods are running:
```bash
kubectl get pods -n tyk-cp
kubectl get pods -n tyk-dp
```

## Architecture

```
┌─────────────────┐    ┌─────────────────┐
│   Control Plane │    │   Data Plane    │
│                 │    │                 │
│ ┌─────────────┐ │    │ ┌─────────────┐ │
│ │  Dashboard  │ │    │ │   Gateway   │ │
│ └─────────────┘ │    │ └─────────────┘ │
│ ┌─────────────┐ │    │ ┌─────────────┐ │
│ │   Gateway   │ │    │ │    Redis    │ │
│ └─────────────┘ │    │ └─────────────┘ │
│ ┌─────────────┐ │    └─────────────────┘
│ │    MDCB     │ │              │
│ └─────────────┘ │              │
│ ┌─────────────┐ │              │
│ │    Pump     │ │              │
│ └─────────────┘ │              │
└─────────────────┘              │
         │                       │
         │                       │
         └─────── MDCB ──────────┘
```

## Security Features

- **Zero Hardcoding**: No passwords or credentials in configuration files
- **Environment Variables**: Sensitive data passed via environment variables
- **Kubernetes Secrets**: Credentials stored in Kubernetes secrets
- **Automatic Cleanup**: Temporary files cleaned up after deployment

## Support

For issues related to:
- **Tyk Charts**: [Tyk Charts Repository](https://github.com/TykTechnologies/tyk-charts)
- **Tyk Documentation**: [Tyk Docs](https://tyk.io/docs/)
- **Kubernetes**: [Kubernetes Documentation](https://kubernetes.io/docs/) 