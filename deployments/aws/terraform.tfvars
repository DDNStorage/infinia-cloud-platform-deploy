infinia_deployment_name = "demo"
aws_region         = "us-east-1"
vpc_id             = "vpc-07077509cd5b0bbfd"
subnet_ids         = ["subnet-00c82fa683b0b31d8", "subnet-05c8a5c5a03e5e2e9"]
security_group_id  = "sg-0dbea165c6fa823cb"
infinia_ami_id     = "ami-0e2c8caa4b6378d8c"
client_ami_id      = "ami-0e2c8caa4b6378d8c"
num_infinia_instances = 2
num_client_instances  = 1
key_pair_name = "my-key-pair"
instance_type_infinia = "i3en.12xlarge"    # Override with your desired instance type
instance_type_client  = "t3.large"         # Override with your desired instance type
