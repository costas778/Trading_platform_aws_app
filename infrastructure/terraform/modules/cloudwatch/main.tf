resource "aws_cloudwatch_log_group" "eks" {
  name              = "/aws/eks/${var.project_name}-${var.environment}/cluster"
  retention_in_days = var.log_retention_days

  lifecycle {
    create_before_destroy = true
    ignore_changes = [
      tags,
      name
    ]
  }

  tags = {
    Name        = "${var.project_name}-${var.environment}-eks-logs"
    Environment = var.environment
  }
}

resource "aws_cloudwatch_metric_alarm" "node_cpu" {
  count               = length(var.node_group_names)
  alarm_name          = "${var.project_name}-${var.environment}-node-cpu-${count.index + 1}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period             = "300"
  statistic          = "Average"
  threshold          = var.cpu_threshold
  alarm_description  = "This metric monitors EC2 CPU utilization for EKS nodes"

  dimensions = {
    AutoScalingGroupName = var.node_group_names[count.index]
  }

  alarm_actions = var.alarm_actions
}

resource "aws_cloudwatch_metric_alarm" "node_memory" {
  count               = length(var.node_group_names)
  alarm_name          = "${var.project_name}-${var.environment}-node-memory-${count.index + 1}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "MemoryUtilization"
  namespace           = "AWS/EC2"
  period             = "300"
  statistic          = "Average"
  threshold          = var.memory_threshold
  alarm_description  = "This metric monitors EC2 memory utilization for EKS nodes"

  dimensions = {
    AutoScalingGroupName = var.node_group_names[count.index]
  }

  alarm_actions = var.alarm_actions
}
