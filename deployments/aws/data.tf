


data "aws_secretsmanager_secret" "realm_credentials" {
  name = "realm_password"
}

data "aws_secretsmanager_secret_version" "realm_credentials" {
  secret_id = data.aws_secretsmanager_secret.realm_credentials.id
}

data "aws_subnet" "selected_subnet" {
  id = element(var.subnet_ids, 0)
}

# data "aws_subnet" "selected_subnet" {
#   count = var.use_ebs_volumes ? 1 : 0
#   id    = var.interface_type == "" ? element(var.subnet_ids, 0) : aws_network_interface.efa_realm[0].subnet_id
# }
#
