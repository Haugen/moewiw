#!/bin/bash

# This script extracts credentials needed for GitHub Actions secrets

set -e

echo "=== Azure Container Registry Credentials ==="
echo ""

cd ../infra

echo "ACR_LOGIN_SERVER:"
terraform output -raw acr_login_server
echo ""
echo ""

echo "ACR_USERNAME:"
terraform output -raw acr_admin_username
echo ""
echo ""

echo "ACR_PASSWORD:"
terraform output -raw acr_admin_password
echo ""
echo ""

echo "VM_HOST:"
terraform output -raw vm_public_ip
echo ""
echo ""

echo "=== Instructions ==="
echo "Add these as GitHub repository secrets:"
echo ""
echo "1. Go to: https://github.com/YOUR_USERNAME/YOUR_REPO/settings/secrets/actions"
echo "2. Click 'New repository secret'"
echo "3. Add each of the above values"
echo ""
echo "Also add SSH_PRIVATE_KEY:"
echo "  - Run: cat ~/.ssh/id_rsa"
echo "  - Copy the entire private key (including BEGIN/END lines)"
echo "  - Add as SSH_PRIVATE_KEY secret"
echo ""
