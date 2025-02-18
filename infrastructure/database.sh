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
TERRAFORM_DIR="${BASE_DIR}/infrastructure/terraform"
ENV_DIR="${TERRAFORM_DIR}/environments/${DEPLOY_ENV}"
MIGRATIONS_DIR="${BASE_DIR}/database/migrations"

# Load environment variables
if [ -z "$ENV_FILE" ]; then
    echo -e "${RED}Error: ENV_FILE not set${NC}"
    exit 1
fi

source "$ENV_FILE"

# Deploy database infrastructure
deploy_database() {
    echo -e "${YELLOW}Deploying database infrastructure...${NC}"
    
    cd "${ENV_DIR}"
    
    # Initialize Terraform for RDS
    terraform init \
        -backend-config="bucket=${TF_STATE_BUCKET}" \
        -backend-config="key=${DEPLOY_ENV}/rds/terraform.tfstate" \
        -backend-config="region=${AWS_REGION}"
    
    # Plan and apply RDS infrastructure
    terraform plan -target=module.rds -out=rds.tfplan
    terraform apply rds.tfplan
    
    echo -e "${GREEN}Database infrastructure deployed successfully${NC}"
}

# Configure database security
configure_db_security() {
    echo -e "${YELLOW}Configuring database security...${NC}"
    
    # Get DB security group ID
    DB_SG_ID=$(aws rds describe-db-instances \
        --db-instance-identifier "${DB_INSTANCE_NAME}" \
        --query 'DBInstances[0].VpcSecurityGroups[0].VpcSecurityGroupId' \
        --output text)
    
    # Update security group rules for each service type
    for service in ${CORE_SERVICES} ${DEPENDENT_SERVICES} ${BUSINESS_SERVICES}; do
        aws ec2 authorize-security-group-ingress \
            --group-id "${DB_SG_ID}" \
            --protocol tcp \
            --port "${DB_PORT}" \
            --source-group "${service}-sg-${DEPLOY_ENV}" || true
    done
}

# Initialize databases for all services
initialize_databases() {
    echo -e "${YELLOW}Initializing databases for all services...${NC}"
    
    # Get RDS endpoint
    DB_ENDPOINT=$(aws rds describe-db-instances \
        --db-instance-identifier "${DB_INSTANCE_NAME}" \
        --query 'DBInstances[0].Endpoint.Address' \
        --output text)
    
    # Create databases for core services
    for service in ${CORE_SERVICES}; do
        echo -e "${YELLOW}Initializing database for ${service}...${NC}"
        PGPASSWORD="${DB_PASSWORD}" psql -h "${DB_ENDPOINT}" -U "${DB_USERNAME}" -d postgres <<EOF
CREATE DATABASE ${service}_${DEPLOY_ENV};
GRANT ALL PRIVILEGES ON DATABASE ${service}_${DEPLOY_ENV} TO ${DB_USERNAME};
EOF
    done
    
    # Create databases for dependent services
    for service in ${DEPENDENT_SERVICES}; do
        echo -e "${YELLOW}Initializing database for ${service}...${NC}"
        PGPASSWORD="${DB_PASSWORD}" psql -h "${DB_ENDPOINT}" -U "${DB_USERNAME}" -d postgres <<EOF
CREATE DATABASE ${service}_${DEPLOY_ENV};
GRANT ALL PRIVILEGES ON DATABASE ${service}_${DEPLOY_ENV} TO ${DB_USERNAME};
EOF
    done
    
    # Create databases for business services
    for service in ${BUSINESS_SERVICES}; do
        echo -e "${YELLOW}Initializing database for ${service}...${NC}"
        PGPASSWORD="${DB_PASSWORD}" psql -h "${DB_ENDPOINT}" -U "${DB_USERNAME}" -d postgres <<EOF
CREATE DATABASE ${service}_${DEPLOY_ENV};
GRANT ALL PRIVILEGES ON DATABASE ${service}_${DEPLOY_ENV} TO ${DB_USERNAME};
EOF
    done
}

