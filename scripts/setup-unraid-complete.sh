#!/bin/bash

# TAK server setup script sponsored by CloudRF.com - "The API for RF"
# Complete version for Unraid with automatic JKS certificate generation

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}TAK server setup script sponsored by CloudRF.com - \"The API for RF\"${NC}"
echo -e "${GREEN}Complete version for Unraid with automatic JKS generation${NC}"
echo ""

# Fix architecture detection for Unraid
arch="amd64"
export PATH=$PATH:/sbin:/usr/sbin

# Check required tools
for tool in unzip docker-compose openssl docker; do
    if ! command -v $tool &> /dev/null; then
        echo -e "${RED}Error: $tool command not found.${NC}"
        exit 1
    fi
done

# Port availability checks
echo "Checking port availability..."
ports_to_check=(5432 8445 8446 8447 8092 9003 9004)
for port in "${ports_to_check[@]}"; do
    if netstat -tulpn | grep -q ":$port "; then
        echo -e "${RED}Port $port is in use. Stopping existing service...${NC}"
        sudo fuser -k $port/tcp 2>/dev/null || true
        sleep 2
    fi
    echo -e "${GREEN}Port $port is available.${NC}"
done

# Find TAK server ZIP file
zip_file=$(find . -maxdepth 1 -name "takserver-docker-*.zip" | head -1)
if [ -z "$zip_file" ]; then
    echo -e "${RED}No TAK server ZIP file found.${NC}"
    exit 1
fi
echo -e "${GREEN}Found TAK server file: $zip_file${NC}"

# Stop any existing containers
echo "Stopping existing containers..."
docker-compose down 2>/dev/null || true

# Extract TAK server
echo "Extracting TAK server..."
temp_dir="/tmp/takserver-$$"
mkdir -p "$temp_dir"
unzip -q "$zip_file" -d "$temp_dir"

extracted_dir=$(find "$temp_dir" -maxdepth 1 -type d -name "takserver-docker-*" | head -1)
if [ -z "$extracted_dir" ]; then
    echo -e "${RED}Failed to find extracted TAK server directory.${NC}"
    exit 1
fi

