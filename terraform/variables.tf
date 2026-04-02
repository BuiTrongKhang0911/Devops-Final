# =============================================================================
# VARIABLES.TF - Khai báo biến số cho Infrastructure
# =============================================================================

# ==========================================
# BIẾN BẮT BUỘC - Người dùng phải cung cấp
# ==========================================
variable "key_name" {
  description = "Tên khóa SSH (.pem) trên AWS để truy cập EC2"
  type        = string
}

# ==========================================
# BIẾN MẶC ĐỊNH - Có thể override nếu cần
# ==========================================
variable "aws_region" {
  description = "AWS Region để triển khai"
  type        = string
  default     = "ap-southeast-1"
}

variable "project_name" {
  description = "Tên dự án (dùng cho tags và naming)"
  type        = string
  default     = "devops-final"
}

variable "environment" {
  description = "Môi trường triển khai"
  type        = string
  default     = "production"
}

# ==========================================
# VPC CONFIGURATION
# ==========================================
variable "vpc_cidr" {
  description = "CIDR block cho VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks cho Public Subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks cho Private Subnets"
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24"]
}

# ==========================================
# EKS CONFIGURATION
# ==========================================
variable "cluster_name" {
  description = "Tên EKS Cluster"
  type        = string
  default     = "devops-final-eks"
}

variable "cluster_version" {
  description = "Phiên bản Kubernetes cho EKS"
  type        = string
  default     = "1.35"
}

variable "node_instance_type" {
  description = "Instance type cho EKS Worker Nodes"
  type        = string
  default     = "c7i-flex.large"
}

variable "node_desired_size" {
  description = "Số lượng nodes mong muốn"
  type        = number
  default     = 2
}

variable "node_min_size" {
  description = "Số lượng nodes tối thiểu"
  type        = number
  default     = 2
}

variable "node_max_size" {
  description = "Số lượng nodes tối đa"
  type        = number
  default     = 4
}

# ==========================================
# EC2 STANDALONE SERVERS
# ==========================================
variable "sonarqube_instance_type" {
  description = "Instance type cho SonarQube Server"
  type        = string
  default     = "c7i-flex.large"
}

variable "sonarqube_volume_size" {
  description = "Dung lượng ổ cứng cho SonarQube (GB)"
  type        = number
  default     = 20
}

variable "db_nfs_instance_type" {
  description = "Instance type cho Database + NFS Server"
  type        = string
  default     = "c7i-flex.large"
}

variable "db_nfs_volume_size" {
  description = "Dung lượng ổ cứng cho DB + NFS Server (GB)"
  type        = number
  default     = 30
}
# ==========================================
# HTTPS CONFIGURATION (OPTIONAL)
# ==========================================
variable "domain_name" {
  description = "Domain name cho HTTPS (để trống nếu không dùng)"
  type        = string
  default     = ""
}

variable "enable_https" {
  description = "Bật HTTPS với ACM certificate và Route53"
  type        = bool
  default     = false
}
