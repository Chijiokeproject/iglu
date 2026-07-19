```groovy
pipeline {
  agent any

  parameters {
    choice(
      name: 'ENVIRONMENT',
      choices: ['dev', 'prod'],
      description: 'Terraform environment to deploy'
    )

    choice(
      name: 'ACTION',
      choices: ['plan', 'apply', 'destroy'],
      description: 'Terraform action to run'
    )

    string(
      name: 'MONITORING_AMI_ID',
      defaultValue: '',
      description: 'Optional RHEL AMI ID. Leave empty to automatically discover the latest RHEL 9 AMI.'
    )

    string(
      name: 'ALLOWED_ADMIN_CIDR',
      defaultValue: '',
      description: 'Restricted public IP CIDR allowed to access Grafana and Prometheus, for example 203.0.113.10/32'
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

    stage('Terraform Init') {
      steps {
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

    stage('Terraform Plan') {
      steps {
        dir(
          params.ENVIRONMENT == 'dev'
            ? '.'
            : "terraform/environments/${params.ENVIRONMENT}"
        ) {
          script {
            def monitoringAmiId = params.MONITORING_AMI_ID?.trim()

            if (!monitoringAmiId) {
              echo 'MONITORING_AMI_ID was not supplied.'
              echo 'Searching AWS for the latest RHEL 9 AMI...'

              monitoringAmiId = sh(
                script: '''
                  aws ec2 describe-images \
                    --region "$AWS_DEFAULT_REGION" \
                    --owners 309956199498 \
                    --filters \
                      "Name=state,Values=available" \
                      "Name=architecture,Values=x86_64" \
                      "Name=root-device-type,Values=ebs" \
                      "Name=virtualization-type,Values=hvm" \
                      "Name=name,Values=RHEL-9*_HVM-*-x86_64-*-Hourly2-GP*" \
                    --query "sort_by(Images, &CreationDate)[-1].ImageId" \
                    --output text
                ''',
                returnStdout: true
              ).trim()

              if (!monitoringAmiId || monitoringAmiId == 'None') {
                error '''
                Jenkins could not automatically find a RHEL 9 AMI.

                Supply a valid AMI ID using the MONITORING_AMI_ID parameter,
                for example: ami-0123456789abcdef0
                '''
              }

              echo "Automatically selected monitoring AMI: ${monitoringAmiId}"
            } else {
              echo "Using monitoring AMI supplied through Jenkins: ${monitoringAmiId}"
            }

            def allowedAdminCidr = params.ALLOWED_ADMIN_CIDR?.trim()

            if (!allowedAdminCidr) {
              error '''
              ALLOWED_ADMIN_CIDR is required.

              Enter your public IP address in CIDR format,
              for example: 203.0.113.10/32
              '''
            }

            if (allowedAdminCidr == '0.0.0.0/0') {
              error '''
              ALLOWED_ADMIN_CIDR must be restricted.

              Do not use 0.0.0.0/0.
              Enter your public IP address followed by /32.
              '''
            }

            def terraformEnvironment = [
              "TF_VAR_monitoring_ami_id=${monitoringAmiId}",
              "TF_VAR_allowed_admin_cidr=${allowedAdminCidr}"
            ]

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
          expression {
            params.ACTION == 'apply'
          }

          expression {
            params.ACTION == 'destroy'
          }
        }
      }

      steps {
        input(
          message: "Run terraform ${params.ACTION} for ${params.ENVIRONMENT}?",
          ok: 'Continue'
        )
      }
    }

    stage('Terraform Apply') {
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

    stage('Terraform Destroy') {
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
  }

  post {
    success {
      echo "Terraform ${params.ACTION} completed successfully for ${params.ENVIRONMENT}."
    }

    failure {
      echo "Terraform ${params.ACTION} failed for ${params.ENVIRONMENT}."
    }

    always {
      archiveArtifacts(
        artifacts: '**/tfplan',
        allowEmptyArchive: true
      )
    }
  }
}
```
