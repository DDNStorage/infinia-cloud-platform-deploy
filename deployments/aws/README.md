
# Infinia Deployment on AWS with Terraform

## Overview
This guide will walk you through deploying an Infinia cluster on AWS from absolute scratch — even if you just created your AWS account. Every single step is documented with the exact commands you need to run and
what you should see. By the end, you'll have a fully operational 7-node Infinia cluster running version 2.2.60.

## Prerequisites
1. **Request AMI Access**: Follow the instructions in `docs/customer-ami-access.md` to request access to the Infinia AMI.
2. **License Key**: Contact DDN Sales to obtain a valid Infinia license key required for deployment.
3. **AWS Account**: Ensure you have an AWS account with the necessary permissions.
4. **Terraform**: Install Terraform locally.
5. **AWS CLI**: Install and configure AWS CLI for authentication.
6. **Python 3**: Required for S3 smoke testing and deployment scripts.

## Features
- Deploys Infinia instances using customizable instance types (default: `m7a.2xlarge`).
- Deploys customizable client instances.
- Option to create new VPC and subnets or use existing infrastructure.
- S3 smoke testing capabilities for deployment validation.
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

## Variables

### Core Infrastructure Variables
| Variable              | Description                                      | Default           |
|-----------------------|--------------------------------------------------|-------------------|
| `infinia_deployment_name` | Deployment name for Infinia resources (4-8 lowercase chars) | - |
| `aws_region`          | AWS region for deployment                        | `us-west-2`       |
| `key_pair_name`       | Name of the AWS key pair for SSH access          | -                 |

### Network Configuration (Choose One Approach)
#### Option 1: Use Existing Infrastructure
| Variable              | Description                                      | Default           |
|-----------------------|--------------------------------------------------|-------------------|
| `create_vpc`          | Set to `false` to use existing VPC              | `false`           |
| `vpc_id`              | Existing VPC ID for resource deployment          | -                 |
| `subnet_ids`          | List of existing subnet IDs                      | -                 |
| `security_group_id`   | Existing security group ID allowing access to port 8111 | - |

#### Option 2: Create New VPC and Subnets
| Variable              | Description                                      | Default           |
|-----------------------|--------------------------------------------------|-------------------|
| `create_vpc`          | Set to `true` to create new VPC                 | `false`           |
| `vpc_cidr`            | CIDR block for new VPC                          | `10.0.0.0/16`     |
| `subnet_cidrs`        | List of subnet CIDR blocks                       | `["10.0.1.0/24", "10.0.2.0/24"]` |

### Instance Configuration
| Variable              | Description                                      | Default           |
|-----------------------|--------------------------------------------------|-------------------|
| `infinia_ami_id`      | AMI ID for Infinia instances                     | -                 |
| `client_ami_id`       | AMI ID for client instances                      | -                 |
| `instance_type_infinia` | Instance type for Infinia instances            | `m7a.2xlarge`   |
| `instance_type_client` | Instance type for client instances              | `t3.medium`       |
| `num_infinia_instances` | Number of Infinia instances to deploy          | `6`               |
| `num_client_instances` | Number of client instances to deploy            | `1`               |

### Storage Configuration
| Variable              | Description                                      | Default           |
|-----------------------|--------------------------------------------------|-------------------|
| `use_ebs_volumes`     | Enable EBS volumes for Infinia storage          | `true`            |
| `ebs_volumes_per_vm`  | Number of EBS volumes per Infinia instance       | `4`               |
| `ebs_volume_size`     | Size of each EBS volume (GB)                    | `128`             |
| `root_device_size`    | Size of root device (GB)                        | `256`             |

## Deployment Steps

### Part 0: First-Time AWS Account Setup