# Create tak directory and copy files
echo "Setting up TAK server files..."
rm -rf tak 2>/dev/null || true
mkdir -p tak
cp -r "$extracted_dir"/tak/* tak/
chmod +x tak/*.sh tak/db-utils/*.sh tak/certs/*.sh 2>/dev/null || true
rm -rf "$temp_dir"

# Generate TAK-compliant passwords
admin_pass="TakAdmin$(openssl rand -base64 6 | tr -dc 'a-zA-Z0-9')!@#"
db_pass="TakDB$(openssl rand -base64 8 | tr -dc 'a-zA-Z0-9')$%^"

# Ensure passwords meet TAK requirements
admin_pass="TakAdmin2025!@#${admin_pass: -5}"
db_pass="TakDatabase2025$%^${db_pass: -5}"

echo "Generated TAK-compliant passwords"

# Get server IP
server_ip=$(hostname -I | awk '{print $1}')
[ -z "$server_ip" ] && server_ip="127.0.0.1"

# Configure CoreConfig.xml
echo "Configuring TAK server..."
cp CoreConfig.xml tak/CoreConfig.xml

# Update database password and server IP
sed -i "s/password=\"\"/password=\"$db_pass\"/g" tak/CoreConfig.xml
sed -i "s/127.0.0.1/$server_ip/g" tak/CoreConfig.xml

# Add explicit host bindings for containerized deployment
sed -i 's/<input _name="stdssl" protocol="tls" port="8089"\/>/<input _name="stdssl" protocol="tls" port="8089" host="0.0.0.0"\/>/g' tak/CoreConfig.xml
sed -i 's/<connector port="8443" _name="https"\/>/<connector port="8443" _name="https" host="0.0.0.0"\/>/g' tak/CoreConfig.xml
sed -i 's/<connector port="8444" useFederationTruststore="true" _name="fed_https"\/>/<connector port="8444" useFederationTruststore="true" _name="fed_https" host="0.0.0.0"\/>/g' tak/CoreConfig.xml
sed -i 's/<connector port="8446" clientAuth="false" _name="cert_https"\/>/<connector port="8446" clientAuth="false" _name="cert_https" host="0.0.0.0"\/>/g' tak/CoreConfig.xml

# Replace HOSTIP placeholder
sed -i "s/HOSTIP/$server_ip/g" tak/CoreConfig.xml

echo "Network binding configuration completed"

# Generate certificates with OpenSSL
echo "Generating certificates with OpenSSL..."
cd tak/certs || { echo "Failed to enter certs directory"; exit 1; }

# Create proper directory structure
mkdir -p files CA intermediate

# Set certificate variables
COUNTRY="US"
STATE="California"
CITY="San Francisco"
ORGANIZATION="TAK"
ORGANIZATIONAL_UNIT="TAK-Server"
CERT_PASS="atakatak"

# Generate Root CA private key and certificate
echo "Creating root certificate authority..."
openssl genrsa -out files/ca-do-not-share.key 4096

openssl req -new -x509 -days 3650 -key files/ca-do-not-share.key -out files/ca.pem \
    -subj "/C=$COUNTRY/ST=$STATE/L=$CITY/O=$ORGANIZATION/OU=$ORGANIZATIONAL_UNIT/CN=TAK-ROOT-CA"

# Create truststore file
cp files/ca.pem files/truststore-root.pem
cp files/ca.pem files/ca-trusted.pem

echo "Root CA created successfully"

# Generate server private key and certificate
echo "Creating server certificate..."
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
IP.1 = $server_ip")

echo "Server certificate created successfully"

# Generate admin private key and certificate
echo "Creating admin certificate..."
openssl genrsa -out files/admin.key 2048

openssl req -new -key files/admin.key -out files/admin.csr \
    -subj "/C=$COUNTRY/ST=$STATE/L=$CITY/O=$ORGANIZATION/OU=$ORGANIZATIONAL_UNIT/CN=admin"

openssl x509 -req -in files/admin.csr -CA files/ca.pem -CAkey files/ca-do-not-share.key \
    -CAcreateserial -out files/admin.pem -days 365

# Create PKCS12 file for admin browser import
openssl pkcs12 -export -out files/admin.p12 -inkey files/admin.key -in files/admin.pem \
    -certfile files/ca.pem -password pass:$CERT_PASS

echo "Admin certificate created successfully"

# Generate user1 certificate for testing
echo "Creating user1 certificate..."
openssl genrsa -out files/user1.key 2048

openssl req -new -key files/user1.key -out files/user1.csr \
    -subj "/C=$COUNTRY/ST=$STATE/L=$CITY/O=$ORGANIZATION/OU=$ORGANIZATIONAL_UNIT/CN=user1"

openssl x509 -req -in files/user1.csr -CA files/ca.pem -CAkey files/ca-do-not-share.key \
    -CAcreateserial -out files/user1.pem -days 365

# Create user1 PKCS12 and data package
openssl pkcs12 -export -out files/user1.p12 -inkey files/user1.key -in files/user1.pem \
    -certfile files/ca.pem -password pass:$CERT_PASS

# Create data package ZIP for user1
mkdir -p temp_dp
cp files/user1.p12 temp_dp/
cp files/truststore-root.pem temp_dp/
echo "server=$server_ip:8092:ssl" > temp_dp/manifest.xml
(cd temp_dp && zip -r ../files/user1.zip . >/dev/null 2>&1)
rm -rf temp_dp

echo "All PEM certificates generated successfully"

# **NEW: Automatically convert PEM to JKS using OpenJDK container**
echo -e "${YELLOW}Converting PEM certificates to JKS format using OpenJDK container...${NC}"

# Get the absolute path to certificates
cert_path=$(pwd)/files

# Run OpenJDK container to create JKS files
docker run --rm -v "$cert_path":/certs \
    openjdk:17-slim bash -c "
cd /certs && 
apt update >/dev/null 2>&1 && apt install -y openssl >/dev/null 2>&1 &&

echo 'Converting server certificate to JKS...' &&
openssl pkcs12 -export -out takserver.p12 \
    -inkey takserver.key \
    -in takserver.pem \
    -certfile ca.pem \
    -password pass:$CERT_PASS &&

keytool -importkeystore \
    -srckeystore takserver.p12 \
    -srcstoretype PKCS12 \
    -srcstorepass $CERT_PASS \
    -destkeystore takserver.jks \
    -deststoretype JKS \
    -deststorepass $CERT_PASS \
    -alias 1 \
    -destalias takserver \
    -noprompt &&

echo 'Creating truststore JKS...' &&
keytool -import -trustcacerts \
    -file ca.pem \
    -alias tak-ca \
    -keystore truststore-root.jks \
    -storepass $CERT_PASS \
    -noprompt &&

echo 'Creating federation truststore...' &&
cp truststore-root.jks fed-truststore.jks &&

echo 'JKS files created successfully!' &&
ls -la *.jks
"

if [ $? -eq 0 ]; then
    echo -e "${GREEN}JKS certificates created successfully!${NC}"
else
    echo -e "${RED}Failed to create JKS certificates. TAK Server may not start properly.${NC}"
    exit 1
fi

# Set proper permissions
chmod 644 files/*.pem files/*.p12 files/*.zip files/*.jks 2>/dev/null || true
chmod 600 files/*.key 2>/dev/null || true

echo "Certificate permissions set correctly"

# Return to main directory
cd ../..

# Build and start containers
echo "Building and starting TAK server containers..."
docker-compose up -d

echo "Waiting for TAK server to fully initialize..."
sleep 120

# Check if containers are running
if ! docker-compose ps | grep -q "Up"; then
    echo -e "${RED}Containers failed to start. Check logs with: docker-compose logs${NC}"
    exit 1
fi

# Wait for TAK server to bind to port 8443
echo "Waiting for TAK Server web interface to start..."
for i in {1..30}; do
    if docker exec tak-server-tak-1 netstat -tulpn 2>/dev/null | grep -q ":8443"; then
        echo -e "${GREEN}TAK Server web interface is listening on port 8443!${NC}"
        break
    fi
    echo "Waiting for web interface... ($i/30)"
    sleep 10
done

# Final connectivity test
echo "Testing TAK Server connectivity..."
if curl -k -s --connect-timeout 5 https://$server_ip:8445 >/dev/null 2>&1; then
    echo -e "${GREEN}TAK Server is responding on port 8445!${NC}"
else
    echo -e "${YELLOW}TAK Server may still be initializing. Check logs if issues persist.${NC}"
fi

# Create admin user in database
echo "Setting up admin user..."
container_name=$(docker-compose ps -q tak)
if [ -n "$container_name" ]; then
    # Wait for TAK server to fully start
    sleep 60
    
    docker exec "$container_name" bash -c "
        cd /opt/tak && 
        timeout 30 java -jar utils/UserManager.jar usermod -A -p '$admin_pass' admin
    " 2>/dev/null || echo "Admin user will be created on next restart"
fi

# Display completion message
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}TAK Server Setup Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${YELLOW}---------PASSWORDS----------------${NC}"
echo -e "${YELLOW}Admin user name: admin${NC}"
echo -e "${YELLOW}Admin password: $admin_pass${NC}"
echo -e "${YELLOW}PostgreSQL password: $db_pass${NC}"
echo -e "${YELLOW}Certificate password: $CERT_PASS${NC}"
echo -e "${YELLOW}---------PASSWORDS----------------${NC}"
echo ""
echo -e "${YELLOW}SAVE THESE PASSWORDS - THEY WON'T BE SHOWN AGAIN!${NC}"
echo ""
echo -e "${GREEN}Access your TAK Server at: https://$server_ip:8445${NC}"
echo ""
echo "Certificate files created:"
echo "  • Admin certificate: tak/certs/files/admin.p12 (import to browser)"
echo "  • User1 data package: tak/certs/files/user1.zip (for ATAK clients)"
echo "  • Root CA: tak/certs/files/ca.pem"
echo "  • JKS Keystore: tak/certs/files/takserver.jks"
echo "  • JKS Truststore: tak/certs/files/truststore-root.jks"
echo ""
echo -e "${GREEN}Setup completed successfully!${NC}"
echo -e "${GREEN}Import admin.p12 certificate to your browser and navigate to https://$server_ip:8445${NC}"
