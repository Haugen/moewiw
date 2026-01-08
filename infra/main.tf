# --- Base setup and resource group

# Declares the required provider dependencies for our infra.
# azurerm = Azure Resource Manager
# azuread = Azure Active Directory (for looking up App Registration)
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=4.1.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.1.0"
    }
  }
}

# Configuration for our azure provider.
# Required, even though we don't have any provider specific config at the moment.
provider "azurerm" {
  subscription_id = var.subscription_id
  features {}
}

# Configuration for Azure AD provider
provider "azuread" {
}

# --- Data Sources (lookup existing resources/configuration)

# Get current Terraform executor's identity (you, when running locally)
# Used for: Key Vault tenant_id, granting yourself Key Vault admin rights
data "azurerm_client_config" "current" {}

# Look up the Service Principal for our GitHub Actions App Registration
# Used for: RBAC role assignments to grant GitHub Actions access to resources
data "azuread_service_principal" "moewiw_github_actions" {
  client_id = var.github_actions_client_id
}

# --- Resource Group

# Creates an Azure Resource Group called "rg".
# A logical container for Azure resources.
resource "azurerm_resource_group" "rg" {
  name     = "moewiw"
  location = "North Europe"
}

# --- Networking

# Virtual Network. Defines our overall IP range.
resource "azurerm_virtual_network" "vnet" {
  name                = "moewiw-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

# Subnet for VMs. A smaller slice of the VNet defined above.
# We'll attach our VM to this subnet.
resource "azurerm_subnet" "vm_subnet" {
  name                 = "moewiw-vm-subnet"
  address_prefixes     = ["10.0.1.0/24"]
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
}

# Network Security Group
resource "azurerm_network_security_group" "nsg" {
  name                = "moewiw-nsg"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  # Allow SSH from anywhere (consider restricting to your IP in production)
  security_rule {
    name                       = "AllowSSH"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  # Allow HTTP traffic
  security_rule {
    name                       = "AllowHTTP"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  # Allow HTTPS traffic
  security_rule {
    name                       = "AllowHTTPS"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# Public IP for the VM
resource "azurerm_public_ip" "vm_public_ip" {
  name                = "moewiw-vm-public-ip"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"   # IP doesn't change when VM stops/starts (dynamic IPs can change)
  sku                 = "Standard" # Required for zone-redundant deployments, works with Standard Load Balancers
}

# Network Interface
resource "azurerm_network_interface" "vm_nic" {
  name                = "moewiw-vm-nic"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.vm_subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.vm_public_ip.id
  }
}

# Associate NSG with the Network Interface
resource "azurerm_network_interface_security_group_association" "nsg_association" {
  network_interface_id      = azurerm_network_interface.vm_nic.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

# --- Virtual Machine

# Linux Virtual Machine
resource "azurerm_linux_virtual_machine" "vm" {
  name                = "moewiw-vm"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  size                = "Standard_B2ts_v2"
  admin_username      = "azureuser"

  network_interface_ids = [
    azurerm_network_interface.vm_nic.id,
  ]

  admin_ssh_key {
    username   = "azureuser"
    public_key = file("~/.ssh/moewiw.pub")
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  # Install Docker on VM creation using cloud-init
  custom_data = base64encode(<<-EOF
    #cloud-config

    # Update package cache on first boot
    package_update: true

    # Install required packages
    packages:
      - docker.io
      - curl
      - git

    # Configure system
    runcmd:
      # Enable and start Docker service
      - systemctl enable docker
      - systemctl start docker
      # Add azureuser to docker group (no sudo needed for docker commands)
      - usermod -aG docker azureuser
      # Wait for Docker to be fully ready
      - timeout 30 bash -c 'until docker info >/dev/null 2>&1; do sleep 2; done'
      # Pull nginx image to speed up first deployment
      - docker pull nginx:alpine

    # Final message logged to cloud-init output
    final_message: "Cloud-init setup complete. Docker is ready. System is up after $UPTIME seconds."
  EOF
  )
}

# --- Azure Container Registry

# Azure Container Registry for storing Docker images
resource "azurerm_container_registry" "acr" {
  name                = "moewiwacr" # Must be globally unique, alphanumeric only
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sku                 = "Basic"
  admin_enabled       = true # Enables username/password auth (simpler for learning)
}

# --- Azure Key Vault for Secrets

# Key Vault for secure secret storage
resource "azurerm_key_vault" "kv" {
  name                       = "moewiw-kv"
  location                   = azurerm_resource_group.rg.location
  resource_group_name        = azurerm_resource_group.rg.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  soft_delete_retention_days = 7
  purge_protection_enabled   = false

  # Use Azure RBAC for access control (modern approach)
  enable_rbac_authorization = true
}

# --- RBAC Role Assignments

# Grant Terraform (current user) Key Vault Administrator to write initial secrets
resource "azurerm_role_assignment" "kv_admin_terraform" {
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = data.azurerm_client_config.current.object_id
}

# Grant GitHub Actions Service Principal access to read secrets from Key Vault
resource "azurerm_role_assignment" "kv_secrets_user" {
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = data.azuread_service_principal.moewiw_github_actions.object_id
}

# Grant GitHub Actions permission to push/pull from ACR
resource "azurerm_role_assignment" "acr_push" {
  scope                = azurerm_container_registry.acr.id
  role_definition_name = "AcrPush"
  principal_id         = data.azuread_service_principal.moewiw_github_actions.object_id
}

# Grant GitHub Actions permission to read ACR properties (login server, etc.)
resource "azurerm_role_assignment" "acr_reader" {
  scope                = azurerm_container_registry.acr.id
  role_definition_name = "Reader"
  principal_id         = data.azuread_service_principal.moewiw_github_actions.object_id
}

# Grant GitHub Actions permission to read the VM's Public IP (to get VM IP for SSH)
resource "azurerm_role_assignment" "public_ip_reader" {
  scope                = azurerm_public_ip.vm_public_ip.id
  role_definition_name = "Reader"
  principal_id         = data.azuread_service_principal.moewiw_github_actions.object_id
}

# --- Storing secrets in Key Vault

resource "azurerm_key_vault_secret" "acr_username" {
  name         = "acr-admin-username"
  value        = azurerm_container_registry.acr.admin_username
  key_vault_id = azurerm_key_vault.kv.id

  depends_on = [
    azurerm_role_assignment.kv_admin_terraform
  ]
}

resource "azurerm_key_vault_secret" "acr_password" {
  name         = "acr-admin-password"
  value        = azurerm_container_registry.acr.admin_password
  key_vault_id = azurerm_key_vault.kv.id

  depends_on = [
    azurerm_role_assignment.kv_admin_terraform
  ]
}

resource "azurerm_key_vault_secret" "ssh_key" {
  name         = "vm-ssh-private-key"
  value        = file(var.ssh_private_key_path)
  key_vault_id = azurerm_key_vault.kv.id

  depends_on = [
    azurerm_role_assignment.kv_admin_terraform
  ]
}

# --- Outputs. Just for convenience. we don't need these for anything at this point.

output "vm_public_ip" {
  value       = azurerm_public_ip.vm_public_ip.ip_address
  description = "Public IP address of the VM"
}

output "acr_login_server" {
  value       = azurerm_container_registry.acr.login_server
  description = "ACR login server URL"
}

output "key_vault_name" {
  value       = azurerm_key_vault.kv.name
  description = "Key Vault name for secret storage"
}
