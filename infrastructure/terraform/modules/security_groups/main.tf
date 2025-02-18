# EKS Cluster Security Group
resource "aws_security_group" "eks_cluster" {
  name        = "${var.project_name}-${var.environment}-eks-cluster-sg"
  description = "Security group for EKS cluster"
  vpc_id      = var.vpc_id

  ingress {
    description = "Allow all internal traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project_name}-${var.environment}-eks-cluster-sg"
    Environment = var.environment
  }
}

# RDS Security Group
resource "aws_security_group" "rds" {
  name        = "${var.project_name}-${var.environment}-rds-sg"
  description = "Security group for RDS instances"
  vpc_id      = var.vpc_id

  ingress {
    description     = "Allow PostgreSQL access from EKS"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.eks_cluster.id]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project_name}-${var.environment}-rds-sg"
    Environment = var.environment
  }
}

# Message Queue Security Group
resource "aws_security_group" "mq" {
  name        = "${var.project_name}-${var.environment}-mq-sg"
  description = "Security group for Message Queue"
  vpc_id      = var.vpc_id

  tags = {
    Name        = "${var.project_name}-${var.environment}-mq-sg"
    Environment = var.environment
  }
}

# Cache Security Group
resource "aws_security_group" "cache" {
  name        = "${var.project_name}-${var.environment}-cache-sg"
  description = "Security group for Redis Cache"
  vpc_id      = var.vpc_id

  tags = {
    Name        = "${var.project_name}-${var.environment}-cache-sg"
    Environment = var.environment
  }
}

# MQ Security Group Rules
resource "aws_security_group_rule" "mq_ingress_vpc" {
  type              = "ingress"
  from_port         = 5671  # AMQP with TLS
  to_port           = 5671
  protocol          = "tcp"
  cidr_blocks       = [var.vpc_cidr]
  security_group_id = aws_security_group.mq.id
  description       = "Allow AMQP access from VPC"
}

resource "aws_security_group_rule" "mq_ingress_eks" {
  type                     = "ingress"
  from_port                = 5671
  to_port                  = 5671
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.eks_cluster.id
  security_group_id        = aws_security_group.mq.id
  description              = "Allow AMQP access from EKS"
}

resource "aws_security_group_rule" "mq_egress" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.mq.id
  description       = "Allow all outbound traffic"
}

# Cache Security Group Rules
resource "aws_security_group_rule" "cache_ingress_vpc" {
  type              = "ingress"
  from_port         = 6379  # Redis
  to_port           = 6379
  protocol          = "tcp"
  cidr_blocks       = [var.vpc_cidr]
  security_group_id = aws_security_group.cache.id
  description       = "Allow Redis access from VPC"
}

resource "aws_security_group_rule" "cache_ingress_eks" {
  type                     = "ingress"
  from_port                = 6379
  to_port                  = 6379
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.eks_cluster.id
  security_group_id        = aws_security_group.cache.id
  description              = "Allow Redis access from EKS"
}

resource "aws_security_group_rule" "cache_egress" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.cache.id
  description       = "Allow all outbound traffic"
}
