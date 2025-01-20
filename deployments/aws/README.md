
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

## Deployment Steps

### 1. Infrastructure Setup
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

3. Deploy infrastructure:
   ```bash
   terraform init
   terraform plan
   terraform apply
   ```

### 2. RED Deployment Guide

#### Prerequisites
- Download RED packages
- Base operating system: Ubuntu 24.04

#### Environment Setup
```bash
export BASE_PKG_URL="https://storage.googleapis.com/ddn-redsetup-public"
export RELEASE_TYPE=""
export TARGET_ARCH="$(dpkg --print-architecture)"
export REL_DIST_PATH="ubuntu/24.04"
export REL_PKG_URL="${BASE_PKG_URL}/releases${RELEASE_TYPE}/${REL_DIST_PATH}"
export RED_VER=1.3.37
```

#### Install redsetup
```bash
wget $REL_PKG_URL/redsetup_"${RED_VER}"_"${TARGET_ARCH}${RELEASE_TYPE}".deb?cache-time="$(date +$s)" \
-O /tmp/redsetup.deb && sudo apt install -y /tmp/redsetup.deb
```

#### Realm Entry Node Setup
```bash
wget $BASE_PKG_URL/releases/rmd_template.json -O /tmp/rmd_template.json && \
envsubst < /tmp/rmd_template.json > /tmp/rmd.json && \
sudo redsetup --realm-entry-secret <YOUR_SECRET> --admin-password <YOUR_ADMIN_PASSWORD> \
--realm-entry --ctrl-plane-ip $(hostname --ip-address) \
--release-metadata-file /tmp/rmd.json
```

#### Non-Realm Entry Node Setup
```bash
sudo redsetup --realm-entry-address <REALM_ENTRY_NODE_IP> --realm-entry-secret <YOUR_SECRET>
```

#### Deploy RED Cluster
1. Login to RED CLI:
   ```bash
   redcli user login realm_admin -p <YOUR_ADMIN_PASSWORD>
   ```

2. Generate and update realm configuration:
   ```bash
   redcli realm config generate
   redcli realm config update -f realm_config.yaml
   ```

3. Install license:
   ```bash
   redcli license install -a <YOUR_LICENSE_KEY> -y
   ```

4. Create and verify cluster:
   ```bash
   redcli cluster create c1 -S=false -z
   redcli cluster show
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

