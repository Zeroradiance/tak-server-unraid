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
        if
