NAMESPACE=tyk-cp
REDIS_BITNAMI_CHART_VERSION=19.0.2
POSTGRES_BITNAMI_CHART_VERSION=12.12.10

kubectl create namespace $NAMESPACE

helm upgrade tyk-redis oci://registry-1.docker.io/bitnamicharts/redis -n $NAMESPACE --install --version $REDIS_BITNAMI_CHART_VERSION
#helm upgrade tyk-redis oci://registry-1.docker.io/bitnamicharts/redis -n tyk-cp --install --version 19.0.2

#retrieve secret
export REDIS_PASSWORD=$(kubectl get secret -n $NAMESPACE tyk-redis -o jsonpath="{.data.redis-password}" | base64 -d)

echo "REDIS_PASSWORD: $REDIS_PASSWORD"


#POSTGRESQL
helm upgrade tyk-postgres oci://registry-1.docker.io/bitnamicharts/postgresql \
  --install \
  --version "$POSTGRES_BITNAMI_CHART_VERSION" \
  --set auth.database=tyk_analytics \
  --set auth.postgresPassword=trainingdemo \
  -n "$NAMESPACE"

export POSTGRES_PASSWORD=$(kubectl get secret -n $NAMESPACE tyk-postgres-postgresql -o jsonpath="{.data.postgres-password}" | base64 -d)

echo "POSTGRES_PASSWORD: $POSTGRES_PASSWORD"
