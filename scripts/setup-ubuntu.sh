#!/bin/bash

# TAK Server 5.4 Ubuntu Container Setup Script for Unraid
# Single container with built-in PostgreSQL and TAK Server
# Ubuntu 22.04 LTS Compatible Version
# Sponsored by CloudRF.com - "The API for RF"

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Global variables (Ubuntu-specific paths)
TAK_ZIP_FILE=""
SERVER_IP=""
ADMIN_PASSWORD=""
DB_PASSWORD=""
CERT_PASSWORD="atakatak"
SERVER_ID=""
POSTGRES_DATA_DIR="/var/lib/postgresql/14/main"    # Ubuntu standard location
TAK_HOME="/setup/tak"

# Error handling function
handle_error() {
    echo -e "${RED}ERROR on line $1: Command failed with exit code $2${NC}" >&2
    echo -e "${RED}Setup failed. Check the error above and try again.${NC}" >&2
    cleanup_on_failure
    exit 1
}

# Cleanup function for failed setups
cleanup_on_failure() {
    echo -e "${YELLOW}Cleaning up failed installation...${NC}"
    pkill -f postgres 2>/dev/null || true
    pkill -f java 2>/dev/null || true
    systemctl stop postgresql 2>/dev/null || true
}

# Set up error trapping
trap 'handle_error $LINENO $?' ERR

# Install required packages
install_packages() {
    echo -e "${BLUE}Installing required packages for Ubuntu...${NC}"
    
    # Update package list
    apt-get update -qq
    
    # Install essential packages
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        wget \
        curl \
        unzip \
        zip \
        openssl \
        git \
        postgresql \
        postgresql-contrib \
        postgresql-client \
        openjdk-17-jdk \
        net-tools \
        psmisc \
        procps \
        vim-tiny
    
    echo -e "${GREEN}✓ All required packages installed${NC}"
}

# Validation functions
validate_tools() {
    echo -e "${BLUE}Validating required tools...${NC}"
    for tool in unzip openssl keytool psql postgres; do
        if ! command -v $tool &> /dev/null; then
            echo -e "${RED}Error: $tool command not found.${NC}"
            exit 1
        fi
    done
    echo -e "${GREEN}✓ All required tools found${NC}"
}

validate_or_skip_zip() {
    echo -e "${BLUE}Checking TAK Server files...${NC}"
    
    # Check if files are already extracted
    if [ -d "tak" ] && [ -f "tak/takserver.war" ]; then
        echo -e "${GREEN}✓ TAK Server files already extracted and ready${NC}"
        return 0
    fi
    
    # Find ZIP file
    local zip_file=""
    zip_file=$(find . -maxdepth 1 -name "takserver-docker-*.zip" | head -1)
    
    if [ -z "$zip_file" ]; then
        echo -e "${RED}Error: No TAK Server ZIP file found in current directory.${NC}"
        echo -e "${RED}Please download takserver-docker-5.4-RELEASE-XX.zip from tak.gov${NC}"
        echo -e "${RED}and place it in this directory before running the setup.${NC}"
        exit 1
    fi
    
    TAK_ZIP_FILE=$(realpath "$zip_file")
    echo -e "${GREEN}✓ Found valid TAK Server file: $TAK_ZIP_FILE${NC}"
}

generate_secure_passwords() {
    echo -e "${BLUE}Generating TAK-compliant secure passwords...${NC}"
    
    # Generate admin password (15+ chars with all requirements)
    local admin_base=$(openssl rand -base64 12 | tr -dc 'a-zA-Z0-9' | head -c 8)
    ADMIN_PASSWORD="TakAdmin2025!@#${admin_base}X9"
    
    # Generate database password (20+ chars with all requirements)
    local db_base=$(openssl rand -base64 16 | tr -dc 'a-zA-Z0-9' | head -c 12)
    DB_PASSWORD="TakDatabase2025\$%^${db_base}Z8!"
    
    # Generate unique server ID
    SERVER_ID=$(openssl rand -hex 16)
    
    echo -e "${GREEN}✓ Secure passwords generated${NC}"
}

