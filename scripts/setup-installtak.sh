#!/bin/bash

# TAK Server 5.4 InstallTAK DEB Wrapper for Unraid Containers
# Fixed Ubuntu mirrors and PostgreSQL service handling
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
echo -e "${GREEN}Fixed Ubuntu mirrors and service handling${NC}"
echo -e "${GREEN}Sponsored by CloudRF.com - The API for RF${NC}"
echo ""

# Fix Ubuntu repository mirrors (CRITICAL FIX!)
echo -e "${BLUE}Fixing Ubuntu repository mirrors...${NC}"
sed -i 's|http://archive.ubuntu.com/ubuntu|http://us.archive.ubuntu.com/ubuntu|g' /etc/apt/sources.list
sed -i 's|http://security.ubuntu.com/ubuntu|http://security.ubuntu.com/ubuntu|g' /etc/apt/sources.list

# Add additional backup mirrors
cat >> /etc/apt/sources.list << EOF
# Backup mirrors to avoid 403 errors
deb http://mirror.math.princeton.edu/pub/ubuntu/ jammy main restricted universe multiverse
deb http://mirror.math.princeton.edu/pub/ubuntu/ jammy-updates main restricted universe multiverse
deb http://mirror.math.princeton.edu/pub/ubuntu/ jammy-security main restricted universe multiverse
EOF

echo -e "${GREEN}✓ Ubuntu mirrors updated${NC}"

# Update with fixed mirrors
echo -e "${BLUE}Updating package lists with reliable mirrors...${NC}"
apt-get update -qq --fix-missing || apt-get update -qq

# Install basic dependencies first
echo -e "${BLUE}Installing core dependencies...${NC}"
apt-get install -y --fix-missing \
    git \
    wget \
    curl \
    sudo \
    dialog \
    unzip \
    zip \
    gnupg2 \
    lsb-release \
    ca-certificates

echo -e "${GREEN}✓ Core dependencies installed${NC}"

# Add PostgreSQL repository using proper method
echo -e "${BLUE}Adding PostgreSQL 15 repository...${NC}"
wget -O- https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor | tee /etc/apt/trusted.gpg.d/postgresql.org.gpg > /dev/null
echo "deb https://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list

# Update with PostgreSQL repo
apt-get update -qq

echo -e "${GREEN}✓ PostgreSQL 15 repository added${NC}"

# Install PostgreSQL with explicit version
echo -e "${BLUE}Installing PostgreSQL 15 and PostGIS...${NC}"
apt-get install -y --fix-missing \
    postgresql-15 \
    postgresql-15-postgis-3 \
    postgresql-client-15 \
    postgresql-contrib-15 \
    postgresql-15-postgis-3-scripts

echo -e "${GREEN}✓ PostgreSQL 15 installed${NC}"

# Set up PGDATA and start PostgreSQL properly
echo -e "${BLUE}Configuring PostgreSQL environment...${NC}"
export PGDATA="/var/lib/postgresql/15/main"
echo "export PGDATA=/var/lib/postgresql/15/main" >> /etc/environment

# Start PostgreSQL using pg_ctl directly (more reliable in containers)
echo -e "${BLUE}Starting PostgreSQL 15...${NC}"
su postgres -c "pg_ctl start -D /var/lib/postgresql/15/main -l /var/log/postgresql/postgresql-15-main.log" || true

# Alternative: try service command
service postgresql start || true

# Wait and verify PostgreSQL is running
for i in {1..30}; do
    if su postgres -c "pg_isready -p 5432" >/dev/null 2>&1; then
        echo -e "${GREEN}✓ PostgreSQL 15 is running${NC}"
        break
    fi
    if [ $i -eq 30 ]; then
        echo -e "${YELLOW}PostgreSQL may not be running, but continuing...${NC}"
        # Show PostgreSQL status for debugging
        su postgres -c "pg_ctl status -D /var/lib/postgresql/15/main" || true
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

# Set environment variables for InstallTAK
echo -e "${BLUE}Setting up environment for InstallTAK...${NC}"
export PGDATA="/var/lib/postgresql/15/main"
export DEBIAN_FRONTEND=noninteractive

# Run InstallTAK with retries on package failures
echo -e "${BLUE}Running InstallTAK script...${NC}"
echo -e "${YELLOW}This may take 10-15 minutes...${NC}"

cd /opt/installTAK

# Run with fallback for package errors
./installTAK "$(basename "$TAK_DEB_FILE")" || {
    echo -e "${YELLOW}InstallTAK encountered errors, trying with --fix-missing...${NC}"
    apt-get install -f --fix-missing -y
    ./installTAK "$(basename "$TAK_DEB_FILE")"
}

# Check final status
echo -e "${BLUE}Checking TAK Server status...${NC}"

# Try multiple ways to check/start TAK Server
if service takserver status >/dev/null 2>&1; then
    echo -e "${GREEN}✓ TAK Server is running${NC}"
elif /opt/tak/takserver.sh status >/dev/null 2>&1; then
    echo -e "${GREEN}✓ TAK Server is running${NC}"
else
    echo -e "${YELLOW}Starting TAK Server manually...${NC}"
    service takserver start || /opt/tak/takserver.sh start || true
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}TAK Server Setup Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${GREEN}Access TAK Server at: https://$(hostname -I | awk '{print $1}'):8443${NC}"
echo ""

# Keep container running
while true; do
    sleep 60
done
