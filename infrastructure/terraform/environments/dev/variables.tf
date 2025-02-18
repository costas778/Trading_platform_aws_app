variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
}

variable "database_username" {
  description = "Database master username"
  type        = string
}

variable "database_password" {
  description = "Database master password"
  type        = string
  sensitive   = true
}

variable "eks_node_max_size" {
  description = "Maximum number of nodes in EKS node group"
  type        = number
  default     = 4
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "availability_zones" {
  description = "List of availability zones"
  type        = list(string)
}

variable "bucket_name" {
  description = "Name of the S3 bucket"
  type        = string
}

variable "node_desired_size" {
  description = "Desired number of nodes in the EKS node group"
  type        = number
}

variable "node_max_size" {
  description = "Maximum number of nodes in the EKS node group"
  type        = number
}

variable "db_instance_class" {
  description = "The instance type of the RDS instance"
  type        = string
}

variable "db_storage" {
  description = "Allocated storage for the RDS instance in GB"
  type        = number
}

variable "database_name" {
  description = "Name of the database"
  type        = string
}

variable "node_min_size" {
  description = "Minimum number of nodes in the EKS node group"
  type        = number
}

variable "kubernetes_version" {
  description = "Version of Kubernetes to use for EKS cluster"
  type        = string
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "node_instance_type" {
  description = "Instance type for the EKS nodes"
  type        = string
}

