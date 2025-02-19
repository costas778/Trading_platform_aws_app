#!/bin/bash

# Set strict error handling
set -euo pipefail

# Constants
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SECRET_PREFIX="/trading-platform/development"

# Logging function
log() {
    local level="$1"
    local message="$2"
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [${level}] ${message}"
}

# Verify AWS identity
verify_aws_identity() {
    log "INFO" "=== Verifying AWS Identity ==="
    
    local account_info
    if account_info=$(aws sts get-caller-identity --output json 2>/dev/null); then
        local account_id=$(echo "$account_info" | jq -r .Account)
        local arn=$(echo "$account_info" | jq -r .Arn)
        
        log "INFO" "Current AWS Identity:"
        log "INFO" "  Account: ${account_id}"
        log "INFO" "  ARN: ${arn}"
        log "INFO" "  Region: ${AWS_DEFAULT_REGION:-not_set}"
        
        # Test Secrets Manager access
        if aws secretsmanager list-secrets --max-items 1 >/dev/null 2>&1; then
            log "INFO" "✓ Secrets Manager access verified"
        else
            log "ERROR" "× Cannot access Secrets Manager"
            return 1
        fi
    else
        log "ERROR" "Failed to get AWS identity information"
        return 1
    fi
}

# Verify secrets exist and are accessible
verify_secrets() {
    log "INFO" "=== Verifying Secrets ==="
    
    local secrets=("db-credentials")
    local success=true
    
    for secret in "${secrets[@]}"; do
        log "INFO" "Checking secret: ${secret}"
        if secret_value=$(aws secretsmanager get-secret-value \
            --secret-id "${SECRET_PREFIX}/${secret}" \
            --query 'SecretString' \
            --output text 2>/dev/null); then
            log "INFO" "✓ Successfully retrieved ${secret}"
            
            # Verify JSON structure without showing values
            if echo "$secret_value" | jq -e . >/dev/null 2>&1; then
                log "INFO" "✓ ${secret} has valid JSON format"
                log "INFO" "Fields present: $(echo "$secret_value" | jq -r 'keys | join(", ")')"
            else
                log "ERROR" "× ${secret} has invalid JSON format"
                success=false
            fi
        else
            log "ERROR" "× Failed to retrieve ${secret}"
            success=false
        fi
    done
    
    return $([ "$success" = true ])
}

# Verify set-env.sh integration
verify_env_integration() {
    log "INFO" "=== Verifying Environment Integration ==="
    
    if [ ! -f "${SCRIPT_DIR}/set-env.sh" ]; then
        log "ERROR" "set-env.sh not found"
        return 1
    fi

    log "INFO" "Testing set-env.sh environment loading..."
    
    # Create temporary test script
    local test_script=$(mktemp)
    cat << 'EOF' > "$test_script"
#!/bin/bash
source ./set-env.sh >/dev/null 2>&1
declare -a vars=(
    "DB_USERNAME"
    "AWS_DEFAULT_REGION"
    "BUILD_VERSION"
    "DOMAIN_NAME"
    "HOSTED_ZONE_ID"
    "TF_STATE_BUCKET"
    "CLUSTER_NAME"
)
for var in "${vars[@]}"; do
    echo "$var=${!var:-not_set}"
done
EOF
    chmod +x "$test_script"

    log "INFO" "Environment variables status:"
    if ! "$test_script"; then
        log "ERROR" "× Failed to load environment from set-env.sh"
        rm "$test_script"
        return 1
    fi
    
    rm "$test_script"
    return 0
}

# Main function
main() {
    log "INFO" "Starting verification of secrets configuration..."
    
    local exit_code=0
    
    # Run verifications
    if ! verify_aws_identity; then
        log "ERROR" "AWS identity verification failed"
        exit_code=1
    fi
    
    if ! verify_secrets; then
        log "ERROR" "Secrets verification failed"
        exit_code=1
    fi
    
    if ! verify_env_integration; then
        log "ERROR" "Environment integration verification failed"
        exit_code=1
    fi
    
    if [ $exit_code -eq 0 ]; then
        log "INFO" "✓ All verifications passed successfully"
    else
        log "ERROR" "× Some verifications failed"
    fi
    
    return $exit_code
}

# Run main function
main