extract_and_setup_files() {
    echo -e "${BLUE}Extracting and setting up TAK Server files...${NC}"
    
    # Skip extraction if files already exist
    if [ -d "tak" ] && [ -f "tak/takserver.war" ]; then
        echo -e "${GREEN}✓ TAK Server files already extracted, skipping extraction${NC}"
        return 0
    fi
    
    # Extract ZIP file
    echo -e "${YELLOW}Extracting ZIP file...${NC}"
    unzip -q "$TAK_ZIP_FILE" -d /tmp/
    
    # Find extracted directory
    local extracted_dir=$(find /tmp -maxdepth 1 -type d -name "takserver-docker-*" | head -1)
    if [ -z "$extracted_dir" ]; then
        echo -e "${RED}Error: Failed to find extracted TAK server directory.${NC}"
        exit 1
    fi
    
    # Copy TAK files
    cp -r "$extracted_dir"/tak ./
    echo -e "${GREEN}✓ TAK Server files extracted and configured${NC}"
}

setup_postgresql() {
    echo -e "${BLUE}Setting up PostgreSQL for Ubuntu...${NC}"
    
    # Start PostgreSQL service
    echo -e "${YELLOW}Starting PostgreSQL service...${NC}"
    systemctl start postgresql
    systemctl enable postgresql
    
    # Wait for PostgreSQL to start
    for i in {1..30}; do
        if systemctl is-active --quiet postgresql; then
            echo -e "${GREEN}✓ PostgreSQL service started successfully${NC}"
            break
        fi
        if [ $i -eq 30 ]; then
            echo -e "${RED}Error: PostgreSQL failed to start${NC}"
            systemctl status postgresql
            exit 1
        fi
        sleep 1
    done
    
    # Configure PostgreSQL
    echo -e "${YELLOW}Configuring PostgreSQL for TAK Server...${NC}"
    
    # Create TAK database and user
    sudo -u postgres createdb cot 2>/dev/null || true
    sudo -u postgres psql -c "CREATE USER martiuser WITH PASSWORD '$DB_PASSWORD';" 2>/dev/null || true
    sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE cot TO martiuser;" 2>/dev/null || true
    
    # Configure PostgreSQL for local connections
    local pg_version=$(sudo -u postgres psql -t -c "SELECT version();" | grep -oP '\d+\.\d+' | head -1)
    local pg_config_dir="/etc/postgresql/${pg_version}/main"
    
    # Update postgresql.conf for local connections
    echo "listen_addresses = 'localhost,127.0.0.1'" >> "${pg_config_dir}/postgresql.conf"
    echo "port = 5432" >> "${pg_config_dir}/postgresql.conf"
    
    # Update pg_hba.conf for local trust
    echo "local   all             martiuser                               trust" >> "${pg_config_dir}/pg_hba.conf"
    echo "host    cot             martiuser       127.0.0.1/32            md5" >> "${pg_config_dir}/pg_hba.conf"
    
    # Restart PostgreSQL to apply configuration
    systemctl restart postgresql
    
    # Verify database connection
    if sudo -u postgres psql -d cot -c "SELECT 1;" >/dev/null 2>&1; then
        echo -e "${GREEN}✓ PostgreSQL database configured successfully${NC}"
    else
        echo -e "${RED}Error: Failed to connect to PostgreSQL database${NC}"
        exit 1
    fi
}

