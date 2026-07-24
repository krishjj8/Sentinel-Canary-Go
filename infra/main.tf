terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  default     = "ap-south-1"
  description = "AWS region for resources"
}

variable "repo_name" {
  default     = "sentinel-canary"
  description = "AWS ECR Repository Name"
}

# ------------------------------------------------------------------
# 1. AWS ECR Repository (Private Container Registry)
# ------------------------------------------------------------------
resource "aws_ecr_repository" "sentinel" {
  name                 = var.repo_name
  image_tag_mutability = "MUTABLE"
  force_delete        = true 

  image_scanning_configuration {
    scan_on_push = true
  }
}

# ------------------------------------------------------------------
# 2. VPC & Networking
# ------------------------------------------------------------------
resource "aws_vpc" "sentinel_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "sentinel-vpc"
  }
}

resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.sentinel_vpc.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true

  tags = {
    Name = "sentinel-public-subnet"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.sentinel_vpc.id

  tags = {
    Name = "sentinel-igw"
  }
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.sentinel_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

resource "aws_route_table_association" "public_assoc" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_rt.id
}

# ------------------------------------------------------------------
# 3. Security Group (Port 22 SSH, 80 HTTP, 8080 App, 6443 K8s)
# ------------------------------------------------------------------
resource "aws_security_group" "sentinel_sg" {
  name        = "sentinel-sg"
  description = "Security group for Sentinel K3s Node"
  vpc_id      = aws_vpc.sentinel_vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ------------------------------------------------------------------
# 4. EC2 Instance (t3a.medium) + K3s User Data Installation
# ------------------------------------------------------------------
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}
resource "aws_key_pair" "sentinel_key" {
  key_name   = "sentinel-canary-key" 
  public_key = file("${path.module}/demo.pub")
}

resource "aws_instance" "k3s_node" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3a.medium"
  subnet_id              = aws_subnet.public_subnet.id
  vpc_security_group_ids = [aws_security_group.sentinel_sg.id]
  key_name               = aws_key_pair.sentinel_key.key_name

  # Add 4GB Swap for memory 
  user_data = <<-EOF
    #!/bin/bash
    fallocate -l 4G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo '/swapfile none swap sw 0 0' >> /etc/fstab

    # Install K3s Lite
    curl -sfL https://get.k3s.io | sh -s - --write-kubeconfig-mode 644
  EOF

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  tags = {
    Name = "Sentinel-K3s-Node"
  }
}

# ------------------------------------------------------------------
# 5. Outputs
# ------------------------------------------------------------------
output "ecr_repository_url" {
  value       = aws_ecr_repository.sentinel.repository_url
  description = "Full ECR Repository URL"
}

output "ecr_repository_name" {
  value       = aws_ecr_repository.sentinel.name
  description = "ECR Repository Name"
}

output "k3s_node_public_ip" {
  value       = aws_instance.k3s_node.public_ip
  description = "Public IP of K3s EC2 Node"
}