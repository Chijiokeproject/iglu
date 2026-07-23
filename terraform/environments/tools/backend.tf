terraform {
  backend "s3" {
    bucket         = "iglu-terraform-state"
    key            = "tools/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "iglu-terraform-locks"
    encrypt        = true
  }
}