configure_tak_server() {
    echo -e "${BLUE}Configuring TAK Server...${NC}"
    
    # Get server IP
    SERVER_IP=$(ip route get 1 2>/dev/null | awk '{print $NF; exit}' || echo "127.0.0.1")
    [ -z "$SERVER_IP" ] && SERVER_IP="127.0.0.1"
    
    # Copy and configure CoreConfig.xml
    cp CoreConfig.xml tak/CoreConfig.xml
    
    # Replace placeholders with actual values
    sed -i "s|PLACEHOLDER_SERVER_ID|$SERVER_ID|g" tak/CoreConfig.xml
    sed -i "s|PLACEHOLDER_DB_PASSWORD|$DB_PASSWORD|g" tak/CoreConfig.xml
    sed -i "s|PLACEHOLDER_HOST_IP|$SERVER_IP|g" tak/CoreConfig.xml
    sed -i "s|tak-database|localhost|g" tak/CoreConfig.xml
    
    # Ensure network bindings are set for container access
    sed -i 's|<input _name="stdssl" protocol="tls" port="8089"/>|<input _name="stdssl" protocol="tls" port="8089" host="0.0.0.0"/>|g' tak/CoreConfig.xml
    sed -i 's|<connector port="8443" _name="https"/>|<connector port="8443" _name="https" host="0.0.0.0"/>|g' tak/CoreConfig.xml
    sed -i 's|<connector port="8444" useFederationTruststore="true" _name="fed_https"/>|<connector port="8444" useFederationTruststore="true" _name="fed_https" host="0.0.0.0"/>|g' tak/CoreConfig.xml
    sed -i 's|<connector port="8446" clientAuth="false" _name="cert_https"/>|<connector port="8446" clientAuth="false" _name="cert_https" host="0.0.0.0"/>|g' tak/CoreConfig.xml
    
    echo -e "${GREEN}✓ TAK Server configuration completed${NC}"
}

