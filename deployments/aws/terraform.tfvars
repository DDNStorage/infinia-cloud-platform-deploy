aws_region              = "us-east-1"
vpc_id                  = "vpc-0643ea52b06790437"
security_group_id       = "sg-0514508ec0ae982b9"
key_pair_name           = "dev-keys"
infinia_ami_id          = "ami-01eb4635e82858e09"
num_ephemeral_device    = "0"
subnet_ids              = ["subnet-06c1a6ccde3dec102"]
infinia_version         = "2.2.28"
enable_public_ip        = "false"
num_infinia_instances   = "3"
ebs_volumes_per_vm      = "2"
infinia_deployment_name = "jazmin"
bucket_name             = "terraform-dev-raid"

