#!/bin/bash
# =============================================================================
# CLEANUP.SH - Clean up AWS resources before Terraform destroy
# =============================================================================
# Script này xóa các resources được tạo bởi Kubernetes/Helm/setup.sh
# mà Terraform KHÔNG quản lý, để tránh lỗi dependency khi terraform destroy
#
# Resources cần xóa manual:
# 1. ALB (do Kubernetes Ingress tạo qua AWS Load Balancer Controller)
# 2. Target Groups (do ALB tạo)
# 3. Security Groups của ALB (có tag elbv2.k8s.aws/cluster)
# 4. ENI của ALB
# 5. CNAME record (do setup.sh tạo)
#
# Resources để Terraform tự xóa:
# - VPC, Subnets, IGW, NAT Gateway, EIP, Route Tables
# - EKS Cluster, Node Groups
# - IAM Roles/Policies
# - ACM Certificate (nếu có)
# =============================================================================

set -e

REGION="ap-southeast-1"
CLUSTER_NAME="devops-final-eks"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=============================================${NC}"
echo -e "${GREEN}🧹 AWS CLEANUP SCRIPT${NC}"
echo -e "${GREEN}=============================================${NC}"
echo ""

# =============================================================================
# STEP 0: Install kubectl if not present
# =============================================================================
if ! command -v kubectl &> /dev/null; then
  echo -e "${YELLOW}kubectl not found. Installing...${NC}"
  cd /tmp
  curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
  chmod +x kubectl
  sudo mv kubectl /usr/local/bin/
  cd - > /dev/null
  echo -e "${GREEN}✅ kubectl installed${NC}"
fi

# Configure kubectl if not already configured
if ! kubectl cluster-info &>/dev/null; then
  echo -e "${YELLOW}Configuring kubectl for EKS cluster...${NC}"
  aws eks update-kubeconfig --name $CLUSTER_NAME --region $REGION 2>/dev/null || true
fi

# =============================================================================
# STEP 1: Delete Kubernetes Ingress (triggers ALB deletion)
# =============================================================================
echo ""
echo -e "${YELLOW}=== Step 1: Deleting Kubernetes Ingress ===${NC}"

# Check if kubectl is configured
if kubectl cluster-info &>/dev/null; then
  echo "Deleting all Ingress resources..."
  kubectl delete ingress --all -n devops-final 2>/dev/null || echo "No ingress found"
  
  echo "Deleting all LoadBalancer services (if any)..."
  kubectl delete svc --all -n devops-final 2>/dev/null || echo "No LoadBalancer services found"
  
  echo -e "${GREEN}✅ Kubernetes resources deleted${NC}"
else
  echo -e "${YELLOW}⚠️  kubectl not configured, skipping Kubernetes cleanup${NC}"
fi

echo "Waiting 60 seconds for ALB deletion to start..."
sleep 60

# =============================================================================
# STEP 2: Force delete remaining ALBs (created by Kubernetes)
# =============================================================================
echo ""
echo -e "${YELLOW}=== Step 2: Force deleting remaining ALBs ===${NC}"

ALB_ARNS=$(aws elbv2 describe-load-balancers --region $REGION 2>/dev/null | \
  grep -o 'arn:aws:elasticloadbalancing[^"]*' || echo "")

if [ -z "$ALB_ARNS" ]; then
  echo -e "${GREEN}✅ No ALBs found${NC}"
else
  echo "$ALB_ARNS" | while read arn; do
    if [ ! -z "$arn" ]; then
      echo "Deleting ALB: $arn"
      aws elbv2 delete-load-balancer --load-balancer-arn "$arn" --region $REGION 2>/dev/null || true
    fi
  done
  echo -e "${GREEN}✅ ALB deletion triggered${NC}"
  echo "Waiting 120 seconds for ALB cleanup..."
  sleep 120
fi

# =============================================================================
# STEP 3: Delete Route53 CNAME records (created by setup.sh)
# =============================================================================
echo ""
echo -e "${YELLOW}=== Step 3: Deleting Route53 CNAME records ===${NC}"

# Get Hosted Zone ID
HOSTED_ZONE_ID=$(aws route53 list-hosted-zones \
  --query "HostedZones[?Name=='devops-midterm.online.'].Id" \
  --output text 2>/dev/null | cut -d'/' -f3 || echo "")

if [ -z "$HOSTED_ZONE_ID" ] || [ "$HOSTED_ZONE_ID" == "None" ]; then
  echo -e "${YELLOW}⚠️  Hosted Zone not found, skipping CNAME deletion${NC}"
