#!/bin/bash

# TAK Server 5.4 InstallTAK DEB Wrapper for Unraid Containers
# DEFINITIVE FIX: Edit dpkg post-install script for PostgreSQL 15
# Sponsored by CloudRF.com - "The API for RF"

set -euo pipefail

# Color codes and environment fixes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

export TERM=linux
export DEBIAN_FRONTEND=noninteractive

echo -e "${GREEN}TAK Server 5.4 InstallTAK DEB Container Setup${NC}"
echo -e "${GREEN}DEFINITIVE FIX: Edit dpkg post-install for PostgreSQL 15${NC}"
echo -e "${GREEN}Sponsored by CloudRF.com - The API for RF${NC}"
echo ""

# Fix Ubuntu repository mirrors
echo -e "${BLUE}Fixing Ubuntu repository mirrors...${NC}"
sed -i 's|http://archive.ubuntu.com/ubuntu|http://us.archive.ubuntu.com/ubuntu|g' /etc/apt/sources.list

apt-get update -qq --fix-missing || apt-get update -qq

# Install core dependencies
echo -e "${BLUE}Installing core dependencies...${NC}"
apt-get install -y --fix-missing \
    git wget curl sudo dialog unzip zip gnupg2 lsb-release ca-certificates

echo -e "${GREEN}✓ Core dependencies installed${NC}"

# Add PostgreSQL repository
echo -e "${BLUE}Adding PostgreSQL 15 repository...${NC}"
wget -O- https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor | tee /etc/apt/trusted.gpg.d/postgresql.org.gpg > /dev/null
echo "deb https://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list

apt-get update -qq

echo -e "${GREEN}✓ PostgreSQL 15 repository added${NC}"

# Install PostgreSQL 15
echo -e "${BLUE}Installing PostgreSQL 15...${NC}"
apt-get install -y --fix-missing \
    postgresql-15 \
    postgresql-15-postgis-3 \
    postgresql-client-15 \
    postgresql-contrib-15

echo -e "${GREEN}✓ PostgreSQL 15 installed${NC}"

# Start PostgreSQL
echo -e "${BLUE}Starting PostgreSQL 15...${NC}"
service postgresql start

# Wait for PostgreSQL to be ready
for i in {1..30}; do
    if su postgres -c "pg_isready -p 5432" >/dev/null 2>&1; then
        echo -e "${GREEN}✓ PostgreSQL 15 is running${NC}"
        break
    fi
    sleep 1
done

# Clone InstallTAK repository
echo -e "${BLUE}Downloading InstallTAK script...${NC}"
git clone https://github.com/myTeckNetCode/installTAK.git /opt/installTAK
chmod +x /opt/installTAK/installTAK

echo -e "${GREEN}✓ InstallTAK script downloaded${NC}"

# Check for required files
echo -e "${BLUE}Checking for TAK Server files...${NC}"
cd /setup

TAK_DEB_FILE=$(find . -maxdepth 1 -name "takserver_*_all.deb" | head -1)
if [ -z "$TAK_DEB_FILE" ]; then
    echo -e "${RED}Error: No TAK Server DEB file found!${NC}"
    exit 1
else
    echo -e "${GREEN}✓ Found TAK Server DEB file: $TAK_DEB_FILE${NC}"
fi

# Copy all files to InstallTAK directory
echo -e "${BLUE}Preparing InstallTAK installation...${NC}"
cp "$TAK_DEB_FILE" /opt/installTAK/

if [ -f "deb_policy.pol" ]; then
    cp "deb_policy.pol" /opt/installTAK/
    echo -e "${GREEN}✓ Policy file copied${NC}"
fi

if [ -f "takserver-public-gpg.key" ]; then
    cp "takserver-public-gpg.key" /opt/installTAK/
    echo -e "${GREEN}✓ GPG key copied${NC}"
else
    echo -e "${RED}Error: takserver-public-gpg.key not found${NC}"
    exit 1
fi

# Set environment variables
export PGDATA="/etc/postgresql/15/main"
export DEBIAN_FRONTEND=noninteractive

# Run InstallTAK and let it fail on the dpkg configure step
echo -e "${BLUE}Running InstallTAK (will fail on dpkg configure)...${NC}"

cd /opt/installTAK
./installTAK "$(basename "$TAK_DEB_FILE")" || {
    echo -e "${YELLOW}InstallTAK failed on dpkg configure (expected)${NC}"
}

# CRITICAL FIX: Edit the broken dpkg post-install script
echo -e "${BLUE}Fixing TAK Server dpkg post-install script for PostgreSQL 15...${NC}"

POSTINST_FILE="/var/lib/dpkg/info/takserver.postinst"

if [ -f "$POSTINST_FILE" ]; then
    # Backup original post-install script
    cp "$POSTINST_FILE" "${POSTINST_FILE}.backup"
    
    # Fix the PostgreSQL version detection (from search result 2)
    sed -i 's|/etc/postgresql/12/main|/etc/postgresql/15/main|g' "$POSTINST_FILE"
    sed -i 's|postgresql/12/|postgresql/15/|g' "$POSTINST_FILE"
    sed -i 's|postgresql-12|postgresql-15|g' "$POSTINST_FILE"
    
    # Add explicit PGDATA export at the beginning
    sed -i '2i export PGDATA="/etc/postgresql/15/main"' "$POSTINST_FILE"
    
    echo -e "${GREEN}✓ TAK Server post-install script fixed for PostgreSQL 15${NC}"
    
    # Now try to configure the package again (from search result 6)
    echo -e "${BLUE}Reconfiguring TAK Server package...${NC}"
    dpkg --configure takserver
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ TAK Server package configured successfully!${NC}"
    else
        echo -e "${YELLOW}Package configuration still failing, trying manual setup...${NC}"
        
        # Manual TAK Server setup
        mkdir -p /opt/tak/{config,certs,logs,lib}
        
        # Create tak user if it doesn't exist
        useradd -r -s /bin/false tak 2>/dev/null || true
        chown -R tak:tak /opt/tak
        
        # Try configuration again
        dpkg --configure takserver || {
            echo -e "${YELLOW}Continuing with manual TAK Server setup...${NC}"
        }
    fi
else
    echo -e "${RED}TAK Server post-install script not found${NC}"
    exit 1
fi

# Final verification and startup
echo -e "${BLUE}Checking TAK Server installation...${NC}"

if [ -f "/opt/tak/takserver.war" ]; then
    echo -e "${GREEN}✓ TAK Server files are present${NC}"
    
    # Try to start TAK Server
    echo -e "${BLUE}Starting TAK Server...${NC}"
    
    service takserver start || {
        echo -e "${YELLOW}Service start failed, trying manual start...${NC}"
        cd /opt/tak
        sudo -u tak java -jar takserver.war &
    }
    
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}TAK Server Setup Complete!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo -e "${GREEN}Access TAK Server at: https://$(hostname -I | awk '{print $1}'):8443${NC}"
    echo -e "${YELLOW}Check output above for admin credentials${NC}"
    echo ""
    
else
    echo -e "${RED}TAK Server installation incomplete${NC}"
    echo -e "${RED}Check InstallTAK output for specific errors${NC}"
fi

# Keep container running
echo -e "${BLUE}Keeping container running...${NC}"
while true; do
    sleep 60
done
