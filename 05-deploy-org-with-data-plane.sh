#!/bin/bash

# === Deploy Organization with Dedicated Data Plane Script ===
# This script creates a new organization with a user and deploys a dedicated data plane
# This enables multi-tenant deployments where each org has its own data plane

set -e

echo "🏢 Creating New Organization with Dedicated Data Plane..."
echo "=========================================================="

# Check if organization name is provided
if [ -z "$1" ]; then
    echo "❌ ERROR: Organization name is required"
    echo "Usage: $0 <org-name> [user-email] [user-password]"
    echo "Example: $0 acme-corp admin@acme.com password123"
    exit 1
fi

ORG_NAME="$1"
USER_EMAIL="${2:-admin@${ORG_NAME}.com}"
USER_PASSWORD="${3:-changeme123}"

# Sanitize org name for namespace (lowercase, alphanumeric and hyphens only)
ORG_NAMESPACE=$(echo "$ORG_NAME" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g' | sed 's/--*/-/g')
NAMESPACE="tyk-dp-${ORG_NAMESPACE}"

echo "📊 Configuration:"
echo "  - Organization Name: ${ORG_NAME}"
echo "  - User Email: ${USER_EMAIL}"
echo "  - Namespace: ${NAMESPACE}"
echo ""

# 1. Check Dashboard accessibility
echo "🔍 Checking Dashboard accessibility..."
if ! curl -s -H "admin-auth: 12345" http://localhost:3000/admin/organisations > /dev/null 2>&1; then
    echo "❌ ERROR: Cannot access Tyk Dashboard at http://localhost:3000"
    echo "Please ensure the Dashboard is running and accessible. You may need to port-forward:"
    echo "kubectl port-forward service/dashboard-svc-tyk-cp-tyk-dashboard 3000:3000 -n tyk-cp"
    exit 1
fi

# 2. Create new organization
echo "🏢 Creating organization '${ORG_NAME}'..."
CREATE_ORG_RESPONSE=$(curl -s -X POST -H "admin-auth: 12345" -H "Content-Type: application/json" \
    -d "{
        \"owner_name\": \"${ORG_NAME} Admin\",
        \"owner_slug\": \"${ORG_NAMESPACE}\",
        \"cname_enabled\": true,
        \"cname\": \"${ORG_NAMESPACE}.tyk.local\",
        \"hybrid_enabled\": true
    }" \
    http://localhost:3000/admin/organisations)

# Extract org ID
NEW_ORG_ID=$(echo "$CREATE_ORG_RESPONSE" | jq -r '.Meta // empty')

if [ -z "$NEW_ORG_ID" ]; then
    echo "❌ Failed to create organization. Response:"
    echo "$CREATE_ORG_RESPONSE" | jq '.'
    exit 1
fi

echo "✅ Organization created with ID: ${NEW_ORG_ID}"

# 3. Create user for the organization
echo "👤 Creating user for organization..."
CREATE_USER_RESPONSE=$(curl -s -X POST -H "admin-auth: 12345" -H "Content-Type: application/json" \
    -d "{
        \"first_name\": \"${ORG_NAME}\",
        \"last_name\": \"Admin\",
        \"email_address\": \"${USER_EMAIL}\",
        \"password\": \"${USER_PASSWORD}\",
        \"active\": true,
        \"org_id\": \"${NEW_ORG_ID}\"
    }" \
    http://localhost:3000/admin/users)

# Extract user API key
USER_API_KEY=$(echo "$CREATE_USER_RESPONSE" | jq -r '.Message // empty')

if [ -z "$USER_API_KEY" ]; then
    echo "❌ Failed to create user. Response:"
    echo "$CREATE_USER_RESPONSE" | jq '.'
    exit 1
fi

echo "✅ User created with API Key: ${USER_API_KEY:0:12}..."

# 4. Set group ID for this org's data plane
GROUP_ID="${ORG_NAMESPACE}-dp"
echo "🏷️  Using group ID: ${GROUP_ID}"

# 5. Calculate port for this data plane
echo "🔍 Calculating port for data plane..."
EXISTING_DPS=$(kubectl get namespaces -o name | grep -c "namespace/tyk-dp" || echo "0")
NEW_PORT=$((8080 + EXISTING_DPS))
echo "🔌 Gateway will use port: ${NEW_PORT}"

# 6. Create namespace
echo "📦 Creating namespace ${NAMESPACE}..."
kubectl create namespace ${NAMESPACE}

# 7. Create the Kubernetes secret for the data plane
echo "🔐 Creating data plane secret..."
kubectl create secret generic tyk-data-plane-details \
  --from-literal "orgId=${NEW_ORG_ID}" \
  --from-literal "userApiKey=${USER_API_KEY}" \
  --from-literal "groupID=${GROUP_ID}" \
  --namespace ${NAMESPACE}

# Also create a secret with org details for reference
kubectl create secret generic tyk-org-details \
  --from-literal "orgName=${ORG_NAME}" \
  --from-literal "orgId=${NEW_ORG_ID}" \
  --from-literal "userEmail=${USER_EMAIL}" \
  --from-literal "userPassword=${USER_PASSWORD}" \
  --namespace ${NAMESPACE}

echo "✅ Secrets created in namespace ${NAMESPACE}"

# 8. Export the MDCB connection string
export MDCB_CONNECTIONSTRING="mdcb-svc-tyk-cp-tyk-mdcb.tyk-cp.svc:9091"
echo "🔗 MDCB_CONNECTIONSTRING: $MDCB_CONNECTIONSTRING"

# 9. Deploy Redis for this data plane
echo "📦 Deploying Redis for ${ORG_NAME} data plane..."
REDIS_BITNAMI_CHART_VERSION=19.0.2

helm upgrade tyk-redis oci://registry-1.docker.io/bitnamicharts/redis \
  -n ${NAMESPACE} \
  --install \
  --version $REDIS_BITNAMI_CHART_VERSION \
  --set image.registry=docker.io \
  --set image.repository=bitnami/redis \
  --set image.tag=latest \
  --set metrics.image.registry=docker.io \
  --set metrics.image.repository=bitnami/redis-exporter \
  --set metrics.image.tag=latest

# 10. Wait for Redis to be ready
echo "⏳ Waiting for Redis to be ready..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=redis -n ${NAMESPACE} --timeout=300s

# 11. Retrieve the Redis password
export REDIS_PASSWORD=$(kubectl get secret tyk-redis -n ${NAMESPACE} -o jsonpath="{.data.redis-password}" | base64 --decode)
echo "🔑 Redis password retrieved"

# 12. Create values file for this org's data plane
echo "📝 Creating values file for ${ORG_NAME} data plane..."
VALUES_FILE="values-dp-${ORG_NAMESPACE}.yaml"

cat > ${VALUES_FILE} << EOF
# Values for ${ORG_NAME} Data Plane
# Organization: ${ORG_NAME}
# Org ID: ${NEW_ORG_ID}
# Namespace: ${NAMESPACE}
# Auto-generated by 05-deploy-org-with-data-plane.sh

global:
  components:
    pump: false

  servicePorts:
    gateway: ${NEW_PORT}

  remoteControlPlane:
    useSecretName: tyk-data-plane-details
    enabled: true
    connectionString: "${MDCB_CONNECTIONSTRING}"
    useSSL: false
    sslInsecureSkipVerify: true

  mdcbSynchronizer:
    enabled: false
    keySpaceSyncInterval: 10

  tls:
    gateway: false
    useDefaultTykCertificate: true

  secrets:
    APISecret: CHANGEME
    useSecretName: ""

  redis:
    addrs:
      - tyk-redis-master.${NAMESPACE}.svc.cluster.local:6379
    passSecret:
      name: tyk-redis
      keyName: redis-password
    storage:
      database: 0

  hashKeys: true

  streaming:
    enabled: true

tyk-gateway:
  nameOverride: ""
  fullnameOverride: ""

  gateway:
    hostName: ${ORG_NAMESPACE}.tyk.local
    enableFixedWindowRateLimiter: false

    tls:
      secretName: tyk-default-tls-secret
      insecureSkipVerify: false
      certificatesMountPath: "/etc/certs/tyk-gateway"
      certificates:
        - domain_name: "*"
          cert_file: "/etc/certs/tyk-gateway/tls.crt"
          key_file: "/etc/certs/tyk-gateway/tls.key"

    kind: Deployment
    replicaCount: 1
    podAnnotations:
      org-name: "${ORG_NAME}"
      org-id: "${NEW_ORG_ID}"
    podLabels:
      org: "${ORG_NAMESPACE}"
    autoscaling: {}

    image:
      repository: tykio/tyk-gateway
      tag: v5.8.1
      pullPolicy: IfNotPresent

    initContainers:
      setupDirectories:
        repository: busybox
        tag: 1.32
        resources: {}

    imagePullSecrets: []
    containerPort: ${NEW_PORT}

    service:
      type: ClusterIP
      externalTrafficPolicy: Local
      loadBalancerIP: ""
      annotations:
        org-name: "${ORG_NAME}"

    control:
      enabled: false
      containerPort: 9696
      port: 9696
      type: ClusterIP
      annotations: {}

    ingress:
      enabled: false
      className: ""
      annotations: {}
      hosts:
        - host: ${ORG_NAMESPACE}.tyk.local
          paths:
            - path: /
              pathType: ImplementationSpecific
      tls: []

    pdb:
      enabled: false
      minAvailable: ""
      maxUnavailable: ""

    resources: {}
    livenessProbe: {}
    readinessProbe: {}
    startupProbe: {}

    securityContext:
      runAsUser: 1000
      fsGroup: 2000
      runAsNonRoot: true

    containerSecurityContext:
      runAsNonRoot: true
      runAsUser: 1000
      allowPrivilegeEscalation: false
      privileged: false
      readOnlyRootFilesystem: true
      seccompProfile:
        type: RuntimeDefault
      capabilities:
        drop:
          - ALL

    nodeSelector: {}
    tolerations:
      - key: node-role.kubernetes.io/master
        effect: NoSchedule
    affinity: {}

    extraContainers: []
    extraEnvs: []

    sharding:
      enabled: false
      tags: ""

    analyticsEnabled: ""
    analyticsConfigType: ""

    opentelemetry:
      enabled: false

    enablePathPrefixMatching: true
    enablePathSuffixMatching: true
    enableStrictRoutes: true

    extraVolumes: []
    extraVolumeMounts: []

    log:
      level: "debug"
      format: "default"

    accessLogs:
      enabled: false

    allowInsecureConfigs: true
    globalSessionLifetime: 100
    enableCustomDomains: true
    maxIdleConnectionsPerHost: 500

tyk-pump:
  pump:
    replicaCount: 0

tests:
  enabled: false
EOF

echo "✅ Values file created: ${VALUES_FILE}"

# 13. Add Tyk Helm repository
echo "📚 Adding Tyk Helm repository..."
helm repo add tyk-helm https://helm.tyk.io/public/helm/charts/ || true
helm repo update

# 14. Install the data plane
echo "🚀 Installing ${ORG_NAME} Data Plane..."
RELEASE_NAME="tyk-dp-${ORG_NAMESPACE}"

helm upgrade --install ${RELEASE_NAME} tyk-helm/tyk-data-plane \
  -n ${NAMESPACE} \
  -f ${VALUES_FILE}

echo ""
echo "✅ ${ORG_NAME} Organization and Data Plane Deployment Complete!"
echo "================================================================"
echo ""
echo "📋 Organization Details:"
echo "  - Name: ${ORG_NAME}"
echo "  - Org ID: ${NEW_ORG_ID}"
echo "  - User Email: ${USER_EMAIL}"
echo "  - User Password: ${USER_PASSWORD}"
echo "  - API Key: ${USER_API_KEY:0:12}...${USER_API_KEY: -4}"
echo ""
echo "📋 Data Plane Details:"
echo "  - Namespace: ${NAMESPACE}"
echo "  - Group ID: ${GROUP_ID}"
echo "  - Gateway Port: ${NEW_PORT}"
echo "  - Helm Release: ${RELEASE_NAME}"
echo ""
echo "🔗 Access this gateway:"
echo "  kubectl port-forward -n ${NAMESPACE} service/gateway-svc-${RELEASE_NAME}-tyk-gateway ${NEW_PORT}:${NEW_PORT}"
echo "  curl localhost:${NEW_PORT}/hello"
echo ""
echo "🔐 User Credentials (save these):"
echo "  Dashboard URL: http://localhost:3000"
echo "  Email: ${USER_EMAIL}"
echo "  Password: ${USER_PASSWORD}"
echo ""
echo "📊 View organization's data plane:"
echo "  kubectl get pods -n ${NAMESPACE}"
echo "  kubectl get secret tyk-org-details -n ${NAMESPACE} -o yaml"
echo ""

