#!/bin/bash

# TAK Server 5.4 InstallTAK DEB Wrapper for Unraid Containers
# FIXED: Set PGDATA to PostgreSQL CONFIG directory, not data directory
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
echo -e "${GREEN}FIXED: Proper PGDATA configuration for TAK Server${NC}"
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

# CRITICAL FIX: Set PGDATA to CONFIG directory (what TAK Server expects!)
echo -e "${BLUE}Configuring PGDATA for TAK Server...${NC}"
export PGDATA="/etc/postgresql/15/main"  # CONFIG directory, not data!
echo "export PGDATA=/etc/postgresql/15/main" >> /etc/environment
echo "export PGDATA=/etc/postgresql/15/main" >> /etc/profile

echo -e "${GREEN}✓ PGDATA set to CONFIG directory: $PGDATA${NC}"

# Start PostgreSQL and ensure it's configured
echo -e "${BLUE}Starting and configuring PostgreSQL...${NC}"
service postgresql start || true

# Wait for PostgreSQL to be ready
for i in {1..30}; do
    if su postgres -c "pg_isready -p 5432" >/dev/null 2>&1; then
        echo -e "${GREEN}✓ PostgreSQL 15 is running${NC}"
        break
    fi
    sleep 1
done

# Create TAK database and user (do this BEFORE installing TAK Server)
echo -e "${BLUE}Creating TAK database and user...${NC}"
su postgres -c "createdb cot" 2>/dev/null || true
su postgres -c "psql -c \"CREATE USER martiuser WITH PASSWORD 'atakatak' SUPERUSER;\"" 2>/dev/null || true
su postgres -c "psql -c \"GRANT ALL PRIVILEGES ON DATABASE cot TO martiuser;\"" 2>/dev/null || true

echo -e "${GREEN}✓ TAK database prepared${NC}"

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

# Set critical environment variables for InstallTAK
echo -e "${BLUE}Setting environment for InstallTAK...${NC}"
export PGDATA="/etc/postgresql/15/main"  # CONFIG directory!
export DEBIAN_FRONTEND=noninteractive
export IS_DOCKER=true

echo "PGDATA is set to: $PGDATA"
echo "Contents of PGDATA directory:"
ls -la "$PGDATA" || echo "PGDATA directory not found"

# Run InstallTAK script
echo -e "${BLUE}Running InstallTAK script with correct PGDATA...${NC}"
echo -e "${YELLOW}This may take 10-15 minutes...${NC}"

cd /opt/installTAK
./installTAK "$(basename "$TAK_DEB_FILE")"

# If TAK Server package failed to configure, try manual fix
if dpkg -l | grep takserver | grep -q "iF"; then
    echo -e "${YELLOW}TAK Server package needs reconfiguration...${NC}"
    
    # Create missing directories if needed
    mkdir -p /opt/tak/config
    
    # Try to reconfigure the package
    dpkg --configure takserver || {
        echo -e "${YELLOW}Manual configuration needed...${NC}"
        
        # Create basic TAK Server structure if missing
        mkdir -p /opt/tak/{config,certs,logs,lib}
        chown -R tak:tak /opt/tak 2>/dev/null || true
        
        # Try reconfigure again
        dpkg --configure takserver || true
    }
fi

# Final status check
echo -e "${BLUE}Checking TAK Server status...${NC}"

if [ -d "/opt/tak" ] && [ -f "/opt/tak/takserver.war" ]; then
    echo -e "${GREEN}✓ TAK Server files are present${NC}"
    
    # Try to start TAK Server manually if service didn't start
    if ! service takserver status >/dev/null 2>&1; then
        echo -e "${YELLOW}Starting TAK Server manually...${NC}"
        cd /opt/tak
        sudo -u tak java -jar takserver.war &
    fi
    
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}TAK Server Setup Complete!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo -e "${GREEN}Access TAK Server at: https://$(hostname -I | awk '{print $1}'):8443${NC}"
    echo -e "${YELLOW}Default credentials may be in InstallTAK output above${NC}"
    echo ""
else
    echo -e "${RED}TAK Server installation incomplete${NC}"
    echo "Check InstallTAK output for errors"
fi

# Keep container running
echo -e "${BLUE}Keeping container running...${NC}"
while true; do
    sleep 60
done
