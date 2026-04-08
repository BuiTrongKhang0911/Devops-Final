#!/bin/bash
# =============================================================================
# CLEANUP.SH - Clean up ALL Kubernetes resources before Terraform destroy
# =============================================================================
# Chiến lược: XÓA TẤT CẢ resources do Kubernetes tạo TRƯỚC
# Sau đó Terraform destroy chỉ việc xóa infrastructure thuần túy
#
# KUBERNETES RESOURCES (xóa bởi script này):
# 1. Ingress → triggers ALB deletion
# 2. LoadBalancer Services
# 3. ALB (Application Load Balancer)
# 4. Target Groups
# 5. ENIs (Elastic Network Interfaces) - ALB, EKS, VPC CNI
# 6. Security Groups - ALB SGs, EKS SGs (k8s-traffic-*)
# 7. Route53 DNS records (created by setup.sh)
#
# TERRAFORM RESOURCES (xóa bởi terraform destroy):
# - VPC, Subnets, IGW, NAT Gateway, EIP, Route Tables
# - EKS Cluster, Node Groups
# - EC2 instances (SonarQube, DB+NFS)
# - IAM Roles/Policies
# - Security Groups (Terraform-managed)
# - ACM Certificate
# =============================================================================

set -e

# Disable AWS CLI pager to prevent script from stopping
export AWS_PAGER=""

REGION="ap-southeast-1"
CLUSTER_NAME="devops-final-eks"
DOMAIN_NAME="devops-midterm.online"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${GREEN}=============================================${NC}"
echo -e "${GREEN}🧹 KUBERNETES CLEANUP SCRIPT${NC}"
echo -e "${GREEN}=============================================${NC}"
echo ""
echo -e "${CYAN}Strategy: Delete ALL Kubernetes resources first${NC}"
echo -e "${CYAN}Then let Terraform destroy handle infrastructure${NC}"
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

# Configure kubectl
if ! kubectl cluster-info &>/dev/null; then
  echo -e "${YELLOW}Configuring kubectl for EKS cluster...${NC}"
  aws eks update-kubeconfig --name $CLUSTER_NAME --region $REGION 2>/dev/null || true
fi

# =============================================================================
# STEP 1: Delete ALL Kubernetes resources
# =============================================================================
echo ""
echo -e "${YELLOW}=== Step 1: Deleting Kubernetes Resources ===${NC}"

if kubectl cluster-info &>/dev/null; then
  echo "🗑️  Deleting Ingress resources (triggers ALB deletion)..."
  kubectl delete ingress --all -n devops-final 2>/dev/null || echo "  No ingress in devops-final"
  kubectl delete ingress --all -n staging 2>/dev/null || echo "  No ingress in staging"
  kubectl delete ingress --all -n monitoring 2>/dev/null || echo "  No ingress in monitoring"
  
  echo "🗑️  Deleting LoadBalancer services..."
  kubectl delete svc --all -n devops-final 2>/dev/null || echo "  No services in devops-final"
  kubectl delete svc --all -n staging 2>/dev/null || echo "  No services in staging"
  
  echo -e "${GREEN}✅ Kubernetes resources deleted${NC}"
  echo "⏳ Waiting 60 seconds for ALB deletion to start..."
  sleep 60
else
  echo -e "${YELLOW}⚠️  kubectl not configured, skipping Kubernetes cleanup${NC}"
fi

# =============================================================================
# STEP 2: Force delete ALL ALBs
# =============================================================================
echo ""
echo -e "${YELLOW}=== Step 2: Force deleting ALL ALBs ===${NC}"

ALB_ARNS=$(aws elbv2 describe-load-balancers --region $REGION 2>/dev/null | \
  grep -o 'arn:aws:elasticloadbalancing[^"]*' || echo "")

if [ -z "$ALB_ARNS" ]; then
  echo -e "${GREEN}✅ No ALBs found${NC}"
else
  echo "Found ALBs, deleting..."
  echo "$ALB_ARNS" | while read arn; do
    if [ ! -z "$arn" ]; then
      echo "  Deleting: $arn"
      aws elbv2 delete-load-balancer --load-balancer-arn "$arn" --region $REGION 2>/dev/null || true
    fi
  done
  echo -e "${GREEN}✅ ALB deletion triggered${NC}"
  echo "⏳ Waiting 120 seconds for ALB cleanup..."
  sleep 120
