#!/bin/sh
set -eu

STATE_BUCKET="${STATE_BUCKET:-iglu-terraform-state}"
LOCK_TABLE="${LOCK_TABLE:-iglu-terraform-locks}"
AWS_REGION="${AWS_REGION:-us-east-1}"

echo "Creating Terraform remote state resources"
echo "Bucket: ${STATE_BUCKET}"
echo "DynamoDB lock table: ${LOCK_TABLE}"
echo "Region: ${AWS_REGION}"

if aws s3api head-bucket --bucket "${STATE_BUCKET}" 2>/dev/null; then
  echo "S3 bucket already exists: ${STATE_BUCKET}"
else
  if [ "${AWS_REGION}" = "us-east-1" ]; then
    aws s3api create-bucket \
      --bucket "${STATE_BUCKET}" \
      --region "${AWS_REGION}"
  else
    aws s3api create-bucket \
      --bucket "${STATE_BUCKET}" \
      --region "${AWS_REGION}" \
      --create-bucket-configuration LocationConstraint="${AWS_REGION}"
  fi
fi

aws s3api put-public-access-block \
  --bucket "${STATE_BUCKET}" \
  --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

aws s3api put-bucket-versioning \
  --bucket "${STATE_BUCKET}" \
  --versioning-configuration Status=Enabled

aws s3api put-bucket-encryption \
  --bucket "${STATE_BUCKET}" \
  --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

if aws dynamodb describe-table --table-name "${LOCK_TABLE}" --region "${AWS_REGION}" >/dev/null 2>&1; then
  echo "DynamoDB lock table already exists: ${LOCK_TABLE}"
else
  aws dynamodb create-table \
    --table-name "${LOCK_TABLE}" \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region "${AWS_REGION}"

  aws dynamodb wait table-exists \
    --table-name "${LOCK_TABLE}" \
    --region "${AWS_REGION}"
fi

echo "Remote state is ready."
echo "Use these backend values:"
echo "bucket         = \"${STATE_BUCKET}\""
echo "dynamodb_table = \"${LOCK_TABLE}\""
echo "region         = \"${AWS_REGION}\""
echo "encrypt        = true"
