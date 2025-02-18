output "id" {
  description = "ID of the ElastiCache cluster"
  value       = aws_elasticache_cluster.trading_cache.id
}

output "arn" {
  description = "ARN of the ElastiCache cluster"
  value       = aws_elasticache_cluster.trading_cache.arn
}

output "cache_nodes" {
  description = "List of node objects including id, address, port and availability_zone"
  value       = aws_elasticache_cluster.trading_cache.cache_nodes
}

output "port" {
  description = "Port number of the cache cluster"
  value       = aws_elasticache_cluster.trading_cache.port
}

output "engine_version" {
  description = "Redis engine version"
  value       = aws_elasticache_cluster.trading_cache.engine_version
}
