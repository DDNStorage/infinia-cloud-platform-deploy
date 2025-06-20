# Create_instance.py terraform version 

This Python script automates the process of generating terraform.tfvars, initializing, planning, applying, and destroying Terraform infrastructure for supported cloud providers (AWS and GCP)

# Note:  This script is not a replacement (yet) to current create_instance.py

🚀 F Features
 - Automatically generates terraform.tfvars from user input or variables.tf

 - Lists available Terraform input variables

 - Supports both AWS and GCP

🛠️ Requirements
 - Python 3.6+

 - Terraform installed and available in $PATH

📌 Usage
Basic Command Format 
 ``` bash
    python create_vm.py [gcp|aws] [OPTIONS]
    
    # GCP example
    python create_vm.py gcp --var "region=us-central1" --var "project_id=my-project" --deploy

    # AWS exampel for 1 Infinia node with 9t  
    python create_vm.py aws  --var infinia_deployment_name=raidtest --deploy
```

#  Destroy cluster
  ```bash 
     python create_vm.py  [aws|gcp]  --destroy
  ```

# Variable overdie 

 ```bash 
    python create_vm.py  [aws|gcp] --var infinia_version="custom_version" --deploy

  # List availble variuabls 
    python create_vm.py [aws|gcp] --list-vars 

📝 Note on Default Variables
 
⚙️ Provider Default Variables
# AWS 
| Variable               | Default Value                  |
| ---------------------- | ------------------------------ |
| `aws_region`           | `us-east-1`                    |
| `vpc_id`               | `vpc-02adcd19590b5bbd0`        |
| `security_group_id`    | `sg-0de3d39aa32fc75d3`         |
| `key_pair_name`        | `red-poc-keys`                 |
| `infinia_ami_id`       | `ami-08391efc712c82150`        |
| `num_ephemeral_device` | `0`                            |
| `subnet_ids`           | `['subnet-047805b425b67e6c6']` |
| `infinia_version`      | `2.1.30`                       |

# GCP 
| Variable           | Default Value   |
| ------------------ | --------------- |
| `zone`             | `us-central1-a` |
| `project_id`       | `red-101`       |
| `desired_capacity` | `9`             |
| `infinia_version`  | `2.1.30`                       |
