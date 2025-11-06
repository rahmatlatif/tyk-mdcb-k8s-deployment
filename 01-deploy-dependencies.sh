#!/bin/bash

NAMESPACE=tyk-cp
REDIS_BITNAMI_CHART_VERSION=19.0.2
POSTGRES_BITNAMI_CHART_VERSION=12.12.10

# Clean up any existing resources
echo "🧹 Cleaning up any existing Tyk resources..."
kubectl delete namespace $NAMESPACE --ignore-not-found
helm uninstall tyk-redis -n $NAMESPACE --ignore-not-found 2>/dev/null || true
helm uninstall tyk-postgres -n $NAMESPACE --ignore-not-found 2>/dev/null || true

# Wait a moment for cleanup to complete
sleep 3

kubectl create namespace $NAMESPACE

echo "📦 Installing Redis..."
echo "⚠️  Note: Using image overrides to work around Bitnami's image access changes"
helm upgrade tyk-redis oci://registry-1.docker.io/bitnamicharts/redis \
  -n $NAMESPACE \
  --install \
  --version $REDIS_BITNAMI_CHART_VERSION \
  --set image.registry=docker.io \
  --set image.repository=bitnami/redis \
  --set image.tag=latest \
  --set metrics.image.registry=docker.io \
  --set metrics.image.repository=bitnami/redis-exporter \
  --set metrics.image.tag=latest

#retrieve secret
export REDIS_PASSWORD=$(kubectl get secret -n $NAMESPACE tyk-redis -o jsonpath="{.data.redis-password}" | base64 -d)

echo "REDIS_PASSWORD: $REDIS_PASSWORD"


#POSTGRESQL
echo "📦 Installing PostgreSQL..."
echo "⚠️  Note: Using image overrides to work around Bitnami's image access changes"
helm upgrade tyk-postgres oci://registry-1.docker.io/bitnamicharts/postgresql \
  --install \
  --version "$POSTGRES_BITNAMI_CHART_VERSION" \
  --set auth.database=tyk_analytics \
  --set auth.postgresPassword=trainingdemo \
  --set primary.persistence.enabled=false \
  --set image.registry=docker.io \
  --set image.repository=bitnami/postgresql \
  --set image.tag=latest \
  --set metrics.image.registry=docker.io \
  --set metrics.image.repository=bitnami/postgres-exporter \
  --set metrics.image.tag=latest \
  -n "$NAMESPACE"

export POSTGRES_PASSWORD=$(kubectl get secret -n $NAMESPACE tyk-postgres-postgresql -o jsonpath="{.data.postgres-password}" | base64 -d)

echo "POSTGRES_PASSWORD: $POSTGRES_PASSWORD"

# Save environment variables to a file for other scripts to use
cat > .env.tyk << EOF
REDIS_PASSWORD=$REDIS_PASSWORD
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
NAMESPACE=$NAMESPACE
EOF

echo "✅ Environment variables saved to .env.tyk"
echo "You can now run: ./02-deploy-control-plane.sh"
