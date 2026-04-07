# =============================================================================
# EC2.TF - Standalone EC2 Instances cho SonarQube và Database+NFS
# =============================================================================
# Tạo 2 EC2 instances trong Public Subnet:
# 1. SonarQube Server - Code quality analysis
# 2. Database + NFS Server - PostgreSQL và NFS storage (cùng 1 máy để tiết kiệm)
# =============================================================================

# ==========================================
# SECURITY GROUP - SONARQUBE SERVER
# ==========================================
resource "aws_security_group" "sonarqube_sg" {
  name        = "${var.project_name}-sonarqube-sg"
  description = "Security group cho SonarQube Server"
  vpc_id      = module.vpc.vpc_id

  # SSH từ Internet
  ingress {
    description = "SSH from anywhere"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # SonarQube Web UI từ Internet
  ingress {
    description = "SonarQube Web UI"
    from_port   = 9000
    to_port     = 9000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTP - cho Nginx và Certbot validation
  ingress {
    description = "HTTP for Nginx/Certbot"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTPS - cho SonarQube qua Nginx
  ingress {
    description = "HTTPS for SonarQube"
    from_port   = 443
    to_port     = 443
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

  tags = {
    Name        = "${var.project_name}-sonarqube-sg"
    Environment = var.environment
    Project     = var.project_name
  }
}

# ==========================================
# SECURITY GROUP - DATABASE + NFS SERVER
# ==========================================
resource "aws_security_group" "db_nfs_sg" {
  name        = "${var.project_name}-db-nfs-sg"
  description = "Security group cho Database + NFS Server"
  vpc_id      = module.vpc.vpc_id

  # SSH từ Internet (để chạy Ansible)
  ingress {
    description = "SSH from anywhere for Ansible"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # PostgreSQL - CHỈ từ VPC internal
  ingress {
    description = "PostgreSQL from VPC"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # PostgreSQL - từ EKS Node Security Group
  ingress {
    description     = "PostgreSQL from EKS nodes"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [module.eks.node_security_group_id]
  }

  # NFS - CHỈ từ VPC internal
  ingress {
    description = "NFS from VPC"
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # NFS - từ EKS Node Security Group
  ingress {
    description     = "NFS from EKS nodes"
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [module.eks.node_security_group_id]
  }

  # Allow all outbound
  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project_name}-db-nfs-sg"
    Environment = var.environment
    Project     = var.project_name
  }
}

# ==========================================
# EC2 INSTANCE - SONARQUBE SERVER
# ==========================================
resource "aws_instance" "sonarqube" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.sonarqube_instance_type
  key_name                    = var.key_name
  subnet_id                   = module.vpc.public_subnets[0]
  vpc_security_group_ids      = [aws_security_group.sonarqube_sg.id]
  associate_public_ip_address = true

  root_block_device {
    volume_size           = var.sonarqube_volume_size
    volume_type           = "gp3"
    delete_on_termination = true
  }

  tags = {
    Name        = "${var.project_name}-sonarqube"
    Environment = var.environment
    Project     = var.project_name
    Role        = "sonarqube-server"
  }
}

# ==========================================
# EC2 INSTANCE - DATABASE + NFS SERVER
# ==========================================
resource "aws_instance" "db_nfs" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.db_nfs_instance_type
  key_name                    = var.key_name
  subnet_id                   = module.vpc.public_subnets[0]
  vpc_security_group_ids      = [aws_security_group.db_nfs_sg.id]
  associate_public_ip_address = true

  root_block_device {
    volume_size           = var.db_nfs_volume_size
    volume_type           = "gp3"
    delete_on_termination = true
  }

  tags = {
    Name        = "${var.project_name}-db-nfs"
    Environment = var.environment
    Project     = var.project_name
    Role        = "database-nfs-server"
  }
}

# ==========================================
# ELASTIC IPs - IP cố định cho các servers
# ==========================================
resource "aws_eip" "sonarqube_eip" {
  instance = aws_instance.sonarqube.id
  domain   = "vpc"

  tags = {
    Name        = "${var.project_name}-sonarqube-eip"
    Environment = var.environment
    Project     = var.project_name
  }

  depends_on = [aws_instance.sonarqube]
}

resource "aws_eip" "db_nfs_eip" {
  instance = aws_instance.db_nfs.id
  domain   = "vpc"

  tags = {
    Name        = "${var.project_name}-db-nfs-eip"
    Environment = var.environment
    Project     = var.project_name
  }

  depends_on = [aws_instance.db_nfs]
}
