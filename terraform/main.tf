# =============================================================================
# MAIN.TF - Infrastructure chính cho DevOps Final Project
# =============================================================================
# Tạo 2 EC2 instances:
#   1. K8s Master Node - chạy Kubernetes cluster
#   2. SonarQube Server - code quality analysis
# =============================================================================

# ==========================================
# 1. KHAI BÁO PROVIDER & TERRAFORM VERSION
# ==========================================
terraform {
  required_version = ">= 1.0.0"
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

# ==========================================
# 2. DATA SOURCE - TÌM UBUNTU 24.04 LTS
# ==========================================
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical Official

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ==========================================
# 3. SECURITY GROUP - KUBERNETES CLUSTER
# ==========================================
resource "aws_security_group" "k8s_sg" {
  name        = "${var.project_name}-k8s-sg"
  description = "Security group cho Kubernetes Cluster"

  tags = {
    Name        = "${var.project_name}-k8s-sg"
    Environment = var.environment
    Project     = var.project_name
  }

  # SSH Access
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTP
  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTPS
  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Kubernetes API Server
  ingress {
    description = "Kubernetes API"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Kubelet API
  ingress {
    description = "Kubelet API"
    from_port   = 10250
    to_port     = 10250
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # kube-scheduler
  ingress {
    description = "kube-scheduler"
    from_port   = 10251
    to_port     = 10251
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # kube-controller-manager
  ingress {
    description = "kube-controller-manager"
    from_port   = 10252
    to_port     = 10252
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # etcd
  ingress {
    description = "etcd client"
    from_port   = 2379
    to_port     = 2380
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # NodePort Services Range
  ingress {
    description = "NodePort Services"
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Flannel VXLAN (nếu dùng Flannel CNI)
  ingress {
    description = "Flannel VXLAN"
    from_port   = 8472
    to_port     = 8472
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Calico BGP (nếu dùng Calico CNI)
  ingress {
    description = "Calico BGP"
    from_port   = 179
    to_port     = 179
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all outbound
  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ==========================================
# 4. SECURITY GROUP - SONARQUBE SERVER
# ==========================================
resource "aws_security_group" "sonarqube_sg" {
  name        = "${var.project_name}-sonarqube-sg"
  description = "Security group cho SonarQube Server"

  tags = {
    Name        = "${var.project_name}-sonarqube-sg"
    Environment = var.environment
    Project     = var.project_name
  }

  # SSH Access
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # SonarQube Web UI
  ingress {
    description = "SonarQube Web"
    from_port   = 9000
    to_port     = 9000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all outbound
  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ==========================================
# 5. EC2 INSTANCE - KUBERNETES MASTER NODE
# ==========================================
resource "aws_instance" "k8s_master" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type_k8s
  key_name                    = var.key_name
  vpc_security_group_ids      = [aws_security_group.k8s_sg.id]
  associate_public_ip_address = true

  root_block_device {
    volume_size           = 25 # 25GB cho K8s + images
    volume_type           = "gp3"
    delete_on_termination = true
  }

  tags = {
    Name        = "${var.project_name}-k8s-master"
    Environment = var.environment
    Project     = var.project_name
    Role        = "kubernetes-master"
  }
}

# ==========================================
# 6. EC2 INSTANCE - SONARQUBE SERVER
# ==========================================
resource "aws_instance" "sonarqube" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type_sonarqube
  key_name                    = var.key_name
  vpc_security_group_ids      = [aws_security_group.sonarqube_sg.id]
  associate_public_ip_address = true

  root_block_device {
    volume_size           = 20 # 20GB cho SonarQube
    volume_type           = "gp3"
    delete_on_termination = true
  }

  tags = {
    Name        = "${var.project_name}-sonarqube"
    Environment = var.environment
    Project     = var.project_name
    Role        = "sonarqube-server"
  }

  # User data script - Auto install Docker & SonarQube
  user_data = <<-EOF
              #!/bin/bash
              set -e
              
              # Log output để debug
              exec > >(tee /var/log/user-data.log) 2>&1
              echo "=== Starting SonarQube Setup ==="
              
              # Update system
              apt-get update -y
              apt-get upgrade -y
              
              # Install Docker
              apt-get install -y docker.io
              systemctl start docker
              systemctl enable docker
              
              # Add ubuntu user to docker group
              usermod -aG docker ubuntu
              
              # Cấu hình kernel cho Elasticsearch (SonarQube requirement)
              sysctl -w vm.max_map_count=524288
              sysctl -w fs.file-max=131072
              echo "vm.max_map_count=524288" >> /etc/sysctl.conf
              echo "fs.file-max=131072" >> /etc/sysctl.conf
              
              # Cấu hình ulimits
              ulimit -n 131072
              ulimit -u 8192
              
              # Tạo volume cho SonarQube data persistence
              docker volume create sonarqube_data
              docker volume create sonarqube_logs
              docker volume create sonarqube_extensions
              
              # Chạy SonarQube với volumes
              docker run -d \
                --name sonarqube \
                --restart always \
                -p 9000:9000 \
                -v sonarqube_data:/opt/sonarqube/data \
                -v sonarqube_logs:/opt/sonarqube/logs \
                -v sonarqube_extensions:/opt/sonarqube/extensions \
                sonarqube:community
              
              echo "=== SonarQube Setup Complete ==="
              EOF
}

# ==========================================
# 7. ELASTIC IP - K8S MASTER (IP cố định)
# ==========================================
resource "aws_eip" "k8s_eip" {
  instance = aws_instance.k8s_master.id
  domain   = "vpc"

  tags = {
    Name        = "${var.project_name}-k8s-eip"
    Environment = var.environment
    Project     = var.project_name
  }
}

# ==========================================
# 8. ELASTIC IP - SONARQUBE (IP cố định)
# ==========================================
resource "aws_eip" "sonarqube_eip" {
  instance = aws_instance.sonarqube.id
  domain   = "vpc"

  tags = {
    Name        = "${var.project_name}-sonarqube-eip"
    Environment = var.environment
    Project     = var.project_name
  }
}
