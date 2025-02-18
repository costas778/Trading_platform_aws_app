#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%dT%H:%M:%S%z')] $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%dT%H:%M:%S%z')] ERROR: $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%dT%H:%M:%S%z')] WARNING: $1${NC}"
}

# Check required environment variables
check_required_vars() {
    log "Checking required environment variables..."
    
    log "Current environment variables status:"
    echo "BUILD_VERSION=${BUILD_VERSION:-NOT SET}"
    echo "DOMAIN_NAME=${DOMAIN_NAME:-NOT SET}"
    echo "HOSTED_ZONE_ID=${HOSTED_ZONE_ID:-NOT SET}"
    echo "TF_STATE_BUCKET=${TF_STATE_BUCKET:-NOT SET}"
    echo "TF_LOCK_TABLE=${TF_LOCK_TABLE:-NOT SET}"
    echo "AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION:-NOT SET}"
    echo "CLUSTER_NAME=${CLUSTER_NAME:-NOT SET}"
    echo "MICROSERVICES=${MICROSERVICES:-NOT SET}"
    
    required_vars=(
        "BUILD_VERSION"
        "DOMAIN_NAME"
        "HOSTED_ZONE_ID"
        "TF_STATE_BUCKET"
        "TF_LOCK_TABLE"
        "AWS_DEFAULT_REGION"
        "CLUSTER_NAME"
        "MICROSERVICES"
        "AWS_ACCESS_KEY_ID"
        "AWS_SECRET_ACCESS_KEY"
    )

    missing_vars=0
    for var in "${required_vars[@]}"; do
        if [ -z "${!var}" ]; then
            error "$var is not set"
            missing_vars=$((missing_vars + 1))
        fi
    done
    
    if [ $missing_vars -gt 0 ]; then
        error "Total missing variables: $missing_vars"
        error "Please check if set-env.sh exists and contains all required variables"
        error "Current working directory: $(pwd)"
        if [ -f "set-env.sh" ]; then
            error "set-env.sh exists but variables are not being set properly"
        else
            error "set-env.sh does not exist in current directory"
        fi
        return 1
    fi
    
    log "All required environment variables are set"
}

# Check AWS credentials
check_aws_credentials() {
    log "Checking AWS credentials..."
    
    if ! aws sts get-caller-identity &>/dev/null; then
        error "Invalid or missing AWS credentials. Please configure AWS CLI first."
        return 1
    fi
    
    log "AWS credentials are valid"
}

# Check if infrastructure exists
check_infrastructure_exists() {
    log "Checking if infrastructure exists..."
    
    # Check VPC
    vpc_count=$(aws ec2 describe-vpcs --filters "Name=tag:Environment,Values=${ENVIRONMENT}" --query 'length(Vpcs)' --output text 2>/dev/null || echo "0")
    if [ "$vpc_count" -eq "0" ]; then
        warn "No VPC found - infrastructure may not be provisioned yet"
        return 1
    fi
    
    # Check EKS
    if ! aws eks describe-cluster --name "${CLUSTER_NAME}" &>/dev/null; then
        warn "No EKS cluster found - infrastructure may not be provisioned yet"
        return 1
    fi
    
    log "Infrastructure exists"
    return 0
}

# Test VPC and Networking
test_networking() {
    log "Testing VPC and Networking..."
    
    # Check VPC exists
    vpc_id=$(aws ec2 describe-vpcs --filters "Name=tag:Environment,Values=${ENVIRONMENT}" --query 'Vpcs[0].VpcId' --output text)
    if [ "$vpc_id" == "None" ] || [ -z "$vpc_id" ]; then
        error "VPC not found"
        return 1
    fi
    
    # Check subnets
    subnet_count=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=${vpc_id}" --query 'length(Subnets)' --output text)
    if [ -z "$subnet_count" ] || [ "$subnet_count" -lt 6 ]; then
        error "Expected at least 6 subnets, found ${subnet_count:-0}"
        return 1
    fi
    
    log "Network tests passed"
}

# Test EKS Cluster
test_eks() {
    log "Testing EKS Cluster..."
    
    # Check if cluster exists first
    if ! aws eks describe-cluster --name "${CLUSTER_NAME}" &>/dev/null; then
        error "EKS cluster ${CLUSTER_NAME} does not exist"
        return 1
    fi
    
    # Check cluster status
    cluster_status=$(aws eks describe-cluster --name "${CLUSTER_NAME}" --query 'cluster.status' --output text)
    if [ "$cluster_status" != "ACTIVE" ]; then
        error "EKS cluster not active: ${cluster_status}"
        return 1
    fi
    
    # Check node groups
    nodegroup_count=$(aws eks list-nodegroups --cluster-name "${CLUSTER_NAME}" --query 'length(nodegroups)' --output text)
    if [ "$nodegroup_count" -lt 1 ]; then
        error "No node groups found"
        return 1
    fi
    
    log "EKS tests passed"
}

# Main test execution
main() {
    log "Starting infrastructure validation..."
    
    # First check required environment variables
    check_required_vars || exit 1
    
    # Then check AWS credentials
    check_aws_credentials || exit 1
    
    # Then check if infrastructure exists
    if ! check_infrastructure_exists; then
        warn "Infrastructure does not exist yet. Please provision it first using Terraform."
        exit 1
    fi
    
    # If we get here, infrastructure exists, so we can test it
    test_networking || exit 1
    test_eks || exit 1
    
    log "All validation tests completed successfully!"
}

main "$@"
