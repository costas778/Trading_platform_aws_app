#!/bin/bash

# Set strict error handling
set -euo pipefail

# Constants and variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="${SCRIPT_DIR}/backups/$(date +%Y%m%d_%H%M%S)"
SECRET_PREFIX="/trading-platform/development"
DRY_RUN=false
ROLLBACK_NEEDED=false
CREATED_SECRETS=()

# Default values for environment variables
: "${AWS_DEFAULT_REGION:=us-east-1}"
: "${DB_USERNAME:=dbmaster}"
: "${DB_PASSWORD:=}"
: "${DB_PORT:=5432}"
: "${DB_INSTANCE_NAME:=db_dev_211125333901}"

# Parse command line options
while getopts "d" opt; do
    case $opt in
        d) DRY_RUN=true ;;
        *) echo "Usage: $0 [-d] (d: dry-run)" && exit 1 ;;
    esac
done

# Logging function
log() {
    local level="$1"
    local message="$2"
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [${level}] ${message}"
}

# Load environment variables
load_environment() {
    if [ -f "${SCRIPT_DIR}/set-env.sh" ]; then
        log "INFO" "Loading environment from set-env.sh"
        if [ "$DRY_RUN" = true ]; then
            log "DRY-RUN" "Would source ${SCRIPT_DIR}/set-env.sh"
        else
            # shellcheck source=/dev/null
            source "${SCRIPT_DIR}/set-env.sh"
        fi
    fi
}

