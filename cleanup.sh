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
# STEP 1: Delete Kubernetes Ingress (triggers ALB deletion)
# =============================================================================
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