else
  echo "Found Hosted Zone: $HOSTED_ZONE_ID"
  
  # Delete A record for root domain
  echo "  Deleting ${DOMAIN_NAME}..."
  RECORD_EXISTS=$(aws route53 list-resource-record-sets \
    --hosted-zone-id $HOSTED_ZONE_ID \
    --query "ResourceRecordSets[?Name=='devops-midterm.online.' && Type=='A'].AliasTarget.DNSName" \
    --output text 2>/dev/null || echo "")
  
  if [ -z "$RECORD_EXISTS" ] || [ "$RECORD_EXISTS" == "None" ]; then
    echo -e "${GREEN}✅ No A record found for root domain${NC}"
  else
    cat > /tmp/delete-root-a.json <<EOF
{
  "Changes": [{
    "Action": "DELETE",
    "ResourceRecordSet": {
      "Name": "devops-midterm.online",
      "Type": "A",
      "AliasTarget": {
        "HostedZoneId": "Z1LMS91P8CMLE5",
        "DNSName": "$RECORD_EXISTS",
        "EvaluateTargetHealth": false
      }
    }
  }]
}
EOF
    
    aws route53 change-resource-record-sets \
      --hosted-zone-id $HOSTED_ZONE_ID \
      --change-batch file:///tmp/delete-root-a.json 2>/dev/null || true
    
    rm -f /tmp/delete-root-a.json
    echo -e "${GREEN}✅ A record deleted: devops-midterm.online${NC}"
  fi
  
  # Delete CNAME record for grafana
  echo "  Deleting grafana.devops-midterm.online..."
  CNAME_VALUE=$(aws route53 list-resource-record-sets \
    --hosted-zone-id $HOSTED_ZONE_ID \
    --query "ResourceRecordSets[?Name=='grafana.devops-midterm.online.' && Type=='CNAME'].ResourceRecords[0].Value" \
    --output text 2>/dev/null || echo "")
  
  if [ -z "$CNAME_VALUE" ] || [ "$CNAME_VALUE" == "None" ]; then
    echo -e "${GREEN}✅ No CNAME record found for grafana${NC}"
  else
    cat > /tmp/delete-grafana-cname.json <<EOF
{
  "Changes": [{
    "Action": "DELETE",
    "ResourceRecordSet": {
      "Name": "grafana.devops-midterm.online",
      "Type": "CNAME",
      "TTL": 300,
      "ResourceRecords": [{"Value": "$CNAME_VALUE"}]
    }
  }]
}
EOF
    
    aws route53 change-resource-record-sets \
      --hosted-zone-id $HOSTED_ZONE_ID \
      --change-batch file:///tmp/delete-grafana-cname.json 2>/dev/null || true
    
    rm -f /tmp/delete-grafana-cname.json
    echo -e "${GREEN}✅ CNAME record deleted: grafana.devops-midterm.online${NC}"
  fi
fi

# =============================================================================
# STEP 3.5: Delete ENIs and Security Groups (created by Kubernetes)
# =============================================================================
echo ""
echo -e "${YELLOW}=== Step 3.5: Deleting ENIs and Security Groups ===${NC}"

# Get VPC ID
VPC_ID=$(aws ec2 describe-vpcs --region $REGION \
  --filters "Name=tag:Name,Values=devops-final-vpc" \
  --query "Vpcs[0].VpcId" --output text 2>/dev/null || echo "")

if [ -z "$VPC_ID" ] || [ "$VPC_ID" == "None" ]; then
  echo -e "${YELLOW}⚠️  VPC not found, skipping ENI/SG cleanup${NC}"