fi

# =============================================================================
# STEP 3: Delete Route53 DNS records (created by setup.sh)
# =============================================================================
echo ""
echo -e "${YELLOW}=== Step 3: Deleting Route53 DNS records ===${NC}"

HOSTED_ZONE_ID=$(aws route53 list-hosted-zones \
  --query "HostedZones[?Name=='${DOMAIN_NAME}.'].Id" \
  --output text 2>/dev/null | cut -d'/' -f3 || echo "")

if [ -z "$HOSTED_ZONE_ID" ] || [ "$HOSTED_ZONE_ID" == "None" ]; then
  echo -e "${YELLOW}⚠️  Hosted Zone not found${NC}"
else
  echo "Found Hosted Zone: $HOSTED_ZONE_ID"
  
  # Delete A record for root domain
  echo "  Deleting ${DOMAIN_NAME}..."
  RECORD_EXISTS=$(aws route53 list-resource-record-sets \
    --hosted-zone-id $HOSTED_ZONE_ID \
    --query "ResourceRecordSets[?Name=='${DOMAIN_NAME}.' && Type=='A'].AliasTarget.DNSName" \
    --output text 2>/dev/null || echo "")
  
  if [ ! -z "$RECORD_EXISTS" ] && [ "$RECORD_EXISTS" != "None" ]; then
    cat > /tmp/delete-root-a.json <<EOF
{
  "Changes": [{
    "Action": "DELETE",
    "ResourceRecordSet": {
      "Name": "${DOMAIN_NAME}",
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
    echo -e "${GREEN}    ✅ Deleted${NC}"
  else
    echo "    No record found"
  fi
  
  # Delete CNAME for grafana
  echo "  Deleting grafana.${DOMAIN_NAME}..."
  CNAME_VALUE=$(aws route53 list-resource-record-sets \
    --hosted-zone-id $HOSTED_ZONE_ID \
    --query "ResourceRecordSets[?Name=='grafana.${DOMAIN_NAME}.' && Type=='CNAME'].ResourceRecords[0].Value" \
    --output text 2>/dev/null || echo "")
  
  if [ ! -z "$CNAME_VALUE" ] && [ "$CNAME_VALUE" != "None" ]; then
    cat > /tmp/delete-grafana-cname.json <<EOF
{
  "Changes": [{
    "Action": "DELETE",
    "ResourceRecordSet": {
      "Name": "grafana.${DOMAIN_NAME}",
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
    echo -e "${GREEN}    ✅ Deleted${NC}"
  else
    echo "    No record found"
  fi
  
  # Delete CNAME for staging
  echo "  Deleting staging.${DOMAIN_NAME}..."
  STAGING_CNAME=$(aws route53 list-resource-record-sets \
    --hosted-zone-id $HOSTED_ZONE_ID \
    --query "ResourceRecordSets[?Name=='staging.${DOMAIN_NAME}.' && Type=='CNAME'].ResourceRecords[0].Value" \
    --output text 2>/dev/null || echo "")
  
  if [ ! -z "$STAGING_CNAME" ] && [ "$STAGING_CNAME" != "None" ]; then
    cat > /tmp/delete-staging-cname.json <<EOF
{
  "Changes": [{
    "Action": "DELETE",
    "ResourceRecordSet": {
      "Name": "staging.${DOMAIN_NAME}",
      "Type": "CNAME",
      "TTL": 300,
      "ResourceRecords": [{"Value": "$STAGING_CNAME"}]
    }
  }]
}
EOF
    aws route53 change-resource-record-sets \
      --hosted-zone-id $HOSTED_ZONE_ID \
      --change-batch file:///tmp/delete-staging-cname.json 2>/dev/null || true
    rm -f /tmp/delete-staging-cname.json
    echo -e "${GREEN}    ✅ Deleted${NC}"
  else
    echo "    No record found"
  fi
  
  # Delete A record for sonar
  echo "  Deleting sonar.${DOMAIN_NAME}..."
  SONAR_IP=$(aws route53 list-resource-record-sets \
    --hosted-zone-id $HOSTED_ZONE_ID \
    --query "ResourceRecordSets[?Name=='sonar.${DOMAIN_NAME}.' && Type=='A'].ResourceRecords[0].Value" \
    --output text 2>/dev/null || echo "")
  
  if [ ! -z "$SONAR_IP" ] && [ "$SONAR_IP" != "None" ]; then
    cat > /tmp/delete-sonar-a.json <<EOF
{
  "Changes": [{
    "Action": "DELETE",
    "ResourceRecordSet": {
      "Name": "sonar.${DOMAIN_NAME}",
      "Type": "A",
      "TTL": 300,
      "ResourceRecords": [{"Value": "$SONAR_IP"}]
    }
  }]
}
EOF
    aws route53 change-resource-record-sets \
      --hosted-zone-id $HOSTED_ZONE_ID \
      --change-batch file:///tmp/delete-sonar-a.json 2>/dev/null || true
    rm -f /tmp/delete-sonar-a.json
    echo -e "${GREEN}    ✅ Deleted${NC}"
  else
    echo "    No record found"
  fi
  
  echo -e "${GREEN}✅ Route53 cleanup completed${NC}"
fi

# =============================================================================
# STEP 4: Delete ALL ENIs (Elastic Network Interfaces) - AGGRESSIVE
# =============================================================================
echo ""
echo -e "${YELLOW}=== Step 4: Deleting ALL ENIs (Aggressive Mode) ===${NC}"

VPC_ID=$(aws ec2 describe-vpcs --region $REGION \
  --filters "Name=tag:Name,Values=devops-final-vpc" \
  --query "Vpcs[0].VpcId" --output text 2>/dev/null || echo "")

if [ -z "$VPC_ID" ] || [ "$VPC_ID" == "None" ]; then
  echo -e "${YELLOW}⚠️  VPC not found${NC}"
else
  echo "Found VPC: $VPC_ID"
  
  # ROUND 1: Find and delete ALL ENIs in VPC
  echo "🔍 Round 1: Finding ALL ENIs in VPC..."
  ALL_ENI_IDS=$(aws ec2 describe-network-interfaces --region $REGION \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --query "NetworkInterfaces[].NetworkInterfaceId" \
    --output text 2>/dev/null || echo "")
  
  if [ -z "$ALL_ENI_IDS" ]; then
    echo -e "${GREEN}✅ No ENIs found${NC}"
  else
    echo "Found ENIs: $(echo $ALL_ENI_IDS | wc -w) total"
    for ENI_ID in $ALL_ENI_IDS; do
      ENI_DESC=$(aws ec2 describe-network-interfaces --region $REGION \
        --network-interface-ids $ENI_ID \
        --query "NetworkInterfaces[0].Description" \
        --output text 2>/dev/null || echo "unknown")
      
      echo "  Processing: $ENI_ID ($ENI_DESC)"
      
      # Force detach if attached
      ATTACHMENT_ID=$(aws ec2 describe-network-interfaces --region $REGION \
        --network-interface-ids $ENI_ID \
        --query "NetworkInterfaces[0].Attachment.AttachmentId" \
        --output text 2>/dev/null || echo "")
      
      if [ ! -z "$ATTACHMENT_ID" ] && [ "$ATTACHMENT_ID" != "None" ]; then
        echo "    Force detaching..."
        aws ec2 detach-network-interface --region $REGION \
          --attachment-id $ATTACHMENT_ID --force 2>/dev/null || true
        sleep 3
      fi
      
      # Delete ENI
      echo "    Deleting..."
      aws ec2 delete-network-interface --region $REGION \
        --network-interface-id $ENI_ID 2>/dev/null && {
        echo -e "${GREEN}    ✅ Deleted${NC}"
      } || {
        echo -e "${YELLOW}    ⚠️  Failed (will retry)${NC}"
      }
    done
    
    echo "⏳ Waiting 20 seconds for ENI deletion..."
    sleep 20
    
    # ROUND 2: Retry failed ENIs
    echo "🔄 Round 2: Retrying remaining ENIs..."
    REMAINING_ENIS=$(aws ec2 describe-network-interfaces --region $REGION \
      --filters "Name=vpc-id,Values=$VPC_ID" \
      --query "NetworkInterfaces[].NetworkInterfaceId" \
      --output text 2>/dev/null || echo "")
    
    if [ ! -z "$REMAINING_ENIS" ]; then
      echo "Found $(echo $REMAINING_ENIS | wc -w) remaining ENIs"
      for ENI_ID in $REMAINING_ENIS; do
        echo "  Retry: $ENI_ID"
        # Try detach again
        ATTACHMENT_ID=$(aws ec2 describe-network-interfaces --region $REGION \
          --network-interface-ids $ENI_ID \
          --query "NetworkInterfaces[0].Attachment.AttachmentId" \
          --output text 2>/dev/null || echo "")
        
        if [ ! -z "$ATTACHMENT_ID" ] && [ "$ATTACHMENT_ID" != "None" ]; then
          aws ec2 detach-network-interface --region $REGION \
            --attachment-id $ATTACHMENT_ID --force 2>/dev/null || true
          sleep 5
        fi
        
        aws ec2 delete-network-interface --region $REGION \
          --network-interface-id $ENI_ID 2>/dev/null || true
      done
      
      echo "⏳ Waiting 30 seconds for final ENI cleanup..."
      sleep 30
    fi
    
    echo -e "${GREEN}✅ ENI cleanup completed${NC}"
  fi
fi

# =============================================================================
# STEP 5: Delete ALL Kubernetes Security Groups
# =============================================================================
echo ""
echo -e "${YELLOW}=== Step 5: Deleting ALL Kubernetes Security Groups ===${NC}"

if [ ! -z "$VPC_ID" ] && [ "$VPC_ID" != "None" ]; then
  # Find ALL non-default, non-Terraform Security Groups
  echo "🔍 Finding Kubernetes Security Groups..."
  
  # Get ALL SGs in VPC (except default)
  ALL_SG_IDS=$(aws ec2 describe-security-groups --region $REGION \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --query "SecurityGroups[?GroupName!='default'].GroupId" \
    --output text 2>/dev/null || echo "")
  
  if [ -z "$ALL_SG_IDS" ]; then
    echo -e "${GREEN}✅ No Security Groups to clean${NC}"
  else
    echo "Found Security Groups: $ALL_SG_IDS"
    
    # CRITICAL: Remove ALL rules from ALL SGs to break circular dependencies
    echo "🔓 Removing all ingress/egress rules (breaks circular dependencies)..."
    for SG_ID in $ALL_SG_IDS; do
      SG_NAME=$(aws ec2 describe-security-groups --region $REGION --group-ids $SG_ID \
        --query "SecurityGroups[0].GroupName" --output text 2>/dev/null || echo "unknown")
      echo "  Processing: $SG_ID ($SG_NAME)"
      
      # Revoke ingress
      INGRESS=$(aws ec2 describe-security-groups --region $REGION --group-ids $SG_ID \
        --query "SecurityGroups[0].IpPermissions" --output json 2>/dev/null || echo "[]")
      if [ "$INGRESS" != "[]" ] && [ "$INGRESS" != "null" ]; then
        echo "$INGRESS" > /tmp/ing-$SG_ID.json
        aws ec2 revoke-security-group-ingress --region $REGION \
          --group-id $SG_ID --ip-permissions file:///tmp/ing-$SG_ID.json 2>/dev/null || true
        rm -f /tmp/ing-$SG_ID.json
      fi
      
      # Revoke egress
      EGRESS=$(aws ec2 describe-security-groups --region $REGION --group-ids $SG_ID \
        --query "SecurityGroups[0].IpPermissionsEgress" --output json 2>/dev/null || echo "[]")
      if [ "$EGRESS" != "[]" ] && [ "$EGRESS" != "null" ]; then
        echo "$EGRESS" > /tmp/eg-$SG_ID.json
        aws ec2 revoke-security-group-egress --region $REGION \
          --group-id $SG_ID --ip-permissions file:///tmp/eg-$SG_ID.json 2>/dev/null || true
        rm -f /tmp/eg-$SG_ID.json
      fi
    done
    
    echo "⏳ Waiting 10 seconds for rule removal to propagate..."
    sleep 10
    
    # Now delete ONLY Kubernetes-created Security Groups
    echo "🗑️  Deleting Kubernetes Security Groups..."
    for SG_ID in $ALL_SG_IDS; do
      SG_NAME=$(aws ec2 describe-security-groups --region $REGION --group-ids $SG_ID \
        --query "SecurityGroups[0].GroupName" --output text 2>/dev/null || echo "")
      
      # Only delete Kubernetes SGs: k8s-traffic-*, ALB SGs with elbv2 tag
      IS_K8S_SG=false
      if [[ "$SG_NAME" == k8s-traffic-* ]]; then
        IS_K8S_SG=true
      fi
      
      # Check for ALB tag
      HAS_ALB_TAG=$(aws ec2 describe-security-groups --region $REGION --group-ids $SG_ID \
        --query "SecurityGroups[0].Tags[?Key=='elbv2.k8s.aws/cluster'].Value" \
        --output text 2>/dev/null || echo "")
      if [ ! -z "$HAS_ALB_TAG" ]; then
        IS_K8S_SG=true
      fi
      
      if [ "$IS_K8S_SG" = true ]; then
        echo "  Deleting Kubernetes SG: $SG_ID ($SG_NAME)"
        aws ec2 delete-security-group --region $REGION --group-id $SG_ID 2>/dev/null && {
          echo -e "${GREEN}    ✅ Deleted${NC}"
        } || {
          echo -e "${YELLOW}    ⚠️  Cannot delete (will retry)${NC}"
        }
      else
        echo "  Skipping Terraform SG: $SG_ID ($SG_NAME)"
      fi
    done
    
    # Final retry for stubborn SGs with more aggressive approach
    echo "🔄 Final retry - deleting all non-default SGs..."
    sleep 15
    
    # Get fresh list of SGs
    REMAINING_SGS=$(aws ec2 describe-security-groups --region $REGION \
      --filters "Name=vpc-id,Values=$VPC_ID" \
      --query "SecurityGroups[?GroupName!='default'].GroupId" \
      --output text 2>/dev/null || echo "")
    
    for SG_ID in $REMAINING_SGS; do
      SG_NAME=$(aws ec2 describe-security-groups --region $REGION --group-ids $SG_ID \
        --query "SecurityGroups[0].GroupName" --output text 2>/dev/null || echo "")
      
      # Try to delete any non-default SG
      if [ "$SG_NAME" != "default" ]; then
        echo "  Attempting to delete: $SG_ID ($SG_NAME)"
        aws ec2 delete-security-group --region $REGION --group-id $SG_ID 2>/dev/null && {
          echo -e "${GREEN}    ✅ Deleted${NC}"
        } || {
          echo -e "${YELLOW}    ⚠️  Still has dependencies (Terraform will handle)${NC}"
        }
      fi
    done
    
    echo -e "${GREEN}✅ Security Groups cleanup completed${NC}"
    echo -e "${CYAN}Note: Remaining SGs will be deleted by Terraform${NC}"
  fi
fi

# =============================================================================
# STEP 6: Terraform Destroy (clean infrastructure)
# =============================================================================
echo ""
echo -e "${YELLOW}=== Step 6: Running Terraform Destroy ===${NC}"
echo ""
echo -e "${CYAN}All Kubernetes resources have been cleaned up!${NC}"
echo -e "${CYAN}Now Terraform can safely destroy infrastructure...${NC}"
echo ""

cd terraform

echo -e "${RED}⚠️  This will destroy all Terraform-managed resources:${NC}"
echo "  - VPC, Subnets, Internet Gateway, NAT Gateway"
echo "  - EKS Cluster, Node Groups"
echo "  - EC2 instances (SonarQube, DB+NFS)"
echo "  - IAM Roles, Policies"
echo "  - Terraform-managed Security Groups"
echo "  - ACM Certificate (if HTTPS enabled)"
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
echo -e "${CYAN}Summary:${NC}"
echo "  ✅ Kubernetes resources deleted"
echo "  ✅ ALBs deleted"
echo "  ✅ Route53 DNS records deleted"
echo "  ✅ ENIs deleted"
echo "  ✅ Kubernetes Security Groups deleted"
echo "  ✅ Terraform infrastructure destroyed"
echo ""
echo -e "${YELLOW}📝 If you see any errors, you may need to:${NC}"
echo "  1. Wait a few minutes for AWS to finish cleanup"
echo "  2. Run this script again"
echo "  3. Check AWS Console for remaining resources"
echo ""
