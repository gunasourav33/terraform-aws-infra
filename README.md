# Terraform AWS Infrastructure

![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg) ![Terraform](https://img.shields.io/badge/terraform-1.x-purple.svg) ![AWS](https://img.shields.io/badge/AWS-VPC%20%7C%20EC2%20%7C%20S3-orange.svg) ![IaC](https://img.shields.io/badge/IaC-reusable--modules-blue.svg)

Reusable Terraform modules for a standard AWS landing zone. Includes VPC, EC2/ASG, and S3 with reasonable defaults for production use.

## Structure

```
terraform-aws-infra/
├── modules/
│   ├── vpc/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── ec2/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   └── s3/
│       └── main.tf
├── envs/
│   ├── dev/
│   │   └── main.tf
└── README.md
```

## Quick start

### Prerequisites

- Terraform >= 1.0
- AWS CLI configured with credentials
- S3 bucket + DynamoDB table for remote state (see below)

### Set up remote state

```bash
# Create S3 bucket for state
aws s3api create-bucket \
  --bucket terraform-state-$(aws sts get-caller-identity --query Account -o text) \
  --region us-east-1

# Create DynamoDB table for locking
aws dynamodb create-table \
  --table-name terraform-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5 \
  --region us-east-1
```

### Deploy dev environment

```bash
cd envs/dev
terraform init
terraform plan
terraform apply
```

## Module usage

### VPC Module

```hcl
module "vpc" {
  source = "../../modules/vpc"

  vpc_cidr        = "10.0.0.0/16"
  environment     = "dev"
  project_name    = "myapp"
  az_count        = 2
  enable_flow_logs = true

  common_tags = {
    Owner   = "platform-team"
    Project = "myapp"
  }
}
```

### EC2 Module

```hcl
module "app_asg" {
  source = "../../modules/ec2"

  name_prefix          = "app"
  environment          = "dev"
  vpc_id               = module.vpc.vpc_id
  subnet_ids           = module.vpc.private_subnet_ids
  min_size             = 1
  max_size             = 3
  desired_capacity     = 2
  instance_type        = "t3.large"

  common_tags = {
    Owner   = "platform-team"
    Project = "myapp"
  }
}
```

## Known gotchas

- **NAT Gateway costs**: Only one NAT gateway provisioned in the first AZ to save costs. Set `nat_gateway_per_az = true` for HA
- **EC2 AMI**: Modules use the latest Amazon Linux 2023 AMI. Update `data.aws_ami` for a different base image
- **IMDSv2 enforcement**: Enforced on all EC2 instances. Update launch template for legacy apps needing IMDSv1
- **VPC Flow Logs**: Enabled by default to CloudWatch Logs. Disable with `enable_flow_logs = false` if budget-sensitive
- **State locking**: DynamoDB locking can fail on inconsistent state. Manually clean up DynamoDB locks if needed

## TODO

- [ ] Add RDS module with automated backups
- [ ] Add CloudFront distribution for static assets
- [ ] Implement cross-region replication for S3
- [ ] Add cost allocation tags enforcement
