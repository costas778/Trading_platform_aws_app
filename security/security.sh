#!/bin/bash

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Load environment variables
if [ ! -f .env ]; then
    echo -e "${RED}Error: .env file not found${NC}"
    exit 1
fi
source .env

# Function to create KMS key
create_kms_key() {
    echo -e "${YELLOW}Creating KMS key for ${DEPLOY_ENV} environment...${NC}"
    
    # Create KMS key
    KMS_KEY_ID=$(aws kms create-key \
        --description "Key for ${PROJECT_NAME}-${DEPLOY_ENV}" \
        --tags TagKey=Environment,TagValue=${DEPLOY_ENV} \
        --query 'KeyMetadata.KeyId' \
        --output text)
    
    # Create alias for the key
    aws kms create-alias \
        --alias-name "alias/${PROJECT_NAME}-${DEPLOY_ENV}" \
        --target-key-id "${KMS_KEY_ID}"
        
    echo -e "${GREEN}KMS key created with ID: ${KMS_KEY_ID}${NC}"
    
    # Store KMS key ID in AWS Parameter Store
    aws ssm put-parameter \
        --name "/${PROJECT_NAME}/${DEPLOY_ENV}/kms-key-id" \
        --value "${KMS_KEY_ID}" \
        --type "SecureString" \
        --overwrite
}

# Function to create secrets in AWS Secrets Manager
create_secrets() {
    echo -e "${YELLOW}Creating secrets for ${DEPLOY_ENV} environment...${NC}"
    
    # Database credentials
    aws secretsmanager create-secret \
        --name "/${PROJECT_NAME}/${DEPLOY_ENV}/db-credentials" \
        --description "Database credentials for ${PROJECT_NAME}" \
        --secret-string "{\"username\":\"${DB_USERNAME}\",\"password\":\"${DB_PASSWORD}\"}" \
        --kms-key-id "${KMS_KEY_ID}"
    
    # API keys and other sensitive data
    aws secretsmanager create-secret \
        --name "/${PROJECT_NAME}/${DEPLOY_ENV}/api-keys" \
        --description "API keys for ${PROJECT_NAME}" \
        --secret-string "{\"key1\":\"${API_KEY_1}\",\"key2\":\"${API_KEY_2}\"}" \
        --kms-key-id "${KMS_KEY_ID}"
}

# Function to create Kubernetes secrets
create_k8s_secrets() {
    echo -e "${YELLOW}Creating Kubernetes secrets...${NC}"
    
    # Create namespace if it doesn't exist
    kubectl create namespace ${DEPLOY_ENV} --dry-run=client -o yaml | kubectl apply -f -
    
    # Create secret for database credentials
    kubectl create secret generic db-credentials \
        --from-literal=username=${DB_USERNAME} \
        --from-literal=password=${DB_PASSWORD} \
        --namespace ${DEPLOY_ENV} \
        --dry-run=client -o yaml | kubectl apply -f -
    
    # Create secret for TLS certificates
    kubectl create secret tls tls-secret \
        --cert=${TLS_CERT_PATH} \
        --key=${TLS_KEY_PATH} \
        --namespace ${DEPLOY_ENV} \
        --dry-run=client -o yaml | kubectl apply -f -
}

# Function to validate secrets
validate_secrets() {
    echo -e "${YELLOW}Validating secrets configuration...${NC}"
    
    # Check if KMS key exists
    if ! aws kms describe-key --key-id "alias/${PROJECT_NAME}-${DEPLOY_ENV}" &>/dev/null; then
        echo -e "${RED}Error: KMS key not found${NC}"
        return 1
    fi
    
    # Check if secrets exist in Secrets Manager
    if ! aws secretsmanager describe-secret --secret-id "/${PROJECT_NAME}/${DEPLOY_ENV}/db-credentials" &>/dev/null; then
        echo -e "${RED}Error: Database credentials secret not found${NC}"
        return 1
    fi
    
    # Check if Kubernetes secrets exist
    if ! kubectl get secret db-credentials -n ${DEPLOY_ENV} &>/dev/null; then
        echo -e "${RED}Error: Kubernetes database credentials secret not found${NC}"
        return 1
    fi
    
    echo -e "${GREEN}All secrets validated successfully${NC}"
    return 0
}

# Main execution
main() {
    echo -e "${YELLOW}Starting secrets management setup for ${DEPLOY_ENV} environment...${NC}"
    
    # Create KMS key
    create_kms_key
    
    # Create AWS Secrets Manager secrets
    create_secrets
    
    # Create Kubernetes secrets
    create_k8s_secrets
    
    # Validate all secrets
    validate_secrets
    
    echo -e "${GREEN}Secrets management setup completed successfully${NC}"
}

# Check if environment is provided
if [ -z "${DEPLOY_ENV}" ]; then
    echo -e "${RED}Error: DEPLOY_ENV not set${NC}"
    exit 1
fi

# Execute main function
mainkubectl apply -f security/policies/network-policies.yaml
kubectl apply -f security/policies/rbac.yaml
