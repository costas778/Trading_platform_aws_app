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

module "eks" {
  source = "../../modules/eks"
  
  project_name       = var.project_name
  environment        = var.environment
  kubernetes_version = var.kubernetes_version
  subnet_ids        = [
    "subnet-083f2c6f799ce28d2",  # us-east-1a
    "subnet-00dbbfe91bc52065e",  # us-east-1b
    "subnet-0c7193c65c67aed35"   # us-east-1c
  ]
  node_desired_size = var.node_desired_size
  node_max_size     = var.node_max_size
  node_min_size     = var.node_min_size
  instance_types    = [var.node_instance_type]
}

# Add outputs to get cluster information
output "cluster_name" {
  description = "The name of the EKS cluster"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "The endpoint for the EKS cluster"
  value       = module.eks.cluster_endpoint
}

output "cluster_security_group_id" {
  description = "Security group ID for the cluster control plane"
  value       = module.eks.cluster_security_group_id
}

output "node_group_id" {
  description = "ID of the EKS node group"
  value       = module.eks.node_group_id
}