#### Step 0.1: Create Your AWS Account (Skip if you have one)
1. Go to https://aws.amazon.com
2. Click **Create an AWS Account**
3. Follow the signup process (you'll need a credit card)
4. Choose the **Basic Support - Free** plan

#### Step 0.2: Secure Your Root Account
Once your account is created:
1. Sign in to AWS Console: https://console.aws.amazon.com

#### Step 0.3: Create an IAM User for Daily Use
1. Go to IAM service: https://console.aws.amazon.com/iam
2. Click **Users** → **Create user**
3. User name: `admin-user` (or your name)
4. Click **Next**
5. Select **Attach policies directly**
6. Search for and check: `AdministratorAccess`
7. Click **Next** → **Create user**

#### Step 0.4: Create Access Keys for CLI
Still in IAM, with your new user:
1. Click on the user you just created
2. Go to **Security credentials** tab
3. Under **Access keys**, click **Create access key**
4. Select **Command Line Interface (CLI)**
5. Check the confirmation box → **Next**
6. Description: **Infinia deployment keys**
7. Click **Create access key**
**IMPORTANT: Save these credentials immediately!**
Access key ID: AKIA...............
Secret access key: ########################################
Copy these somewhere safe.

### Part 1: Setting Up Your Local Computer

#### Step 1.1: Install AWS CLI
**On Mac:**
Check if you have Homebrew installed
```bash
which brew
```
If not, install Homebrew first:
```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```
Install AWS CLI
```bash
brew install awscli
```
**On Linux (Ubuntu/Debian):**
```bash
sudo apt update
sudo apt install awscli -y
```
**On any system (alternative):**
```bash
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
```
Verify installation:
```bash
aws --version
```
You should see something like:
```bash
aws-cli/2.x.x Python/3.x.x ..
```

#### Step 1.2: Install Terraform
**On Mac:**
```bash
brew tap hashicorp/tap
brew install hashicorp/tap/terraform
```
**On Linux:**
Download Terraform (check latest version at terraform.io)
```bash
wget https://releases.hashicorp.com/terraform/1.5.7/terraform_1.5.7_linux_amd64.zip
unzip terraform_1.5.7_linux_amd64.zip
sudo mv terraform /usr/local/bin/
```
Verify installation:
```bash
terraform --version
```
You should see:
```bash
Terraform v1.x.x
```
#### Step 1.3: Install Python 3 and Dependencies
**On Mac:**
```bash
# Python 3 is usually pre-installed, check version
python3 --version
# If not installed or version is too old (< 3.7), install via Homebrew
brew install python3
```

**On Linux (Ubuntu/Debian):**
```bash
# Install Python 3 and pip
sudo apt update
sudo apt install python3 python3-pip -y
```

**Install Python dependencies:**
```bash
# Install required Python packages
pip3 install boto3 requests
```

Verify Python installation:
```bash
python3 --version
# Should show Python 3.7 or higher
python3 -c "import boto3; print('boto3 installed successfully')"
```

#### Step 1.4: Install Required Tools
Install jq (for JSON parsing)
On Mac:
```bash
brew install jq
```
On Linux:
```bash
sudo apt install jq -y
# Install curl (usually pre-installed)
which curl || sudo apt install curl -y
```
#### Step 1.5: Configure AWS CLI
Now configure the AWS CLI with your access keys from **Step 0.4**:
```bash
aws configure
```
When prompted, enter:
```bash
AWS Access Key ID [None]: AKIA....... (paste your key from Step 0.4)
AWS Secret Access Key [None]: ######## (paste your secret from Step 0.4)
Default region name [None]: us-west-2
Default output format [None]: json
```
Verify it's working:
```bash
aws sts get-caller-identity
```
You should see:
```bash
{
 "UserId": "AIDAXXXXXXXXX",
 "Account": "123456789012",
 "Arn": "arn:aws:iam::123456789012:user/admin-user"
}
```
If you see an error, run `aws configure` again and check your keys.

### Part 2: Preparing the Infrastructure
#### Step 3: Create an S3 Bucket for Terraform State
Terraform needs a place to store its state. Let's create a unique bucket:
```bash
BUCKET_NAME="terraform-infinia-$(date +%Y%m%d-%H%M%S)"
echo "Creating bucket: $BUCKET_NAME"
aws s3api create-bucket \
 --bucket $BUCKET_NAME \
 --region us-west-2 \
 --create-bucket-configuration LocationConstraint=us-west-2
 ```
Save this bucket name:
```bash
echo "Your bucket name is: $BUCKET_NAME"
```
#### Step 4: Get Network Information
Let's find your default VPC and subnet. Most AWS accounts have these already.
Get your default VPC
```bash
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=is-default,Values=true" \
 --query 'Vpcs[0].VpcId' --output text --region us-west-2)
echo "Your VPC ID: $VPC_ID"
# Get a subnet from that VPC
SUBNET_ID=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" \
 --query 'Subnets[0].SubnetId' --output text --region us-west-2)
echo "Your Subnet ID: $SUBNET_ID
```

### Step 5: Create a Security Group
The cluster needs specific network access rules.
Create the security group
```bash
SG_ID=$(aws ec2 create-security-group \
 --group-name infinia-cluster-sg \
 --description "Security group for Infinia cluster" \
 --vpc-id $VPC_ID \
 --region us-west-2 \
 --output text --query 'GroupId')
echo "Created security group: $SG_ID"
```
Now add the necessary rules:
Get your current IP address
```bash
# Allow inbound HTTPS (443) from anywhere. For production, restrict to trusted IP ranges/CIDRs.
aws ec2 authorize-security-group-ingress \
   --group-id $SG_ID \
 --protocol tcp \
 --port 443 \
 --cidr 0.0.0.0/0 \
 --region us-west-2
# Allow all traffic within the security group
aws ec2 authorize-security-group-ingress \
 --group-id $SG_ID \
 --protocol -1 \
 --source-group $SG_ID \
 --region us-west-2
echo "Security group rules added successfully."
```

### Step 6: Create an SSH Key Pair
You'll need this to access the instances if needed.
```bash
KEY_NAME="infinia-key-$(date +%s)"
# Create the key pair and save it locally
aws ec2 create-key-pair \
 --key-name $KEY_NAME \
 --region us-west-2 \
 --query 'KeyMaterial' \
 --output text > ~/.ssh/${KEY_NAME}.pem
# Set proper permissions
chmod 600 ~/.ssh/${KEY_NAME}.pem
echo "SSH key created: $KEY_NAME"
echo "Key saved to: ~/.ssh/${KEY_NAME}.pem"
```

### Step 7: Find the Correct AMI 
First, check if you have access to the private DDN AMI:
Search for DDN Infinia AMIs shared with your account
```bash
aws ec2 describe-images \
 --owners 471441381769 \
 --filters "Name=name,Values=infinia-*" \
 --query 'Images[*].[ImageId,Name,Description]' \
 --output table \
 --region us-west-2
```
If you see results like:
```bash
-------------------------------------------
| DescribeImages |
+-------------------+---------------------+
| ami-0d7c810c3064cb61a | infinia-2-2-24 | ... |
+-------------------+---------------------+
```
Then set and use that AMI:
```bash
INFINIA_AMI_ID="ami-0d7c810c3064cb61a" # Use the AMI ID from above
INFINIA_VERSION="2.2.24" # Use the version from the above
echo "Using Infinia AMI: $INFINIA_AMI_ID"
echo "Using Infinia Version: $INFINIA_VERSION"
```
**If you DON'T see any results:** You need to request access:
1. Contact DDN Sales with your AWS Account ID
2. Request access to the Infinia AMI for region **us-west-2**
3. They will share the AMI with your account (this can take 24–48 hours)
4. You **CANNOT** proceed without this AMI access
To find your AWS Account ID for the request:
```bash
aws sts get-caller-identity --query 'Account' --output text
```

### Step 8: Clone the Repository
Get the deployment code:
```bash
cd ~/Desktop
git clone https://github.com/DDNStorage/infinia-cloud-platform-deploy.git
cd infinia-cloud-platform-deploy/deployments/aws
```

### Step 9: Configure Terraform Backend
Update the S3 backend configuration with your bucket name:
```bash
cat > providers.tf << EOF
provider "aws" {
 region = var.aws_region
}
terraform {
 backend "s3" {
 bucket = "${BUCKET_NAME}"
 key = "infinia/state.tfstate"
 region = "us-west-2"
 }
}
EOF
```
Verify it was created correctly:
```bash
cat providers.tf
# Should show your bucket name, not ${BUCKET_NAME}
```

### Step 10: Choose Your Network Configuration

You have two options for network setup:

#### Option A: Use Existing VPC (Recommended for existing AWS accounts)
If you followed the previous steps and have existing VPC, subnets, and security groups.

#### Option B: Create New VPC (Recommended for new deployments)
Let Terraform create a new VPC, subnets, and security groups for you.

### Step 10.1: Create terraform.tfvars

**Option A - Using Existing Infrastructure:**
```bash
cat > terraform.tfvars << EOF
# Core configuration
aws_region = "us-west-2"
infinia_deployment_name = "infinia"
key_pair_name = "${KEY_NAME}"

# Use existing infrastructure
create_vpc = false
vpc_id = "${VPC_ID}"
subnet_ids = ["${SUBNET_ID}"]
security_group_id = "${SG_ID}"

# Instance configuration
infinia_ami_id = "${INFINIA_AMI_ID}"
client_ami_id = "${INFINIA_AMI_ID}"
infinia_version = "${INFINIA_VERSION}"
num_infinia_instances = 6
num_client_instances = 1
instance_type_infinia = "m7a.2xlarge"
instance_type_client = "m7a.2xlarge"

# Storage configuration
use_ebs_volumes = true
ebs_volumes_per_vm = 4
ebs_volume_size = 128
root_device_size = 256

# Other settings
enable_public_ip = true
bucket_name = "${BUCKET_NAME}"
EOF
```

**Option B - Create New VPC (Simpler setup):**
```bash
cat > terraform.tfvars << EOF
# Core configuration
aws_region = "us-west-2"
infinia_deployment_name = "infinia"
key_pair_name = "${KEY_NAME}"

# Create new VPC and subnets
create_vpc = true
vpc_cidr = "10.0.0.0/16"
subnet_cidrs = ["10.0.1.0/24", "10.0.2.0/24"]

# Instance configuration
infinia_ami_id = "${INFINIA_AMI_ID}"
client_ami_id = "${INFINIA_AMI_ID}"
infinia_version = "${INFINIA_VERSION}"
num_infinia_instances = 6
num_client_instances = 1
instance_type_infinia = "m7a.2xlarge"
instance_type_client = "m7a.2xlarge"

# Storage configuration
use_ebs_volumes = true
ebs_volumes_per_vm = 4
ebs_volume_size = 128
root_device_size = 256

# Other settings
enable_public_ip = false
bucket_name = "${BUCKET_NAME}"
EOF
```

> **Note:** Option B (create_vpc = true) is simpler as it handles all networking automatically. Option A gives you more control but requires pre-existing infrastructure.
Verify all variables were substituted:
```bash
cat terraform.tfvars
# Should show actual IDs, not variable names like ${VPC_ID}
# Example: vpc_id = "vpc-0796295778b00a4a5"
```
If any show as `${VARIABLE_NAME}`, you need to re-run the commands to get those values:
```bash
# Re-get any missing values:
echo "VPC_ID=$VPC_ID"
echo "SUBNET_ID=$SUBNET_ID"
echo "SG_ID=$SG_ID"
echo "KEY_NAME=$KEY_NAME"
echo "BUCKET_NAME=$BUCKET_NAME"
echo "INFINIA_AMI_ID=$INFINIA_AMI_ID
```

### Step 11: Initialize Terraform
Now we're ready to deploy:
```bash
terraform init
```
Expected output should include these key lines:
```bash
Initializing the backend...
Successfully configured the backend "s3"! Terraform will automatically use this backend unless the backend configuration changes.
Initializing provider plugins...
- Installing hashicorp/aws v6.11.0...
- Installed hashicorp/aws v6.11.0 (signed by HashiCorp)
- Installing hashicorp/time v0.13.1...
- Installed hashicorp/time v0.13.1 (signed by HashiCorp)
- Installing hashicorp/local v2.5.3...
- Installed hashicorp/local v2.5.3 (signed by HashiCorp)
Terraform has been successfully initialized!
```
If you see errors about the S3 bucket, verify your bucket was created:
```bash
aws s3 ls | grep $BUCKET_NAME
```

### Step 12: Review the Deployment Plan
Export your realm_password and infinia_license_key
$TF_VAR_admin_password and $TF_VAR_realm_license environment variables can be used instead of hardcoded password
```bash
export TF_VAR_admin_password=<YOUR-REALM-PASSWORD>
export TF_VAR_realm_license=<YOUR-LICENSE-KEY-FROM-DDN>
```
Always check what Terraform will create:
```bash
terraform plan --var-file terraform.tfvars
```
You should see at the end:
```
Plan: 19 to add, 0 to change, 0 to destroy.
```
The 19 resources should include:
- 7 EC2 instances (1 realm + 6 storage)
- 6 Network interfaces for EFA
- IAM role and instance profile
- Security group rules
- Various supporting resources
If you see errors about:
- **InvalidAMIID.NotFound** — You don't have access to the Infinia AMI, see **Step 7**
- **UnauthorizedOperation** — Your IAM user lacks permissions
- **VpcLimitExceeded** — You've hit AWS limits, contact AWS support

### Step 13: Deploy the Infrastructure
This is it — let's create your cluster:
```bash
terraform apply --var-file terraform.tfvars --auto-approve
```
This will take about 5–7 minutes. You'll see resources being created:
- IAM roles and policies
- Network interfaces
- EC2 instances (1 realm + 6 storage nodes)
- The instances will automatically configure themselves
When complete, you'll see:
```bash
Apply complete! Resources: 19 added, 0 changed, 0 destroyed.
```

### Step 14: Get Your Cluster Information
After deployment, get the important details:
Get the realm node's public IP
```bash
REALM_IP=$(terraform output -json | jq -r '.infinia_instance_realm_ids.value' | \
 xargs -I {} aws ec2 describe-instances --instance-ids {} \
 --query 'Reservations[0].Instances[0].PublicIpAddress' \
 --output text --region us-west-2)
echo "================================"
echo "Cluster Successfully Deployed!"
echo "================================"
echo "Web Interface: https://${REALM_IP}"
echo "Username: realm_admin"
echo "Password: [The password you set in Step 2]"
echo "SSH Key: ~/.ssh/${KEY_NAME}.pem"
echo "================================"
```

### Step 15: Check Cluster Status
Let's verify everything is working:
Get the realm instance ID
```bash
REALM_INSTANCE=$(terraform output -raw infinia_instance_realm_ids)
REALM_INSTANCE=$(terraform output -json infinia_instance_realm_ids | jq -r 'if type=="array" then .[0] else . end')
echo "Instances: ${REALM_INSTANCE}"
# Check the cluster inventory
CMD_ID=$(aws ssm send-command \
  --instance-ids "${REALM_INSTANCE}" \
  --document-name "AWS-RunShellScript" \
  --parameters "commands=[\"redcli user login realm_admin -p ${TF_VAR_admin_password}\",\"redcli inventory show\"]" \
  --region us-west-2 \
  --output text --query 'Command.CommandId')
echo "Command ID: $CMD_ID"
```
Wait a few seconds, then check the output:
```bash
aws ssm wait command-executed \
  --command-id "$CMD_ID" \
  --instance-id "$REALM_INSTANCE" \
  --region us-west-2

aws ssm get-command-invocation \
  --command-id "$CMD_ID" \
  --instance-id "$REALM_INSTANCE" \
  --region us-west-2 \
  --output text --query 'StandardOutputContent'
```

You should see all 7 nodes listed with their capacity and status.

### Step 16: Run S3 Smoke Test (Optional but Recommended)

After deployment, verify that the S3 API is working correctly:

```bash
# Run the S3 smoke test
cd ~/Desktop/infinia-cloud-platform-deploy/
python3 scripts/s3_smoke_test_aws.py \
    --region "us-west-2" \
    --admin-password "${TF_VAR_admin_password}" \
    --client-tag-key "Role" --client-tag-value "client" \
    --endpoint-port 8111 \
    --no-verify-ssl \
    --timeout-sec 1800
```

**Expected output on success:**
```
Selected endpoint: https://10.0.x.x:8111
---- Client i-xxxxxxxxx (Success) ----
upload: test-xxxxx.txt to s3://infinia-smoke-xxxxx/test-xxxxx.txt
LIST:test-xxxxx.txt
OK
✅ S3 smoke test passed on all clients
```

**If the test fails:**
- Check that all instances are running: `aws ec2 describe-instances --region us-west-2`
- Verify client instances have the correct tags
- Ensure the Infinia cluster is fully initialized (may take 10-15 minutes after deployment)

### Step 17: Access the Web Interface
Open your browser and navigate to:
https://[REALM_IP]
Login with:
- Username: `realm_admin`
- Password: Your password from **Step 2**

## Troubleshooting

### Common Issues

#### S3 Smoke Test Fails
```bash
# Check if Infinia cluster is ready
REALM_INSTANCE=$(terraform output -raw infinia_instance_realm_ids)
aws ssm send-command \
  --instance-ids "${REALM_INSTANCE}" \
  --document-name "AWS-RunShellScript" \
  --parameters "commands=[\"redcli inventory show\"]" \
  --region us-west-2
```

#### Python Dependencies Issues
```bash
# Reinstall Python packages
pip3 install --upgrade boto3 requests

# On some systems, use pip instead of pip3
pip install boto3 requests
```

#### Terraform Backend Issues
If you see S3 backend errors:
```bash
# Verify bucket exists
aws s3 ls s3://$BUCKET_NAME

# If bucket doesn't exist, recreate it
aws s3api create-bucket --bucket $BUCKET_NAME --region us-west-2 --create-bucket-configuration LocationConstraint=us-west-2
```

### Log Locations
- **Instance startup logs**: `/var/log/infinia-deployment.log`
- **Terraform logs**: Enable with `export TF_LOG=DEBUG`

## Tear-Down
To destroy everything and start over:
```bash
terraform destroy --var-file terraform.tfvars --auto-approve
echo "Deleting state bucket: $BUCKET_NAME"
aws s3 rb "s3://$BUCKET_NAME" --force --region us-west-2
```





