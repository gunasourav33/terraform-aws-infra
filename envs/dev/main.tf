terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "terraform-state-ACCOUNT-ID"  # Replace with actual account ID
    key            = "dev/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-locks"
  }
}

provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = {
      Environment = "dev"
      ManagedBy   = "Terraform"
      Project     = "myapp"
      CostCenter  = "engineering"
    }
  }
}

# VPC
module "vpc" {
  source = "../../modules/vpc"

  vpc_cidr         = "10.0.0.0/16"
  environment      = "dev"
  project_name     = "myapp"
  az_count         = 2
  enable_flow_logs = false  # Disabled in dev to save costs

  common_tags = {
    Owner   = "platform-team"
    Project = "myapp"
  }
}

# EC2 ASG — Application Servers
module "app_asg" {
  source = "../../modules/ec2"

  name_prefix      = "app"
  environment      = "dev"
  vpc_id           = module.vpc.vpc_id
  subnet_ids       = module.vpc.private_subnet_ids
  instance_type    = "t3.medium"  # Smaller instances in dev
  min_size         = 1
  max_size         = 2
  desired_capacity = 1

  root_volume_size          = 30
  container_port            = 8080
  health_check_type         = "ELB"
  health_check_grace_period = 300

  common_tags = {
    Owner   = "platform-team"
    Project = "myapp"
    Role    = "app-server"
  }
}

# S3 Bucket for application data
resource "aws_s3_bucket" "app_data" {
  bucket = "myapp-dev-${data.aws_caller_identity.current.account_id}"

  tags = {
    Name    = "myapp-dev-data"
    Project = "myapp"
  }
}

resource "aws_s3_bucket_versioning" "app_data" {
  bucket = aws_s3_bucket.app_data.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "app_data" {
  bucket = aws_s3_bucket.app_data.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "app_data" {
  bucket                  = aws_s3_bucket.app_data.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

data "aws_caller_identity" "current" {}

# Outputs
output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "private_subnet_ids" {
  description = "Private subnet IDs"
  value       = module.vpc.private_subnet_ids
}

output "app_asg_name" {
  description = "Application ASG name"
  value       = module.app_asg.asg_name
}

output "nat_gateway_ip" {
  description = "NAT Gateway public IP"
  value       = module.vpc.nat_gateway_ip
}

output "app_s3_bucket" {
  description = "Application S3 bucket name"
  value       = aws_s3_bucket.app_data.id
}
