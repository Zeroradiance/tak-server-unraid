# Troubleshooting Guide

Common issues and solutions for TAK Server 5.4 on Unraid.

## Container Won't Start

### Check Container Logs
docker-compose logs
docker logs tak-server-tak-1
docker logs tak-server-db-1
### Restart Containers
docker-compose restart

## Web Interface Not Accessible

### Verify Port Listening
docker exec tak-server-tak-1 netstat -tulpn | grep 8443

### Check TAK Server Logs
docker exec tak-server-tak-1 tail -f /opt/tak/logs/takserver-api.log

### Test Connectivity
curl -k -v https://YOUR-IP:8445

## Certificate Issues

### Verify JKS Files Exist
ls -la /mnt/user/appdata/tak-server-unraid/tak/certs/files/*.jks

### Check Certificate Validity
openssl x509 -in /mnt/user/appdata/tak-server-unraid/tak/certs/files/admin.pem -text -noout

## Port Conflicts

### Check Port Usage
netstat -tulpn | grep -E ":(8445|8446|8447|8092|9003|9004) "

### Kill Conflicting Processes
sudo fuser -k 8445/tcp

## Database Connection Issues

### Test Database
docker exec tak-server-db-1 psql -U martiuser -d cot -c "\dt"

## Getting Help

If you encounter issues not covered here:
1. Check the GitHub Issues page
2. Post in the Unraid Community Forum thread
3. Include relevant logs and system information
