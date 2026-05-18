terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region = "ap-south-1" 
}

# Generates a fresh unique string on every unique execution structure
resource "random_pet" "suffix" {
  length = 1
}

# ==============================================================================
# 1. NETWORK LOOKUPS (Targeting your specific infrastructure)
# ==============================================================================

# Finds your existing VPC based on its template tag name
data "aws_vpc" "existing_vpc" {
  filter {
    name   = "tag:Name"
    values = ["CodePipelineStarterTemplate-DeployToECSFargate-1jJEBszQ/SimpleDockerEcsCluster-0262a13086f3/Vpc"]
  }
}

# Dynamically gathers all public subnets created by that template across your AZs
data "aws_subnets" "public_subnets" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.existing_vpc.id]
  }

  filter {
    name   = "tag:Name"
    values = ["CodePipelineStarterTemplate-DeployToECSFargate-1jJEBszQ/SimpleDockerEcsCluster-0262a13086f3/Vpc/PublicSubnet*"] 
  }
}

# ==============================================================================
# 2. IAM ROLES & LOGGING (Now fully dynamic to prevent duplicate errors)
# ==============================================================================

resource "aws_cloudwatch_log_group" "ecs_log_group" {
  name              = "/ecs/arunconty-tf-${random_pet.suffix.id}"
  retention_in_days = 7
}

resource "aws_iam_role" "ecs_execution_role" {
  name = "ecsExecutionRole-tf-${random_pet.suffix.id}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_execution_policy" {
  role       = aws_iam_role.ecs_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ==============================================================================
# 3. TASK DEFINITION (Port 3000 Matrix)
# ==============================================================================

resource "aws_ecs_task_definition" "arunconty_task" {
  family                   = "arunconty-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn

  container_definitions = jsonencode([
    {
      name      = "arunconty"
      image     = "arun586/service_1:latest"
      cpu       = 0
      essential = true
      
      portMappings = [
        {
          containerPort = 3000
          hostPort      = 3000
          protocol      = "tcp"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs_log_group.name
          "awslogs-region"        = "ap-south-1"
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])
}

# ==============================================================================
# 4. LOAD BALANCER & NETWORKING ARTIFACTS (Isolated Unique Naming)
# ==============================================================================

resource "aws_security_group" "alb_sg" {
  name        = "arunconty-alb-sg-${random_pet.suffix.id}"
  description = "Allow public HTTP traffic"
  vpc_id      = data.aws_vpc.existing_vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_lb" "main_alb" {
  name               = "arunconty-alb-${random_pet.suffix.id}"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = data.aws_subnets.public_subnets.ids
}

resource "aws_lb_target_group" "ecs_tg" {
  name        = "tg-3000-${random_pet.suffix.id}" # Dynamically unique name
  port        = 3000
  protocol    = "HTTP"
  vpc_id      = data.aws_vpc.existing_vpc.id
  target_type = "ip"

  health_check {
    path                = "/"
    port                = "3000"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

resource "aws_lb_listener" "http_listener" {
  load_balancer_arn = aws_lb.main_alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ecs_tg.arn
  }
}

# ==============================================================================
# 5. ECS CLUSTER & SERVICE MANAGEMENT
# ==============================================================================

resource "aws_ecs_cluster" "main_cluster" {
  name = "new_cluster"
}

resource "aws_ecs_service" "main_service" {
  name            = "new_secvice"
  cluster         = aws_ecs_cluster.main_cluster.id
  task_definition = aws_ecs_task_definition.arunconty_task.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = data.aws_subnets.public_subnets.ids
    security_groups  = [aws_security_group.alb_sg.id] 
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.ecs_tg.arn
    container_name   = "arunconty"
    container_port   = 3000
  }

  depends_on = [aws_lb_listener.http_listener]
}

# ==============================================================================
# OUTPUTS
# ==============================================================================

output "alb_dns_name" {
  description = "Open this link in your browser to check your running web application!"
  value       = aws_lb.main_alb.dns_name
}
