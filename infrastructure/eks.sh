#!/bin/bash
set -x 
set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Get absolute paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TERRAFORM_DIR="${PROJECT_ROOT}/infrastructure/terraform/environments/${DEPLOY_ENV}"

# Load environment variables
if [ -z "$ENV_FILE" ]; then
    echo -e "${RED}Error: ENV_FILE not set${NC}"
    exit 1
fi

source "$ENV_FILE"

# Deploy EKS cluster
deploy_eks() {
    echo -e "${YELLOW}Deploying EKS cluster...${NC}"
    
    if [ ! -d "${TERRAFORM_DIR}" ]; then
        echo -e "${RED}Error: Directory ${TERRAFORM_DIR} does not exist${NC}"
        exit 1
    fi
    
    cd "${TERRAFORM_DIR}"
    
    # Initialize terraform without modifying backend configuration
    terraform init
    
    # Plan and apply the EKS resources
    terraform plan -target=module.eks -out=eks.tfplan
    terraform apply eks.tfplan
    
    echo -e "${GREEN}EKS cluster deployed successfully${NC}"
}

# Configure kubectl
configure_kubectl() {
    echo -e "${YELLOW}Configuring kubectl...${NC}"
    
    aws eks update-kubeconfig \
        --name "${CLUSTER_NAME}" \
        --region "${AWS_REGION}"
}

# Validate cluster
validate_cluster() {
    echo -e "${YELLOW}Validating cluster setup...${NC}"
    
    CLUSTER_STATUS=$(aws eks describe-cluster \
        --name "${CLUSTER_NAME}" \
        --query 'cluster.status' \
        --output text)
    
    if [ "$CLUSTER_STATUS" != "ACTIVE" ]; then
        echo -e "${RED}Error: Cluster is not active${NC}"
        exit 1
    fi
    
    kubectl get nodes || {
        echo -e "${RED}Error: Unable to get cluster nodes${NC}"
        exit 1
    }
    
    echo -e "${GREEN}Cluster validation completed${NC}"
}

# Main execution
main() {
    deploy_eks
    configure_kubectl
    validate_cluster
}

main