# Run database migrations
run_migrations() {
    echo -e "${YELLOW}Running database migrations...${NC}"
    
    # Get RDS endpoint
    DB_ENDPOINT=$(aws rds describe-db-instances \
        --db-instance-identifier "${DB_INSTANCE_NAME}" \
        --query 'DBInstances[0].Endpoint.Address' \
        --output text)
    
    # Run migrations for each service
    for service in ${CORE_SERVICES} ${DEPENDENT_SERVICES} ${BUSINESS_SERVICES}; do
        echo -e "${YELLOW}Running migrations for ${service}...${NC}"
        
        if [ -d "${MIGRATIONS_DIR}/${service}" ]; then
            # Using flyway for database migrations
            flyway \
                -url="jdbc:postgresql://${DB_ENDPOINT}:${DB_PORT}/${service}_${DEPLOY_ENV}" \
                -user="${DB_USERNAME}" \
                -password="${DB_PASSWORD}" \
                -locations="filesystem:${MIGRATIONS_DIR}/${service}" \
                migrate
        else
            echo -e "${YELLOW}No migrations found for ${service}${NC}"
        fi
    done
}

# Setup database backups
setup_backups() {
    echo -e "${YELLOW}Setting up database backups...${NC}"
    
    # Configure automated backups with different retention periods based on environment
    case "${DEPLOY_ENV}" in
        "prod")
            BACKUP_RETENTION=35
            BACKUP_WINDOW="00:00-01:00"
            ;;
        "staging")
            BACKUP_RETENTION=14
            BACKUP_WINDOW="01:00-02:00"
            ;;
        *)
            BACKUP_RETENTION=7
            BACKUP_WINDOW="02:00-03:00"
            ;;
    esac
    
    aws rds modify-db-instance \
        --db-instance-identifier "${DB_INSTANCE_NAME}" \
        --backup-retention-period ${BACKUP_RETENTION} \
        --preferred-backup-window "${BACKUP_WINDOW}" \
        --apply-immediately
}

# Setup monitoring and alerts
setup_db_monitoring() {
    echo -e "${YELLOW}Setting up database monitoring...${NC}"
    
    # CPU utilization alarm
    aws cloudwatch put-metric-alarm \
        --alarm-name "${DEPLOY_ENV}-db-high-cpu" \
        --alarm-description "Database CPU utilization exceeded threshold" \
        --metric-name CPUUtilization \
        --namespace AWS/RDS \
        --dimensions Name=DBInstanceIdentifier,Value="${DB_INSTANCE_NAME}" \
        --period 300 \
        --evaluation-periods 2 \
        --threshold 80 \
        --comparison-operator GreaterThanThreshold \
        --statistic Average \
        --alarm-actions "${SNS_TOPIC_ARN}"
    
    # Storage space alarm
    aws cloudwatch put-metric-alarm \
        --alarm-name "${DEPLOY_ENV}-db-storage" \
        --alarm-description "Database free storage space below threshold" \
        --metric-name FreeStorageSpace \
        --namespace AWS/RDS \
        --dimensions Name=DBInstanceIdentifier,Value="${DB_INSTANCE_NAME}" \
        --period 300 \
        --evaluation-periods 2 \
        --threshold 5000000000 \
        --comparison-operator LessThanThreshold \
        --statistic Average \
        --alarm-actions "${SNS_TOPIC_ARN}"
}

# Validate database setup
validate_database() {
    echo -e "${YELLOW}Validating database setup...${NC}"
    
    # Get RDS endpoint
    DB_ENDPOINT=$(aws rds describe-db-instances \
        --db-instance-identifier "${DB_INSTANCE_NAME}" \
        --query 'DBInstances[0].Endpoint.Address' \
        --output text)
    
    # Check database connectivity and existence for each service
    for service in ${CORE_SERVICES} ${DEPENDENT_SERVICES} ${BUSINESS_SERVICES}; do
        echo -e "${YELLOW}Validating database for ${service}...${NC}"
        PGPASSWORD="${DB_PASSWORD}" psql -h "${DB_ENDPOINT}" \
            -U "${DB_USERNAME}" \
            -d "${service}_${DEPLOY_ENV}" \
            -c "SELECT 1;" || {
            echo -e "${RED}Error: Database validation failed for ${service}${NC}"
            exit 1
        }
    done
    
    echo -e "${GREEN}Database validation completed${NC}"
}

# Main execution
main() {
    deploy_database
    configure_db_security
    initialize_databases
    run_migrations
    setup_backups
    setup_db_monitoring
    validate_database
}

main
