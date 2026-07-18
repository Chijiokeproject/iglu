#!/bin/sh
set -eu

BUCKET="${STATE_BUCKET:-iglu-terraform-state}"
TABLE="${LOCK_TABLE:-iglu-terraform-locks}"
REGION="${AWS_REGION:-us-east-1}"

echo "This will delete:"
echo "  S3 bucket: ${BUCKET}"
echo "  DynamoDB table: ${TABLE}"
printf "Type DELETE to continue: "
read -r answer

if [ "${answer}" != "DELETE" ]; then
  echo "Cancelled."
  exit 1
fi

if aws dynamodb describe-table --table-name "${TABLE}" --region "${REGION}" >/dev/null 2>&1; then
  aws dynamodb delete-table --table-name "${TABLE}" --region "${REGION}" >/dev/null
  aws dynamodb wait table-not-exists --table-name "${TABLE}" --region "${REGION}"
else
  echo "DynamoDB table not found: ${TABLE}"
fi

if aws s3api head-bucket --bucket "${BUCKET}" 2>/dev/null; then
  aws s3 rm "s3://${BUCKET}" --recursive

  aws s3api list-object-versions \
    --bucket "${BUCKET}" \
    --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}' \
    --output json > /tmp/versions.json

  aws s3api list-object-versions \
    --bucket "${BUCKET}" \
    --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}' \
    --output json > /tmp/delete-markers.json

  grep -q '"Key"' /tmp/versions.json &&
    aws s3api delete-objects --bucket "${BUCKET}" --delete file:///tmp/versions.json >/dev/null

  grep -q '"Key"' /tmp/delete-markers.json &&
    aws s3api delete-objects --bucket "${BUCKET}" --delete file:///tmp/delete-markers.json >/dev/null

  rm -f /tmp/versions.json /tmp/delete-markers.json
  aws s3api delete-bucket --bucket "${BUCKET}" --region "${REGION}"
else
  echo "S3 bucket not found: ${BUCKET}"
fi

echo "Done."
