#!/bin/bash

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}Installing prerequisites...${NC}"

# Update package list
sudo apt-get update

# Install PostgreSQL client
if ! command -v psql &> /dev/null; then
    echo -e "${YELLOW}Installing PostgreSQL client...${NC}"
    sudo apt-get install -y postgresql-client
fi

# Install Flyway
if ! command -v flyway &> /dev/null; then
    echo -e "${YELLOW}Installing Flyway...${NC}"
    cd /tmp
    wget -qO- https://repo1.maven.org/maven2/org/flywaydb/flyway-commandline/9.22.3/flyway-commandline-9.22.3-linux-x64.tar.gz | tar xvz
    sudo mv flyway-9.22.3 /opt/flyway
    sudo ln -s /opt/flyway/flyway /usr/local/bin
fi

# Install jq if not present
if ! command -v jq &> /dev/null; then
    echo -e "${YELLOW}Installing jq...${NC}"
    sudo apt-get install -y jq
fi

# Verify installations
echo -e "${YELLOW}Verifying installations...${NC}"

echo -e "${YELLOW}PostgreSQL client version:${NC}"
psql --version

echo -e "${YELLOW}Flyway version:${NC}"
flyway --version

echo -e "${YELLOW}jq version:${NC}"
jq --version

echo -e "${GREEN}Prerequisites installation completed${NC}"
