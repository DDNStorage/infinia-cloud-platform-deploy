# Google Cloud Marketplace Terraform Module

## Usage
The provided test configuration can be used by executing:

```
terraform plan --var-file marketplace_test.tfvars --var project_id=<YOUR_PROJECT>
```

## Inputs
| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| desired_capacity | Desired capacity in TB. Minimum is 54TB. | `number` | `54` | yes |
| project_id | The ID of the project in which to provision resources. | `string` | `null` | yes |
| goog_cm_deployment_name | The name of the deployment and VM instance. | `string` | `null` | yes |
| zone | The zone for the solution to be deployed. | `string` | `null` | yes |
| networks | The network name to attach the VM instance. | `list(string)` | `["default"]` | no |
| sub_networks | The sub network name to attach the VM instance. | `list(string)` | `[]` | no |
| external_ips | The external IPs assigned to the VM for public access. | `list(string)` | `["EPHEMERAL"]` | no |
| enable_tcp_80 | Allow HTTP traffic from the Internet | `bool` | `true` | no |
| tcp_80_source_ranges | Source IP ranges for HTTP traffic | `string` | `""` | no |
| enable_tcp_443 | Allow HTTPS traffic from the Internet | `bool` | `true` | no |
| tcp_443_source_ranges | Source IP ranges for HTTPS traffic | `string` | `""` | no |
| adminEmailAddress | The e-mail address used to create the administrator account for Infinia. | `string` | `null` | yes |
| httpsEnabled | Enabled HTTPS communication. | `bool` | `true` | no |
| enable_cloud_logging | Enables Cloud Logging. | `bool` | `false` | no |
| enable_cloud_monitoring | Enables Cloud Monitoring. | `bool` | `false` | no |

## Outputs

| Name | Description |
|------|-------------|
| site_url | Site Url |
| realm_entry_secret | Password for realm entry. |
| admin_password | Password for admin. |
| instance_self_link | Self-link for the compute instance. |
| instance_zone | Zone for the compute instance. |
| instance_nat_ip | External IP of the compute instance. |
| instance_network | Self-link for the network of the compute instance. |
| total_capacity | Total capacity provisioned in TB. |
| total_throughput | Total throughput provisioned in GB/s. |
| vm_count| Total number of VMs provisioned. |


## Requirements
### Terraform

Be sure you have the correct Terraform version (1.2.0+), you can choose the binary here:

https://releases.hashicorp.com/terraform/

### Configure a Service Account
In order to execute this module you must have a Service Account with the following project roles:

- `roles/compute.admin`
- `roles/iam.serviceAccountUser`

If you are using a shared VPC:

- `roles/compute.networkAdmin` is required on the Shared VPC host project.

### Enable API
In order to operate with the Service Account you must activate the following APIs on the project where the Service Account was created:

- Compute Engine API - `compute.googleapis.com`
