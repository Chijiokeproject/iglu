#!/usr/bin/env bash
set -euo pipefail

deployment_environment="${1:-}"
aws_region="${AWS_DEFAULT_REGION:-us-east-1}"

if [[ "$deployment_environment" != "dev" && "$deployment_environment" != "prod" ]]; then
  echo "Usage: $0 <dev|prod>" >&2
  exit 1
fi

api_secret_name="${DATADOG_API_SECRET_NAME:-iglu/${deployment_environment}/datadog/api-key}"
app_secret_name="${DATADOG_APP_SECRET_NAME:-iglu/${deployment_environment}/datadog/app-key}"

for secret_name in "$api_secret_name" "$app_secret_name"; do
  if ! aws secretsmanager describe-secret \
    --region "$aws_region" \
    --secret-id "$secret_name" >/dev/null; then
    echo "Secret $secret_name does not exist. Apply Terraform once with enable_datadog=false first." >&2
    exit 1
  fi

  deleted_date="$(aws secretsmanager describe-secret \
    --region "$aws_region" \
    --secret-id "$secret_name" \
    --query 'DeletedDate' \
    --output text)"

  if [[ "$deleted_date" != "None" && "$deleted_date" != "null" && -n "$deleted_date" ]]; then
    echo "Secret $secret_name is scheduled for deletion. Run ./recover-datadog-secrets.sh $deployment_environment first." >&2
    exit 1
  fi
done

api_key_file="$(mktemp)"
app_key_file="$(mktemp)"
chmod 600 "$api_key_file" "$app_key_file"

cleanup() {
  rm -f "$api_key_file" "$app_key_file"
}
trap cleanup EXIT

read -r -s -p "Datadog API key: " datadog_api_key
echo
read -r -s -p "Datadog application key: " datadog_app_key
echo

if [[ -z "$datadog_api_key" || -z "$datadog_app_key" ]]; then
  echo "Both Datadog keys are required." >&2
  exit 1
fi

printf '%s' "$datadog_api_key" >"$api_key_file"
printf '%s' "$datadog_app_key" >"$app_key_file"
unset datadog_api_key datadog_app_key

aws secretsmanager put-secret-value \
  --region "$aws_region" \
  --secret-id "$api_secret_name" \
  --secret-string "file://${api_key_file}" >/dev/null

aws secretsmanager put-secret-value \
  --region "$aws_region" \
  --secret-id "$app_secret_name" \
  --secret-string "file://${app_key_file}" >/dev/null

echo "Updated Datadog secrets for ${deployment_environment} in ${aws_region}."
