#!/bin/bash

# TAK Server 5.4 InstallTAK DEB Wrapper for Unraid Containers
# Uses InstallTAK in DEB mode instead of Docker mode
# Sponsored by CloudRF.com - "The API for RF"

set -euo pipefail

# Color codes and environment fixes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Fix terminal issues
export TERM=linux
export DEBIAN_FRONTEND=noninteractive

echo -e "${GREEN}TAK Server 5.4 InstallTAK DEB Container Setup${NC}"
echo -e "${GREEN}Using InstallTAK in DEB mode (not Docker mode)${NC}"
echo -e "${GREEN}Sponsored by CloudRF.com - The API for RF${NC}"
echo ""

# Update system and install dependencies
echo -e "${BLUE}Installing dependencies...${NC}"
apt-get update -qq
apt-get install -y \
    git \
    wget \
    curl \
    sudo \
    systemd \
    systemd-sysv \
    init \
    dialog \
    unzip \
    zip

echo -e "${GREEN}✓ Dependencies installed${NC}"

# Clone InstallTAK repository
echo -e "${BLUE}Downloading InstallTAK script...${NC}"
git clone https://github.com/myTeckNetCode/installTAK.git /opt/installTAK
chmod +x /opt/installTAK/installTAK

echo -e "${GREEN}✓ InstallTAK script downloaded${NC}"

# Check for TAK Server DEB file
echo -e "${BLUE}Checking for TAK Server DEB files...${NC}"
cd /setup

TAK_DEB_FILE=""
TAK_DEB_FILE=$(find . -maxdepth 1 -name "takserver_*_all.deb" | head -1)

if [ -z "$TAK_DEB_FILE" ]; then
    echo -e "${RED}Error: No TAK Server DEB file found!${NC}"
    echo -e "${RED}Please download takserver_5.4-RELEASE-XX_all.deb from tak.gov${NC}"
    echo -e "${RED}NOT the docker ZIP file - we need the DEB package!${NC}"
    echo -e "${RED}Place it in /mnt/user/appdata/tak-server/ before starting${NC}"
    echo ""
    echo -e "${YELLOW}Container will keep running for you to add the file...${NC}"
    
    # Keep container alive for user to add DEB file
    while true; do
        sleep 300  # Check every 5 minutes
        if find . -maxdepth 1 -name "takserver_*_all.deb" | head -1 >/dev/null 2>&1; then
            echo -e "${GREEN}DEB file detected! Please restart container to begin installation.${NC}"
        fi
    done
else
    echo -e "${GREEN}✓ Found TAK Server DEB file: $TAK_DEB_FILE${NC}"
fi

# Copy DEB file to InstallTAK directory
echo -e "${BLUE}Preparing InstallTAK installation...${NC}"
cp "$TAK_DEB_FILE" /opt/installTAK/

# Copy policy file if it exists
if [ -f "deb_policy.pol" ]; then
    cp "deb_policy.pol" /opt/installTAK/
    echo -e "${GREEN}✓ Policy file found and copied${NC}"
else
    echo -e "${RED}Warning: deb_policy.pol not found${NC}"
fi

# Copy GPG key file if it exists - THIS WAS THE MISSING PIECE!
if [ -f "takserver-public-gpg.key" ]; then
    cp "takserver-public-gpg.key" /opt/installTAK/
    echo -e "${GREEN}✓ GPG key file found and copied${NC}"
else
    echo -e "${RED}Error: takserver-public-gpg.key not found${NC}"
    echo -e "${RED}Files in /setup:${NC}"
    ls -la /setup/
    exit 1
fi

# Verify all files are in place
echo -e "${BLUE}Verifying all required files...${NC}"
cd /opt/installTAK
if [ -f "$(basename "$TAK_DEB_FILE")" ] && [ -f "takserver-public-gpg.key" ]; then
    echo -e "${GREEN}✓ All required files present in InstallTAK directory${NC}"
    ls -la /opt/installTAK/
else
    echo -e "${RED}Error: Missing required files in InstallTAK directory${NC}"
    ls -la /opt/installTAK/
    exit 1
fi

# Run InstallTAK script in DEB mode
echo -e "${BLUE}Running InstallTAK script in DEB mode...${NC}"
echo -e "${YELLOW}This may take 5-10 minutes depending on your system...${NC}"

cd /opt/installTAK
./installTAK "$(basename "$TAK_DEB_FILE")"

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
    echo -e "${YELLOW}Check InstallTAK output above for credentials${NC}"
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
