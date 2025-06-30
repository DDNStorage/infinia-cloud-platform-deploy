resource "null_resource" "run_ansible" {
  provisioner "local-exec" {
    command = <<EOT
      ansible-playbook -i ${path.module}/ansible/aws_ec2.yml \
                       --extra-vars "@${path.module}/ansible/vars.yml" \
                       ${path.module}/ansible/main.yml --vault-password-file ~/.vault
    EOT
  }
  depends_on = [
    local_file.ansible_inventory,
    local_file.ansible_vars
  ]

}

