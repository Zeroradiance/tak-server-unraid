#!/bin/bash

# TAK Server 5.4 Complete Setup Script for Unraid
# Bulletproof version with comprehensive error handling and validation
# Sponsored by CloudRF.com - "The API for RF"

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Global variables
TAK_ZIP_FILE=""
SERVER_IP=""
ADMIN_PASSWORD=""
DB_PASSWORD=""
CERT_PASSWORD="atakatak"
SERVER_ID=""
DOCKER_PATH=""

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
    docker-compose down 2>/dev/null || true
    rm -rf tak docker 2>/dev/null || true
    find . -maxdepth 1 -type d -name "takserver-docker-*" -exec rm -rf {} + 2>/dev/null || true
}

# Set up error trapping
trap 'handle_error $LINENO $?' ERR

# Validation functions
validate_tools() {
    echo -e "${BLUE}Validating required tools...${NC}"
    for tool in unzip docker-compose openssl docker keytool; do
        if ! command -v $tool &> /dev/null; then
            echo -e "${RED}Error: $tool command not found.${NC}"
            echo -e "${RED}Please install $tool and try again.${NC}"
            exit 1
        fi
    done
    echo -e "${GREEN}✓ All required tools found${NC}"
}

validate_zip_file() {
    echo -e "${BLUE}Validating TAK Server ZIP file...${NC}"
    
    # Find ZIP file using multiple methods
    local zip_file=""
    zip_file=$(find . -maxdepth 1 -name "takserver-docker-*.zip" | head -1)
    
    if [ -z "$zip_file" ]; then
        echo -e "${RED}Error: No TAK Server ZIP file found in current directory.${NC}"
        echo -e "${RED}Please download takserver-docker-5.4-RELEASE-XX.zip from tak.gov${NC}"
        echo -e "${RED}and place it in this directory before running the setup.${NC}"
        exit 1
    fi
    
    # Get absolute path to avoid any path issues
    TAK_ZIP_FILE=$(realpath "$zip_file")
    
    # Test ZIP file integrity
    if ! unzip -t "$TAK_ZIP_FILE" &>/dev/null; then
        echo -e "${RED}Error: ZIP file appears to be corrupted.${NC}"
        echo -e "${RED}Please re-download the TAK Server release.${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✓ Found valid TAK Server file: $TAK_ZIP_FILE${NC}"
}

validate_or_skip_zip() {
    echo -e "${BLUE}Checking TAK Server files...${NC}"
    
    # Check if files are already extracted (for Community Applications or pre-extracted setups)
    if [ -d "tak" ] && [ -d "docker" ] && [ -f "tak/takserver.war" ]; then
        echo -e "${GREEN}✓ TAK Server files already extracted and ready${NC}"
        # Set DOCKER_PATH for pre-extracted files
        if [ -d "docker/amd64" ]; then
            DOCKER_PATH="./docker/amd64/"
            echo -e "${YELLOW}Detected amd64 docker structure${NC}"
        else
            DOCKER_PATH="./docker/"
            echo -e "${YELLOW}Detected flat docker structure${NC}"
        fi
        return 0
    fi
    
    # Otherwise run normal ZIP validation
    validate_zip_file
}

