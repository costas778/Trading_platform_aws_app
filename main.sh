#!/bin/bash

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Set and export ENV_FILE at the beginning
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export ENV_FILE="${SCRIPT_DIR}/.env"
export AWS_DEFAULT_OUTPUT="json"
export TF_VAR_bucket_name=$TF_STATE_BUCKET

BASE_DIR="${SCRIPT_DIR}"

# Check if environment parameter is provided
if [ -z "$1" ]; then
    echo -e "${RED}Error: Environment parameter is required (dev|staging|prod)${NC}"
    exit 1
fi

# Set and export the deployment environment
export DEPLOY_ENV="$1"

# Validate environment
case "${DEPLOY_ENV}" in
    dev|staging|prod)
        echo "Starting deployment for environment: ${DEPLOY_ENV}"
        ;;
    *)
        echo -e "${RED}Error: Invalid environment. Must be one of: dev, staging, prod${NC}"
        exit 1
        ;;
esac

# Load environment variables
if [ ! -f "${ENV_FILE}" ]; then
    echo -e "${RED}Error: .env file not found at ${ENV_FILE}${NC}"
    exit 1
fi
source "${ENV_FILE}"

# Pre-deployment validation
validate_prerequisites() {
    echo -e "${YELLOW}Validating prerequisites...${NC}"
    
    # Check required tools
    for tool in aws kubectl terraform psql flyway jq; do
        if ! command -v $tool &> /dev/null; then
            echo -e "${RED}Error: $tool is required but not installed${NC}"
            exit 1
        fi
    done
    
    # Validate AWS credentials
    aws sts get-caller-identity || {
        echo -e "${RED}Error: Invalid AWS credentials${NC}"
        exit 1
    }
    
    # Handle AWS region - use existing AWS_REGION if set
    if [ -z "${AWS_REGION}" ] && [ -z "${AWS_DEFAULT_REGION}" ]; then
        echo -e "${RED}Error: No AWS region configured${NC}"
        exit 1
    fi
    
    # Export AWS_REGION if not set but AWS_DEFAULT_REGION is available
    if [ -z "${AWS_REGION}" ] && [ -n "${AWS_DEFAULT_REGION}" ]; then
        export AWS_REGION="${AWS_DEFAULT_REGION}"
    fi
    
    # Export AWS_DEFAULT_REGION if not set but AWS_REGION is available
    if [ -z "${AWS_DEFAULT_REGION}" ] && [ -n "${AWS_REGION}" ]; then
        export AWS_DEFAULT_REGION="${AWS_REGION}"
    fi
    
    echo -e "${GREEN}Using AWS Region: ${AWS_REGION}${NC}"
    
    # Check required environment variables
    required_vars=(
        "TF_STATE_BUCKET"
        "TF_LOCK_TABLE"
        "CLUSTER_NAME"
        "DB_USERNAME"
        "DB_PASSWORD"
    )
    
    for var in "${required_vars[@]}"; do
        if [ -z "${!var}" ]; then
            echo -e "${RED}Error: Required environment variable $var is not set${NC}"
            exit 1
        fi
    done
}

# Setup infrastructure
setup_infrastructure() {
    echo -e "${YELLOW}Setting up infrastructure...${NC}"
    
    # Setup Terraform backend
    "${SCRIPT_DIR}/terraform-setup.sh"
    
    # Deploy infrastructure using eks.sh
    "${SCRIPT_DIR}/infrastructure/eks.sh"
    
    # Setup database infrastructure
    "${SCRIPT_DIR}/infrastructure/database.sh"
    
    # Setup monitoring infrastructure
    "${SCRIPT_DIR}/monitoring/cloudwatch.sh"
    "${SCRIPT_DIR}/monitoring/logging.sh"
}

# Deploy applications
deploy_applications() {
    echo -e "${YELLOW}Deploying applications...${NC}"
    
    # Build and push Docker images
    "${SCRIPT_DIR}/deployment/build.sh"
    
    # Deploy services
    "${SCRIPT_DIR}/deployment/deploy.sh"
}

# Monitor deployment
monitor_deployment() {
    echo -e "${YELLOW}Setting up monitoring...${NC}"
    
    # Setup CloudWatch monitoring
    setup_cloudwatch_monitoring
    
    # Setup logging
    setup_logging
    
    # Setup alerts
    setup_alerts
}

# Rollback procedure
rollback() {
    echo -e "${RED}Error occurred. Initiating rollback...${NC}"
    
    # Rollback services
    kubectl rollout undo deployment -n trading-services --all
    
    # Rollback database changes if needed
    for service in ${CORE_SERVICES} ${DEPENDENT_SERVICES} ${BUSINESS_SERVICES}; do
        flyway \
            -url="jdbc:postgresql://${DB_ENDPOINT}:${DB_PORT}/${service}_${DEPLOY_ENV}" \
            -user="${DB_USERNAME}" \
            -password="${DB_PASSWORD}" \
            -locations="filesystem:${SCRIPT_DIR}/infrastructure/migrations/${service}" \
            undo
    done
    
    exit 1
}

# Main execution with proper order and error handling
main() {
    # Trap errors for rollback
    trap 'rollback' ERR
    
    # Stage 1: Validation
    validate_prerequisites
    
    # Stage 2: Infrastructure Setup
    setup_infrastructure
    
    # Stage 3: Database Setup
    "${SCRIPT_DIR}/infrastructure/database.sh"
    
    # Stage 4: Application Deployment
    deploy_applications
    
    # Stage 5: Monitoring Setup
    monitor_deployment
    
    # Stage 6: Post-deployment Validation
    validate_deployment
    
    echo -e "${GREEN}Deployment completed successfully${NC}"
}

# Execute main function
main "$@"
