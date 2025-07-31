resource "local_file" "ansible_inventory" {
  filename = "${path.module}/ansible/aws_ec2.yml"
  content  = <<EOT
plugin: aws_ec2
regions:
  - ${var.aws_region}
filters:
  tag:Deployment: "${var.infinia_deployment_name}"
use_extra_vars: true
keyed_groups:
  - prefix: role
    key: tags['Role']
hostnames:
  - instance-id
groups:
  client_nodes: "tags.Name is defined and 'cn' in tags.Name"
  realm_nodes: "tags.Role is defined and tags.Role == 'realm'"
  nonrealm_nodes: "tags.Role is defined and tags.Role == 'nonrealm'"
EOT
}

# Ansible Variables Output
resource "local_file" "ansible_vars" {
  filename = "${path.module}/ansible/vars.yml"
  content  = <<EOT
# vars.yml
infinia_version: ${var.infinia_version}
ansible_connection: aws_ssm
ansible_aws_ssm_bucket_name: ${var.bucket_name}
ansible_aws_ssm_region: ${var.aws_region}
ansible_aws_ssm_timeout: 3600
ansible_aws_ssm_retries: 200
EOT
}
