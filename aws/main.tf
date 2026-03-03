# Terraform configuration for AWS EC2 + Docker Static Website
# Project: Multi-Cloud Static Website Deployment
# Author: Ramya
# Date: January 2026

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region = "ap-south-1" # Mumbai region (closest to Tamil Nadu)
}

# ─────────────────────────────────────────────
# Fetch your current public IP dynamically
# (used to restrict SSH access - same as Azure)
# ─────────────────────────────────────────────
data "http" "my_ip" {
  url = "https://api.ipify.org"
}

locals {
  my_public_ip = chomp(data.http.my_ip.response_body)
  # Fallback if fetch fails: "0.0.0.0/0" (insecure - only for testing!)
}

# ─────────────────────────────────────────────
# Latest Amazon Linux 2023 AMI (x86_64)
# ─────────────────────────────────────────────
data "aws_ssm_parameter" "al2023_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

# ─────────────────────────────────────────────
# VPC & Subnet (AWS equivalent of Azure VNet/Subnet)
# ─────────────────────────────────────────────
data "aws_vpc" "default" {
  default = true
}

data "aws_subnet" "default" {
  vpc_id            = data.aws_vpc.default.id
  availability_zone = "ap-south-1a" # or let it pick first available
  default_for_az    = true
}

# ─────────────────────────────────────────────
# Public IP (Elastic IP - AWS equivalent of Azure Static Public IP)
# ─────────────────────────────────────────────
resource "aws_eip" "static_ip" {
  domain = "vpc"
  tags = {
    Name    = "ramya-website-static-ip"
    project = "multi-cloud-static-site"
  }
}

# ─────────────────────────────────────────────
# Security Group (AWS equivalent of Azure NSG)
# HTTP on port 82 + SSH from your IP only
# ─────────────────────────────────────────────
resource "aws_security_group" "allow_http82_and_ssh" {
  name        = "ramya-website-sg"
  description = "Allow HTTP on port 82 from anywhere + SSH from my IP"
  vpc_id      = data.aws_vpc.default.id

  # HTTP on port 82 (same as your Azure setup)
  ingress {
    description = "HTTP port 82 from anywhere"
    from_port   = 82
    to_port     = 82
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # SSH from your current IP only (dynamic - same as Azure)
  ingress {
    description = "SSH from my current IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["${local.my_public_ip}/32"]
  }

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "ramya-website-sg"
    project     = "multi-cloud-static-site"
    environment = "dev"
    owner       = "ramya"
  }
}

# ─────────────────────────────────────────────
# EC2 Instance (AWS equivalent of Azure Linux VM)
# Amazon Linux 2023 + Docker + Static Website
# ─────────────────────────────────────────────
resource "aws_instance" "website" {
  ami                    = data.aws_ssm_parameter.al2023_ami.value
  instance_type          = "t3.micro" # Free-tier eligible (equivalent to B2s)
  subnet_id              = data.aws_subnet.default.id
  vpc_security_group_ids = [aws_security_group.allow_http82_and_ssh.id]

  # Associate the static Elastic IP
  associate_public_ip_address = true
  private_ip                  = null # Let AWS assign

  # Optional: SSH key pair for secure access (create one in AWS console first)
  # key_name = "ramya-mumbai-key"  # ← Uncomment and add your key pair name

  # User data script (AWS equivalent of Azure custom_data)
  user_data = base64encode(<<-EOT
    #!/bin/bash
    echo "Starting user-data script at $(date)" >> /var/log/user-data.log 2>&1

    # Update system and install Docker
    dnf update -y
    dnf install -y docker

    # Start and enable Docker service
    systemctl start docker
    systemctl enable docker

    # Add ec2-user to docker group (no sudo needed)
    usermod -aG docker ec2-user

    # Give Docker time to initialize
    sleep 10

    # Stop and remove old container if exists (idempotent)
    docker stop ramya-static-app || true
    docker rm ramya-static-app || true

    # Pull and run static website container on port 82 → 80
    docker run -d --restart unless-stopped \
      -p 82:80 \
      --name ramya-static-app \
      ramyavs/static-website:latest \
      >> /var/log/user-data.log 2>&1

    # Log success
    echo "Static website started on port 82 at $(date)" > /home/ec2-user/app-started.txt
    echo "Image: ramyavs/static-website:latest" >> /home/ec2-user/app-started.txt
    echo "Access: http://<your-public-ip>:82" >> /home/ec2-user/app-started.txt
    echo "Check logs: docker logs ramya-static-app" >> /home/ec2-user/app-started.txt

    echo "User-data script finished at $(date)" >> /var/log/user-data.log
  EOT
  )

  # Associate the Elastic IP after instance creation
  depends_on = [aws_eip.static_ip]

  tags = {
    Name        = "ramya-static-website-ec2"
    project     = "multi-cloud-static-site"
    environment = "dev"
    owner       = "ramya"
    purpose     = "static-website"
  }

  # Ensure EIP association
  lifecycle {
    ignore_changes = [associate_public_ip_address]
  }
}

# ─────────────────────────────────────────────
# Associate Elastic IP with EC2 Instance
# ─────────────────────────────────────────────
resource "aws_eip_association" "eip_assoc" {
  instance_id   = aws_instance.website.id
  allocation_id = aws_eip.static_ip.id
}

# ─────────────────────────────────────────────
# Outputs – Important info after terraform apply
# ─────────────────────────────────────────────
output "vpc_id" {
  value       = data.aws_vpc.default.id
  description = "Default VPC ID"
}

output "website_url" {
  value       = "http://${aws_eip.static_ip.public_ip}:82"
  description = "Open this URL in browser (wait 2-4 minutes after apply)"
}

output "ec2_public_ip" {
  value       = aws_eip.static_ip.public_ip
  description = "Static Public IP - use this for SSH and website access"
}

output "ssh_command_example" {
  value       = "ssh -i your-key.pem ec2-user@${aws_eip.static_ip.public_ip}"
  description = "SSH command (uncomment key_name in code first)"
}

output "your_current_ip_used_for_ssh" {
  value       = local.my_public_ip
  description = "This IP was used to allow SSH access - re-apply if it changes"
}

output "docker_container_name" {
  value       = "ramya-static-app"
  description = "Name of the running Docker container"
}

