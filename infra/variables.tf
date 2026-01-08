# Variables for infrastructure configuration

# Azure Subscription ID
# The subscription where all resources will be created
variable "subscription_id" {
  type        = string
  description = "Azure Subscription ID"
}

# GitHub Actions App Registration Client ID
# This is the Application (client) ID from your App Registration in Azure AD
# Used to look up the Service Principal for RBAC role assignments
variable "github_actions_client_id" {
  type        = string
  description = "Client ID of the GitHub Actions App Registration"
}

# Path to SSH private key
# Used to store the SSH key in Key Vault for GitHub Actions to access the VM
variable "ssh_private_key_path" {
  type        = string
  description = "Path to SSH private key file"
  default     = "~/.ssh/id_rsa"
}
