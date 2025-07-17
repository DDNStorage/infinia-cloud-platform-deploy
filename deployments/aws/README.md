
# Infinia Deployment on AWS with Terraform

## Overview
This Terraform module deploys Infinia instances and client instances on AWS. It also sets up an internal Network Load Balancer (NLB) for high availability and seamless client communication.

## Prerequisites
1. **Request AMI Access**: Follow the instructions in `docs/customer-ami-access.md` to request access to the Infinia AMI.
2. **License Key**: Contact DDN Sales to obtain a valid Infinia license key required for deployment.
3. **AWS Account**: Ensure you have an AWS account with the necessary permissions.
4. **Terraform**: Install Terraform locally.
5. **AWS CLI**: Install and configure AWS CLI for authentication.

## Features
- Deploys Infinia instances using customizable instance types (default: `m7a.2xlarge`).
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

## Deployment Steps

### 1. Prerequisites
1. **Create S3 Bucket**: Create a unique S3 bucket in your AWS region for Terraform state storage.
2. **Update Backend Configuration**: In `providers.tf`, update the S3 backend bucket name to match your created bucket.
3. **Configure terraform.tfvars**: Copy `terraform.tfvars.example` to `terraform.tfvars` and update with your values.

### 2. Infrastructure Setup
1. Clone the repository:
   ```bash
   git clone <repository-url>
   cd infinia-deployment
   ```

2. Create your configuration file:
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   # Edit terraform.tfvars with your specific values
   ```

3. Export AWS Credentials:
   ```bash
   export AWS_ACCESS_KEY_ID="..."
   export AWS_SECRET_ACCESS_KEY="..."
   export AWS_SESSION_TOKEN="..."
   ```

4. Deploy infrastructure:
   ```bash
   terraform init
   terraform plan
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
| `instance_type_infinia` | Instance type for Infinia instances            | `m7a.2xlarge`   |
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

## Next Steps

After successful Terraform deployment, proceed with node setup and cluster configuration by following the instructions in `scripts/README.md`. The scripts will guide you through:
1. Setting up the realm entry node
2. Configuring non-realm entry nodes
3. Initializing the cluster

You can find the instance IP addresses in the Terraform outputs:
```bash
terraform output infinia_instance_private_ips
terraform output client_instance_private_ips
```