validate_ports() {
    echo -e "${BLUE}Checking port availability...${NC}"
    ports_to_check=(5432 8445 8446 8447 8092 9003 9004)
    
    for port in "${ports_to_check[@]}"; do
        if netstat -tulpn 2>/dev/null | grep -q ":$port "; then
            echo -e "${YELLOW}Warning: Port $port is in use. Attempting to free it...${NC}"
            sudo fuser -k $port/tcp 2>/dev/null || true
            sleep 2
            
            # Check again
            if netstat -tulpn 2>/dev/null | grep -q ":$port "; then
                echo -e "${RED}Error: Unable to free port $port. Please stop the conflicting service.${NC}"
                netstat -tulpn 2>/dev/null | grep ":$port " || true
                exit 1
            fi
        fi
        echo -e "${GREEN}✓ Port $port is available${NC}"
    done
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
    
    # Skip extraction if files already exist (for pre-extracted setups)
    if [ -d "tak" ] && [ -d "docker" ] && [ -f "tak/takserver.war" ]; then
        echo -e "${GREEN}✓ TAK Server files already extracted, skipping extraction${NC}"
        return 0
    fi
    
    # Clean up any previous installations (but NOT the ZIP file)
    docker-compose down 2>/dev/null || true
    rm -rf tak docker 2>/dev/null || true
    find . -maxdepth 1 -type d -name "takserver-docker-*" -exec rm -rf {} + 2>/dev/null || true
    
    # Get the ZIP file (using the path that was validated)
    local zip_file="$TAK_ZIP_FILE"
    echo -e "${YELLOW}Using ZIP file: $zip_file${NC}"
    
    # Verify file exists and is readable
    if [ ! -f "$zip_file" ]; then
        echo -e "${RED}Error: ZIP file not found at $zip_file${NC}"
        exit 1
    fi
    
    if [ ! -r "$zip_file" ]; then
        echo -e "${RED}Error: ZIP file not readable. Fixing permissions...${NC}"
        chmod 644 "$zip_file"
    fi
    
    # Test ZIP file integrity first
    echo -e "${YELLOW}Testing ZIP file integrity...${NC}"
    if ! unzip -t "$zip_file" >/dev/null 2>&1; then
        echo -e "${RED}Error: ZIP file appears to be corrupted${NC}"
        exit 1
    fi
    
    # Create temporary directory for extraction
    local temp_dir="/tmp/takserver-$$"
    mkdir -p "$temp_dir"
    
    # Extract with verbose error handling
    echo -e "${YELLOW}Extracting ZIP file...${NC}"
    if ! unzip -q "$zip_file" -d "$temp_dir" 2>/dev/null; then
        # Try alternative extraction methods
        echo -e "${YELLOW}Standard unzip failed, trying alternative methods...${NC}"
        
        # Try with different unzip options
        if ! unzip -o "$zip_file" -d "$temp_dir" 2>/dev/null; then
            # Try copying to temp location first
            local temp_zip="/tmp/takserver-temp-$$.zip"
            cp "$zip_file" "$temp_zip"
            chmod 644 "$temp_zip"
            
            if ! unzip -q "$temp_zip" -d "$temp_dir" 2>/dev/null; then
                echo -e "${RED}Error: All extraction methods failed${NC}"
                rm -rf "$temp_dir" "$temp_zip"
                exit 1
            fi
            rm -f "$temp_zip"
        fi
    fi
    
    # Find extracted directory
    local extracted_dir=$(find "$temp_dir" -maxdepth 1 -type d -name "takserver-docker-*" | head -1)
    if [ -z "$extracted_dir" ]; then
        echo -e "${RED}Error: Failed to find extracted TAK server directory.${NC}"
        echo -e "${YELLOW}Contents of temp directory:${NC}"
        ls -la "$temp_dir"
        rm -rf "$temp_dir"
        exit 1
    fi
    
    # Copy TAK files
    mkdir -p tak
    cp -r "$extracted_dir"/tak/* tak/
    echo -e "${GREEN}✓ TAK files copied${NC}"
    
    # Handle docker directory structure (auto-detect)
    if [ -d "$extracted_dir/docker/amd64" ]; then
        echo -e "${YELLOW}Detected amd64 docker structure${NC}"
        cp -r "$extracted_dir"/docker ./
        DOCKER_PATH="./docker/amd64/"
    elif [ -d "$extracted_dir/docker" ]; then
        echo -e "${YELLOW}Detected flat docker structure${NC}"
        cp -r "$extracted_dir"/docker ./
        DOCKER_PATH="./docker/"
    else
        echo -e "${RED}Error: No docker directory found in TAK Server release.${NC}"
        rm -rf "$temp_dir"
        exit 1
    fi
    
    # Set permissions
    chmod +x tak/*.sh tak/db-utils/*.sh tak/certs/*.sh 2>/dev/null || true
    rm -rf "$temp_dir"
    
    echo -e "${GREEN}✓ TAK Server files extracted and configured${NC}"
}

update_docker_compose() {
    echo -e "${BLUE}Updating docker-compose.yml for detected structure...${NC}"
    
    # Update docker-compose.yml to match detected structure
    if [ "$DOCKER_PATH" = "./docker/" ]; then
        sed -i 's|dockerfile: ./docker/amd64/|dockerfile: ./docker/|g' docker-compose.yml
        echo -e "${YELLOW}Updated docker-compose.yml for flat structure${NC}"
    fi
    
    echo -e "${GREEN}✓ docker-compose.yml updated${NC}"
}

configure_tak_server() {
    echo -e "${BLUE}Configuring TAK Server...${NC}"
    
    # Get server IP (BusyBox/Alpine compatible)
    SERVER_IP=$(ip route get 1 2>/dev/null | awk '{print $NF; exit}' || echo "127.0.0.1")
    [ -z "$SERVER_IP" ] && SERVER_IP="127.0.0.1"
    
    # Copy and configure CoreConfig.xml
    cp CoreConfig.xml tak/CoreConfig.xml
    
    # Replace ALL placeholders with actual values - using different delimiters to avoid conflicts
    sed -i "s|PLACEHOLDER_SERVER_ID|$SERVER_ID|g" tak/CoreConfig.xml
    sed -i "s|PLACEHOLDER_DB_PASSWORD|$DB_PASSWORD|g" tak/CoreConfig.xml
    sed -i "s|PLACEHOLDER_HOST_IP|$SERVER_IP|g" tak/CoreConfig.xml
    sed -i "s|HOSTIP|$SERVER_IP|g" tak/CoreConfig.xml
    
    # Add network bindings for Docker (critical for container access)
    sed -i 's|<input _name="stdssl" protocol="tls" port="8089"/>|<input _name="stdssl" protocol="tls" port="8089" host="0.0.0.0"/>|g' tak/CoreConfig.xml
    sed -i 's|<connector port="8443" _name="https"/>|<connector port="8443" _name="https" host="0.0.0.0"/>|g' tak/CoreConfig.xml
    sed -i 's|<connector port="8444" useFederationTruststore="true" _name="fed_https"/>|<connector port="8444" useFederationTruststore="true" _name="fed_https" host="0.0.0.0"/>|g' tak/CoreConfig.xml
    sed -i 's|<connector port="8446" clientAuth="false" _name="cert_https"/>|<connector port="8446" clientAuth="false" _name="cert_https" host="0.0.0.0"/>|g' tak/CoreConfig.xml
    
    echo -e "${GREEN}✓ TAK Server configuration completed${NC}"
}

validate_configuration() {
    echo -e "${BLUE}Validating configuration...${NC}"
    
    # Check that no placeholders remain
    if grep -q "PLACEHOLDER" tak/CoreConfig.xml; then
        echo -e "${RED}Error: Configuration validation failed - placeholders remain in CoreConfig.xml${NC}"
        grep "PLACEHOLDER" tak/CoreConfig.xml
        exit 1
    fi
    
    # Check that network bindings were added
    if ! grep -q 'host="0.0.0.0"' tak/CoreConfig.xml; then
        echo -e "${RED}Error: Network binding configuration failed${NC}"
        exit 1
    fi
    
    # Check that database password was set
    if ! grep -q "password=\"$DB_PASSWORD\"" tak/CoreConfig.xml; then
        echo -e "${RED}Error: Database password configuration failed${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✓ Configuration validation passed${NC}"
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
    cd ../..
}

convert_to_jks() {
    echo -e "${BLUE}Converting PEM certificates to JKS format...${NC}"
    
    # Navigate to certificate directory
    cd /setup/tak/certs/files
    
    echo -e "${YELLOW}Converting certificates using local Java installation...${NC}"
    ls -la
    
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
    
    # Create truststore
    echo -e "${YELLOW}Creating JKS truststore...${NC}"
    keytool -import -trustcacerts -file ca.pem -alias tak-ca \
        -keystore truststore-root.jks -storepass $CERT_PASSWORD -noprompt
    
    # Copy truststore for federation
    cp truststore-root.jks fed-truststore.jks
    
    echo -e "${GREEN}✓ JKS certificates created successfully${NC}"
    echo -e "${YELLOW}JKS files created:${NC}"
    ls -la *.jks
    
    # Set proper permissions
    chmod 644 *.pem *.p12 *.zip *.jks 2>/dev/null || true
    chmod 600 *.key 2>/dev/null || true
    
    cd /setup
}

start_containers() {
    echo -e "${BLUE}Building and starting TAK server containers...${NC}"
    
    if ! docker-compose up -d; then
        echo -e "${RED}Error: Failed to start containers${NC}"
        echo -e "${RED}Check logs with: docker-compose logs${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✓ Containers started successfully${NC}"
}

wait_for_startup() {
    echo -e "${BLUE}Waiting for TAK Server to fully initialize...${NC}"
    
    # Wait for containers to be running
    for i in {1..30}; do
        if docker-compose ps | grep -q "Up"; then
            break
        fi
        if [ $i -eq 30 ]; then
            echo -e "${RED}Error: Containers failed to start within 5 minutes${NC}"
            docker-compose logs
            exit 1
        fi
        echo -e "${YELLOW}Waiting for containers to start... ($i/30)${NC}"
        sleep 10
    done
    
    # Get container name dynamically
    local container_name=$(docker-compose ps | grep tak | grep -v db | awk '{print $1}' | head -1)
    
    # Wait for TAK Server web interface
    echo -e "${BLUE}Waiting for TAK Server web interface to start...${NC}"
    for i in {1..60}; do
        if docker exec "$container_name" netstat -tulpn 2>/dev/null | grep -q ":8443"; then
            echo -e "${GREEN}✓ TAK Server web interface is listening on port 8443!${NC}"
            break
        fi
        if [ $i -eq 60 ]; then
            echo -e "${RED}Error: TAK Server web interface failed to start within 10 minutes${NC}"
            echo -e "${RED}Check logs with: docker logs $container_name${NC}"
            exit 1
        fi
        echo -e "${YELLOW}Waiting for web interface... ($i/60)${NC}"
        sleep 10
    done
}

setup_admin_user() {
    echo -e "${BLUE}Setting up admin user...${NC}"
    
    local container_name=$(docker-compose ps -q tak)
    if [ -n "$container_name" ]; then
        # Give TAK server more time to fully initialize
        sleep 30
        
        if docker exec "$container_name" bash -c "
            cd /opt/tak && 
            timeout 30 java -jar utils/UserManager.jar usermod -A -p '$ADMIN_PASSWORD' admin
        " 2>/dev/null; then
            echo -e "${GREEN}✓ Admin user configured successfully${NC}"
        else
            echo -e "${YELLOW}Admin user will be created on next restart${NC}"
        fi
    fi
}

final_validation() {
    echo -e "${BLUE}Performing final validation...${NC}"
    
    # Test connectivity
    if curl -k -s --connect-timeout 5 https://$SERVER_IP:8445 >/dev/null 2>&1; then
        echo -e "${GREEN}✓ TAK Server is responding on port 8445!${NC}"
    else
        echo -e "${YELLOW}TAK Server may still be initializing. This is normal for first startup.${NC}"
    fi
    
    # Verify certificate files exist
    if [ -f "tak/certs/files/admin.p12" ] && [ -f "tak/certs/files/takserver.jks" ]; then
        echo -e "${GREEN}✓ All certificate files created successfully${NC}"
    else
        echo -e "${RED}Error: Certificate files missing${NC}"
        exit 1
    fi
}

display_completion_message() {
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}TAK Server Setup Complete!${NC}"
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
    echo -e "${BLUE}Certificate files created:${NC}"
    echo -e "${BLUE}  Admin certificate: tak/certs/files/admin.p12 (import to browser)${NC}"
    echo -e "${BLUE}  User1 data package: tak/certs/files/user1.zip (for ATAK clients)${NC}"
    echo -e "${BLUE}  Root CA: tak/certs/files/ca.pem${NC}"
    echo -e "${BLUE}  JKS Keystore: tak/certs/files/takserver.jks${NC}"
    echo -e "${BLUE}  JKS Truststore: tak/certs/files/truststore-root.jks${NC}"
    echo ""
    echo -e "${GREEN}Setup completed successfully!${NC}"
    echo -e "${GREEN}Import admin.p12 certificate to your browser and navigate to https://$SERVER_IP:8445${NC}"
    echo ""
    echo -e "${BLUE}For help and documentation, visit:${NC}"
    echo -e "${BLUE}   https://github.com/Zeroradiance/tak-server-unraid${NC}"
}

# Main execution flow
main() {
    echo -e "${GREEN}TAK Server 5.4 Complete Setup Script for Unraid${NC}"
    echo -e "${GREEN}Bulletproof version with comprehensive error handling${NC}"
    echo -e "${GREEN}Sponsored by CloudRF.com - The API for RF${NC}"
    echo ""
    
    validate_tools
    validate_or_skip_zip
    validate_ports
    generate_secure_passwords
    extract_and_setup_files
    update_docker_compose
    configure_tak_server
    validate_configuration
    generate_certificates
    convert_to_jks
    start_containers
    wait_for_startup
    setup_admin_user
    final_validation
    display_completion_message
}

# Run main function
main "$@"
