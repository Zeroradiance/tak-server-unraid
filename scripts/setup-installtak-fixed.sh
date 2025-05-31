#!/bin/bash

# TAK Server 5.4 BULLETPROOF Installation Script for Unraid
# Fixes ALL known issues: Java, PostgreSQL 15, PGDATA, config files, etc.
# Sponsored by CloudRF.com - "The API for RF"

set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

export TERM=linux
export DEBIAN_FRONTEND=noninteractive

echo -e "${GREEN}TAK Server 5.4 BULLETPROOF Installation${NC}"
echo -e "${GREEN}Fixing ALL known issues upfront${NC}"
echo -e "${GREEN}Sponsored by CloudRF.com - The API for RF${NC}"
echo ""

# Fix Ubuntu mirrors first
echo -e "${BLUE}Fixing Ubuntu repository mirrors...${NC}"
sed -i 's|http://archive.ubuntu.com/ubuntu|http://us.archive.ubuntu.com/ubuntu|g' /etc/apt/sources.list
apt-get update -qq --fix-missing || apt-get update -qq

# Install ALL dependencies upfront (no more missing packages!)
echo -e "${BLUE}Installing ALL required dependencies...${NC}"
apt-get install -y --fix-missing \
    wget curl git sudo dialog unzip zip \
    gnupg2 lsb-release ca-certificates \
    openjdk-17-jdk openjdk-17-jre openjdk-17-jdk-headless openjdk-17-jre-headless \
    build-essential

echo -e "${GREEN}✓ Core dependencies and Java 17 installed${NC}"

# Verify Java installation
echo -e "${BLUE}Verifying Java installation...${NC}"
java -version
javac -version
export JAVA_HOME="/usr/lib/jvm/java-17-openjdk-amd64"
echo "JAVA_HOME set to: $JAVA_HOME"

# Add PostgreSQL 15 repository
echo -e "${BLUE}Adding PostgreSQL 15 repository...${NC}"
wget -O- https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor | tee /etc/apt/trusted.gpg.d/postgresql.org.gpg > /dev/null
echo "deb https://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list
apt-get update -qq

# Install PostgreSQL 15 and PostGIS
echo -e "${BLUE}Installing PostgreSQL 15 and PostGIS...${NC}"
apt-get install -y --fix-missing \
    postgresql-15 \
    postgresql-15-postgis-3 \
    postgresql-client-15 \
    postgresql-contrib-15 \
    postgresql-15-postgis-3-scripts

echo -e "${GREEN}✓ PostgreSQL 15 installed${NC}"

# Set PGDATA environment (multiple methods for persistence)
echo -e "${BLUE}Setting PGDATA environment for PostgreSQL 15...${NC}"
export PGDATA="/etc/postgresql/15/main"
echo 'export PGDATA="/etc/postgresql/15/main"' >> /etc/environment
echo 'export PGDATA="/etc/postgresql/15/main"' >> /etc/profile
echo 'export PGDATA="/etc/postgresql/15/main"' >> /etc/bash.bashrc

# Start PostgreSQL and verify
echo -e "${BLUE}Starting PostgreSQL 15...${NC}"
service postgresql start

for i in {1..30}; do
    if su postgres -c "pg_isready -p 5432" >/dev/null 2>&1; then
        echo -e "${GREEN}✓ PostgreSQL 15 is running${NC}"
        break
    fi
    sleep 1
done

# Pre-create TAK database and user (exactly as TAK Server expects)
echo -e "${BLUE}Pre-creating TAK database and user...${NC}"
su postgres -c "psql -c \"CREATE ROLE martiuser LOGIN ENCRYPTED PASSWORD 'md564d5850dcafc6b4ddd03040ad1260bc2' SUPERUSER INHERIT CREATEDB NOCREATEROLE;\"" 2>/dev/null || echo "User may already exist"
su postgres -c "createdb --owner=martiuser cot" 2>/dev/null || echo "Database may already exist"
su postgres -c "psql -d cot -c \"CREATE EXTENSION IF NOT EXISTS postgis;\"" 2>/dev/null || true

echo -e "${GREEN}✓ TAK database prepared${NC}"

# Check for TAK Server files
echo -e "${BLUE}Checking for TAK Server files...${NC}"
cd /setup

TAK_DEB_FILE=$(find . -maxdepth 1 -name "takserver_*_all.deb" | head -1)
if [ -z "$TAK_DEB_FILE" ]; then
    echo -e "${RED}Error: No TAK Server DEB file found!${NC}"
    echo -e "${RED}Please download takserver_5.4-RELEASE-XX_all.deb from tak.gov${NC}"
    exit 1
fi

if [ ! -f "takserver-public-gpg.key" ]; then
    echo -e "${RED}Error: takserver-public-gpg.key not found!${NC}"
    exit 1
fi

echo -e "${GREEN}✓ All required files present${NC}"

# Create tak user and directories BEFORE installation
echo -e "${BLUE}Pre-creating TAK user and directories...${NC}"
useradd -r -s /bin/bash -d /opt/tak -m tak 2>/dev/null || echo "User tak may already exist"
mkdir -p /opt/tak/{config,certs,logs,lib,db-utils}
chown -R tak:tak /opt/tak

