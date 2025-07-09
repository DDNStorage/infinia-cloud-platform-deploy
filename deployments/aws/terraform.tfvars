aws_region        = "us-east-1"
vpc_id            = "vpc-0643ea52b06790437"
security_group_id = "sg-0514508ec0ae982b9"
key_pair_name     = "dev-keys"
#infinia_ami_id          = "ami-020cba7c55df1f615" #clean
infinia_ami_id          = "ami-055bf27bf881fe1c5"
num_ephemeral_device    = "0"
subnet_ids              = ["subnet-0bcc62fd072a08b7e"]
infinia_version         = "2.2.16"
enable_public_ip        = "true"
infinia_deployment_name = "amirr"
root_device_size        = 256
num_infinia_instances   = "1"

