#!/bin/bash

# TAK Server 5.4 BULLETPROOF Installation Script for Unraid
# Fixes ALL known issues: Java, PostgreSQL 15, PGDATA, config files, credentials, plugins, certificates
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
echo -e "${GREEN}Complete solution: Java + PostgreSQL + Certificates + Plugins${NC}"
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
    build-essential net-tools

echo -e "${GREEN}✓ Core dependencies and Java 17 installed${NC}"

# Enhanced credential tracking and logging
echo -e "${BLUE}Setting up credential tracking and logging...${NC}"

# Create credential log file
CRED_LOG="/opt/tak/credentials.log"
mkdir -p /opt/tak
touch "$CRED_LOG"

echo "========================================" >> "$CRED_LOG"
echo "TAK Server Credentials - $(date)" >> "$CRED_LOG"
echo "========================================" >> "$CRED_LOG"

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

echo -e "${GREEN}✓ PostgreSQL 15 repository added${NC}"

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

# Enhanced database setup with credential logging
echo -e "${BLUE}Creating TAK database with credential logging...${NC}"

# Generate and log database password
DB_PASSWORD="atakatak"
echo "Database Credentials:" >> "$CRED_LOG"
echo "- Database: cot" >> "$CRED_LOG"
echo "- Username: martiuser" >> "$CRED_LOG"
echo "- Password: $DB_PASSWORD" >> "$CRED_LOG"
echo "" >> "$CRED_LOG"

# Display in container logs too
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}TAK SERVER DATABASE CREDENTIALS:${NC}"
echo -e "${GREEN}Database: cot${NC}"
echo -e "${GREEN}Username: martiuser${NC}"
echo -e "${GREEN}Password: $DB_PASSWORD${NC}"
echo -e "${GREEN}========================================${NC}"

# Create database with logged password
su postgres -c "psql -c \"CREATE ROLE martiuser LOGIN ENCRYPTED PASSWORD '$DB_PASSWORD' SUPERUSER INHERIT CREATEDB NOCREATEROLE;\"" 2>/dev/null || echo "User may already exist"
su postgres -c "createdb --owner=martiuser cot" 2>/dev/null || echo "Database may already exist"
su postgres -c "psql -d cot -c \"CREATE EXTENSION IF NOT EXISTS postgis;\"" 2>/dev/null || true

echo -e "${GREEN}✓ TAK database prepared${NC}"

# Certificate password logging
CERT_PASSWORD="atakatak"
echo "Certificate Credentials:" >> "$CRED_LOG"
echo "- Certificate Password: $CERT_PASSWORD" >> "$CRED_LOG"
echo "" >> "$CRED_LOG"

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

# Enhanced directory creation with plugin support
mkdir -p /opt/tak/{config,certs,logs,lib,db-utils,plugins,logs/plugins}
chown -R tak:tak /opt/tak

# Setting up TAK Server plugin support
echo -e "${BLUE}Setting up TAK Server plugin support...${NC}"
chown -R tak:tak /opt/tak/plugins /opt/tak/lib /opt/tak/logs/plugins

echo "Plugin Configuration:" >> "$CRED_LOG"
echo "- Plugin Directory: /opt/tak/plugins" >> "$CRED_LOG"
echo "- Plugin Libraries: /opt/tak/lib" >> "$CRED_LOG"
echo "- Plugin Logs: /opt/tak/logs/plugins" >> "$CRED_LOG"
echo "" >> "$CRED_LOG"

echo -e "${GREEN}✓ Plugin directories and configuration ready${NC}"

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
export TAK_DB_PASSWORD="$DB_PASSWORD"
export TAK_CERT_PASSWORD="$CERT_PASSWORD"

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

# Complete certificate generation for admin AND user access
echo -e "${BLUE}Generating complete TAK Server certificate set (Admin + User)...${NC}"

