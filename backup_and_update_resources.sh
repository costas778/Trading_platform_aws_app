#!/bin/bash

# backup_and_update_resources.sh
set -e

# Configuration
BACKUP_TIME=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="./k8s/backups/${BACKUP_TIME}"
TEMPLATES_DIR="./k8s/templates"
LOG_FILE="resource_update_${BACKUP_TIME}.log"

# Logging function
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "${LOG_FILE}"
}

# Error handling
handle_error() {
    log "ERROR: An error occurred on line $1"
    log "Starting rollback process..."
    rollback
    exit 1
}

trap 'handle_error $LINENO' ERR

# Improved backup function
create_backups() {
    log "Creating backups..."
    
    # Create main backup directory
    mkdir -p "${BACKUP_DIR}"
    
    # Find all deployment files and create backups with directory structure
    find ./k8s/base -name "deployment.yaml" | while read file; do
        if [ -f "${file}" ]; then
            # Create the directory structure in backup location
            backup_path="${BACKUP_DIR}$(dirname ${file})"
            mkdir -p "${backup_path}"
            
            # Copy the file
            cp "${file}" "${backup_path}/$(basename ${file}).bak"
            log "Backed up: ${file}"
        else
            log "WARNING: Could not find ${file}"
        fi
    done
    
    log "Backups created in ${BACKUP_DIR}"
}

# Create resource templates with simplified structure
create_templates() {
    log "Creating resource templates..."
    mkdir -p "${TEMPLATES_DIR}"
    
    # High Resource Template
    cat <<EOF > "${TEMPLATES_DIR}/high-resource-template.yaml"
replicas: 3
resources:
  requests:
    memory: "1Gi"
    cpu: "500m"
  limits:
    memory: "2Gi"
    cpu: "1000m"
EOF

    # Medium Resource Template
    cat <<EOF > "${TEMPLATES_DIR}/medium-resource-template.yaml"
replicas: 2
resources:
  requests:
    memory: "512Mi"
    cpu: "250m"
  limits:
    memory: "1Gi"
    cpu: "500m"
EOF

    # Base Resource Template
    cat <<EOF > "${TEMPLATES_DIR}/base-resource-template.yaml"
replicas: 1
resources:
  requests:
    memory: "512Mi"
    cpu: "250m"
  limits:
    memory: "1Gi"
    cpu: "500m"
EOF
    log "Templates created successfully"
}

