# Installation Guide

Complete installation instructions for TAK Server 5.4 on Unraid.

## Prerequisites

- Unraid 6.9+ with Docker support
- 4GB+ RAM (8GB+ recommended)
- 2GB+ free storage space
- TAK Server 5.4 release ZIP file from tak.gov

## Quick Installation

1. SSH into your Unraid server
2. Navigate to appdata directory: cd /mnt/user/appdata
3. 3. Clone this repository: git clone https://github.com/Zeroradiance/tak-server-unraid.git
cd tak-server-unraid
4. Download TAK Server 5.4 ZIP from https://tak.gov/products/tak-server
5. Copy the ZIP file to this directory
6. Run the automated setup: chmod +x scripts/setup-unraid-complete.sh
./scripts/setup-unraid-complete.sh

## What the Setup Does

- Extracts TAK Server files
- Generates PEM certificates with OpenSSL
- Converts PEM to JKS format using OpenJDK container
- Configures network binding for Docker
- Sets up database with generated passwords
- Creates admin and user certificates
- Starts TAK Server containers

## Post-Installation

After successful setup:
1. Save the generated passwords (displayed only once)
2. Download admin.p12 certificate from tak/certs/files/
3. Import certificate to your browser (password: atakatak)
4. Access web interface at https://YOUR-IP:8445

## Port Mappings

- 8445: Admin Web Interface
- 8446: API Port
- 8447: Streaming Port
- 8092: TAK Client Connections
- 9003: Federation Port
- 9004: Ignite Port
