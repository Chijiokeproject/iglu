#!/usr/bin/env bash

set -euo pipefail

AWS_REGION="${AWS_REGION:-us-east-1}"
SECRET_NAME="${DATADOG_SECRET_NAME:-iglu/datadog/api-key}"

if ! command -v aws >/dev/null 2>&1; then
  echo "AWS CLI is required." >&2
  exit 1
fi

read -r -s -p "Enter your Datadog API key: " DATADOG_API_KEY
echo

if [[ -z "${DATADOG_API_KEY}" ]]; then
  echo "The Datadog API key cannot be empty." >&2
  exit 1
fi

if aws secretsmanager describe-secret \
  --secret-id "${SECRET_NAME}" \
  --region "${AWS_REGION}" >/dev/null 2>&1; then
  printf '%s' "${DATADOG_API_KEY}" | aws secretsmanager put-secret-value \
    --secret-id "${SECRET_NAME}" \
    --secret-string file:///dev/stdin \
    --region "${AWS_REGION}" \
    --query ARN \
    --output text
  echo "Updated Datadog API-key secret: ${SECRET_NAME}"
else
  printf '%s' "${DATADOG_API_KEY}" | aws secretsmanager create-secret \
    --name "${SECRET_NAME}" \
    --description "Datadog API key for IGLU ECS Fargate monitoring" \
    --secret-string file:///dev/stdin \
    --region "${AWS_REGION}" \
    --query ARN \
    --output text
  echo "Created Datadog API-key secret: ${SECRET_NAME}"
fi

unset DATADOG_API_KEY
