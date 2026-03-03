# Terraform configuration for Azure VM + Docker
# Project: Multi-Cloud CI/CD with Monitoring
# Author: Ramya
# Date: January 2026

terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }

    http = {
      source  = "hashicorp/http"
      version = "~> 3.0"
    }

  }
}

provider "azurerm" {
  features {}
  subscription_id = "2844b3ce-6365-47df-b696-441aa242fe24"
}

# ─────────────────────────────────────────────
# Fetch your current public IP dynamically
# (used to restrict SSH access)
# ─────────────────────────────────────────────
data "http" "my_ip" {
  url = "https://api.ipify.org"
}

locals {
  my_public_ip = chomp(data.http.my_ip.response_body)
  # If fetching fails for any reason, you can temporarily fallback to:
  # my_public_ip = "0.0.0.0"   # but NEVER leave this in production!
}

# ─────────────────────────────────────────────
# Resource Group
# ─────────────────────────────────────────────
resource "azurerm_resource_group" "rg" {
  name     = "ecom-multi-cloud-website"
  location = "centralindia" # Change to eastus / southeastasia etc. if needed
}

# ─────────────────────────────────────────────
# Virtual Network & Subnet
# ─────────────────────────────────────────────
resource "azurerm_virtual_network" "vnet" {
  name                = "ramya-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_subnet" "subnet" {
  name                 = "web-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

# ─────────────────────────────────────────────
# Public IP (Static – keeps the same IP after restarts)
# ─────────────────────────────────────────────
resource "azurerm_public_ip" "public_ip" {
  name                = "web-public-ip"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

# ─────────────────────────────────────────────
# Network Security Group (HTTP open + SSH from your IP only)
# ─────────────────────────────────────────────
resource "azurerm_network_security_group" "nsg" {
  name                = "web-nsg"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  security_rule {
    name                       = "Allow-HTTP"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Allow-SSH"
    priority                   = 1002
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = local.my_public_ip # ← dynamically fetched your IP
    destination_address_prefix = "*"
  }

  # Optional: deny all other inbound (Azure adds a default deny, but explicit is clearer)
  security_rule {
    name                       = "Deny-All-Inbound"
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# ─────────────────────────────────────────────
# Network Interface
# ─────────────────────────────────────────────
resource "azurerm_network_interface" "nic" {
  name                = "web-nic"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.public_ip.id
  }

  depends_on = [
    azurerm_subnet.subnet,
    azurerm_virtual_network.vnet,
    azurerm_public_ip.public_ip
  ]
}

resource "azurerm_network_interface_security_group_association" "nsg_assoc" {
  network_interface_id      = azurerm_network_interface.nic.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

# ─────────────────────────────────────────────
# Linux VM (Ubuntu 22.04) + Docker + Your App
# ─────────────────────────────────────────────
resource "azurerm_linux_virtual_machine" "app_vm" {
  name                            = "ecom-multi-cloud-vm"
  resource_group_name             = azurerm_resource_group.rg.name
  location                        = azurerm_resource_group.rg.location
  size                            = "Standard_D2s_v3" # small burstable – cheap
  admin_username                  = "azureuser"
  admin_password                  = "R@my@@26!!!" # ← CHANGE THIS to something strong!
  disable_password_authentication = false

  network_interface_ids = [azurerm_network_interface.nic.id]

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

  # Cloud-init: install Docker + run container
 custom_data = base64encode(<<-EOT
  #!/bin/bash
  apt-get update -y && apt-get upgrade -y
  apt-get install -y docker.io
  systemctl start docker
  systemctl enable docker
  usermod -aG docker azureuser

  # Optional: pull latest image first
  docker pull ramyavs/static-website:latest

  # Stop and remove old container if exists (idempotent)
  docker stop ramya-static-app || true
  docker rm ramya-static-app || true

  docker run -d --restart unless-stopped \
    -p 80:80 \
    --name ramya-static-app \
    ramyavs/static-website:latest

  echo "Container (updated) started at $(date)" > /home/azureuser/app-started.txt
  echo "Updated at $(date)" >> /var/log/cloud-init-custom.log
EOT
)

  tags = {
    project     = "multi-cloud-ci-cd"
    environment = "dev"
    owner       = "ramya"
  }

  depends_on = [azurerm_network_interface_security_group_association.nsg_assoc]
}

# ─────────────────────────────────────────────
# Outputs – Important info after terraform apply
# ─────────────────────────────────────────────
output "resource_group_name" {
  value = azurerm_resource_group.rg.name
}

output "vm_public_ip" {
  value       = azurerm_public_ip.public_ip.ip_address
  description = "Wait 4-8 minutes after apply, then open http://this-ip in browser"
}

output "vm_ssh_command_example" {
  value       = "ssh azureuser@${azurerm_public_ip.public_ip.ip_address}"
  description = "Use the password you set. Run from your local machine (only works from your current IP)"
}

output "your_current_ip_used_for_ssh" {
  value       = local.my_public_ip
  description = "This is the IP Terraform used to allow SSH – if it changes, re-apply"
}
