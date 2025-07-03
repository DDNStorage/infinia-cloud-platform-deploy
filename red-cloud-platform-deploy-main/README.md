# Red Cloud Platform Deploy

This repository contains Terraform and Ansible code for deploying an Infinia cluster. Multiple cloud providers are present in the tree, but the `deployments/aws` directory is fully functional and provides an automated AWS deployment.

## Getting Started on AWS
1. Copy `deployments/aws/terraform.tfvars.example` to `deployments/aws/terraform.tfvars` and edit the values to match your environment.
2. Run Terraform from the `deployments/aws` directory:
   ```bash
   terraform init
   terraform apply
   ```
   This creates the EC2 instances and generates Ansible inventory files.
3. Change to the `deployments/aws/ansible` directory and run the playbook:
   ```bash
   ansible-playbook main.yml -i aws_ec2.yml --ask-vault-pass
   ```
   The playbook configures the nodes and brings the cluster online.

See the `deployments/aws/README.md` for detailed variable descriptions and outputs.

