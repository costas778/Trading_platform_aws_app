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

# Setup ECR repositories
setup_ecr_repos() {
    echo -e "${YELLOW}Setting up ECR repositories...${NC}"
    
    # Create repositories for core services
    for service in ${CORE_SERVICES}; do
        aws ecr create-repository \
            --repository-name "${DEPLOY_ENV}/trading/${service}" \
            --image-scanning-configuration scanOnPush=true \
            --tags Key=Environment,Value="${DEPLOY_ENV}" || true
    done

    # Create repositories for dependent services
    for service in ${DEPENDENT_SERVICES}; do
        aws ecr create-repository \
            --repository-name "${DEPLOY_ENV}/trading/${service}" \
            --image-scanning-configuration scanOnPush=true \
            --tags Key=Environment,Value="${DEPLOY_ENV}" || true
    done

    # Create repositories for business services
    for service in ${BUSINESS_SERVICES}; do
        aws ecr create-repository \
            --repository-name "${DEPLOY_ENV}/trading/${service}" \
            --image-scanning-configuration scanOnPush=true \
            --tags Key=Environment,Value="${DEPLOY_ENV}" || true
    done
    
    # ECR login
    aws ecr get-login-password --region "${AWS_REGION}" | \
    docker login --username AWS --password-stdin "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
}

# Build Docker images
build_images() {
    echo -e "${YELLOW}Building Docker images...${NC}"
    
    # Build core services
    for service in ${CORE_SERVICES}; do
        echo -e "${YELLOW}Building ${service}...${NC}"
        docker build \
            --build-arg ENV="${DEPLOY_ENV}" \
            -t "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${DEPLOY_ENV}/trading/${service}:${BUILD_VERSION}" \
            -f "docker/trading-services/${service}/Dockerfile" .
        
        # Push image
        docker push "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${DEPLOY_ENV}/trading/${service}:${BUILD_VERSION}"
    done

    # Build dependent services
    for service in ${DEPENDENT_SERVICES}; do
        echo -e "${YELLOW}Building ${service}...${NC}"
        docker build \
            --build-arg ENV="${DEPLOY_ENV}" \
            -t "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${DEPLOY_ENV}/trading/${service}:${BUILD_VERSION}" \
            -f "docker/trading-services/${service}/Dockerfile" .
        
        # Push image
        docker push "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${DEPLOY_ENV}/trading/${service}:${BUILD_VERSION}"
    done

    # Build business services
    for service in ${BUSINESS_SERVICES}; do
        echo -e "${YELLOW}Building ${service}...${NC}"
        docker build \
            --build-arg ENV="${DEPLOY_ENV}" \
            -t "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${DEPLOY_ENV}/trading/${service}:${BUILD_VERSION}" \
            -f "docker/trading-services/${service}/Dockerfile" .
        
        # Push image
        docker push "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${DEPLOY_ENV}/trading/${service}:${BUILD_VERSION}"
    done
}

# Run security scans
run_security_scans() {
    echo -e "${YELLOW}Running security scans...${NC}"
    
    for service in ${CORE_SERVICES} ${DEPENDENT_SERVICES} ${BUSINESS_SERVICES}; do
        # Wait for scan completion
        aws ecr wait image-scan-complete \
            --repository-name "${DEPLOY_ENV}/trading/${service}" \
            --image-id imageTag="${BUILD_VERSION}"
        
        # Check scan results
        FINDINGS=$(aws ecr describe-image-scan-findings \
            --repository-name "${DEPLOY_ENV}/trading/${service}" \
            --image-id imageTag="${BUILD_VERSION}" \
            --query 'imageScanFindings.findingSeverityCounts.HIGH' \
            --output text)
        
        if [ "$FINDINGS" -gt 0 ]; then
            echo -e "${RED}High severity vulnerabilities found in ${service}${NC}"
            exit 1
        fi
    done
}

# Validate builds
validate_builds() {
    echo -e "${YELLOW}Validating builds...${NC}"
    
    for service in ${CORE_SERVICES} ${DEPENDENT_SERVICES} ${BUSINESS_SERVICES}; do
        # Check if image exists
        aws ecr describe-images \
            --repository-name "${DEPLOY_ENV}/trading/${service}" \
            --image-ids imageTag="${BUILD_VERSION}" || {
            echo -e "${RED}Error: Image for ${service} not found${NC}"
            exit 1
        }
    done
    
    echo -e "${GREEN}Build validation completed${NC}"
}

# Main execution
main() {
    setup_ecr_repos
    build_images
    run_security_scans
    validate_builds
}

main