# Check prerequisites
check_prerequisites() {
    local missing_deps=()

    if ! command -v aws >/dev/null 2>&1; then
        missing_deps+=("aws-cli")
    fi

    if ! command -v jq >/dev/null 2>&1; then
        missing_deps+=("jq")
    fi

    if [ ${#missing_deps[@]} -ne 0 ]; then
        log "ERROR" "Missing dependencies: ${missing_deps[*]}"
        log "ERROR" "Please install required dependencies and try again"
        exit 1
    fi

    # Check AWS credentials
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        log "ERROR" "Invalid AWS credentials or no AWS credentials found"
        log "ERROR" "Please configure AWS credentials and try again"
        exit 1
    fi
}

# Backup function
backup_file() {
    local file="$1"
    if [[ -f "$file" ]]; then
        mkdir -p "${BACKUP_DIR}"
        cp "$file" "${BACKUP_DIR}/$(basename "$file").bak"
        log "INFO" "Backed up $file to ${BACKUP_DIR}"
    fi
}

# Rollback function
rollback() {
    log "INFO" "Initiating rollback..."
    
    if [ "$DRY_RUN" = true ]; then
        log "DRY-RUN" "Would restore any backed up files"
        log "DRY-RUN" "Would remove any created secrets"
        return 0
    fi
    
    # Restore backups if they exist
    if [ -d "${BACKUP_DIR}" ]; then
        for file in "${BACKUP_DIR}"/*; do
            if [ -f "$file" ]; then
                cp "$file" "${SCRIPT_DIR}/$(basename "${file%.*}")"
                log "INFO" "Restored: $(basename "${file%.*}")"
            fi
        done
    fi

    # Remove created secrets
    for secret in "${CREATED_SECRETS[@]}"; do
        log "INFO" "Removing secret: $secret"
        aws secretsmanager delete-secret \
            --secret-id "${SECRET_PREFIX}/${secret}" \
            --force-delete-without-recovery \
            --region "${AWS_DEFAULT_REGION}" || true
    done
}

# Setup IAM permissions for Secrets Manager
setup_iam_permissions() {
    log "INFO" "Setting up IAM permissions for Secrets Manager..."
    
    # Get current user/role
    local current_identity
    if ! current_identity=$(aws sts get-caller-identity --query 'Arn' --output text); then
        log "ERROR" "Failed to get current IAM identity"
        return 1
    fi

    if [ "$DRY_RUN" = true ]; then
        log "DRY-RUN" "Would create IAM policy for: $current_identity"
        log "DRY-RUN" "Would setup necessary permissions for Secrets Manager"
        return 0
    fi

    # Create policy document
    local policy_name="TradingPlatformSecretsAccess"
    local account_id=$(aws sts get-caller-identity --query Account --output text)
    
    local policy_document=$(cat << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "secretsmanager:GetSecretValue",
                "secretsmanager:DescribeSecret",
                "secretsmanager:PutSecretValue",
                "secretsmanager:UpdateSecret",
                "secretsmanager:CreateSecret",
                "secretsmanager:DeleteSecret"
            ],
            "Resource": [
                "arn:aws:secretsmanager:${AWS_DEFAULT_REGION}:${account_id}:secret:${SECRET_PREFIX}/*"
            ]
        }
    ]
}
EOF
)

    # Create or update policy
    local policy_arn="arn:aws:iam::${account_id}:policy/${policy_name}"
    
    if ! aws iam get-policy --policy-arn "$policy_arn" 2>/dev/null; then
        log "INFO" "Creating new IAM policy: $policy_name"
        if ! aws iam create-policy \
            --policy-name "$policy_name" \
            --policy-document "$policy_document"; then
            log "ERROR" "Failed to create IAM policy"
            return 1
        fi
    else
        log "INFO" "Updating existing IAM policy: $policy_name"
        if ! aws iam create-policy-version \
            --policy-arn "$policy_arn" \
            --policy-document "$policy_document" \
            --set-as-default; then
            log "ERROR" "Failed to update IAM policy"
            return 1
        fi
        
        # Cleanup old policy versions
        local versions_to_delete=$(aws iam list-policy-versions \
            --policy-arn "$policy_arn" \
            --query 'Versions[?!IsDefaultVersion].VersionId' \
            --output text)
        
        for version in $versions_to_delete; do
            aws iam delete-policy-version \
                --policy-arn "$policy_arn" \
                --version-id "$version"
        done
    fi

    # Attach policy to current user/role if needed
    if [[ $current_identity == *":user/"* ]]; then
        local user_name=$(echo "$current_identity" | cut -d'/' -f2)
        if ! aws iam list-attached-user-policies --user-name "$user_name" \
            --query 'AttachedPolicies[?PolicyArn==`'"$policy_arn"'`].PolicyArn' \
            --output text | grep -q "$policy_arn"; then
            
            log "INFO" "Attaching policy to user: $user_name"
            if ! aws iam attach-user-policy \
                --user-name "$user_name" \
                --policy-arn "$policy_arn"; then
                log "ERROR" "Failed to attach policy to user"
                return 1
            fi
        fi
    elif [[ $current_identity == *":role/"* ]]; then
        local role_name=$(echo "$current_identity" | cut -d'/' -f2)
        if ! aws iam list-attached-role-policies --role-name "$role_name" \
            --query 'AttachedPolicies[?PolicyArn==`'"$policy_arn"'`].PolicyArn' \
            --output text | grep -q "$policy_arn"; then
            
            log "INFO" "Attaching policy to role: $role_name"
            if ! aws iam attach-role-policy \
                --role-name "$role_name" \
                --policy-arn "$policy_arn"; then
                log "ERROR" "Failed to attach policy to role"
                return 1
            fi
        fi
    fi

    return 0
}

# Create or update secret
create_update_secret() {
    local secret_name="$1"
    local secret_value="$2"
    local full_secret_path="${SECRET_PREFIX}/${secret_name}"

    if [ "$DRY_RUN" = true ]; then
        log "DRY-RUN" "Would create/update secret: $secret_name"
        log "DRY-RUN" "Value would be: $secret_value"
        return 0
    fi

    if ! aws secretsmanager describe-secret --secret-id "$full_secret_path" 2>/dev/null; then
        aws secretsmanager create-secret \
            --name "$full_secret_path" \
            --description "Managed by setup_secrets_configuration.sh" \
            --secret-string "$secret_value"
        CREATED_SECRETS+=("$secret_name")
    else
        aws secretsmanager update-secret \
            --secret-id "$full_secret_path" \
            --secret-string "$secret_value"
    fi
}

# Prompt for credentials
prompt_credentials() {
    log "INFO" "Please enter database credentials"
    
    read -p "Enter database username [${DB_USERNAME}]: " input_username
    INPUT_DB_USERNAME=${input_username:-${DB_USERNAME}}
    
    read -s -p "Enter database password: " input_password
    echo
    read -s -p "Confirm database password: " password_confirm
    echo
    
    if [ "$input_password" != "$password_confirm" ]; then
        log "ERROR" "Passwords do not match"
        return 1
    fi
    
    INPUT_DB_PASSWORD=$input_password

    if [ "$DRY_RUN" = true ]; then
        log "DRY-RUN" "Would use username: ${INPUT_DB_USERNAME}"
        log "DRY-RUN" "Would use password: [REDACTED]"
    fi

    return 0
}

# Validate secret
validate_secret() {
    local secret_type="$1"
    local secret_value="$2"
    
    case "$secret_type" in
        "db-credentials")
            if ! echo "$secret_value" | jq -e '.username and .password and .host and .port and .engine' >/dev/null; then
                log "ERROR" "Invalid database credentials format"
                return 1
            fi
            local password=$(echo "$secret_value" | jq -r '.password')
            if [[ ${#password} -lt 8 ]]; then
                log "ERROR" "Password must be at least 8 characters long"
                return 1
            fi
            ;;
    esac
    return 0
}

# Migrate credentials
migrate_credentials() {
    local skip_prompt=${1:-false}
    
    if [ "$skip_prompt" = true ] && [ -n "${DB_PASSWORD:-}" ]; then
        log "INFO" "Using existing credentials from environment"
        return 0
    fi

    # Always prompt for credentials in dry-run mode
    if [ "$DRY_RUN" = true ] || [ "$skip_prompt" = false ]; then
        prompt_credentials || return 1
    fi

    local db_username=${INPUT_DB_USERNAME:-${DB_USERNAME}}
    local db_password=${INPUT_DB_PASSWORD:-${DB_PASSWORD}}
    
    if [ -z "$db_password" ]; then
        log "ERROR" "Database password is required"
        return 1
    fi

    local db_creds
    db_creds=$(cat << EOF
{
    "username": "${db_username}",
    "password": "${db_password}",
    "host": "${DB_INSTANCE_NAME}",
    "port": "${DB_PORT}",
    "engine": "postgres"
}
EOF
)
    
    if validate_secret "db-credentials" "$db_creds"; then
        create_update_secret "db-credentials" "$db_creds"
    else
        log "ERROR" "Invalid database credentials"
        return 1
    fi
}

# Test secrets
test_secrets() {
    log "INFO" "Testing secret retrieval..."
    
    if [ "$DRY_RUN" = true ]; then
        log "DRY-RUN" "Would test retrieving secrets:"
        for secret in "db-credentials"; do
            log "DRY-RUN" "Would verify ${secret} exists and is accessible"
            log "DRY-RUN" "Would validate ${secret} format and content"
        done
        return 0
    fi
    
    local secrets=("db-credentials")
    local success=true
    
    for secret in "${secrets[@]}"; do
        if secret_value=$(aws secretsmanager get-secret-value \
            --secret-id "${SECRET_PREFIX}/${secret}" \
            --query 'SecretString' \
            --output text 2>/dev/null); then
            log "INFO" "✓ Successfully retrieved ${secret}"
            
            if validate_secret "$secret" "$secret_value"; then
                log "INFO" "✓ ${secret} validation passed"
            else
                log "ERROR" "× ${secret} validation failed"
                success=false
            fi
        else
            log "ERROR" "× Failed to retrieve ${secret}"
            success=false
        fi
    done
    
    return $([ "$success" = true ])
}

# Test configuration
test_configuration() {
    log "INFO" "Testing configuration..."
    
    if [ -f "${SCRIPT_DIR}/set-env.sh" ]; then
        if [ "$DRY_RUN" = false ]; then
            source "${SCRIPT_DIR}/set-env.sh"
        else
            log "DRY-RUN" "Would source set-env.sh"
        fi
    fi

    if [ "$DRY_RUN" = false ]; then
        log "INFO" "Testing database connection..."
        if command -v psql >/dev/null 2>&1; then
            PGPASSWORD="${DB_PASSWORD}" psql \
                -h "${DB_INSTANCE_NAME}" \
                -U "${DB_USERNAME}" \
                -p "${DB_PORT}" \
                -c "\l" >/dev/null 2>&1
            
            if [ $? -eq 0 ]; then
                log "INFO" "✓ Database connection successful"
            else
                log "ERROR" "× Database connection failed"
                return 1
            fi
        else
            log "WARN" "psql not installed, skipping database connection test"
        fi
    else
        log "DRY-RUN" "Would test database connection"
        log "DRY-RUN" "Would verify database connectivity using provided credentials"
    fi

    return 0
}

# Main function
main() {
    log "INFO" "Starting secrets configuration setup..."
    if [ "$DRY_RUN" = true ]; then
        log "DRY-RUN" "Running in dry-run mode"
    fi
    
    check_prerequisites
    
    # Load environment if available
    load_environment
    
    # Setup IAM permissions first
    if ! setup_iam_permissions; then
        ROLLBACK_NEEDED=true
        rollback
        exit 1
    fi
    
    # Backup existing files
    mkdir -p "${BACKUP_DIR}"
    
    # Prompt for migration preference
    read -p "Would you like to migrate existing credentials? (y/n): " migrate_existing
    if [[ $migrate_existing =~ ^[Yy]$ ]]; then
        migrate_credentials true || { ROLLBACK_NEEDED=true; rollback; exit 1; }
    else
        migrate_credentials false || { ROLLBACK_NEEDED=true; rollback; exit 1; }
    fi
    
    # Test secrets
    if ! test_secrets; then
        ROLLBACK_NEEDED=true
        rollback
        exit 1
    fi
    
    # Test final configuration
    if ! test_configuration; then
        ROLLBACK_NEEDED=true
        rollback
        exit 1
    fi
    
    if [ "$DRY_RUN" = false ]; then
        log "INFO" "Configuration setup completed successfully"
        log "INFO" "Backup created at: ${BACKUP_DIR}"
    else
        log "DRY-RUN" "Configuration setup would complete successfully"
        log "DRY-RUN" "Would create backup at: ${BACKUP_DIR}"
    fi
}

# Run main function with error handling
trap 'if [ "$ROLLBACK_NEEDED" = true ]; then rollback; fi' EXIT
main
