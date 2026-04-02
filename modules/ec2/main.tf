terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Get latest Amazon Linux 2023 AMI
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

# IAM Role for EC2 instances
resource "aws_iam_role" "ec2_role" {
  name = "${var.name_prefix}-ec2-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })

  tags = merge(var.common_tags, { Name = "${var.name_prefix}-ec2-role-${var.environment}" })
}

# Attach SSM managed policy for SSH-less access
resource "aws_iam_role_policy_attachment" "ssm_managed" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# IAM Instance Profile
resource "aws_iam_instance_profile" "ec2_profile" {
  name = "${var.name_prefix}-ec2-profile-${var.environment}"
  role = aws_iam_role.ec2_role.name
}

# Security Group for ASG instances
resource "aws_security_group" "asg" {
  name        = "${var.name_prefix}-asg-${var.environment}"
  description = "Security group for ${var.name_prefix} ASG"
  vpc_id      = var.vpc_id

  tags = merge(var.common_tags, { Name = "${var.name_prefix}-asg-sg-${var.environment}" })
}

# Inbound from ALB
resource "aws_vpc_security_group_ingress_rule" "from_alb" {
  count                        = length(var.alb_security_group_ids) > 0 ? 1 : 0
  security_group_id            = aws_security_group.asg.id
  description                  = "From ALB"
  from_port                    = var.container_port
  to_port                      = var.container_port
  ip_protocol                  = "tcp"
  referenced_security_group_id = var.alb_security_group_ids[0]
}

# Outbound to anywhere
resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.asg.id
  description       = "Allow all outbound"
  from_port         = 0
  to_port           = 0
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# Launch Template
resource "aws_launch_template" "asg" {
  name_prefix   = "${var.name_prefix}-"
  image_id      = data.aws_ami.amazon_linux_2023.id
  instance_type = var.instance_type

  iam_instance_profile {
    name = aws_iam_instance_profile.ec2_profile.name
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_type           = "gp3"
      volume_size           = var.root_volume_size
      delete_on_termination = true
      encrypted             = true
    }
  }

  # IMDSv2 only — prevents SSRF attacks from accessing instance metadata
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  monitoring {
    enabled = true
  }

  network_interfaces {
    associate_public_ip_address = false
    security_groups             = [aws_security_group.asg.id]
    delete_on_termination       = true
  }

  user_data = var.user_data != "" ? base64encode(var.user_data) : null

  tag_specifications {
    resource_type = "instance"
    tags          = merge(var.common_tags, { Name = "${var.name_prefix}-instance-${var.environment}" })
  }

  tag_specifications {
    resource_type = "volume"
    tags          = merge(var.common_tags, { Name = "${var.name_prefix}-volume-${var.environment}" })
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Auto Scaling Group
resource "aws_autoscaling_group" "asg" {
  name                      = "${var.name_prefix}-asg-${var.environment}"
  vpc_zone_identifier       = var.subnet_ids
  target_group_arns         = var.target_group_arns
  health_check_type         = var.health_check_type
  health_check_grace_period = var.health_check_grace_period

  min_size         = var.min_size
  max_size         = var.max_size
  desired_capacity = var.desired_capacity
  default_cooldown = 300

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage  = 90
      instance_warmup = 300
    }
  }

  launch_template {
    id      = aws_launch_template.asg.id
    version = "$Latest"
  }

  dynamic "tag" {
    for_each = var.common_tags
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = false
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Scale up on high CPU
resource "aws_autoscaling_policy" "scale_up" {
  name                   = "${var.name_prefix}-scale-up-${var.environment}"
  adjustment_type        = "ChangeInCapacity"
  autoscaling_group_name = aws_autoscaling_group.asg.name
  scaling_adjustment     = 1
  cooldown               = 300
}

resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "${var.name_prefix}-cpu-high-${var.environment}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = 70
  dimensions          = { AutoScalingGroupName = aws_autoscaling_group.asg.name }
  alarm_actions       = [aws_autoscaling_policy.scale_up.arn]
}

# Scale down on low CPU
resource "aws_autoscaling_policy" "scale_down" {
  name                   = "${var.name_prefix}-scale-down-${var.environment}"
  adjustment_type        = "ChangeInCapacity"
  autoscaling_group_name = aws_autoscaling_group.asg.name
  scaling_adjustment     = -1
  cooldown               = 300
}

resource "aws_cloudwatch_metric_alarm" "cpu_low" {
  alarm_name          = "${var.name_prefix}-cpu-low-${var.environment}"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = 30
  dimensions          = { AutoScalingGroupName = aws_autoscaling_group.asg.name }
  alarm_actions       = [aws_autoscaling_policy.scale_down.arn]
}

output "asg_name" {
  description = "Auto Scaling Group name"
  value       = aws_autoscaling_group.asg.name
}

output "security_group_id" {
  description = "ASG security group ID"
  value       = aws_security_group.asg.id
}

output "launch_template_id" {
  description = "Launch template ID"
  value       = aws_launch_template.asg.id
}
