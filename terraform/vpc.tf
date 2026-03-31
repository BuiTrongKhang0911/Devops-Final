# =============================================================================
# VPC.TF - Virtual Private Cloud với Public/Private Subnets
# =============================================================================
# Sử dụng official AWS VPC module để tạo:
# - 1 VPC với CIDR 10.0.0.0/16
# - 2 Public Subnets (có Internet Gateway)
# - 2 Private Subnets (có NAT Gateway)
# - Tags chuẩn cho AWS Load Balancer Controller
# =============================================================================

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${var.project_name}-vpc"
  cidr = var.vpc_cidr

  # Sử dụng 2 Availability Zones đầu tiên
  azs = slice(data.aws_availability_zones.available.names, 0, 2)

  # Public Subnets - cho ALB và EC2 standalone servers
  public_subnets = var.public_subnet_cidrs

  # Private Subnets - cho EKS Worker Nodes
  private_subnets = var.private_subnet_cidrs

  # Enable NAT Gateway cho Private Subnets (để nodes có thể pull images)
  enable_nat_gateway = true
  single_nat_gateway = true # Dùng 1 NAT Gateway để tiết kiệm chi phí

  # Enable DNS
  enable_dns_hostnames = true
  enable_dns_support   = true

  # Tags chung cho VPC
  tags = {
    Name        = "${var.project_name}-vpc"
    Environment = var.environment
    Project     = var.project_name
  }

  # Tags cho Public Subnets - để AWS Load Balancer Controller nhận diện
  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }

  # Tags cho Private Subnets - để AWS Load Balancer Controller nhận diện
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
}
