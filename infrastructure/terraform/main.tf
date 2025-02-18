terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

module "cloudwatch" {
  source             = "./modules/cloudwatch"
  project_name       = var.project_name
  environment        = var.environment
  node_group_names   = module.eks.node_group_names
  eks_cluster_id     = module.eks.cluster_id
  log_retention_days = 30
  cpu_threshold      = 80
  memory_threshold   = 80
  alarm_actions      = []
}

module "vpc" {
  source = "./modules/vpc"
  environment = var.environment
  project_name = var.project_name
}

module "eks" {
  source = "./modules/eks"
  environment = var.environment
  project_name = var.project_name
  vpc_id = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids
}

module "api_gateway" {
  source = "./modules/api-gateway"
  environment = var.environment
  project_name = var.project_name
  vpc_id = module.vpc.vpc_id
}

module "cache" {
  source = "./modules/cache"
  environment = var.environment
  project_name = var.project_name
  vpc_id = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids
}

module "message_queue" {
  source = "./modules/message-queue"
  environment = var.environment
  project_name = var.project_name
  vpc_id = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids
}
