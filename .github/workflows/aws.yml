provider "aws" {
  region = "us-east-1"
}

# --- EXISTING CODE FIXES ---

resource "aws_cloudwatch_log_group" "ecs_log_group" {
  name              = "/ecs/arunconty"
  retention_in_days = 7
}

resource "aws_iam_role" "ecs_execution_role" {
  name = "ecsTaskExecutionRole-terraform" # Unique name to fix 409 error

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

# --- NEW ALB & ECS SERVICE NETWORKING ADDITIONS ---

# 1. Define your existing VPC and Subnets (Replace these placeholder strings!)
variable "vpc_id" {
  default = "vpc-xxxxxxxxxxxxxxxxx" 
}

variable "public_subnets" {
  type    = list(string)
  default = ["subnet-xxxxxxxxxxxxxxxxx", "subnet-yyyyyyyyyyyyyyyyy"] 
}

# 2. Security Group for the Load Balancer (Allows public web traffic on port 80)
resource "aws_security_group" "alb_sg" {
  name        = "alb-security-group"
  vpc_id      = var.vpc_id

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

# 3. The Application Load Balancer
resource "aws_lb" "main_alb" {
  name               = "arunconty-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = var.public_subnets
}

# 4. Target Group mapping traffic to your container's port 3000
resource "aws_lb_target_group" "ecs_tg" {
  name        = "ecs-target-group"
  port        = 3000
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip" # Required for Fargate awsvpc mode

  health_check {
    path                = "/"
    port                = "3000"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 3
    unhealthy_threshold = 3
  }
}

# 5. ALB Listener routing public port 80 traffic into Target Group (port 3000)
resource "aws_lb_listener" "http_listener" {
  load_balancer_arn = aws_lb.main_alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ecs_tg.arn
  }
}

# 6. ECS Cluster
resource "aws_ecs_cluster" "main_cluster" {
  name = "new_cluster"
}

# 7. ECS Service managing your Fargate Tasks and attaching to the ALB
resource "aws_ecs_service" "main_service" {
  name            = "new_secvice"
  cluster         = aws_ecs_cluster.main_cluster.id
  task_definition = aws_ecs_task_definition.arunconty_task.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.public_subnets
    security_groups  = [aws_security_group.alb_sg.id] # For testing, allows traffic to pass through
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.ecs_tg.arn
    container_name   = "arunconty"
    container_port   = 3000
  }

  depends_on = [aws_lb_listener.http_listener]
}

# Output the DNS name of the Load Balancer to access your app
output "alb_dns_name" {
  value = aws_lb.main_alb.dns_name
}
