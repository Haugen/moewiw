#!/bin/bash

# Manual deployment script - useful for testing before setting up GitHub Actions

set -e

cd "$(dirname "$0")/.."

echo "=== Building and deploying moewiw app ==="

# Get infrastructure outputs
cd infra
ACR_LOGIN_SERVER=$(terraform output -raw acr_login_server)
ACR_USERNAME=$(terraform output -raw acr_admin_username)
ACR_PASSWORD=$(terraform output -raw acr_admin_password)
VM_IP=$(terraform output -raw vm_public_ip)
cd ..

IMAGE_NAME="$ACR_LOGIN_SERVER/moewiw:latest"

echo ""
echo "Step 1: Login to ACR..."
echo "$ACR_PASSWORD" | docker login $ACR_LOGIN_SERVER -u $ACR_USERNAME --password-stdin

echo ""
echo "Step 2: Build Docker image for linux/amd64..."
cd app
docker build --platform linux/amd64 -t $IMAGE_NAME .

echo ""
echo "Step 3: Push to ACR..."
docker push $IMAGE_NAME

echo ""
echo "Step 4: Deploy to VM..."
ssh -i ~/.ssh/moewiw -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null azureuser@$VM_IP << ENDSSH
  echo "Logging into ACR on VM..."
  echo "$ACR_PASSWORD" | docker login $ACR_LOGIN_SERVER -u $ACR_USERNAME --password-stdin
  
  echo "Pulling new image..."
  docker pull $IMAGE_NAME
  
  echo "Stopping old container..."
  docker stop webapp 2>/dev/null || true
  docker rm webapp 2>/dev/null || true
  
  echo "Starting new container..."
  docker run -d -p 80:80 --name webapp --restart unless-stopped $IMAGE_NAME
  
  echo "Checking container status..."
  docker ps
ENDSSH

echo ""
echo "=== Deployment complete! ==="
echo "Visit: http://$VM_IP"
