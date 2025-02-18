variable "name" {
  description = "Name of the cache cluster"
  type        = string
}

variable "environment" {
  description = "Environment (dev/staging/prod)"
  type        = string
}

variable "node_type" {
  description = "The compute and memory capacity of the nodes"
  type        = string
  default     = "cache.t3.micro"
}

variable "num_cache_nodes" {
  description = "Number of cache nodes"
  type        = number
  default     = 1
}

variable "security_group_ids" {
  description = "Security group IDs for the cache cluster"
  type        = list(string)
}

variable "subnet_group_name" {
  description = "Name of the subnet group to be used for the cache cluster"
  type        = string
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
