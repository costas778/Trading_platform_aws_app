#!/bin/bash

# Set error handling
set -e

# Color codes for output
RED=$(printf '\033[0;31m')
GREEN=$(printf '\033[0;32m')
YELLOW=$(printf '\033[1;33m')
NC=$(printf '\033[0m')

# Configuration
AWS_REGION="${AWS_DEFAULT_REGION}"
ECR_REPOSITORY_PREFIX="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com"

# Define services and their ports
declare -A SERVICES=(
    ["market-data"]="8080"
    ["portfolio-management"]="8081"
    ["risk-management"]="8082"
    ["audit"]="8083"
    ["api-gateway"]="8084"
    ["price-feed"]="8085"
    ["authentication"]="8086"
    ["quote-service"]="8087"
    ["settlement"]="8088"
    ["notification"]="8089"
    ["message-queue"]="8090"
    ["logging"]="8091"
    ["compliance"]="8092"
    ["order-management"]="8093"
    ["reporting"]="8094"
    ["trade-execution"]="8095"
    ["authorization"]="8096"
    ["cache"]="8097"
    ["user-management"]="8098"
    ["position-management"]="8099"
)

# Logging functions
log() {
    printf "${GREEN}[%s] %s${NC}\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

warn() {
    printf "${YELLOW}[%s] WARNING: %s${NC}\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

error() {
    printf "${RED}[%s] ERROR: %s${NC}\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
    exit 1
}

# Setup ECR authentication
setup_ecr_auth() {
    log "Setting up ECR authentication..."
    
    # Get ECR token
    TOKEN=$(aws ecr get-login-password --region ${AWS_DEFAULT_REGION})
    
    # Create or update docker-registry secret
    kubectl create secret docker-registry ecr-secret \
        --docker-server=${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com \
        --docker-username=AWS \
        --docker-password="${TOKEN}" \
        --namespace=default \
        --dry-run=client -o yaml | kubectl apply -f -
    
    # Patch the default service account
    kubectl patch serviceaccount default -n default \
        -p '{"imagePullSecrets": [{"name": "ecr-secret"}]}'
        
    log "ECR authentication setup completed"
}

# Create initial Kubernetes deployments
create_k8s_deployments() {
    log "Creating initial Kubernetes deployments..."
    
    for service in "${!SERVICES[@]}"; do
        PORT="${SERVICES[$service]}"
        DEPLOYMENT_FILE="k8s/${service}-deployment.yaml"
        
        # Create deployment YAML
        cat << EOF > "$DEPLOYMENT_FILE"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${service}
  namespace: default
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ${service}
  template:
    metadata:
      labels:
        app: ${service}
    spec:
      containers:
      - name: ${service}
        image: ${ECR_REPOSITORY_PREFIX}/${service}:latest
        ports:
        - containerPort: ${PORT}
        resources:
          requests:
            memory: "512Mi"
            cpu: "250m"
          limits:
            memory: "1Gi"
            cpu: "500m"
        livenessProbe:
          httpGet:
            path: /actuator/health
            port: ${PORT}
          initialDelaySeconds: 60
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /actuator/health
            port: ${PORT}
          initialDelaySeconds: 30
          periodSeconds: 10
---
apiVersion: v1
kind: Service
metadata:
  name: ${service}
spec:
  selector:
    app: ${service}
  ports:
  - port: ${PORT}
    targetPort: ${PORT}
  type: ClusterIP
EOF

        # Apply the deployment
        log "Creating deployment for ${service}..."
        kubectl apply -f "$DEPLOYMENT_FILE"
    done
}

# Main execution
main() {
    # Create k8s directory if it doesn't exist
    mkdir -p k8s
    
    # Setup ECR authentication
    setup_ecr_auth
    
    # Create deployments
    create_k8s_deployments
    
    log "Initial deployments created successfully!"
}

# Execute main function
main "$@"
