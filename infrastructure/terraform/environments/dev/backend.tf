terraform {
  backend "s3" {
    bucket         = "bucket3637423471201"
    key            = "dev/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-state-lock"
    encrypt        = true
  }
}
