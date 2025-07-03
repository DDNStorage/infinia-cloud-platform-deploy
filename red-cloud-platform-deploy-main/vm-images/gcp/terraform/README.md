# Create GCP VM Image Automation

This Terraform project automates the creation of a Google Cloud VM instance, runs a startup script to install the necessary software, and creates a public image for use in a GCP Marketplace solution.

## Directory Structure

```plaintext
create-gcp-vm-image/
├── main.tf          # Terraform configuration for resources
├── variables.tf     # Input variables for customization
├── outputs.tf       # Outputs for reuse
├── terraform.tfvars # Default variable values
└── README.md        # Documentation
```

## Prerequisites

1. **Google Cloud Platform**:
   - A GCP project with billing enabled.
   - IAM role with `Compute Admin` and `IAM Admin` permissions.

2. **Terraform**:
   - Install Terraform (v1.5.0 or higher).
   - Authenticate with GCP using a service account key:
     ```bash
     gcloud auth application-default login
     ```

3. **Service Account Key**:
   - Store the service account key JSON in a secure location.
   - Set the `GOOGLE_APPLICATION_CREDENTIALS` environment variable:
     ```bash
     export GOOGLE_APPLICATION_CREDENTIALS="/path/to/service-account-key.json"
     ```

4. **Enable APIs**:
   - Enable the following APIs in your GCP project:
     - Compute Engine API

## Configuration

Customize the `terraform.tfvars` file to set the required variables:

```hcl
infinia_version = "1.3.52"           # Version of Infinia to install
project_id      = "my-gcp-project" # GCP Project ID
local_disks     = 24               # Number of local NVMe disks
machine_type    = "n2d-standard-32" # Machine type
zone            = "us-central1-a"  # Compute Engine zone
```

## Usage

### 1. Initialize Terraform

Run the following command to initialize the Terraform working directory and set up the backend:

```bash
terraform init
```

### 2. Validate the Configuration

Validate the configuration to ensure there are no errors:

```bash
terraform validate
```

### 3. Plan the Deployment

Generate and review an execution plan:

```bash
terraform plan
```

### 4. Apply the Configuration

Deploy the resources to GCP:

```bash
terraform apply -auto-approve
```

### 5. Outputs

After successful deployment, the following outputs will be available:
- `image_name`: Name of the created image.
- `instance_name`: Name of the VM instance.
- `instance_zone`: Zone of the VM instance.

Example:

```plaintext
Outputs:
image_name     = "infinia-1.3.52"
instance_name  = "infinia-1.3.52"
instance_zone  = "us-central1-a"
```

## Project Workflow

1. **Create VM**:
   - Terraform creates a VM instance and attaches 24 NVMe scratch disks.

2. **Run Startup Script**:
   - The startup script installs Infinia and prepares the instance.

3. **Stop VM**:
   - Terraform or a `null_resource` triggers VM shutdown.

4. **Create Image**:
   - Terraform invokes the `gcloud` CLI to create a public image.

5. **Publish Image**:
   - The image is made public for use in the GCP Marketplace.

## Cleanup

To destroy all resources created by this Terraform configuration, run:

```bash
terraform destroy -auto-approve
```

## Notes

- Ensure that the `startup-script` section in `main.tf` is customized for your use case.
- The project uses 24 NVMe scratch disks by default. Modify the `local_disks` variable if needed.

---

## Troubleshooting

### Common Issues

- **Authentication Error**:
  Ensure `GOOGLE_APPLICATION_CREDENTIALS` is correctly set to the service account JSON file.

- **API Errors**:
  Verify that the Compute Engine API is enabled in your GCP project.

- **Quota Issues**:
  Check your project's quota for CPUs and local SSDs in the specified zone.
