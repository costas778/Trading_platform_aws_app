#!/bin/bash

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Load environment variables
if [ -z "$ENV_FILE" ]; then
    echo -e "${RED}Error: ENV_FILE not set${NC}"
    exit 1
fi

source "$ENV_FILE"

# Setup KMS keys
setup_kms() {
    echo -e "${YELLOW}Setting up KMS keys...${NC}"
    
    # Create KMS key for application secrets
    KMS_KEY_ID=$(aws kms create-key \
        --description "${DEPLOY_ENV} application secrets encryption key" \
        --tags TagKey=Environment,TagValue="${DEPLOY_ENV}" \
        --query 'KeyMetadata.KeyId' \
        --output text)
    
    # Create alias for the key
    aws kms create-alias \
        --alias-name "alias/${DEPLOY_ENV}/app-secrets" \
        --target-key-id "${KMS_KEY_ID}"
    
    # Store KMS key ID in SSM
    aws ssm put-parameter \
        --name "/${DEPLOY_ENV}/kms/app-secrets-key-id" \
        --value "${KMS_KEY_ID}" \
        --type String \
        --overwrite
}

# Setup Secrets Manager
setup_secrets_manager() {
    echo -e "${YELLOW}Setting up Secrets Manager...${NC}"
    
    # Create secrets for database credentials
    aws secretsmanager create-secret \
        --name "/${DEPLOY_ENV}/database/credentials" \
        --description "Database credentials for ${DEPLOY_ENV}" \
        --secret-string "{\"username\":\"${DB_USERNAME}\",\"password\":\"${DB_PASSWORD}\"}" \
        --kms-key-id "${KMS_KEY_ID}"
    
    # Create secrets for API keys
    aws secretsmanager create-secret \
        --name "/${DEPLOY_ENV}/api/keys" \
        --description "API keys for ${DEPLOY_ENV}" \
        --secret-string "{\"key\":\"${API_KEY}\"}" \
        --kms-key-id "${KMS_KEY_ID}"
}

# Configure IAM roles and policies
setup_iam_roles() {
    echo -e "${YELLOW}Setting up IAM roles...${NC}"
    
    # Create EKS service role
    aws iam create-role \
        --role-name "${DEPLOY_ENV}-eks-service-role" \
        --assume-role-policy-document file://iam/eks-trust-policy.json
    
    # Attach required policies
    aws iam attach-role-policy \
        --role-name "${DEPLOY_ENV}-eks-service-role" \
        --policy-arn "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# Validate security setup
validate_security() {
    echo -e "${YELLOW}Validating security setup...${NC}"
    
    # Verify KMS key
    aws kms describe-key \
        --key-id "${KMS_KEY_ID}" >/dev/null || {
        echo -e "${RED}Error: KMS key validation failed${NC}"
        exit 1
    }
    
    # Verify secrets
    aws secretsmanager describe-secret \
        --secret-id "/${DEPLOY_ENV}/database/credentials" >/dev/null || {
        echo -e "${RED}Error: Database credentials secret validation failed${NC}"
        exit 1
    }
    
    echo -e "${GREEN}Security validation completed${NC}"
}

# Main execution
main() {
    setup_kms
    setup_secrets_manager
    setup_iam_roles
    validate_security
}

main
kubectl apply -f security/certificates/certificate-config.yaml
