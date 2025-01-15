
# Infinia Deployment on AWS with Terraform

## Overview
This Terraform module deploys Infinia instances and client instances on AWS. It also sets up an internal Network Load Balancer (NLB) for high availability and seamless client communication.

## Prerequisites
1. **AWS Account**: Ensure you have an AWS account with the necessary permissions.
2. **Terraform**: Install Terraform locally.
3. **AWS CLI**: Install and configure AWS CLI for authentication.

## Features
- Deploys Infinia instances using customizable instance types (default: `i3en.24xlarge`).
- Deploys customizable client instances.
- Sets up an internal Network Load Balancer (NLB) for routing traffic.
- Health checks on port `8111` for instance availability.

## Directory Structure
```plaintext
infinia-deployment/
├── main.tf
├── variables.tf
├── outputs.tf
├── providers.tf
├── terraform.tfvars
└── README.md
```

## Usage
1. Clone the repository:
   ```bash
   git clone <repository-url>
   cd infinia-deployment
   ```

2. Create a `terraform.tfvars` file with your configuration:
   ```hcl
   infinia_deployment_name = "demo"
   aws_region         = "us-east-1"
   vpc_id             = "vpc-xxxxxxxxxxxxxxxxx"
   subnet_ids         = ["subnet-xxxxxxxxxxxxxxxxx", "subnet-yyyyyyyyyyyyyyyyy"]
   security_group_id  = "sg-xxxxxxxxxxxxxxxxx"
   infinia_ami_id     = "ami-xxxxxxxxxxxxxxxxx"
   client_ami_id      = "ami-yyyyyyyyyyyyyyyyy"
   num_infinia_instances = 2
   num_client_instances  = 1
   key_pair_name      = "my-key-pair"
   ```

3. Initialize Terraform:
   ```bash
   terraform init
   ```

4. Plan the deployment:
   ```bash
   terraform plan
   ```

5. Apply the configuration:
   ```bash
   terraform apply
   ```

## Variables
| Variable              | Description                                      | Default           |
|-----------------------|--------------------------------------------------|-------------------|
| `infinia_deployment_name` | Deployment name for Infinia resources (4-8 lowercase chars) | - |
| `aws_region`          | AWS region for deployment                        | `us-west-2`       |
| `vpc_id`              | VPC ID for resource deployment                   | -                 |
| `subnet_ids`          | List of subnet IDs                               | -                 |
| `security_group_id`   | Security group ID allowing access to port 8111   | -                 |
| `infinia_ami_id`      | AMI ID for Infinia instances                     | -                 |
| `client_ami_id`       | AMI ID for client instances                      | -                 |
| `instance_type_infinia` | Instance type for Infinia instances            | `i3en.24xlarge`   |
| `instance_type_client` | Instance type for client instances              | `t3.medium`       |
| `num_infinia_instances` | Number of Infinia instances to deploy          | `1`               |
| `num_client_instances` | Number of client instances to deploy            | `1`               |
| `key_pair_name`       | Name of the AWS key pair for SSH access          | -                 |

## Outputs
- **Internal Load Balancer DNS Name**: DNS name of the NLB
- **Load Balancer ARN**: ARN of the NLB
- **Infinia Instance Private IPs**: Private IP addresses of Infinia instances
- **Infinia Instance IDs**: Instance IDs of Infinia instances
- **Client Instance Private IPs**: Private IP addresses of client instances
- **Client Instance IDs**: Instance IDs of client instances
- **VPC ID**: ID of the VPC where resources are deployed
- **Subnet IDs**: IDs of the subnets used for deployment
- **Security Group ID**: ID of the security group used for instances
- **Infinia Instance Count**: Number of Infinia instances deployed
- **Client Instance Count**: Number of client instances deployed

## Notes
- Ensure the AMI IDs for your instances are available in the specified region.
- The security group must allow inbound traffic on port `8111`.
- For additional customization, edit the `variables.tf` file.

---

**Happy Deploying!**
