# --- Base setup and resource group

# Declares the required provider dependencies for our infra.
# azurerm = Azure Resource Manager
terraform { 
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=4.1.0"
    }
  }
}

# Configuration for our azure provider.
# Required, even though we don't have any provider specific config at the moment.
provider "azurerm" {
	# subscription_id required after version 4.
	# Non-sensitive, but could be extracted to env var eventually.
	subscription_id = "82f1c4b4-d4ed-4a73-abb8-471a7c48dc35"
  features {}
}

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
  allocation_method   = "Static" # IP doesn't change when VM stops/starts (dynamic IPs can change)
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
    public_key = file("~/.ssh/id_rsa.pub")
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

  # Install Docker on VM creation
  custom_data = base64encode(<<-EOF
    #!/bin/bash
    apt-get update
    apt-get install -y docker.io
    systemctl start docker
    systemctl enable docker
    usermod -aG docker azureuser
  EOF
  )
}

# Output the public IP so we can access the VM
output "vm_public_ip" {
  value       = azurerm_public_ip.vm_public_ip.ip_address
  description = "Public IP address of the VM"
}
