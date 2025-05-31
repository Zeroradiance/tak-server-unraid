#!/bin/bash

# Quick TAK Server Ubuntu Installation Script
# For users who want to run directly without Unraid

set -e

echo "🚀 TAK Server 5.4 Ubuntu Quick Install"
echo "======================================"

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "❌ Please run as root (sudo ./install-tak-ubuntu.sh)"
    exit 1
fi

# Create directory structure
mkdir -p /opt/tak-server
cd /opt/tak-server

# Download setup files
echo "📥 Downloading TAK Server setup files..."
git clone https://github.com/Zeroradiance/tak-server-unraid.git setup
chmod +x setup/scripts/setup-ubuntu.sh

echo ""
echo "📋 NEXT STEPS:"
echo "1. Download TAK Server 5.4 ZIP from https://tak.gov/products/tak-server"
echo "2. Place the ZIP file in /opt/tak-server/"
echo "3. Run: cd /opt/tak-server && ./setup/scripts/setup-ubuntu.sh"
echo ""
echo "🎯 TAK Server will be available at: https://YOUR-IP:8443"
echo ""
