pipeline {
  agent any

  parameters {
    choice(name: 'ENVIRONMENT', choices: ['dev', 'prod'], description: 'Terraform environment to deploy')
    choice(name: 'ACTION', choices: ['plan', 'apply', 'destroy'], description: 'Terraform action to run')
    booleanParam(name: 'ENABLE_DATADOG', defaultValue: false, description: 'Enable Datadog Agent sidecar for ECS Fargate')
    string(name: 'DATADOG_API_KEY_SECRET_ARN', defaultValue: '', description: 'Secrets Manager ARN for the Datadog API key')
    string(name: 'DATADOG_API_KEY_SECRET_NAME', defaultValue: 'iglu/datadog/api-key', description: 'Secrets Manager name used when no ARN override is supplied')
    string(name: 'DATADOG_SITE', defaultValue: 'datadoghq.com', description: 'Datadog site, for example datadoghq.com or datadoghq.eu')
    string(name: 'MONITORING_AMI_ID', defaultValue: '', description: 'Red Hat Enterprise Linux AMI ID for the monitoring server')
    string(name: 'ALLOWED_ADMIN_CIDR', defaultValue: '', description: 'Restricted public IP CIDR allowed to access Grafana and Prometheus, for example 203.0.113.10/32')
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

    stage('Terraform Init') {
      steps {
        dir(params.ENVIRONMENT == 'dev' ? '.' : "terraform/environments/${params.ENVIRONMENT}") {
          sh 'terraform init'
        }
      }
    }

    stage('Terraform Validate') {
      steps {
        dir(params.ENVIRONMENT == 'dev' ? '.' : "terraform/environments/${params.ENVIRONMENT}") {
          sh 'terraform fmt -check -recursive'
          sh 'terraform validate'
        }
      }
    }

    stage('Terraform Plan') {
      steps {
        dir(params.ENVIRONMENT == 'dev' ? '.' : "terraform/environments/${params.ENVIRONMENT}") {
          script {
            if (!params.MONITORING_AMI_ID?.trim()) {
              error 'MONITORING_AMI_ID is required.'
            }

            if (!params.ALLOWED_ADMIN_CIDR?.trim() || params.ALLOWED_ADMIN_CIDR.trim() == '0.0.0.0/0') {
              error 'ALLOWED_ADMIN_CIDR is required and must be restricted.'
            }

            def terraformEnvironment = [
              "TF_VAR_monitoring_ami_id=${params.MONITORING_AMI_ID.trim()}",
              "TF_VAR_allowed_admin_cidr=${params.ALLOWED_ADMIN_CIDR.trim()}",
              "TF_VAR_enable_datadog=${params.ENABLE_DATADOG}",
              "TF_VAR_datadog_api_key_secret_name=${params.DATADOG_API_KEY_SECRET_NAME.trim()}",
              "TF_VAR_datadog_site=${params.DATADOG_SITE.trim()}"
            ]

            if (params.ENABLE_DATADOG) {
              if (!params.DATADOG_API_KEY_SECRET_ARN?.trim() && !params.DATADOG_API_KEY_SECRET_NAME?.trim()) {
                error 'DATADOG_API_KEY_SECRET_NAME or DATADOG_API_KEY_SECRET_ARN is required when ENABLE_DATADOG is true.'
              }

              if (params.DATADOG_API_KEY_SECRET_ARN?.trim()) {
                terraformEnvironment.add("TF_VAR_datadog_api_key_secret_arn=${params.DATADOG_API_KEY_SECRET_ARN.trim()}")
              }
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

    stage('Approval') {
      when {
        anyOf {
          expression { params.ACTION == 'apply' }
          expression { params.ACTION == 'destroy' }
        }
      }
      steps {
        input message: "Run terraform ${params.ACTION} for ${params.ENVIRONMENT}?", ok: 'Continue'
      }
    }

    stage('Terraform Apply') {
      when {
        expression { params.ACTION == 'apply' }
      }
      steps {
        dir(params.ENVIRONMENT == 'dev' ? '.' : "terraform/environments/${params.ENVIRONMENT}") {
          sh 'terraform apply -auto-approve tfplan'
        }
      }
    }

    stage('Terraform Destroy') {
      when {
        expression { params.ACTION == 'destroy' }
      }
      steps {
        dir(params.ENVIRONMENT == 'dev' ? '.' : "terraform/environments/${params.ENVIRONMENT}") {
          sh 'terraform apply -auto-approve tfplan'
        }
      }
    }
  }
}
