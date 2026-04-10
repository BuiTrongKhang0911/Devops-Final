#!/bin/bash
# =============================================================================
# BOOTSTRAP-BACKEND.SH - Auto Setup Remote State Backend
# =============================================================================
# Purpose: Automatically create S3 bucket and DynamoDB table for Terraform
#          remote state backend
#
# Usage:
#   chmod +x bootstrap-backend.sh
#   ./bootstrap-backend.sh
#
# Output: Bucket name to add as GitHub Secret
#
# Requirements:
#   - AWS CLI configured with credentials
#   - Permissions to create S3 buckets and DynamoDB tables
# =============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

print_header() { echo -e "\n${BLUE}=============================================${NC}\n${BLUE}$1${NC}\n${BLUE}=============================================${NC}\n"; }
print_success() { echo -e "${GREEN}✅ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
print_error() { echo -e "${RED}❌ $1${NC}"; }
print_info() { echo -e "${CYAN}ℹ️  $1${NC}"; }

# =============================================================================
# CHECK AWS CREDENTIALS
# =============================================================================
print_header "1. Kiểm tra AWS Credentials"

if ! aws sts get-caller-identity &> /dev/null; then
    print_error "AWS credentials chưa được cấu hình!"
    echo ""
    echo "Chạy: aws configure"
    echo "Hoặc export AWS_ACCESS_KEY_ID và AWS_SECRET_ACCESS_KEY"
    exit 1
fi

AWS_ACCOUNT=$(aws sts get-caller-identity --query "Account" --output text)
AWS_USER=$(aws sts get-caller-identity --query "Arn" --output text | rev | cut -d'/' -f1 | rev)
AWS_REGION=${AWS_REGION:-ap-southeast-1}

print_success "AWS Account: $AWS_ACCOUNT"
print_success "AWS User/Role: $AWS_USER"
print_success "AWS Region: $AWS_REGION"

# =============================================================================
# CREATE S3 BUCKET
# =============================================================================
print_header "2. Tạo S3 Bucket cho Terraform State"

# Generate unique bucket name
TIMESTAMP=$(date +%s)
BUCKET_NAME="devops-final-tfstate-${TIMESTAMP}"

print_info "Bucket name: $BUCKET_NAME"

# Check if bucket already exists
if aws s3 ls "s3://${BUCKET_NAME}" &> /dev/null; then
    print_warning "Bucket đã tồn tại: $BUCKET_NAME"
else
    # Create bucket
    print_info "Đang tạo S3 bucket..."
    aws s3api create-bucket \
        --bucket "$BUCKET_NAME" \
        --region "$AWS_REGION" \
        --create-bucket-configuration LocationConstraint="$AWS_REGION" \
        > /dev/null

    print_success "S3 bucket đã được tạo: $BUCKET_NAME"
fi

# Enable versioning
print_info "Đang bật versioning..."
aws s3api put-bucket-versioning \
    --bucket "$BUCKET_NAME" \
    --versioning-configuration Status=Enabled

print_success "Versioning đã được bật"

# Enable encryption
print_info "Đang bật encryption..."
aws s3api put-bucket-encryption \
    --bucket "$BUCKET_NAME" \
    --server-side-encryption-configuration \
    '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

print_success "Encryption đã được bật"

# Block public access
print_info "Đang chặn public access..."
aws s3api put-public-access-block \
    --bucket "$BUCKET_NAME" \
    --public-access-block-configuration \
    "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

print_success "Public access đã được chặn"

# =============================================================================
# CREATE DYNAMODB TABLE
# =============================================================================
print_header "3. Tạo DynamoDB Table cho State Locking"

TABLE_NAME="devops-final-tflock"

# Check if table already exists
if aws dynamodb describe-table --table-name "$TABLE_NAME" --region "$AWS_REGION" &> /dev/null; then
    print_success "DynamoDB table đã tồn tại: $TABLE_NAME"
else
    print_info "Đang tạo DynamoDB table: $TABLE_NAME"
    
    aws dynamodb create-table \
        --table-name "$TABLE_NAME" \
        --attribute-definitions AttributeName=LockID,AttributeType=S \
        --key-schema AttributeName=LockID,KeyType=HASH \
        --billing-mode PAY_PER_REQUEST \
        --region "$AWS_REGION" \
        > /dev/null
    
    print_info "Đang đợi table active..."
    aws dynamodb wait table-exists --table-name "$TABLE_NAME" --region "$AWS_REGION"
    
    print_success "DynamoDB table đã được tạo: $TABLE_NAME"
fi

# =============================================================================
# SUMMARY & INSTRUCTIONS
# =============================================================================
print_header "🎉 HOÀN TẤT!"

echo -e "${GREEN}"
cat << EOF
=============================================
     REMOTE STATE BACKEND ĐÃ SẴN SÀNG
=============================================

📦 S3 BUCKET:
   - Name: ${BUCKET_NAME}
   - Region: ${AWS_REGION}
   - Versioning: Enabled
   - Encryption: AES256
   - Public Access: Blocked

🗄️  DYNAMODB TABLE:
   - Name: ${TABLE_NAME}
   - Region: ${AWS_REGION}
   - Billing: Pay-per-request

=============================================
EOF
echo -e "${NC}"

echo ""
print_header "📝 NEXT STEPS - Thêm GitHub Secret"

echo ""
echo -e "${YELLOW}Bước 1: Vào GitHub Repository Settings${NC}"
echo "   → Settings → Secrets and variables → Actions"
echo ""
echo -e "${YELLOW}Bước 2: Click 'New repository secret'${NC}"
echo ""
echo -e "${YELLOW}Bước 3: Thêm secret sau:${NC}"
echo ""
echo -e "${GREEN}   Name:${NC}  TF_BACKEND_BUCKET"
echo -e "${GREEN}   Value:${NC} ${BUCKET_NAME}"
echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}Copy value này:${NC}"
echo ""
echo -e "${GREEN}${BUCKET_NAME}${NC}"
echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${YELLOW}Bước 4: Sau khi thêm secret, workflow sẽ tự động:${NC}"
echo "   - Inject bucket name vào backend config"
echo "   - Chạy terraform init với remote state"
echo "   - Lưu state lên S3"
echo ""
print_success "Bootstrap hoàn tất! Thêm secret vào GitHub và chạy workflow."

