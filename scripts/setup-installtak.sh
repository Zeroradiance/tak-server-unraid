#!/bin/bash

# TAK Server 5.4 InstallTAK Wrapper for Unraid Containers
# Uses proven InstallTAK script from myTeckNetCode
# Sponsored by CloudRF.com - "The API for RF"

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${GREEN}TAK Server 5.4 InstallTAK Container Setup${NC}"
echo -e "${GREEN}Using proven InstallTAK script by myTeckNet${NC}"
echo -e "${GREEN}Sponsored by CloudRF.com - The API for RF${NC}"
echo ""

# Update system and install dependencies
echo -e "${BLUE}Installing dependencies...${NC}"
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y \
    git \
    wget \
    curl \
    sudo \
    systemd \
    init

echo -e "${GREEN}✓ Dependencies installed${NC}"

# Clone InstallTAK repository
echo -e "${BLUE}Downloading InstallTAK script...${NC}"
git clone https://github.com/myTeckNetCode/installTAK.git /opt/installTAK
chmod +x /opt/installTAK/installTAK

echo -e "${GREEN}✓ InstallTAK script downloaded${NC}"

# Check for TAK Server ZIP file
echo -e "${BLUE}Checking for TAK Server files...${NC}"
cd /setup

TAK_ZIP_FILE=""
TAK_ZIP_FILE=$(find . -maxdepth 1 -name "takserver-docker-*.zip" | head -1)

if [ -z "$TAK_ZIP_FILE" ]; then
    echo -e "${RED}Error: No TAK Server ZIP file found!${NC}"
    echo -e "${RED}Please download takserver-docker-5.4-RELEASE-XX.zip from tak.gov${NC}"
    echo -e "${RED}and place it in /mnt/user/appdata/tak-server/ before starting${NC}"
    echo ""
    echo -e "${YELLOW}Container will keep running for you to add the file...${NC}"
    echo -e "${YELLOW}After adding the ZIP file, restart the container.${NC}"
    
    # Keep container alive for user to add ZIP file
    while true; do
        sleep 300  # Check every 5 minutes
        if find . -maxdepth 1 -name "takserver-docker-*.zip" | head -1 >/dev/null 2>&1; then
            echo -e "${GREEN}ZIP file detected! Please restart container to begin installation.${NC}"
        fi
    done
else
    echo -e "${GREEN}✓ Found TAK Server file: $TAK_ZIP_FILE${NC}"
fi

# Copy ZIP file to InstallTAK directory
echo -e "${BLUE}Preparing InstallTAK installation...${NC}"
cp "$TAK_ZIP_FILE" /opt/installTAK/

# Run InstallTAK script
echo -e "${BLUE}Running InstallTAK script...${NC}"
echo -e "${YELLOW}This may take 5-10 minutes depending on your system...${NC}"

cd /opt/installTAK
./installTAK "$(basename "$TAK_ZIP_FILE")"

# Check if installation was successful
if systemctl is-active --quiet takserver; then
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}TAK Server Installation Complete!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo -e "${GREEN}TAK Server is running and accessible at:${NC}"
    echo -e "${GREEN}https://$(hostname -I | awk '{print $1}'):8443${NC}"
    echo ""
    echo -e "${YELLOW}Default credentials:${NC}"
    echo -e "${YELLOW}Username: admin${NC}"
    echo -e "${YELLOW}Password: Check InstallTAK output above for generated password${NC}"
    echo ""
    echo -e "${BLUE}Certificate files can be found in:${NC}"
    echo -e "${BLUE}/opt/tak/certs/${NC}"
    echo ""
else
    echo -e "${RED}InstallTAK completed but TAK Server is not running.${NC}"
    echo -e "${RED}Check the InstallTAK output above for errors.${NC}"
    exit 1
fi

# Keep container running
echo -e "${BLUE}Keeping container running...${NC}"
echo -e "${GREEN}TAK Server is now operational!${NC}"

# Monitor TAK Server service
while true; do
    if ! systemctl is-active --quiet takserver; then
        echo -e "${RED}TAK Server service has stopped!${NC}"
        systemctl status takserver
        exit 1
    fi
    sleep 60
done