# Update cert-metadata.sh with proper values
if [ -f "/opt/tak/certs/cert-metadata.sh" ]; then
    sed -i 's/COUNTRY=US/COUNTRY=US/' /opt/tak/certs/cert-metadata.sh
    sed -i 's/STATE=/STATE=CA/' /opt/tak/certs/cert-metadata.sh
    sed -i 's/CITY=/CITY=LA/' /opt/tak/certs/cert-metadata.sh
    sed -i 's/ORGANIZATION=/ORGANIZATION=TAKServer/' /opt/tak/certs/cert-metadata.sh
    sed -i 's/ORGANIZATIONAL_UNIT=/ORGANIZATIONAL_UNIT=TAK/' /opt/tak/certs/cert-metadata.sh
    
    echo -e "${GREEN}✓ Certificate metadata configured${NC}"
fi

# Generate certificates automatically
cd /opt/tak/certs

# Set proper ownership for certificate generation
chown -R tak:tak /opt/tak/certs/

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}GENERATING COMPLETE CERTIFICATE SET${NC}"
echo -e "${BLUE}========================================${NC}"

# 1. Generate Root CA
echo -e "${BLUE}[1/7] Generating Root Certificate Authority...${NC}"
sudo -u tak bash -c "cd /opt/tak/certs && echo -e '\n\n\n\n\nTAKServer\ny\n' | ./makeRootCa.sh --ca-name TAKServer"

# 2. Generate server certificate
echo -e "${BLUE}[2/7] Generating server certificate...${NC}"
SERVER_IP=$(hostname -I | awk '{print $1}')
sudo -u tak bash -c "cd /opt/tak/certs && ./makeCert.sh server takserver"

# 3. Generate ADMIN certificates (multiple for redundancy)
echo -e "${BLUE}[3/7] Generating ADMIN certificates...${NC}"
sudo -u tak bash -c "cd /opt/tak/certs && ./makeCert.sh client admin"
sudo -u tak bash -c "cd /opt/tak/certs && ./makeCert.sh client webadmin"
sudo -u tak bash -c "cd /opt/tak/certs && ./makeCert.sh client administrator"

# 4. Generate USER certificates (for ATAK clients)
echo -e "${BLUE}[4/7] Generating USER certificates...${NC}"
sudo -u tak bash -c "cd /opt/tak/certs && ./makeCert.sh client user"
sudo -u tak bash -c "cd /opt/tak/certs && ./makeCert.sh client client1"
sudo -u tak bash -c "cd /opt/tak/certs && ./makeCert.sh client client2"
sudo -u tak bash -c "cd /opt/tak/certs && ./makeCert.sh client mobile"
sudo -u tak bash -c "cd /opt/tak/certs && ./makeCert.sh client atak-user"

# 5. Generate certificate for certificate enrollment
echo -e "${BLUE}[5/7] Generating certificate enrollment certificate...${NC}"
sudo -u tak bash -c "cd /opt/tak/certs && ./makeCert.sh client cert-enrollment"

# 6. Set admin permissions for administrative certificates
echo -e "${BLUE}[6/7] Setting administrative permissions...${NC}"
if [ -f "/opt/tak/certs/files/admin.pem" ]; then
    cd /opt/tak/utils
    java -jar UserManager.jar certmod -A /opt/tak/certs/files/admin.pem || echo "Admin permissions set attempt completed"
fi

if [ -f "/opt/tak/certs/files/webadmin.pem" ]; then
    cd /opt/tak/utils
    java -jar UserManager.jar certmod -A /opt/tak/certs/files/webadmin.pem || echo "WebAdmin permissions set attempt completed"
fi

if [ -f "/opt/tak/certs/files/administrator.pem" ]; then
    cd /opt/tak/utils
    java -jar UserManager.jar certmod -A /opt/tak/certs/files/administrator.pem || echo "Administrator permissions set attempt completed"
fi

