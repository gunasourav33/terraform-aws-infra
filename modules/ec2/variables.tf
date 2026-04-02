variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "subnet_ids" {
  description = "List of subnet IDs for the ASG"
  type        = list(string)
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.large"
}

variable "min_size" {
  description = "Minimum number of instances in the ASG"
  type        = number
  default     = 1
}

variable "max_size" {
  description = "Maximum number of instances in the ASG"
  type        = number
  default     = 3
}

variable "desired_capacity" {
  description = "Desired number of instances in the ASG"
  type        = number
  default     = 2
}

variable "root_volume_size" {
  description = "Root EBS volume size in GB"
  type        = number
  default     = 30
}

variable "container_port" {
  description = "Port the application listens on"
  type        = number
  default     = 8080
}

variable "target_group_arns" {
  description = "ARNs of ALB target groups to attach to the ASG"
  type        = list(string)
  default     = []
}

variable "alb_security_group_ids" {
  description = "Security group IDs of ALBs (for ingress rules)"
  type        = list(string)
  default     = []
}

variable "health_check_type" {
  description = "Health check type (ELB or EC2)"
  type        = string
  default     = "ELB"
}

variable "health_check_grace_period" {
  description = "Grace period in seconds before health checks start"
  type        = number
  default     = 300
}

variable "user_data" {
  description = "User data script to run on instance launch"
  type        = string
  default     = ""
}

variable "common_tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
  default     = {}
}
