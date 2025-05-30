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
    for tool in unzip docker-compose openssl docker; do
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
    echo
