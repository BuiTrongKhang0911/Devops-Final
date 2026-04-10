# =============================================================================
# BACKEND.TF - Remote State Backend Configuration
# =============================================================================
# Purpose: Store Terraform state in S3 with DynamoDB locking
# Benefits:
#   - Team collaboration (shared state)
#   - State locking (prevent concurrent modifications)
#   - State versioning (rollback capability)
#   - Encryption at rest
# =============================================================================

terraform {
  backend "s3" {
    # IMPORTANT: Replace "REPLACE_ME" with your actual bucket name
    # Example: devops-final-tfstate-1234567890
    bucket = "devops-final-tfstate-REPLACE_ME"
    
    # State file path within bucket
    key = "production/terraform.tfstate"
    
    # AWS region
    region = "ap-southeast-1"
    
    # DynamoDB table for state locking
    dynamodb_table = "devops-final-tflock"
    
    # Enable encryption at rest
    encrypt = true
  }
}

# =============================================================================
# SETUP INSTRUCTIONS (RUN BEFORE FIRST TERRAFORM INIT)
# =============================================================================
# 1. Create S3 bucket:
#    aws s3api create-bucket \
#      --bucket devops-final-tfstate-$(date +%s) \
#      --region ap-southeast-1 \
#      --create-bucket-configuration LocationConstraint=ap-southeast-1
#
# 2. Enable versioning:
#    aws s3api put-bucket-versioning \
#      --bucket YOUR_BUCKET_NAME \
#      --versioning-configuration Status=Enabled
#
# 3. Enable encryption:
#    aws s3api put-bucket-encryption \
#      --bucket YOUR_BUCKET_NAME \
#      --server-side-encryption-configuration \
#      '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
#
# 4. Create DynamoDB table:
#    aws dynamodb create-table \
#      --table-name devops-final-tflock \
#      --attribute-definitions AttributeName=LockID,AttributeType=S \
#      --key-schema AttributeName=LockID,KeyType=HASH \
#      --billing-mode PAY_PER_REQUEST \
#      --region ap-southeast-1
#
# 5. Update bucket name above (replace REPLACE_ME)
#
# 6. Migrate existing state (if any):
#    terraform init -migrate-state
#
# 7. Verify:
#    terraform state list
# =============================================================================

# =============================================================================
# MIGRATION INSTRUCTIONS
# =============================================================================
# 1. Replace "devops-final-tfstate-REPLACE_ME" with your actual bucket name
# 2. Run: terraform init -migrate-state
# 3. Type "yes" when prompted
# 4. Verify: terraform state list
# 5. Delete local state: rm terraform.tfstate*
# =============================================================================
