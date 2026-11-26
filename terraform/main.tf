terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile
}

data "aws_caller_identity" "current" {}

# Default VPC and default subnets for quick PoC networking
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
  filter {
    name   = "default-for-az"
    values = ["true"]
  }
}

# CloudWatch Logs for ECS tasks
resource "aws_cloudwatch_log_group" "web" {
  name              = "/ecs/digitalstudytools-web"
  retention_in_days = 7
}

# ECR repository
resource "aws_ecr_repository" "web" {
  name                 = "digitalstudytools/web"
  image_tag_mutability = "MUTABLE"
  force_delete         = true
}

# ECS cluster
resource "aws_ecs_cluster" "cluster" {
  name = "digitalstudytools-cluster"
}

# Security group: allow HTTP on port 8000
resource "aws_security_group" "web" {
  name        = "digitalstudytools-web-sg"
  description = "Allow HTTP 8000"
  vpc_id      = data.aws_vpc.default.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP 8000"
    from_port   = 8000
    to_port     = 8000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# IAM role for ECS task execution (pull from ECR, send logs)
resource "aws_iam_role" "ecs_task_execution" {
  name = "digitalstudytools-ecs-task-exec"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = { Service = "ecs-tasks.amazonaws.com" },
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_exec_attach" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Optional task role for the app (empty baseline)
resource "aws_iam_role" "ecs_task" {
  name = "digitalstudytools-ecs-task"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = { Service = "ecs-tasks.amazonaws.com" },
      Action = "sts:AssumeRole"
    }]
  })
}

# ECS task definition (Fargate, port 8000, :latest)
resource "aws_ecs_task_definition" "web" {
  family                   = "digitalstudytools-web"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name      = "web"
      image     = "${aws_ecr_repository.web.repository_url}:latest"
      essential = true
      portMappings = [
        { containerPort = 8000, protocol = "tcp" }
      ]
      environment = [
        { name = "PORT", value = "8000" }
      ]
      logConfiguration = {
        logDriver = "awslogs",
        options = {
          awslogs-group         = aws_cloudwatch_log_group.web.name,
          awslogs-region        = var.aws_region,
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])
}

# ECS service - staging (public IP, no load balancer)
resource "aws_ecs_service" "staging" {
  name            = "digitalstudytools-web-staging"
  cluster         = aws_ecs_cluster.cluster.id
  task_definition = aws_ecs_task_definition.web.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = data.aws_subnets.default.ids
    security_groups  = [aws_security_group.web.id]
    assign_public_ip = true
  }

  lifecycle {
    ignore_changes = [task_definition]
  }
}

# ECS service - production (public IP, no load balancer)
resource "aws_ecs_service" "prod" {
  name            = "digitalstudytools-web-prod"
  cluster         = aws_ecs_cluster.cluster.id
  task_definition = aws_ecs_task_definition.web.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = data.aws_subnets.default.ids
    security_groups  = [aws_security_group.web.id]
    assign_public_ip = true
  }

  lifecycle {
    ignore_changes = [task_definition]
  }
}

# GitHub OIDC provider (use only if not already present)
resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
  client_id_list   = ["sts.amazonaws.com"]
  thumbprint_list  = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e5e3b725f6eddfc6fd1e1e2d5f3f3"
  ]
}

# IAM role for GitHub Actions (OIDC)
resource "aws_iam_role" "github_actions" {
  name = "digitalstudytools-github-actions"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = {
        Federated = aws_iam_openid_connect_provider.github.arn
      },
      Action = "sts:AssumeRoleWithWebIdentity",
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        },
        StringLike = {
          "token.actions.githubusercontent.com:sub" = "repo:${var.github_owner}/${var.github_repo}:*"
        }
      }
    }]
  })
}

# Broad policies for PoC (would have to be limited for production)
resource "aws_iam_role_policy_attachment" "gha_ecr_poweruser" {
  role       = aws_iam_role.github_actions.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser"
}

resource "aws_iam_role_policy_attachment" "gha_ecs_full" {
  role       = aws_iam_role.github_actions.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonECS_FullAccess"
}

output "aws_role_arn_for_github" {
  value = aws_iam_role.github_actions.arn
}

output "ecr_repository_url" {
  value = aws_ecr_repository.web.repository_url
}

output "ecs_cluster_name" {
  value = aws_ecs_cluster.cluster.name
}

output "ecs_services" {
  value = {
    staging = aws_ecs_service.staging.name
    prod    = aws_ecs_service.prod.name
  }
}