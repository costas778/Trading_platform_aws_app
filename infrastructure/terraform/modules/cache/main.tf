resource "aws_elasticache_cluster" "trading_cache" {
  cluster_id           = var.name
  engine              = "redis"
  node_type           = var.node_type
  num_cache_nodes     = var.num_cache_nodes
  parameter_group_name = "default.redis6.x"
  port                = 6379
  security_group_ids  = var.security_group_ids
  subnet_group_name   = var.subnet_group_name

  tags = var.tags
}
