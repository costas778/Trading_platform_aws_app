# Infrastructure configuration
aws_region          = "us-east-1"
environment         = "dev"
project_name        = "abc-trading"
cluster_name        = "abc-trading-dev"
vpc_cidr            = "10.0.0.0/16"
database_name       = "db_dev_637423471201"
database_username   = "dbmaster"

availability_zones  = ["us-east-1a", "us-east-1b", "us-east-1c"]

# EKS configuration
kubernetes_version  = "1.28"
node_instance_type = "t3.medium"
node_desired_size  = 2
node_min_size      = 1
node_max_size      = 4

# RDS configuration
db_instance_class  = "db.t3.medium"
db_storage        = 20
