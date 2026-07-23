pipeline {
  agent any

  options {
    disableConcurrentBuilds()
    timestamps()
  }

  parameters {
    choice(
      name: 'ENVIRONMENT',
      choices: ['dev', 'prod'],
      description: 'Application environment to deploy; the shared tools stage runs before either environment'
    )

    choice(
      name: 'ACTION',
      choices: ['plan', 'apply', 'destroy'],
      description: 'Terraform action to run'
    )

    booleanParam(
      name: 'ENABLE_DATADOG',
      defaultValue: false,
      description: 'Enable Datadog Agent sidecar for ECS Fargate'
    )

    string(
      name: 'DATADOG_API_KEY_SECRET_ARN',
      defaultValue: '',
      description: 'Secrets Manager ARN for the Datadog API key'
    )

    string(
      name: 'DATADOG_API_KEY_SECRET_NAME',
      defaultValue: '',
      description: 'Optional API-key secret name override; blank uses an environment-specific managed secret'
    )

    string(
      name: 'DATADOG_APP_KEY_SECRET_NAME',
      defaultValue: '',
      description: 'Optional application-key secret name override; blank uses an environment-specific managed secret'
    )

    string(
      name: 'DATADOG_SITE',
      defaultValue: 'datadoghq.com',
      description: 'Datadog site, for example datadoghq.com or datadoghq.eu'
    )

    string(
      name: 'MONITORING_AMI_ID',
      defaultValue: '',
      description: 'Optional RHEL AMI ID override; blank uses the Terraform environment default'
    )

    string(
      name: 'ALLOWED_ADMIN_CIDR',
      defaultValue: '',
      description: 'Optional restricted public IP CIDR override; blank uses the Terraform environment default'
    )

    string(
      name: 'PRODUCTION_CONFIRMATION',
      defaultValue: '',
      description: 'Required for prod apply/destroy: enter DEPLOY_PROD'
    )
  }

  environment {
    AWS_DEFAULT_REGION = 'us-east-1'
    TF_IN_AUTOMATION = 'true'
  }

  stages {
    stage('Checkout') {
      steps {
        checkout scm
      }
    }

    stage('Build Toolchain Audit') {
      steps {
        sh 'docker version'
        sh 'docker buildx version'
        sh 'mvn --version'
        sh 'aws --version'
        sh 'terraform version'
        sh 'checkov --version'
      }
    }

    stage('Deployment Guard') {
      steps {
        script {
          if (params.ALLOWED_ADMIN_CIDR?.trim() == '0.0.0.0/0') {
            error 'ALLOWED_ADMIN_CIDR must be restricted and cannot be 0.0.0.0/0.'
          }

          if (
            params.ENVIRONMENT == 'prod' &&
            params.ACTION != 'plan' &&
            params.PRODUCTION_CONFIRMATION?.trim() != 'DEPLOY_PROD'
          ) {
            error 'Production apply/destroy requires PRODUCTION_CONFIRMATION=DEPLOY_PROD.'
          }
        }
      }
    }

    stage('Terraform Init') {
      steps {
        dir('terraform/environments/tools') {
          sh 'terraform init'
        }

        dir(
          params.ENVIRONMENT == 'dev'
            ? '.'
            : "terraform/environments/${params.ENVIRONMENT}"
        ) {
          sh 'terraform init'
        }
      }
    }

    stage('Terraform Validate') {
      steps {
        dir('terraform/environments/tools') {
          sh 'terraform fmt -check -recursive'
          sh 'terraform validate'
        }

        dir(
          params.ENVIRONMENT == 'dev'
            ? '.'
            : "terraform/environments/${params.ENVIRONMENT}"
        ) {
          sh 'terraform fmt -check -recursive'
          sh 'terraform validate'
        }
      }
    }

    stage('Checkov IaC Scan') {
      steps {
        sh 'checkov --directory . --framework terraform --compact --quiet --skip-path .terraform --baseline .checkov.baseline'
      }
    }

    stage('Plan Shared Tools') {
      when {
        expression {
          params.ACTION != 'destroy'
        }
      }

      steps {
        dir('terraform/environments/tools') {
          script {
            def toolsEnvironment = []

            if (params.MONITORING_AMI_ID?.trim()) {
              toolsEnvironment.add("TF_VAR_monitoring_ami_id=${params.MONITORING_AMI_ID.trim()}")
            }

            if (params.ALLOWED_ADMIN_CIDR?.trim()) {
              toolsEnvironment.add("TF_VAR_allowed_admin_cidr=${params.ALLOWED_ADMIN_CIDR.trim()}")
            }

            withEnv(toolsEnvironment) {
              sh 'terraform plan -out=tfplan'
            }
          }
        }
      }
    }

    stage('Plan Application Environment') {
      steps {
        dir(
          params.ENVIRONMENT == 'dev'
            ? '.'
            : "terraform/environments/${params.ENVIRONMENT}"
        ) {
          script {
            def terraformEnvironment = [
              "TF_VAR_enable_datadog=${params.ENABLE_DATADOG}",
              "TF_VAR_datadog_site=${params.DATADOG_SITE.trim()}"
            ]

            if (params.DATADOG_API_KEY_SECRET_NAME?.trim()) {
              terraformEnvironment.add("TF_VAR_datadog_api_key_secret_name=${params.DATADOG_API_KEY_SECRET_NAME.trim()}")
            }

            if (params.DATADOG_APP_KEY_SECRET_NAME?.trim()) {
              terraformEnvironment.add("TF_VAR_datadog_app_key_secret_name=${params.DATADOG_APP_KEY_SECRET_NAME.trim()}")
            }

            if (params.MONITORING_AMI_ID?.trim()) {
              terraformEnvironment.add("TF_VAR_monitoring_ami_id=${params.MONITORING_AMI_ID.trim()}")
            }

            if (params.ALLOWED_ADMIN_CIDR?.trim()) {
              terraformEnvironment.add("TF_VAR_allowed_admin_cidr=${params.ALLOWED_ADMIN_CIDR.trim()}")
            }

            if (params.DATADOG_API_KEY_SECRET_ARN?.trim()) {
              terraformEnvironment.add("TF_VAR_datadog_api_key_secret_arn=${params.DATADOG_API_KEY_SECRET_ARN.trim()}")
            }

            withEnv(terraformEnvironment) {
              if (params.ACTION == 'destroy') {
                sh 'terraform plan -destroy -out=tfplan'
              } else {
                sh 'terraform plan -out=tfplan'
              }
            }
          }
        }
      }
    }

    stage('Manual Approval') {
      when {
        anyOf {
          expression {
            params.ACTION == 'apply'
          }

          expression {
            params.ACTION == 'destroy'
          }
        }
      }

      steps {
        script {
          def approvalMessage = params.ACTION == 'apply'
            ? "Approve shared tools followed by the ${params.ENVIRONMENT} environment?"
            : "Approve destroy for ${params.ENVIRONMENT}? Shared tools will be retained."

          timeout(time: 30, unit: 'MINUTES') {
            input(
              message: approvalMessage,
              ok: 'Approve'
            )
          }
        }
      }
    }

    stage('Apply Shared Tools') {
      when {
        expression {
          params.ACTION == 'apply'
        }
      }

      steps {
        dir('terraform/environments/tools') {
          sh 'terraform apply -auto-approve tfplan'
        }
      }
    }

    stage('Apply Application Environment') {
      when {
        expression {
          params.ACTION == 'apply'
        }
      }

      steps {
        dir(
          params.ENVIRONMENT == 'dev'
            ? '.'
            : "terraform/environments/${params.ENVIRONMENT}"
        ) {
          sh 'terraform apply -auto-approve tfplan'
        }
      }
    }

    stage('Destroy Application Environment') {
      when {
        expression {
          params.ACTION == 'destroy'
        }
      }

      steps {
        dir(
          params.ENVIRONMENT == 'dev'
            ? '.'
            : "terraform/environments/${params.ENVIRONMENT}"
        ) {
          sh 'terraform apply -auto-approve tfplan'
        }
      }
    }

    stage('Verify ECS Deployment') {
      when {
        expression {
          params.ACTION == 'apply'
        }
      }

      steps {
        dir(
          params.ENVIRONMENT == 'dev'
            ? '.'
            : "terraform/environments/${params.ENVIRONMENT}"
        ) {
          script {
            def outputPrefix = params.ENVIRONMENT
            withEnv([
              "ECS_CLUSTER_OUTPUT=${outputPrefix}_cluster_name",
              "ECS_SERVICE_OUTPUT=${outputPrefix}_service_name",
              "VERIFY_DATADOG=${params.ENABLE_DATADOG}"
            ]) {
              sh '''
                set -euo pipefail
                cluster_name=$(terraform output -raw "$ECS_CLUSTER_OUTPUT")
                service_name=$(terraform output -raw "$ECS_SERVICE_OUTPUT")

                test "$(aws ecs describe-clusters \
                  --clusters "$cluster_name" \
                  --query 'clusters[0].status' \
                  --output text)" = "ACTIVE"

                aws ecs wait services-stable \
                  --cluster "$cluster_name" \
                  --services "$service_name"

                running_count=$(aws ecs describe-services \
                  --cluster "$cluster_name" \
                  --services "$service_name" \
                  --query 'services[0].runningCount' \
                  --output text)
                test "$running_count" -ge 1

                if [ "$VERIFY_DATADOG" = "true" ]; then
                  task_definition=$(aws ecs describe-services \
                    --cluster "$cluster_name" \
                    --services "$service_name" \
                    --query 'services[0].taskDefinition' \
                    --output text)
                  aws ecs describe-task-definition \
                    --task-definition "$task_definition" \
                    --query 'taskDefinition.containerDefinitions[].name' \
                    --output text | grep -qw datadog-agent
                fi
              '''
            }
          }
        }
      }
    }
  }

  post {
    success {
      script {
        if (params.ACTION == 'apply') {
          echo "Shared tools and ${params.ENVIRONMENT} apply completed successfully."
        } else {
          echo "Terraform ${params.ACTION} completed successfully for ${params.ENVIRONMENT}; shared tools were retained."
        }
      }
    }

    failure {
      echo "Terraform ${params.ACTION} failed for ${params.ENVIRONMENT}."
    }
  }
}
