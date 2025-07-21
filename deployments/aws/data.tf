


data "aws_secretsmanager_secret" "realm_credentials" {
  name = "realm_password"
}

data "aws_secretsmanager_secret_version" "realm_credentials" {
  secret_id = data.aws_secretsmanager_secret.realm_credentials.id
}

