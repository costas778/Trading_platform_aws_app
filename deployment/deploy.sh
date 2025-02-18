#!/bin/bash

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Get script directory for relative paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
CONFIG_DIR="${BASE_DIR}/config"
K8S_DIR="${BASE_DIR}/k8s"

# Load environment variables
if [ -z "$ENV_FILE" ]; then
    echo -e "${RED}Error: ENV_FILE not set${NC}"
    exit 1
fi

source "$ENV_FILE"

# Update Kubernetes configs
update_k8s_configs() {
    echo -e "${YELLOW}Updating Kubernetes configurations...${NC}"
    
    # Create trading services namespace
    kubectl create namespace trading-services --dry-run=client -o yaml | kubectl apply -f -
    
    # Update Kubernetes secrets for all services
    kubectl create secret generic trading-secrets \
        --from-literal=DB_PASSWORD="${DB_PASSWORD}" \
        --from-literal=API_KEY="${API_KEY}" \
        --from-literal=JWT_SECRET="${JWT_SECRET}" \
        --from-literal=CACHE_PASSWORD="${CACHE_PASSWORD}" \
        --from-literal=MQ_PASSWORD="${MQ_PASSWORD}" \
        -n trading-services \
        --dry-run=client -o yaml | kubectl apply -f -
    
    # Update ConfigMaps for each service type
    # Core Services ConfigMap
    kubectl create configmap core-services-config \
        --from-file="${CONFIG_DIR}/core-services.yaml" \
        -n trading-services \
        --dry-run=client -o yaml | kubectl apply -f -
        
    # Dependent Services ConfigMap
    kubectl create configmap dependent-services-config \
        --from-file="${CONFIG_DIR}/dependent-services.yaml" \
        -n trading-services \
        --dry-run=client -o yaml | kubectl apply -f -
        
    # Business Services ConfigMap
    kubectl create configmap business-services-config \
        --from-file="${CONFIG_DIR}/business-services.yaml" \
        -n trading-services \
        --dry-run=client -o yaml | kubectl apply -f -
}

# Deploy applications in order
deploy_applications() {
    echo -e "${YELLOW}Deploying applications...${NC}"
    
    # Deploy Core Services First
    echo -e "${YELLOW}Deploying Core Services...${NC}"
    for service in ${CORE_SERVICES}; do
        echo -e "${YELLOW}Deploying ${service}...${NC}"
        kubectl apply -f "${K8S_DIR}/base/trading-services/${service}/"
        kubectl rollout status deployment/${service} -n trading-services --timeout=300s
    done
    
    # Deploy Dependent Services
    echo -e "${YELLOW}Deploying Dependent Services...${NC}"
    for service in ${DEPENDENT_SERVICES}; do
        echo -e "${YELLOW}Deploying ${service}...${NC}"
        kubectl apply -f "${K8S_DIR}/base/trading-services/${service}/"
        kubectl rollout status deployment/${service} -n trading-services --timeout=300s
    done
    
    # Deploy Business Services
    echo -e "${YELLOW}Deploying Business Services...${NC}"
    for service in ${BUSINESS_SERVICES}; do
        echo -e "${YELLOW}Deploying ${service}...${NC}"
        kubectl apply -f "${K8S_DIR}/base/trading-services/${service}/"
        kubectl rollout status deployment/${service} -n trading-services --timeout=300s
    done
}

# Setup ingress for all services
setup_ingress() {
    echo -e "${YELLOW}Setting up ingress...${NC}"
    
    # Apply ingress configuration for all services
    kubectl apply -f "${K8S_DIR}/overlays/${DEPLOY_ENV}/trading-ingress.yaml"
    
    # Wait for ALB provisioning
    sleep 30
    
    # Get ALB DNS name
    ALB_DNS=$(kubectl get ingress -n trading-services -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}')
    
    if [ -n "${DOMAIN_NAME}" ] && [ -n "${HOSTED_ZONE_ID}" ]; then
        # Update DNS for trading platform
        aws route53 change-resource-record-sets \
            --hosted-zone-id "${HOSTED_ZONE_ID}" \
            --change-batch "{
                \"Changes\": [{
                    \"Action\": \"UPSERT\",
                    \"ResourceRecordSet\": {
                        \"Name\": \"trading.${DEPLOY_ENV}.${DOMAIN_NAME}\",
                        \"Type\": \"CNAME\",
                        \"TTL\": 300,
                        \"ResourceRecords\": [{
                            \"Value\": \"${ALB_DNS}\"
                        }]
                    }
                }]
            }"
        echo -e "${GREEN}DNS record updated for trading.${DEPLOY_ENV}.${DOMAIN_NAME}${NC}"
    fi
}

# Health checks for all services
perform_health_checks() {
    echo -e "${YELLOW}Performing health checks...${NC}"
    
    # Wait for services to be ready
    sleep 30
    
    # Get the service endpoint
    SERVICE_ENDPOINT="trading.${DEPLOY_ENV}.${DOMAIN_NAME}"
    
    # Check each service's health endpoint
    for service in ${CORE_SERVICES} ${DEPENDENT_SERVICES} ${BUSINESS_SERVICES}; do
        HEALTH_URL="https://${SERVICE_ENDPOINT}/api/${service}/health"
        echo -e "${YELLOW}Checking health for ${service} at ${HEALTH_URL}${NC}"
        curl -sf "${HEALTH_URL}" || {
            echo -e "${RED}Health check failed for ${service}${NC}"
            return 1
        }
        echo -e "${GREEN}Health check passed for ${service}${NC}"
    done
}

# Rollback procedure
rollback() {
    echo -e "${RED}Deployment failed, initiating rollback...${NC}"
    
    # Rollback all services to previous version
    for service in ${CORE_SERVICES} ${DEPENDENT_SERVICES} ${BUSINESS_SERVICES}; do
        echo -e "${YELLOW}Rolling back ${service}...${NC}"
        kubectl rollout undo deployment/${service} -n trading-services
        kubectl rollout status deployment/${service} -n trading-services --timeout=300s
    done
    
    echo -e "${YELLOW}Rollback completed${NC}"
    exit 1
}

# Validate deployment
validate_deployment() {
    echo -e "${YELLOW}Validating deployment...${NC}"
    
    # Check pod status for all services
    for service in ${CORE_SERVICES} ${DEPENDENT_SERVICES} ${BUSINESS_SERVICES}; do
        FAILED_PODS=$(kubectl get pods -n trading-services -l app=${service} --field-selector status.phase!=Running,status.phase!=Succeeded -o name)
        if [ -n "${FAILED_PODS}" ]; then
            echo -e "${RED}Failed pods detected for ${service}${NC}"
            echo "${FAILED_PODS}"
            rollback
        fi
    done
    
    echo -e "${GREEN}Deployment validation completed${NC}"
}

# Main execution
main() {
    update_k8s_configs
    deploy_applications
    setup_ingress
    perform_health_checks
    validate_deployment
}

# Trap errors
trap 'rollback' ERR

main
