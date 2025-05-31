#!/bin/bash

# TAK Server 5.4 InstallTAK DEB Wrapper for Unraid Containers
# FINAL FIX: Properly initialize PostgreSQL before TAK Server installation
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
echo -e "${GREEN}FINAL FIX: Complete PostgreSQL setup before TAK Server${NC}"
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

# Install PostgreSQL 15 completely
echo -e "${BLUE}Installing PostgreSQL 15 with full setup...${NC}"
apt-get install -y --fix-missing \
    postgresql-15 \
    postgresql-15-postgis-3 \
    postgresql-client-15 \
    postgresql-contrib-15 \
    postgresql-15-postgis-3-scripts

echo -e "${GREEN}✓ PostgreSQL 15 installed${NC}"

# CRITICAL: Stop any running PostgreSQL and reinitialize properly
echo -e "${BLUE}Reinitializing PostgreSQL for TAK Server...${NC}"
service postgresql stop || true
killall postgres || true

# Remove any existing cluster and recreate
pg_dropcluster --stop 15 main || true
pg_createcluster 15 main

echo -e "${GREEN}✓ PostgreSQL cluster recreated${NC}"

# Set PGDATA to both data AND config directories
export PGDATA="/etc/postgresql/15/main"
export POSTGRES_DATA="/var/lib/postgresql/15/main"

# Make PGDATA permanent in multiple locations
echo "export PGDATA=/etc/postgresql/15/main" >> /etc/environment
echo "export PGDATA=/etc/postgresql/15/main" >> /etc/profile
echo "export PGDATA=/etc/postgresql/15/main" >> /root/.bashrc

# Set ownership correctly (from search result 4)
chown -R postgres:postgres /var/lib/postgresql/15/main
chown -R postgres:postgres /etc/postgresql/15/main
chmod 700 /var/lib/postgresql/15/main

echo -e "${GREEN}✓ PostgreSQL ownership and permissions set${NC}"

# Start PostgreSQL and ensure it's working
echo -e "${BLUE}Starting PostgreSQL 15...${NC}"
service postgresql start

# Wait for PostgreSQL to be fully ready
for i in {1..60}; do
    if su postgres -c "pg_isready -p 5432" >/dev/null 2>&1; then
        echo -e "${GREEN}✓ PostgreSQL 15 is running and ready${NC}"
        break
    fi
    if [ $i -eq 60 ]; then
        echo -e "${RED}PostgreSQL failed to start properly${NC}"
        service postgresql status
        exit 1
    fi
    sleep 1
done

# Pre-create TAK database and user (exactly like TAK Server expects)
echo -e "${BLUE}Setting up TAK database (like TAK Server setup script)...${NC}"

# Create the martiuser with the exact password TAK expects
su postgres -c "psql -c \"CREATE ROLE martiuser LOGIN ENCRYPTED PASSWORD 'md564d5850dcafc6b4ddd03040ad1260bc2' SUPERUSER INHERIT CREATEDB NOCREATEROLE;\"" 2>/dev/null || true

# Create the cot database
su postgres -c "createdb --owner=martiuser cot" 2>/dev/null || true

# Grant all privileges
su postgres -c "psql -c \"GRANT ALL PRIVILEGES ON DATABASE cot TO martiuser;\"" 2>/dev/null || true

echo -e "${GREEN}✓ TAK database and user created${NC}"

# Verify database setup
echo -e "${BLUE}Verifying database setup...${NC}"
DB_EXISTS=$(su postgres -c "psql -l" | grep cot || true)
if [ -n "$DB_EXISTS" ]; then
    echo -e "${GREEN}✓ Database 'cot' exists and is ready${NC}"
else
    echo -e "${RED}Database setup failed${NC}"
    exit 1
fi

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

# Set all environment variables for InstallTAK
echo -e "${BLUE}Setting complete environment for InstallTAK...${NC}"
export PGDATA="/etc/postgresql/15/main"
export DEBIAN_FRONTEND=noninteractive
export IS_DOCKER=true
export PATH="/usr/lib/postgresql/15/bin:$PATH"

# Verify PGDATA directory exists and has content
echo "PGDATA is set to: $PGDATA"
if [ -d "$PGDATA" ] && [ "$(ls -A $PGDATA)" ]; then
    echo -e "${GREEN}✓ PGDATA directory exists and contains configuration files${NC}"
    ls -la "$PGDATA" | head -5
else
    echo -e "${RED}PGDATA directory is empty or missing${NC}"
    exit 1
fi

# Run InstallTAK with properly configured environment
echo -e "${BLUE}Running InstallTAK with pre-configured PostgreSQL...${NC}"
echo -e "${YELLOW}This should work now since PostgreSQL is properly set up...${NC}"

cd /opt/installTAK

# Export all environment variables for the InstallTAK process
export PGDATA="/etc/postgresql/15/main"
export DEBIAN_FRONTEND=noninteractive

./installTAK "$(basename "$TAK_DEB_FILE")"

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
    echo -e "${YELLOW}InstallTAK completed with warnings/errors${NC}"
    
    # Try to start TAK Server manually if needed
    if [ -f "/opt/tak/takserver.war" ]; then
        echo -e "${YELLOW}Attempting manual TAK Server start...${NC}"
        cd /opt/tak
        service takserver start || {
            sudo -u tak java -jar takserver.war &
        }
    fi
fi

# Keep container running and monitor
echo -e "${BLUE}Keeping container running...${NC}"
while true; do
    sleep 60
done
