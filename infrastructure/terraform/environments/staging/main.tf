provider "aws" {
  region = var.aws_region
}

module "vpc" {
  source = "../../modules/vpc"

  project_name       = var.project_name
  environment        = "dev"
  vpc_cidr          = var.vpc_cidr
  availability_zones = var.availability_zones
}

module "networking" {
  source = "../../modules/networking"

  project_name        = var.project_name
  environment         = "dev"
  vpc_id             = module.vpc.vpc_id
  availability_zones  = var.availability_zones
  private_subnet_ids  = module.vpc.private_subnet_ids
  public_subnet_ids   = module.vpc.public_subnet_ids
  nat_gateway_ids     = module.vpc.nat_gateway_ids
  internet_gateway_id = module.vpc.internet_gateway_id
}

module "security_groups" {
  source = "../../modules/security_groups"

  project_name = var.project_name
  environment  = "dev"
  vpc_id       = module.vpc.vpc_id
}

module "iam" {
  source = "../../modules/iam"

  project_name = var.project_name
  environment  = "dev"
}

module "eks" {
  source = "../../modules/eks"

  project_name      = var.project_name
  environment       = "dev"
  cluster_role_arn  = module.iam.cluster_role_arn
  node_role_arn     = module.iam.node_role_arn
  subnet_ids        = module.vpc.private_subnet_ids
  security_group_id = module.security_groups.eks_cluster_security_group_id
}

module "rds" {
  source = "../../modules/rds"

  project_name        = var.project_name
  environment         = "dev"
  database_name       = var.database_name
  database_username   = var.database_username
  database_password   = var.database_password
  subnet_ids          = module.vpc.private_subnet_ids
  security_group_ids  = [module.security_groups.rds_security_group_id]
}

module "s3" {
  source = "../../modules/s3"

  project_name = var.project_name
  environment  = "dev"
  bucket_name  = var.bucket_name
}

module "cloudwatch" {
  source = "../../modules/cloudwatch"

  project_name      = var.project_name
  environment       = "dev"
  node_group_names  = [module.eks.cluster_name]
}
terraform init && terraform apply -auto-approve
module "vpc" {
  source = "../modules/vpc"
  region = var.region
}
module "networking" {
  source = "../modules/networking"
  region = var.region
}
