#!/bin/bash

# TAK Server 5.4 InstallTAK DEB Wrapper for Unraid Containers
# FINAL FIX: Patch InstallTAK script to handle PostgreSQL 15
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
echo -e "${GREEN}FINAL FIX: Patch InstallTAK for PostgreSQL 15${NC}"
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

# CRITICAL FIX: Patch InstallTAK script for PostgreSQL 15
echo -e "${BLUE}Patching InstallTAK for PostgreSQL 15 compatibility...${NC}"

# Backup original script
cp /opt/installTAK/installTAK /opt/installTAK/installTAK.original

# Patch the PostgreSQL version detection in InstallTAK
sed -i 's|/etc/postgresql/12/main|/etc/postgresql/15/main|g' /opt/installTAK/installTAK
sed -i 's|postgresql/12/|postgresql/15/|g' /opt/installTAK/installTAK
sed -i 's|postgresql-12|postgresql-15|g' /opt/installTAK/installTAK

# Add explicit PGDATA export at the beginning of InstallTAK
sed -i '2i export PGDATA="/etc/postgresql/15/main"' /opt/installTAK/installTAK

# Add PGDATA to all sudo/su commands in InstallTAK
sed -i 's|sudo |sudo PGDATA="/etc/postgresql/15/main" |g' /opt/installTAK/installTAK
sed -i 's|su postgres |PGDATA="/etc/postgresql/15/main" su postgres |g' /opt/installTAK/installTAK

echo -e "${GREEN}✓ InstallTAK script patched for PostgreSQL 15${NC}"

# Set PGDATA system-wide (multiple methods to ensure persistence)
echo -e "${BLUE}Setting PGDATA system-wide...${NC}"

# Method 1: Environment files
echo 'PGDATA="/etc/postgresql/15/main"' >> /etc/environment
echo 'export PGDATA="/etc/postgresql/15/main"' >> /etc/profile
echo 'export PGDATA="/etc/postgresql/15/main"' >> /etc/bash.bashrc

# Method 2: Systemd environment
mkdir -p /etc/systemd/system.conf.d
echo '[Manager]' > /etc/systemd/system.conf.d/pgdata.conf
echo 'DefaultEnvironment=PGDATA=/etc/postgresql/15/main' >> /etc/systemd/system.conf.d/pgdata.conf

# Method 3: Current shell
export PGDATA="/etc/postgresql/15/main"

echo -e "${GREEN}✓ PGDATA set system-wide${NC}"

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

# Final verification
echo -e "${BLUE}Final verification before InstallTAK...${NC}"
echo "PGDATA is set to: $PGDATA"
echo "PostgreSQL 15 config directory exists: $([ -d "/etc/postgresql/15/main" ] && echo "YES" || echo "NO")"
echo "PostgreSQL 15 is running: $(systemctl is-active postgresql 2>/dev/null || echo "service-check")"

# Run the patched InstallTAK script
echo -e "${BLUE}Running patched InstallTAK script...${NC}"
echo -e "${YELLOW}This should now work with PostgreSQL 15...${NC}"

cd /opt/installTAK

# Set environment for InstallTAK process
export PGDATA="/etc/postgresql/15/main"
export DEBIAN_FRONTEND=noninteractive

# Run InstallTAK with explicit environment
PGDATA="/etc/postgresql/15/main" ./installTAK "$(basename "$TAK_DEB_FILE")"

INSTALL_RESULT=$?

if [ $INSTALL_RESULT -eq 0 ]; then
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}TAK Server Installation Successful!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo -e "${GREEN}Access TAK Server at: https://$(hostname -I | awk '{print $1}'):8443${NC}"
    echo -e "${YELLOW}Check InstallTAK output above for admin credentials${NC}"
    echo ""
else
    echo -e "${YELLOW}InstallTAK completed with warnings, checking TAK Server...${NC}"
    
    # Try to start TAK Server manually if needed
    if [ -f "/opt/tak/takserver.war" ]; then
        echo -e "${YELLOW}TAK Server files found, attempting start...${NC}"
        service takserver start || {
            cd /opt/tak
            sudo -u tak java -jar takserver.war &
        }
    fi
fi

# Keep container running and monitor
echo -e "${BLUE}Keeping container running...${NC}"
while true; do
    sleep 60
done