else
  echo "Found VPC: $VPC_ID"
  
  # Delete ENIs created by Kubernetes (ALB, EBS CSI, VPC CNI)
  echo "Finding ENIs in VPC..."
  ENI_IDS=$(aws ec2 describe-network-interfaces --region $REGION \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --query "NetworkInterfaces[?contains(Description, 'ELB') || contains(Description, 'aws-k8s') || contains(Description, 'Amazon EKS')].NetworkInterfaceId" \
    --output text 2>/dev/null || echo "")
  
  if [ -z "$ENI_IDS" ]; then
    echo -e "${GREEN}✅ No Kubernetes ENIs found${NC}"
  else
    for ENI_ID in $ENI_IDS; do
      echo "  Processing ENI: $ENI_ID"
      
      # Check if ENI is attached
      ATTACHMENT_ID=$(aws ec2 describe-network-interfaces --region $REGION \
        --network-interface-ids $ENI_ID \
        --query "NetworkInterfaces[0].Attachment.AttachmentId" \
        --output text 2>/dev/null || echo "")
      
      if [ ! -z "$ATTACHMENT_ID" ] && [ "$ATTACHMENT_ID" != "None" ]; then
        echo "    Detaching ENI..."
        aws ec2 detach-network-interface --region $REGION \
          --attachment-id $ATTACHMENT_ID --force 2>/dev/null || true
        sleep 5
      fi
      
      echo "    Deleting ENI..."
      aws ec2 delete-network-interface --region $REGION \
        --network-interface-id $ENI_ID 2>/dev/null || true
    done
    echo -e "${GREEN}✅ ENIs deleted${NC}"
    sleep 10
  fi
  
  # Delete Security Groups created by Kubernetes (has tag elbv2.k8s.aws/cluster)
  echo "Finding Security Groups created by Kubernetes..."
  SG_IDS=$(aws ec2 describe-security-groups --region $REGION \
    --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag-key,Values=elbv2.k8s.aws/cluster" \
    --query "SecurityGroups[].GroupId" --output text 2>/dev/null || echo "")
  
  if [ -z "$SG_IDS" ]; then
    echo -e "${GREEN}✅ No Kubernetes Security Groups found${NC}"
  else
    for SG_ID in $SG_IDS; do
      echo "  Deleting Security Group: $SG_ID"
      
      # Remove all ingress rules first
      aws ec2 describe-security-groups --region $REGION --group-ids $SG_ID \
        --query "SecurityGroups[0].IpPermissions" --output json > /tmp/sg-ingress-$SG_ID.json 2>/dev/null || true
      
      if [ -s /tmp/sg-ingress-$SG_ID.json ] && [ "$(cat /tmp/sg-ingress-$SG_ID.json)" != "[]" ]; then
        aws ec2 revoke-security-group-ingress --region $REGION \
          --group-id $SG_ID \
          --ip-permissions file:///tmp/sg-ingress-$SG_ID.json 2>/dev/null || true
      fi
      rm -f /tmp/sg-ingress-$SG_ID.json
      
      # Remove all egress rules
      aws ec2 describe-security-groups --region $REGION --group-ids $SG_ID \
        --query "SecurityGroups[0].IpPermissionsEgress" --output json > /tmp/sg-egress-$SG_ID.json 2>/dev/null || true
      
      if [ -s /tmp/sg-egress-$SG_ID.json ] && [ "$(cat /tmp/sg-egress-$SG_ID.json)" != "[]" ]; then
        aws ec2 revoke-security-group-egress --region $REGION \
          --group-id $SG_ID \
          --ip-permissions file:///tmp/sg-egress-$SG_ID.json 2>/dev/null || true
      fi
      rm -f /tmp/sg-egress-$SG_ID.json
      
      # Delete the security group
      aws ec2 delete-security-group --region $REGION --group-id $SG_ID 2>/dev/null || true
    done
    echo -e "${GREEN}✅ Security Groups deleted${NC}"
    sleep 5
  fi
fi

# =============================================================================
# STEP 4: Terraform Destroy (will handle VPC, Subnets, IGW, NAT, EIP, etc.)
# =============================================================================
echo ""
echo -e "${YELLOW}=== Step 4: Running Terraform Destroy ===${NC}"
cd terraform

echo ""
echo -e "${RED}⚠️  This will destroy all Terraform-managed resources!${NC}"
echo -e "${YELLOW}Terraform will automatically delete:${NC}"
echo -e "${YELLOW}  - VPC, Subnets, Internet Gateway${NC}"
echo -e "${YELLOW}  - NAT Gateway, Elastic IP${NC}"
echo -e "${YELLOW}  - EKS Cluster, Node Groups${NC}"
echo -e "${YELLOW}  - IAM Roles, Security Groups${NC}"
echo -e "${YELLOW}  - ACM Certificate (if HTTPS enabled)${NC}"
echo ""
echo -e "${YELLOW}Press Ctrl+C to cancel, or wait 10 seconds to continue...${NC}"
sleep 10

terraform destroy -auto-approve

cd ..

# =============================================================================
# DONE
# =============================================================================
echo ""
echo -e "${GREEN}=============================================${NC}"
echo -e "${GREEN}✅ CLEANUP COMPLETED!${NC}"
echo -e "${GREEN}=============================================${NC}"
echo ""
echo -e "${YELLOW}📝 Note: If you see any errors above, you may need to:${NC}"
echo -e "${YELLOW}   1. Wait a few more minutes for AWS to finish cleanup${NC}"
echo -e "${YELLOW}   2. Run this script again${NC}"
echo -e "${YELLOW}   3. Manually delete remaining resources in AWS Console${NC}"
echo ""