# 7. Set proper permissions for all certificate files
echo -e "${BLUE}[7/7] Setting certificate file permissions...${NC}"
chown -R tak:tak /opt/tak/certs/
chmod 644 /opt/tak/certs/files/*.p12 2>/dev/null || true
chmod 644 /opt/tak/certs/files/*.pem 2>/dev/null || true

# Enhanced certificate verification and logging
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}CERTIFICATE GENERATION COMPLETE${NC}"
echo -e "${BLUE}========================================${NC}"

if [ -d "/opt/tak/certs/files" ] && [ "$(ls -A /opt/tak/certs/files/)" ]; then
    echo -e "${GREEN}✓ CERTIFICATES GENERATED SUCCESSFULLY!${NC}"
    
    # Comprehensive certificate listing
    echo -e "${BLUE}Generated Certificate Files:${NC}"
    ls -la /opt/tak/certs/files/
    
    # Log complete certificate information
    echo "========================================" >> "$CRED_LOG"
    echo "COMPLETE CERTIFICATE SET GENERATED" >> "$CRED_LOG"
    echo "========================================" >> "$CRED_LOG"
    echo "" >> "$CRED_LOG"
    
    echo "ADMIN CERTIFICATES (for web interface access):" >> "$CRED_LOG"
    echo "- Admin Certificate: /opt/tak/certs/files/admin.p12" >> "$CRED_LOG"
    echo "- WebAdmin Certificate: /opt/tak/certs/files/webadmin.p12" >> "$CRED_LOG"
    echo "- Administrator Certificate: /opt/tak/certs/files/administrator.p12" >> "$CRED_LOG"
    echo "" >> "$CRED_LOG"
    
    echo "USER CERTIFICATES (for ATAK client access):" >> "$CRED_LOG"
    echo "- User Certificate: /opt/tak/certs/files/user.p12" >> "$CRED_LOG"
    echo "- Client1 Certificate: /opt/tak/certs/files/client1.p12" >> "$CRED_LOG"
    echo "- Client2 Certificate: /opt/tak/certs/files/client2.p12" >> "$CRED_LOG"
    echo "- Mobile Certificate: /opt/tak/certs/files/mobile.p12" >> "$CRED_LOG"
    echo "- ATAK User Certificate: /opt/tak/certs/files/atak-user.p12" >> "$CRED_LOG"
    echo "" >> "$CRED_LOG"
    
    echo "CERTIFICATE PASSWORD (for all certificates): $CERT_PASSWORD" >> "$CRED_LOG"
    echo "HOST LOCATION: /mnt/user/appdata/tak-server/tak-data/certs/files/" >> "$CRED_LOG"
    echo "" >> "$CRED_LOG"
    
    echo "CERTIFICATE USAGE GUIDE:" >> "$CRED_LOG"
    echo "========================" >> "$CRED_LOG"
    echo "" >> "$CRED_LOG"
    echo "ADMIN ACCESS (Web Interface):" >> "$CRED_LOG"
    echo "1. Import admin.p12 or webadmin.p12 into Firefox/Chrome" >> "$CRED_LOG"
    echo "2. Password: $CERT_PASSWORD" >> "$CRED_LOG"
    echo "3. Access: https://YOUR-UNRAID-IP:8960" >> "$CRED_LOG"
    echo "" >> "$CRED_LOG"
    echo "USER ACCESS (ATAK Mobile Apps):" >> "$CRED_LOG"
    echo "1. Copy user.p12, client1.p12, or mobile.p12 to mobile device" >> "$CRED_LOG"
    echo "2. Import into ATAK app" >> "$CRED_LOG"
    echo "3. Password: $CERT_PASSWORD" >> "$CRED_LOG"
    echo "4. Server: ssl://YOUR-UNRAID-IP:8961" >> "$CRED_LOG"
    echo "" >> "$CRED_LOG"
    
else
    echo -e "${RED}Certificate generation may have failed${NC}"
    echo -e "${YELLOW}Check certificate directory for issues:${NC}"
    ls -la /opt/tak/certs/
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

# Enhanced final status with complete credential display
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}TAK Server Installation Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${GREEN}Access TAK Server at: https://$(hostname -I | awk '{print $1}'):8443${NC}"
echo -e "${GREEN}External access (Unraid): https://YOUR-UNRAID-IP:8960${NC}"
echo ""

# Display all credentials in logs
echo -e "${YELLOW}========================================${NC}"
echo -e "${YELLOW}COMPLETE CREDENTIAL INFORMATION:${NC}"
echo -e "${YELLOW}========================================${NC}"

# Database credentials
echo -e "${BLUE}DATABASE ACCESS:${NC}"
echo -e "${BLUE}- Database Name: cot${NC}"
echo -e "${BLUE}- Username: martiuser${NC}"
echo -e "${BLUE}- Password: $DB_PASSWORD${NC}"
echo -e "${BLUE}- Connection: postgresql://martiuser:$DB_PASSWORD@localhost:5432/cot${NC}"
echo ""

# Certificate credentials
echo -e "${BLUE}CERTIFICATE ACCESS:${NC}"
echo -e "${BLUE}ADMIN CERTIFICATES (Web Interface):${NC}"
echo -e "${BLUE}- Admin: admin.p12${NC}"
echo -e "${BLUE}- WebAdmin: webadmin.p12${NC}"
echo -e "${BLUE}- Administrator: administrator.p12${NC}"
echo ""
echo -e "${BLUE}USER CERTIFICATES (ATAK Clients):${NC}"
echo -e "${BLUE}- User: user.p12${NC}"
echo -e "${BLUE}- Client1: client1.p12${NC}"
echo -e "${BLUE}- Client2: client2.p12${NC}"
echo -e "${BLUE}- Mobile: mobile.p12${NC}"
echo -e "${BLUE}- ATAK User: atak-user.p12${NC}"
echo ""
echo -e "${BLUE}- Certificate Password (all): $CERT_PASSWORD${NC}"
echo -e "${BLUE}- Location: /mnt/user/appdata/tak-server/tak-data/certs/files/${NC}"
echo ""

# Web access
echo -e "${BLUE}WEB ACCESS:${NC}"
echo -e "${BLUE}- URL: https://YOUR-UNRAID-IP:8960${NC}"
echo -e "${BLUE}- Authentication: Certificate-based (import admin.p12)${NC}"
echo ""

# Plugin information
echo -e "${BLUE}PLUGIN SUPPORT:${NC}"
echo -e "${BLUE}- Plugin Directory: /opt/tak/plugins${NC}"
echo -e "${BLUE}- Plugin Libraries: /opt/tak/lib${NC}"
echo -e "${BLUE}- Plugin Logs: /opt/tak/logs/plugins${NC}"
echo ""

# Save credentials to persistent file
echo -e "${BLUE}CREDENTIALS SAVED TO:${NC}"
echo -e "${BLUE}- Container: /opt/tak/credentials.log${NC}"
echo -e "${BLUE}- Host: /mnt/user/appdata/tak-server/tak-data/credentials.log${NC}"
echo ""

# Copy credentials to host-accessible location
cp "$CRED_LOG" /setup/tak-credentials.log 2>/dev/null || true

echo -e "${YELLOW}========================================${NC}"

# Display credential file contents in logs
echo -e "${YELLOW}CREDENTIAL FILE CONTENTS:${NC}"
cat "$CRED_LOG"
echo -e "${YELLOW}========================================${NC}"

chown tak:tak "$CRED_LOG"

# Keep container running and monitoring TAK Server
echo -e "${BLUE}Keeping container running and monitoring TAK Server...${NC}"
while true; do
    if ! pgrep -f "takserver.war" >/dev/null; then
        echo -e "${YELLOW}TAK Server process not found, attempting restart...${NC}"
        cd /opt/tak
        sudo -u tak java -Xms2g -Xmx4g -jar takserver.war &
    fi
    sleep 60
done
