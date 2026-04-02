# =============================================================================
# EKS.TF - Amazon EKS Cluster Configuration
# =============================================================================
# Sử dụng official AWS EKS module để tạo:
# - EKS Control Plane
# - Managed Node Group trong Private Subnets
# - OIDC Provider (bắt buộc cho AWS Load Balancer Controller)
# - IAM Roles tự động
# =============================================================================

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  # ==========================================
  # CLUSTER CONFIGURATION
  # ==========================================
  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version

  # Endpoint access
  cluster_endpoint_public_access  = true
  cluster_endpoint_private_access = true

  # VPC Configuration
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  # ==========================================
  # OIDC PROVIDER - BẮT BUỘC cho AWS LB Controller
  # ==========================================
  enable_irsa = true

  # ==========================================
  # AWS AUTH - Cho phép IAM users/roles truy cập cluster
  # ==========================================
  # Tự động thêm current IAM user/role vào aws-auth
  # Điều này cho phép GitHub Actions (dùng cùng credentials) truy cập cluster
  enable_cluster_creator_admin_permissions = true
  
  # Nếu cần thêm IAM users khác, uncomment và thêm ARN:
  # aws_auth_users = [
  #   {
  #     userarn  = "arn:aws:iam::ACCOUNT_ID:user/github-actions"
  #     username = "github-actions"
  #     groups   = ["system:masters"]
  #   }
  # ]

  # ==========================================
  # CLUSTER ADDONS
  # ==========================================
  cluster_addons = {
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent = true
    }
  }

  # ==========================================
  # MANAGED NODE GROUP
  # ==========================================
  eks_managed_node_groups = {
    main = {
      name = "main-ng"

      # Instance configuration
      instance_types = [var.node_instance_type]
      capacity_type  = "ON_DEMAND"

      # Scaling configuration
      min_size     = var.node_min_size
      max_size     = var.node_max_size
      desired_size = var.node_desired_size

      # Disk configuration
      block_device_mappings = {
        xvda = {
          device_name = "/dev/xvda"
          ebs = {
            volume_size           = 30
            volume_type           = "gp3"
            delete_on_termination = true
          }
        }
      }

      # Network configuration
      subnet_ids = module.vpc.private_subnets

      # Labels
      labels = {
        Environment = var.environment
        NodeGroup   = "main"
      }

      # Tags
      tags = {
        Name        = "${var.project_name}-eks-node"
        Environment = var.environment
        Project     = var.project_name
      }
    }
  }

  # ==========================================
  # CLUSTER SECURITY GROUP RULES
  # ==========================================
  # Cho phép traffic từ EC2 standalone servers vào cluster
  cluster_security_group_additional_rules = {
    ingress_ec2_to_cluster = {
      description = "Allow EC2 instances to communicate with cluster API"
      protocol    = "tcp"
      from_port   = 443
      to_port     = 443
      type        = "ingress"
      cidr_blocks = [var.vpc_cidr]
    }
  }

  # Node security group rules
  node_security_group_additional_rules = {
    # Cho phép nodes communicate với nhau
    ingress_self_all = {
      description = "Node to node all traffic"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "ingress"
      self        = true
    }
    
    # Cho phép traffic từ DB/NFS server vào nodes
    ingress_db_nfs_to_nodes = {
      description = "Allow DB/NFS server to communicate with nodes"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "ingress"
      cidr_blocks = [var.vpc_cidr]
    }
  }

  # ==========================================
  # TAGS
  # ==========================================
  tags = {
    Name        = var.cluster_name
    Environment = var.environment
    Project     = var.project_name
  }
}
