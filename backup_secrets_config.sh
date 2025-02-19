#!/bin/bash
# backup_secrets_config.sh

# Color codes for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Paths
BACKUP_DIR="/home/costas778/abc/trading-platform/backups"
ROOT_DIR="/home/costas778/abc/trading-platform"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Function to print section headers
print_header() {
    echo -e "\n${BLUE}=== $1 ===${NC}\n"
}

# Function to list files in backup
list_backup_contents() {
    local backup_file="$1"
    echo -e "${YELLOW}Contents of backup:${NC}"
    tar -tvf "$backup_file" | while read -r line; do
        echo "  → $line"
    done
}

# Create backup
create_backup() {
    print_header "Creating Backup"
    
    # Create backup directory if it doesn't exist
    mkdir -p "$BACKUP_DIR"
    
    echo -e "${YELLOW}The following files will be backed up:${NC}"
    echo -e "  → infrastructure/terraform/modules/secrets/"
    echo -e "  → infrastructure/terraform/environments/dev/terraform.tfvars"
    echo -e "  → .env"
    echo -e "  → set-env.sh"
    
    # Create tar archive
    local backup_file="${BACKUP_DIR}/secrets_config_${TIMESTAMP}.tar.gz"
    tar -czf "$backup_file" \
        -C "$ROOT_DIR" \
        infrastructure/terraform/modules/secrets \
        infrastructure/terraform/environments/dev/terraform.tfvars \
        .env \
        set-env.sh
    
    if [ $? -eq 0 ]; then
        print_header "Backup Successful"
        echo -e "${GREEN}Backup created at:${NC}"
        echo -e "  $backup_file"
        
        # List contents of backup
        list_backup_contents "$backup_file"
        
        print_header "Restore Instructions"
        echo -e "To restore this backup, use either of these commands:"
        echo -e "${YELLOW}1. Restore this specific backup:${NC}"
        echo -e "  ./backup_secrets_config.sh --restore $backup_file"
        echo -e "\n${YELLOW}2. Restore the latest backup:${NC}"
        echo -e "  ./backup_secrets_config.sh --restore"
    else
        echo -e "${RED}Backup creation failed${NC}"
        exit 1
    fi
}

# Restore from backup
restore_backup() {
    local backup_file="$1"
    
    print_header "Starting Restore Process"
    
    # If no backup file specified, use most recent
    if [ -z "$backup_file" ]; then
        backup_file=$(ls -t "${BACKUP_DIR}"/secrets_config_*.tar.gz | head -1)
        echo -e "${YELLOW}No specific backup file provided. Using most recent:${NC}"
        echo -e "  $backup_file"
    fi
    
    if [ ! -f "$backup_file" ]; then
        echo -e "${RED}Error: Backup file not found!${NC}"
        exit 1
    fi
    
    # Create pre-restore backup
    local pre_restore_backup="${BACKUP_DIR}/pre_restore_${TIMESTAMP}.tar.gz"
    echo -e "${YELLOW}Creating safety backup before restore:${NC}"
    echo -e "  $pre_restore_backup"
    
    tar -czf "$pre_restore_backup" \
        -C "$ROOT_DIR" \
        infrastructure/terraform/modules/secrets \
        infrastructure/terraform/environments/dev/terraform.tfvars \
        .env \
        set-env.sh
    
    print_header "Restoring Files"
    echo -e "${YELLOW}Restoring from:${NC} $backup_file"
    
    # List what will be restored
    echo -e "\n${YELLOW}Files to be restored:${NC}"
    list_backup_contents "$backup_file"
    
    # Perform restore
    tar -xzf "$backup_file" -C "$ROOT_DIR"
    
    if [ $? -eq 0 ]; then
        print_header "Restore Completed Successfully"
        echo -e "${GREEN}✓ All files have been restored${NC}"
        echo -e "\n${YELLOW}Safety backup created at:${NC}"
        echo -e "  $pre_restore_backup"
        echo -e "\n${YELLOW}To undo this restore, use:${NC}"
        echo -e "  ./backup_secrets_config.sh --restore $pre_restore_backup"
    else
        echo -e "${RED}Restore failed${NC}"
        echo -e "${YELLOW}You can attempt to restore using the safety backup:${NC}"
        echo -e "  ./backup_secrets_config.sh --restore $pre_restore_backup"
        exit 1
    fi
}

# List available backups
list_backups() {
    print_header "Available Backups"
    
    if ls "${BACKUP_DIR}"/secrets_config_*.tar.gz >/dev/null 2>&1; then
        echo -e "${YELLOW}Backup files:${NC}"
        ls -lh "${BACKUP_DIR}"/secrets_config_*.tar.gz | while read -r line; do
            echo -e "  → $line"
        done
        
        echo -e "\n${YELLOW}To restore a specific backup:${NC}"
        echo -e "  ./backup_secrets_config.sh --restore <backup_file_path>"
        echo -e "\n${YELLOW}To restore the most recent backup:${NC}"
        echo -e "  ./backup_secrets_config.sh --restore"
    else
        echo -e "${RED}No backups found in ${BACKUP_DIR}${NC}"
    fi
}

# Show help
show_help() {
    print_header "Backup and Restore Help"
    echo -e "Usage: $0 [OPTIONS]"
    echo -e "\nOptions:"
    echo -e "  ${YELLOW}--backup${NC}              Create new backup"
    echo -e "  ${YELLOW}--restore [file]${NC}      Restore from backup (uses latest if file not specified)"
    echo -e "  ${YELLOW}--list${NC}               List available backups"
    echo -e "  ${YELLOW}--help${NC}               Show this help message"
    echo -e "\nExamples:"
    echo -e "  Create backup:     ${GREEN}$0 --backup${NC}"
    echo -e "  List backups:      ${GREEN}$0 --list${NC}"
    echo -e "  Restore latest:    ${GREEN}$0 --restore${NC}"
    echo -e "  Restore specific:  ${GREEN}$0 --restore /path/to/backup.tar.gz${NC}"
}

# Parse command line arguments
case "$1" in
    --backup)
        create_backup
        ;;
    --restore)
        restore_backup "$2"
        ;;
    --list)
        list_backups
        ;;
    --help)
        show_help
        ;;
    *)
        show_help
        exit 1
        ;;
esac