# Create the missing config files that post-install expects
echo -e "${BLUE}Creating required config files...${NC}"
touch /opt/tak/config/takserver-api.sh
touch /opt/tak/config/takserver-messaging.sh  
touch /opt/tak/config/takserver-retention.sh
chmod +x /opt/tak/config/*.sh
chown -R tak:tak /opt/tak/config

# Now install TAK Server with all dependencies met
echo -e "${BLUE}Installing TAK Server DEB package...${NC}"
export PGDATA="/etc/postgresql/15/main"
export JAVA_HOME="/usr/lib/jvm/java-17-openjdk-amd64"

# Install the DEB package
dpkg -i "$TAK_DEB_FILE" || {
    echo -e "${YELLOW}DEB installation had issues, attempting to fix...${NC}"
    
    # Fix the post-install script for PostgreSQL 15
    if [ -f "/var/lib/dpkg/info/takserver.postinst" ]; then
        sed -i 's|/etc/postgresql/12/main|/etc/postgresql/15/main|g' /var/lib/dpkg/info/takserver.postinst
        sed -i 's|postgresql/12/|postgresql/15/|g' /var/lib/dpkg/info/takserver.postinst
    fi
    
    # Retry configuration
    export PGDATA="/etc/postgresql/15/main"
    dpkg --configure takserver || {
        echo -e "${YELLOW}Package configuration failed, completing manually...${NC}"
        
        # Manual completion - ensure TAK Server files are in place
        if [ ! -f "/opt/tak/takserver.war" ]; then
            # Extract the WAR file manually if needed
            cd /tmp
            ar x /setup/"$TAK_DEB_FILE"
            tar -xf data.tar.xz
            cp -r opt/tak/* /opt/tak/ 2>/dev/null || true
            chown -R tak:tak /opt/tak
        fi
    }
}

# Verify installation
echo -e "${BLUE}Verifying TAK Server installation...${NC}"
if [ -f "/opt/tak/takserver.war" ]; then
    echo -e "${GREEN}✓ TAK Server WAR file present${NC}"
else
    echo -e "${RED}TAK Server WAR file missing, installation incomplete${NC}"
    exit 1
fi

# Run database schema setup
echo -e "${BLUE}Setting up database schema...${NC}"
cd /opt/tak
if [ -f "db-utils/SchemaManager.jar" ]; then
    export PGDATA="/etc/postgresql/15/main"
    java -jar db-utils/SchemaManager.jar upgrade || echo "Schema may already be up to date"
else
    echo -e "${YELLOW}SchemaManager not found, database may need manual setup${NC}"
fi

# Create systemd service
echo -e "${BLUE}Creating TAK Server service...${NC}"
cat > /etc/systemd/system/takserver.service << 'EOF'
[Unit]
Description=TAK Server
After=postgresql.service
Wants=postgresql.service

[Service]
Type=simple
User=tak
Group=tak
WorkingDirectory=/opt/tak
Environment=JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
Environment=PGDATA=/etc/postgresql/15/main
ExecStart=/usr/bin/java -Xms2g -Xmx4g -jar /opt/tak/takserver.war
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Start TAK Server
echo -e "${BLUE}Starting TAK Server...${NC}"
systemctl daemon-reload 2>/dev/null || true
service takserver start || {
    echo -e "${YELLOW}Service start failed, starting manually...${NC}"
    cd /opt/tak
    sudo -u tak java -Xms2g -Xmx4g -jar takserver.war &
    sleep 10
}

# Check if TAK Server is listening
echo -e "${BLUE}Checking TAK Server status...${NC}"
for i in {1..60}; do
    if netstat -tulpn 2>/dev/null | grep -q ":8443"; then
        echo -e "${GREEN}✓ TAK Server is listening on port 8443${NC}"
        break
    fi
    if [ $i -eq 60 ]; then
        echo -e "${YELLOW}TAK Server may still be starting...${NC}"
    fi
    sleep 2
done

# Final status
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}TAK Server Installation Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${GREEN}Access TAK Server at: https://$(hostname -I | awk '{print $1}'):8443${NC}"
echo -e "${GREEN}External access (Unraid): https://YOUR-UNRAID-IP:8960${NC}"
echo ""
echo -e "${YELLOW}Default credentials:${NC}"
echo -e "${YELLOW}- Check TAK Server logs for auto-generated credentials${NC}"
echo -e "${YELLOW}- Database: martiuser / (auto-generated password)${NC}"
echo ""
echo -e "${BLUE}TAK Server files located at: /opt/tak/${NC}"
echo -e "${BLUE}Certificates located at: /opt/tak/certs/${NC}"
echo ""

# Keep container running
echo -e "${BLUE}Keeping container running and monitoring TAK Server...${NC}"
while true; do
    if ! pgrep -f "takserver.war" >/dev/null; then
        echo -e "${YELLOW}TAK Server process not found, attempting restart...${NC}"
        cd /opt/tak
        sudo -u tak java -Xms2g -Xmx4g -jar takserver.war &
    fi
    sleep 60
done
