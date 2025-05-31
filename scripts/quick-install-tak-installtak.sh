#!/bin/bash

# Quick TAK Server Installation using InstallTAK
# For direct use without Unraid

echo "🚀 TAK Server InstallTAK Quick Setup"
echo "===================================="

# Check for required files
if [ ! -f takserver-docker-*.zip ]; then
    echo "❌ No takserver-docker-*.zip file found in current directory"
    echo "📥 Please download from https://tak.gov/products/tak-server"
    echo "📁 Place the ZIP file in this directory and run again"
    exit 1
fi

# Run with Docker
echo "🐳 Starting TAK Server with Docker..."
docker run -d \
  --name tak-server-installtak \
  --restart unless-stopped \
  --privileged \
  -p 8443:8443 \
  -p 8089:8089 \
  -p 8080:8080 \
  -p 9000:9000 \
  -v "$(pwd):/setup" \
  ubuntu:22.04 \
  bash -c "
    apt-get update && 
    apt-get install -y git wget curl && 
    git clone https://github.com/Zeroradiance/tak-server-unraid.git /tmp/setup && 
    chmod +x /tmp/setup/scripts/setup-installtak.sh && 
    exec /tmp/setup/scripts/setup-installtak.sh
  "

echo "✅ TAK Server container started!"
echo "📊 Monitor progress: docker logs -f tak-server-installtak"
echo "🌐 Access will be available at: https://localhost:8443"
