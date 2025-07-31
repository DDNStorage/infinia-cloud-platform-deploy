## Terraform: One click deploy

This project enables a one-click deployment of infrastructure using Terraform and cloud-init for automated EC2 instance configuration
# Prerequisites
Before using this Terraform-based one-click deployment, ensure the following are in place:

## Packer Image Prepared for Cloud-Init
The AMI must be built with Packer and include a systemd unit that ensures cloud-init runs fully on first boot. This guarantees that all initialization scripts and configuration modules execute as expected when the EC2 instance is launched.

```
{
  "type": "shell",
  "inline": [
    "cat <<EOF > /etc/systemd/system/cloudinit-rerun.service",
    "[Unit]",
    "Description=Cloud-Init Re-Run",
    "After=network.target",
    "",
    "[Service]",
    "Type=oneshot",
    "ExecStart=/bin/bash -c 'cloud-init clean && cloud-init init && cloud-init modules --mode=config && cloud-init modules --mode=final'",
    "RemainAfterExit=true",
    "",
    "[Install]",
    "WantedBy=multi-user.target",
    "EOF",
    "systemctl enable cloudinit-rerun.service"
  ]
}
```
# Secrets and Licenses Fetched via Terraform Data Resources and AWS KMS
All secrets and licenses must be:

- Encrypted using AWS KMS
- Fetched at deploy time using Terraform data blocks
```

data "aws_secretsmanager_secret" "realm_credentials" {
  name = "realm_password"
}

data "aws_secretsmanager_secret_version" "realm_credentials" {
  secret_id = data.aws_secretsmanager_secret.realm_credentials.id
}
```
# Deploy in One Click
```
terraform init && terraform  plan --var-file terraform.tfvars && terraform  apply --auto-approve 
```
Example of terraform.tfvars:

```
aws_region        = "us-east-1"
vpc_id            = "vpc-0643ea52b06790437"
security_group_id = "sg-0514508ec0ae982b9"
key_pair_name     = "dev-keys"
infinia_ami_id = "ami-01eb4635e82858e09"      # cloud-init
subnet_ids     = ["subnet-06c1a6ccde3dec102"] #private
#subnet_ids            = ["subnet-0bcc62fd072a08b7e"] #public
infinia_version       = "2.2.37"
enable_public_ip      = "false"
root_device_size      = 256
num_infinia_instances = "6"
instance_type_infinia   = "m7a.2xlarge"
ebs_volume_size         = 128
infinia_deployment_name = "raidr"
bucket_name             = "terraform-dev-raid"
ebs_volumes_per_vm      = 4
use_ebs_volumes         = true
```

# Logs & Debugging
Cloud-init generates logs on the instance that are useful for debugging initialization
```
tail -f /var/log/cloud-init-output.log
```
This file contains output from your user_data script and cloud-init modules. It’s the primary source for diagnosing issues during first boot.