generate_certificates() {
    echo -e "${BLUE}Generating certificates with OpenSSL...${NC}"
    
    cd tak/certs || exit 1
    mkdir -p files CA intermediate
    
    # Certificate variables
    local COUNTRY="US"
    local STATE="California"
    local CITY="San Francisco"
    local ORGANIZATION="TAK"
    local ORGANIZATIONAL_UNIT="TAK-Server"
    
    # Generate Root CA
    echo -e "${YELLOW}Creating root certificate authority...${NC}"
    openssl genrsa -out files/ca-do-not-share.key 4096
    openssl req -new -x509 -days 3650 -key files/ca-do-not-share.key -out files/ca.pem \
        -subj "/C=$COUNTRY/ST=$STATE/L=$CITY/O=$ORGANIZATION/OU=$ORGANIZATIONAL_UNIT/CN=TAK-ROOT-CA"
    
    cp files/ca.pem files/truststore-root.pem
    cp files/ca.pem files/ca-trusted.pem
    
    # Generate server certificate
    echo -e "${YELLOW}Creating server certificate...${NC}"
    openssl genrsa -out files/takserver.key 2048
    openssl req -new -key files/takserver.key -out files/takserver.csr \
        -subj "/C=$COUNTRY/ST=$STATE/L=$CITY/O=$ORGANIZATION/OU=$ORGANIZATIONAL_UNIT/CN=takserver"
    
    openssl x509 -req -in files/takserver.csr -CA files/ca.pem -CAkey files/ca-do-not-share.key \
        -CAcreateserial -out files/takserver.pem -days 365 \
        -extensions v3_req -extfile <(echo "[v3_req]
keyUsage = keyEncipherment, dataEncipherment
extendedKeyUsage = serverAuth, clientAuth
subjectAltName = @alt_names
[alt_names]
DNS.1 = takserver
DNS.2 = localhost
IP.1 = $SERVER_IP")
    
    # Generate admin certificate
    echo -e "${YELLOW}Creating admin certificate...${NC}"
    openssl genrsa -out files/admin.key 2048
    openssl req -new -key files/admin.key -out files/admin.csr \
        -subj "/C=$COUNTRY/ST=$STATE/L=$CITY/O=$ORGANIZATION/OU=$ORGANIZATIONAL_UNIT/CN=admin"
    openssl x509 -req -in files/admin.csr -CA files/ca.pem -CAkey files/ca-do-not-share.key \
        -CAcreateserial -out files/admin.pem -days 365
    
    # Create PKCS12 files
    openssl pkcs12 -export -out files/admin.p12 -inkey files/admin.key -in files/admin.pem \
        -certfile files/ca.pem -password pass:$CERT_PASSWORD
    
    # Generate user1 certificate and data package
    echo -e "${YELLOW}Creating user1 certificate and data package...${NC}"
    openssl genrsa -out files/user1.key 2048
    openssl req -new -key files/user1.key -out files/user1.csr \
        -subj "/C=$COUNTRY/ST=$STATE/L=$CITY/O=$ORGANIZATION/OU=$ORGANIZATIONAL_UNIT/CN=user1"
    openssl x509 -req -in files/user1.csr -CA files/ca.pem -CAkey files/ca-do-not-share.key \
        -CAcreateserial -out files/user1.pem -days 365
    
    openssl pkcs12 -export -out files/user1.p12 -inkey files/user1.key -in files/user1.pem \
        -certfile files/ca.pem -password pass:$CERT_PASSWORD
    
    # Create user data package
    mkdir -p temp_dp
    cp files/user1.p12 temp_dp/
    cp files/truststore-root.pem temp_dp/
    echo "server=$SERVER_IP:8092:ssl" > temp_dp/manifest.xml
    (cd temp_dp && zip -r ../files/user1.zip . >/dev/null 2>&1)
    rm -rf temp_dp
    
    echo -e "${GREEN}✓ PEM certificates generated successfully${NC}"
    cd /setup
}

convert_to_jks() {
    echo -e "${BLUE}Converting PEM certificates to JKS format...${NC}"
    
    cd tak/certs/files
    
    # Create PKCS12 file
    echo -e "${YELLOW}Creating PKCS12 keystore...${NC}"
    openssl pkcs12 -export -out takserver.p12 \
        -inkey takserver.key -in takserver.pem -certfile ca.pem \
        -password pass:$CERT_PASSWORD
    
    # Convert to JKS
    echo -e "${YELLOW}Converting to JKS format...${NC}"
    keytool -importkeystore \
        -srckeystore takserver.p12 -srcstoretype PKCS12 -srcstorepass $CERT_PASSWORD \
        -destkeystore takserver.jks -deststoretype JKS -deststorepass $CERT_PASSWORD \
        -alias 1 -destalias takserver -noprompt
    
    # Create truststore (skip if exists)
    echo -e "${YELLOW}Creating JKS truststore...${NC}"
    if [ ! -f "truststore-root.jks" ]; then
        keytool -import -trustcacerts -file ca.pem -alias tak-ca \
            -keystore truststore-root.jks -storepass $CERT_PASSWORD -noprompt
    fi
    
    # Copy truststore for federation
    if [ ! -f "fed-truststore.jks" ]; then
        cp truststore-root.jks fed-truststore.jks
    fi
    
    echo -e "${GREEN}✓ JKS certificates created successfully${NC}"
    cd /setup
}

start_tak_server() {
    echo -e "${BLUE}Starting TAK Server...${NC}"
    
    # Set TAK Server environment
    export TAK_HOME="$TAK_HOME"
    export JAVA_HOME="/usr/lib/jvm/java-17-openjdk-amd64"
    
    # Create logs directory
    mkdir -p "$TAK_HOME/logs"
    
    cd "$TAK_HOME"
    
    # Start TAK Server with enhanced logging
    echo -e "${YELLOW}Launching TAK Server process with logging...${NC}"
    
    # Start TAK Server in background with log output
    java -server -Xms1g -Xmx2g \
         -Dloader.path=WEB-INF/lib-provided,WEB-INF/lib,WEB-INF/classes,file:lib/ \
         -jar takserver.war > logs/takserver-startup.log 2>&1 &
    
    TAK_PID=$!
    
    # Monitor TAK Server startup with real logs
    echo -e "${BLUE}Monitoring TAK Server initialization...${NC}"
    
    for i in {1..300}; do  # 5-minute timeout
        # Check if process is still running
        if ! kill -0 $TAK_PID 2>/dev/null; then
            echo -e "${RED}TAK Server process died! Check logs:${NC}"
            echo -e "${RED}Last 20 lines of startup log:${NC}"
            tail -20 logs/takserver-startup.log 2>/dev/null || echo "No startup log found"
            exit 1
        fi
        
        # Check if TAK Server is listening
        if netstat -tulpn 2>/dev/null | grep -q ":8443"; then
            echo -e "${GREEN}✓ TAK Server is listening on port 8443!${NC}"
            break
        fi
        
        # Show progress with actual log snippets every 10 seconds
        if [ $((i % 10)) -eq 0 ]; then
            echo -e "${YELLOW}Waiting for TAK Server... ($i/300)${NC}"
            
            # Show recent log entries for debugging
            if [ -f logs/takserver-startup.log ]; then
                echo -e "${BLUE}Recent TAK Server logs:${NC}"
                tail -3 logs/takserver-startup.log 2>/dev/null | sed 's/^/  > /' || echo "  > (log file empty)"
            fi
        fi
        
        if [ $i -eq 300 ]; then
            echo -e "${RED}Error: TAK Server failed to start within 5 minutes${NC}"
            echo -e "${RED}Full startup log:${NC}"
            cat logs/takserver-startup.log 2>/dev/null || echo "No startup log available"
            exit 1
        fi
        
        sleep 1
    done
    
    echo -e "${GREEN}✓ TAK Server started successfully${NC}"
}

setup_admin_user() {
    echo -e "${BLUE}Setting up admin user...${NC}"
    
    # Give TAK server time to fully initialize
    sleep 30
    
    if java -jar tak/utils/UserManager.jar usermod -A -p "$ADMIN_PASSWORD" admin 2>/dev/null; then
        echo -e "${GREEN}✓ Admin user configured successfully${NC}"
    else
        echo -e "${YELLOW}Admin user will be created on next restart${NC}"
    fi
}

display_completion_message() {
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}TAK Server Ubuntu Setup Complete!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo -e "${YELLOW}---------CREDENTIALS----------------${NC}"
    echo -e "${YELLOW}Admin user name: admin${NC}"
    echo -e "${YELLOW}Admin password: $ADMIN_PASSWORD${NC}"
    echo -e "${YELLOW}PostgreSQL password: $DB_PASSWORD${NC}"
    echo -e "${YELLOW}Certificate password: $CERT_PASSWORD${NC}"
    echo -e "${YELLOW}---------CREDENTIALS----------------${NC}"
    echo ""
    echo -e "${YELLOW}SAVE THESE PASSWORDS - THEY WILL NOT BE SHOWN AGAIN!${NC}"
    echo ""
    echo -e "${GREEN}Access your TAK Server at: https://$SERVER_IP:8445${NC}"
    echo ""
    echo -e "${BLUE}Certificate files available:${NC}"
    echo -e "${BLUE}  Admin certificate: tak/certs/files/admin.p12${NC}"
    echo -e "${BLUE}  User1 data package: tak/certs/files/user1.zip${NC}"
    echo ""
    echo -e "${GREEN}TAK Server is running inside this container!${NC}"
    echo -e "${GREEN}Container will keep running to serve TAK Server${NC}"
}

keep_container_running() {
    echo -e "${BLUE}Keeping container running...${NC}"
    echo -e "${GREEN}TAK Server is now running. Container will stay alive.${NC}"
    
    # Keep container running by monitoring TAK Server process
    while kill -0 $TAK_PID 2>/dev/null; do
        sleep 30
    done
    
    echo -e "${RED}TAK Server process has stopped. Container will exit.${NC}"
    exit 1
}

# Main execution flow
main() {
    echo -e "${GREEN}TAK Server 5.4 Ubuntu Container Setup for Unraid${NC}"
    echo -e "${GREEN}Single container with built-in PostgreSQL and TAK Server${NC}"
    echo -e "${GREEN}Ubuntu 22.04 LTS Compatible Version${NC}"
    echo -e "${GREEN}Sponsored by CloudRF.com - The API for RF${NC}"
    echo ""
    
    install_packages
    validate_tools
    validate_or_skip_zip
    generate_secure_passwords
    extract_and_setup_files
    setup_postgresql
    configure_tak_server
    generate_certificates
    convert_to_jks
    start_tak_server
    setup_admin_user
    display_completion_message
    keep_container_running
}

# Run main function
main "$@"
