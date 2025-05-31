#!/bin/bash

# TAK Server 5.4 InstallTAK DEB Wrapper for Unraid Containers
# Fixed to use service commands instead of systemctl for Docker compatibility
# Sponsored by CloudRF.com - "The API for RF"

set -euo pipefail

# Color codes and environment fixes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Fix terminal issues
export TERM=linux
export DEBIAN_FRONTEND=noninteractive

echo -e "${GREEN}TAK Server 5.4 InstallTAK DEB Container Setup${NC}"
echo -e "${GREEN}Using service commands for Docker compatibility${NC}"
echo -e "${GREEN}Sponsored by CloudRF.com - The API for RF${NC}"
echo ""

# Update system and install dependencies
echo -e "${BLUE}Installing dependencies...${NC}"
apt-get update -qq
apt-get install -y \
    git \
    wget \
    curl \
    sudo \
    dialog \
    unzip \
    zip \
    gnupg2 \
    lsb-release

echo -e "${GREEN}✓ Dependencies installed${NC}"

# Add PostgreSQL official repository
echo -e "${BLUE}Adding PostgreSQL 15 repository...${NC}"
wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add -
echo "deb http://apt.postgresql.org/pub/repos/apt/ $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list

# Update package lists to include PostgreSQL 15
apt-get update -qq

echo -e "${GREEN}✓ PostgreSQL 15 repository added${NC}"

# Install PostgreSQL 15 and PostGIS
echo -e "${BLUE}Installing PostgreSQL 15 and PostGIS...${NC}"
apt-get install -y \
    postgresql-15 \
    postgresql-15-postgis-3 \
    postgresql-client-15 \
    postgresql-contrib-15

echo -e "${GREEN}✓ PostgreSQL 15 installed${NC}"

# Set up PGDATA environment variable
echo -e "${BLUE}Configuring PGDATA environment variable...${NC}"
export PGDATA="/var/lib/postgresql/15/main"
echo "export PGDATA=/var/lib/postgresql/15/main" >> /etc/environment
echo "export PGDATA=/var/lib/postgresql/15/main" >> /etc/profile

# Start PostgreSQL using service command (DOCKER-COMPATIBLE!)
echo -e "${BLUE}Starting PostgreSQL 15 service...${NC}"
service postgresql start

# Wait for PostgreSQL to be ready
for i in {1..30}; do
    if service postgresql status >/dev/null 2>&1; then
        echo -e "${GREEN}✓ PostgreSQL 15 service started${NC}"
        break
    fi
    sleep 1
done

# Clone InstallTAK repository
echo -e "${BLUE}Downloading InstallTAK script...${NC}"
git clone https://github.com/myTeckNetCode/installTAK.git /opt/installTAK
chmod +x /opt/installTAK/installTAK

echo -e "${GREEN}✓ InstallTAK script downloaded${NC}"

# Check for TAK Server DEB file
echo -e "${BLUE}Checking for TAK Server DEB files...${NC}"
cd /setup

TAK_DEB_FILE=""
TAK_DEB_FILE=$(find . -maxdepth 1 -name "takserver_*_all.deb" | head -1)

if [ -z "$TAK_DEB_FILE" ]; then
    echo -e "${RED}Error: No TAK Server DEB file found!${NC}"
    exit 1
else
    echo -e "${GREEN}✓ Found TAK Server DEB file: $TAK_DEB_FILE${NC}"
fi

# Copy all required files to InstallTAK directory
echo -e "${BLUE}Preparing InstallTAK installation...${NC}"
cp "$TAK_DEB_FILE" /opt/installTAK/

# Copy policy file if it exists
if [ -f "deb_policy.pol" ]; then
    cp "deb_policy.pol" /opt/installTAK/
    echo -e "${GREEN}✓ Policy file found and copied${NC}"
fi

# Copy GPG key file if it exists
if [ -f "takserver-public-gpg.key" ]; then
    cp "takserver-public-gpg.key" /opt/installTAK/
    echo -e "${GREEN}✓ GPG key file found and copied${NC}"
else
    echo -e "${RED}Error: takserver-public-gpg.key not found${NC}"
    exit 1
fi

# Verify prerequisites
echo -e "${BLUE}Verifying installation prerequisites...${NC}"
echo "PGDATA is set to: $PGDATA"
echo "PostgreSQL status: $(service postgresql status | head -1)"

cd /opt/installTAK
echo -e "${GREEN}✓ All prerequisites met${NC}"

# Run InstallTAK script with proper environment
echo -e "${BLUE}Running InstallTAK script...${NC}"
echo -e "${YELLOW}This may take 5-10 minutes...${NC}"

export PGDATA="/var/lib/postgresql/15/main"

cd /opt/installTAK
./installTAK "$(basename "$TAK_DEB_FILE")"

# Check if TAK Server is running using service command
echo -e "${BLUE}Checking TAK Server status...${NC}"
if service takserver status >/dev/null 2>&1; then
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}TAK Server Installation Complete!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo -e "${GREEN}TAK Server is running and accessible at:${NC}"
    echo -e "${GREEN}https://$(hostname -I | awk '{print $1}'):8443${NC}"
    echo ""
    echo -e "${YELLOW}Check InstallTAK output above for credentials${NC}"
    echo ""
else
    echo -e "${YELLOW}Attempting to start TAK Server...${NC}"
    service takserver start || true
fi

# Keep container running and monitor services using service commands
echo -e "${BLUE}Keeping container running...${NC}"
echo -e "${GREEN}TAK Server setup complete!${NC}"

while true; do
    # Check services using service command instead of systemctl
    if ! service postgresql status >/dev/null 2>&1; then
        echo -e "${RED}PostgreSQL service failed!${NC}"
        service postgresql start || true
    fi
    
    if ! service takserver status >/dev/null 2>&1; then
        echo -e "${RED}TAK Server service failed!${NC}"
        service takserver start || true
    fi
    
    sleep 60
done
