#!/usr/bin/env bash
set -euo pipefail

deployment_environment="${1:-}"
aws_region="${AWS_DEFAULT_REGION:-us-east-1}"
repository_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

case "$deployment_environment" in
  dev)
    terraform_directory="$repository_directory"
    ;;
  prod)
    terraform_directory="$repository_directory/terraform/environments/prod"
    ;;
  *)
    echo "Usage: $0 <dev|prod>" >&2
    exit 1
    ;;
esac

api_secret_name="${DATADOG_API_SECRET_NAME:-iglu/${deployment_environment}/datadog/api-key}"
app_secret_name="${DATADOG_APP_SECRET_NAME:-iglu/${deployment_environment}/datadog/app-key}"

if [[ -n "${DATADOG_API_SECRET_NAME:-}" ]]; then
  export TF_VAR_datadog_api_key_secret_name="$DATADOG_API_SECRET_NAME"
fi

if [[ -n "${DATADOG_APP_SECRET_NAME:-}" ]]; then
  export TF_VAR_datadog_app_key_secret_name="$DATADOG_APP_SECRET_NAME"
fi

terraform -chdir="$terraform_directory" init -input=false >/dev/null

restore_and_import() {
  local secret_name="$1"
  local resource_address="$2"
  local deleted_date
  local secret_arn

  if ! deleted_date="$(aws secretsmanager describe-secret \
    --region "$aws_region" \
    --secret-id "$secret_name" \
    --query 'DeletedDate' \
    --output text 2>/dev/null)"; then
    echo "Secret $secret_name was not found; Terraform can create it normally."
    return
  fi

  if [[ "$deleted_date" != "None" && "$deleted_date" != "null" && -n "$deleted_date" ]]; then
    echo "Cancelling scheduled deletion for $secret_name..."
    secret_arn="$(aws secretsmanager restore-secret \
      --region "$aws_region" \
      --secret-id "$secret_name" \
      --query 'ARN' \
      --output text)"
  else
    secret_arn="$(aws secretsmanager describe-secret \
      --region "$aws_region" \
      --secret-id "$secret_name" \
      --query 'ARN' \
      --output text)"
  fi

  if terraform -chdir="$terraform_directory" state show "$resource_address" >/dev/null 2>&1; then
    echo "$secret_name is already managed in Terraform state."
    return
  fi

  echo "Importing $secret_name into Terraform state..."
  terraform -chdir="$terraform_directory" import "$resource_address" "$secret_arn"
}

restore_and_import \
  "$api_secret_name" \
  'module.ecs_fargate.aws_secretsmanager_secret.datadog_api_key[0]'

restore_and_import \
  "$app_secret_name" \
  'module.ecs_fargate.aws_secretsmanager_secret.datadog_app_key[0]'

echo "Datadog secret recovery is complete for ${deployment_environment}. Run terraform plan again."
