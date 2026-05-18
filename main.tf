provider "aws" {
  region = "us-east-1"
}

# 1. Create the CloudWatch Log Group required by the container logs
resource "aws_cloudwatch_log_group" "ecs_log_group" {
  name              = "/ecs/arunconty"
  retention_in_days = 7
}

# 2. Create the IAM Execution Role for ECS Fargate
resource "aws_iam_role" "ecs_execution_role" {
  name = "ecsTaskExecutionRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

# 3. Attach the official AWS policy to the Execution Role
resource "aws_iam_role_policy_attachment" "ecs_execution_policy" {
  role       = aws_iam_role.ecs_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# 4. Define the ECS Fargate Task Definition
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
          "awslogs-region"        = "us-east-1"
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])
}

# Output the Task Definition ARN so you can use it if needed
output "task_definition_arn" {
  value = aws_ecs_task_definition.arunconty_task.arn
}
