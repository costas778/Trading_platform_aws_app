#!/bin/bash
set -x
set -e

# Define SCRIPT_DIR first
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "${SCRIPT_DIR}")"

# Debug statements
echo "SCRIPT_DIR=${SCRIPT_DIR}"
echo "DEPLOY_ENV=${DEPLOY_ENV}"
echo "tf_dir=${tf_dir}"

# Now use the correct path for removal
rm -f "${SCRIPT_DIR}/infrastructure/terraform/environments/backend.tf"

# Add a trap with the correct path
trap 'rm -f "${SCRIPT_DIR}/infrastructure/terraform/environments/backend.tf"' EXIT

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Source set-env.sh for AWS credentials if it exists
SET_ENV_FILE="${SCRIPT_DIR}/set-env.sh"
if [ -f "${SET_ENV_FILE}" ]; then
    echo -e "${YELLOW}Loading AWS credentials from set-env.sh...${NC}"
    source "${SET_ENV_FILE}"
else
    echo -e "${RED}Warning: set-env.sh not found at ${SET_ENV_FILE}${NC}"
fi

# Verify required variables
if [ -z "${TF_STATE_BUCKET}" ] || [ -z "${TF_LOCK_TABLE}" ] || [ -z "${AWS_DEFAULT_REGION}" ]; then
    echo -e "${RED}Error: Required environment variables not set. Ensure .env file is properly sourced.${NC}"
    exit 1
fi

# Use AWS_DEFAULT_REGION if AWS_REGION is not set
if [ -z "${AWS_REGION}" ]; then
    export AWS_REGION="${AWS_DEFAULT_REGION}"
fi

# Remove any leading and trailing slashes from variables
TF_STATE_BUCKET=$(echo "${TF_STATE_BUCKET}" | sed 's:^/::' | sed 's:/*$::')
DEPLOY_ENV=$(echo "${DEPLOY_ENV}" | sed 's:^/::' | sed 's:/*$::')

setup_terraform_backend() {
    echo "Debug: Creating backend.tf in environment: ${DEPLOY_ENV}"
    
    # Set up environment-specific directory
    local tf_dir="${SCRIPT_DIR}/infrastructure/terraform/environments/${DEPLOY_ENV}"
    echo "Debug: Full path: ${tf_dir}"
    
    echo -e "${YELLOW}Setting up Terraform backend...${NC}"
    
    # First check if the S3 bucket exists
    if ! aws s3api head-bucket --bucket "${TF_STATE_BUCKET}" 2>/dev/null; then
        echo -e "${YELLOW}Creating S3 bucket for Terraform state...${NC}"
        # Create the bucket
        aws s3api create-bucket \
            --bucket "${TF_STATE_BUCKET}" \
            --region "${AWS_REGION}" \
            $(if [ "${AWS_REGION}" != "us-east-1" ]; then echo "--create-bucket-configuration LocationConstraint=${AWS_REGION}"; fi)

        # Enable versioning
        aws s3api put-bucket-versioning \
            --bucket "${TF_STATE_BUCKET}" \
            --versioning-configuration Status=Enabled

        # Enable encryption
        aws s3api put-bucket-encryption \
            --bucket "${TF_STATE_BUCKET}" \
            --server-side-encryption-configuration '{
                "Rules": [
                    {
                        "ApplyServerSideEncryptionByDefault": {
                            "SSEAlgorithm": "AES256"
                        }
                    }
                ]
            }'

        # Block public access
        aws s3api put-public-access-block \
            --bucket "${TF_STATE_BUCKET}" \
            --public-access-block-configuration '{
                "BlockPublicAcls": true,
                "IgnorePublicAcls": true,
                "BlockPublicPolicy": true,
                "RestrictPublicBuckets": true
            }'

        echo -e "${GREEN}S3 bucket created successfully${NC}"
    fi

    # Check if DynamoDB table exists
    if ! aws dynamodb describe-table --table-name "${TF_LOCK_TABLE}" >/dev/null 2>&1; then
        echo -e "${YELLOW}Creating DynamoDB table for state locking...${NC}"
        aws dynamodb create-table \
            --table-name "${TF_LOCK_TABLE}" \
            --attribute-definitions AttributeName=LockID,AttributeType=S \
            --key-schema AttributeName=LockID,KeyType=HASH \
            --provisioned-throughput ReadCapacityUnits=1,WriteCapacityUnits=1 \
            --region "${AWS_REGION}"

        # Wait for table to be active
        aws dynamodb wait table-exists --table-name "${TF_LOCK_TABLE}"
        echo -e "${GREEN}DynamoDB table created successfully${NC}"
    fi

    # Ensure the directory exists
    mkdir -p "${tf_dir}"
    
    # Remove root backend.tf if it exists
    rm -f "${SCRIPT_DIR}/infrastructure/terraform/environments/backend.tf"
    
    echo "Debug: About to create backend.tf with following values:"
    echo "TF_STATE_BUCKET: ${TF_STATE_BUCKET}"
    echo "DEPLOY_ENV: ${DEPLOY_ENV}"
    echo "AWS_REGION: ${AWS_REGION}"
    
    # Create or update environment-specific backend.tf
    cat > "${tf_dir}/backend.tf" <<BACKEND
terraform {
  backend "s3" {
    bucket         = "${TF_STATE_BUCKET}"
    key            = "${DEPLOY_ENV}/terraform.tfstate"
    region         = "${AWS_REGION}"
    dynamodb_table = "${TF_LOCK_TABLE}"
    encrypt        = true
  }
}
BACKEND

    # Initialize Terraform
    cd "${tf_dir}"
    
    # Clean any existing terraform files
    rm -rf .terraform
    rm -f .terraform.lock.hcl

    # Initialize with reconfigure flag
    terraform init -reconfigure

    # Create workspace if it doesn't exist and select it
    terraform workspace select "${DEPLOY_ENV}" || terraform workspace new "${DEPLOY_ENV}"

    cd - > /dev/null
}

# Execute the setup_terraform_backend function
setup_terraform_backend
