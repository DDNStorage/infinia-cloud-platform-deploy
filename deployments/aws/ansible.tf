resource "local_file" "ansible_inventory" {
  filename = "${path.module}/ansible/aws_ec2.yml"
  content  = <<EOT
plugin: aws_ec2
regions:
  - ${var.aws_region}
filters:
  tag:Role:
    - realm
    - nonrealm
  tag:Deployment: "${var.infinia_deployment_name}"
use_extra_vars: true
keyed_groups:
  - prefix: role
    key: tags['Role']
hostnames:
  - instance-id
EOT
}

resource "local_file" "ansible_vars" {
  filename = "${path.module}/ansible/vars.yml"
  content  = <<EOT
# vars.yml
# Non-sensitive variables
infinia_version: ${var.infinia_version}
ansible_connection: aws_ssm
ansible_aws_ssm_bucket_name: infinia-tf-state-dev
ansible_aws_ssm_region: ${var.aws_region}
ansible_aws_ssm_timeout: 3600
ansible_aws_ssm_retries: 200
EOT
}



resource "null_resource" "run_ansible_playbook" {
  provisioner "local-exec" {
    command     = <<EOT
      sleep 60
      ansible-playbook -i aws_ec2.yml \
                       main.yml --vault-password-file ~/.vault
    EOT
    working_dir = "${path.module}/ansible"
  }

  triggers = {
    inventory_hash = sha1(local_file.ansible_inventory.content)
    vars_hash      = sha1(local_file.ansible_vars.content)
  }

  depends_on = [
    aws_instance.infinia,
    local_file.ansible_inventory,
    local_file.ansible_vars
  ]
}