# Function to safely update deployment file
update_deployment_file() {
    local file=$1
    local template=$2
    
    # Create a temporary file
    local temp_file=$(mktemp)
    
    # Function to get the container name from deployment file
    get_container_name() {
        grep -A1 "containers:" "$1" | grep "name:" | head -n1 | awk '{print $2}'
    }
    
    # Get container name
    local container_name=$(get_container_name "${file}")
    if [ -z "${container_name}" ]; then
        container_name="app"  # Default container name if not found
    fi

    # Read the entire deployment file
    local deployment_content=$(cat "${file}")
    
    # Extract existing container configuration (excluding resources and replicas)
    local container_config=$(echo "${deployment_content}" | awk '/containers:/{p=1;print;next} /resources:/{p=0} p')
    
    # Create new deployment content
    cat <<EOF > "${temp_file}"
${deployment_content%spec:*}spec:
  replicas: $(grep "replicas:" "${template}" | awk '{print $2}')
  template:
    spec:
      containers:
      - name: ${container_name}
        ${container_config#*name:*$container_name}
        resources:
          requests:
            memory: $(grep "memory:" "${template}" | head -n1 | awk '{print $2}')
            cpu: $(grep "cpu:" "${template}" | head -n1 | awk '{print $2}')
          limits:
            memory: $(grep "memory:" "${template}" | tail -n1 | awk '{print $2}')
            cpu: $(grep "cpu:" "${template}" | tail -n1 | awk '{print $2}')
EOF

    # Preserve any content after the container spec
    echo "${deployment_content}" | awk '/containers:/{p=1} !p{print}' >> "${temp_file}"

    # Validate the new YAML before applying
    if ! kubectl apply --dry-run=client -f "${temp_file}" >/dev/null 2>&1; then
        log "ERROR: YAML validation failed for ${file}"
        rm "${temp_file}"
        return 1
    fi

    # Apply the changes
    mv "${temp_file}" "${file}"
}

# Update configurations with improved YAML handling
update_configurations() {
    log "Updating service configurations..."

    # Function to process service
    process_service() {
        local service=$1
        local template=$2
        
        if [ -d "./k8s/base/trading-services/${service}" ]; then
            log "Processing ${service}..."
            if [ -f "./k8s/base/trading-services/${service}/deployment.yaml" ]; then
                if ! update_deployment_file "./k8s/base/trading-services/${service}/deployment.yaml" "${template}"; then
                    log "ERROR: Failed to update ${service}"
                    return 1
                fi
            else
                log "WARNING: deployment.yaml not found for ${service}"
            fi
        else
            log "WARNING: Directory not found for ${service}"
        fi
    }

    # High Resource Services
    log "Updating high resource services..."
    for service in api-gateway trade-execution market-data authentication authorization; do
        process_service "${service}" "${TEMPLATES_DIR}/high-resource-template.yaml"
    done

    # Medium Resource Services
    log "Updating medium resource services..."
    for service in logging monitoring cache message-queue; do
        process_service "${service}" "${TEMPLATES_DIR}/medium-resource-template.yaml"
    done

    # Base Resource Services
    log "Updating base resource services..."
    for service in $(ls ./k8s/base/trading-services/ 2>/dev/null); do
        if [[ ! " api-gateway trade-execution market-data authentication authorization logging monitoring cache message-queue " =~ " ${service} " ]]; then
            process_service "${service}" "${TEMPLATES_DIR}/base-resource-template.yaml"
        fi
    done
}

# Verify changes
verify_changes() {
    log "Verifying changes..."
    for file in ./k8s/base/trading-services/*/deployment.yaml; do
        if [ -f "${file}" ]; then
            log "=== Checking $(dirname $file) ==="
            kubectl get -f "${file}" -o yaml | grep -A 8 "resources:" >> "${LOG_FILE}" 2>/dev/null || log "No resource configuration found in ${file}"
            kubectl get -f "${file}" -o yaml | grep "replicas:" >> "${LOG_FILE}" 2>/dev/null || log "No replica configuration found in ${file}"
        fi
    done
}

# Apply changes gradually with improved error handling
apply_changes() {
    log "Starting gradual deployment..."
    
    # Function to safely apply deployment
    apply_deployment() {
        local service=$1
        if [ -f "./k8s/base/trading-services/${service}/deployment.yaml" ]; then
            if kubectl apply --dry-run=client -f "./k8s/base/trading-services/${service}/deployment.yaml" >/dev/null 2>&1; then
                kubectl apply -f "./k8s/base/trading-services/${service}/deployment.yaml"
                log "Applied changes for ${service}"
                return 0
            else
                log "ERROR: YAML validation failed for ${service}"
                return 1
            fi
        else
            log "WARNING: deployment.yaml not found for ${service}"
            return 0
        fi
    }
    
    # Base services
    log "Updating base services..."
    for service in reporting audit compliance; do
        apply_deployment "${service}"
    done
    sleep 30
    
    # Medium tier services
    log "Updating medium tier services..."
    for service in logging monitoring cache message-queue; do
        apply_deployment "${service}"
    done
    sleep 30
    
    # High resource services
    log "Updating high resource services..."
    for service in api-gateway trade-execution market-data authentication authorization; do
        apply_deployment "${service}"
    done
}

# Monitor deployment with improved error handling
monitor_deployment() {
    log "Monitoring deployment status..."
    kubectl get pods -w >> "${LOG_FILE}" &
    monitor_pid=$!
    sleep 300  # Monitor for 5 minutes
    kill $monitor_pid 2>/dev/null || true
}

# Improved rollback function
rollback() {
    log "Starting rollback process..."
    if [ -d "${BACKUP_DIR}" ]; then
        find "${BACKUP_DIR}" -type f -name "*.bak" | while read backup_file; do
            # Get the original file path by removing backup dir and .bak extension
            original_file="${backup_file#$BACKUP_DIR}"
            original_file="${original_file%.bak}"
            
            if [ -f "${backup_file}" ]; then
                # Ensure the original directory exists
                mkdir -p "$(dirname "${original_file}")"
                
                # Restore the file
                cp "${backup_file}" "${original_file}"
                log "Restored: ${original_file}"
                
                # Verify YAML syntax
                if ! kubectl apply --dry-run=client -f "${original_file}" >/dev/null 2>&1; then
                    log "WARNING: YAML validation failed for restored file: ${original_file}"
                fi
            else
                log "WARNING: Backup file not found: ${backup_file}"
            fi
        done
        
        log "Reapplying original configurations..."
        kubectl apply -f ./k8s/base/trading-services/*/deployment.yaml || log "WARNING: Error reapplying configurations"
        log "Rollback completed"
    else
        log "ERROR: Backup directory not found: ${BACKUP_DIR}"
        exit 1
    fi
}

# Main execution
main() {
    log "Starting resource update process..."
    create_backups
    create_templates
    update_configurations
    verify_changes
    apply_changes
    monitor_deployment
    log "Resource update completed successfully"
}

# Execute main function
main
