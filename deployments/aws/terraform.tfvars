aws_region        = "us-east-1"
vpc_id            = "vpc-0643ea52b06790437"
security_group_id = "sg-0514508ec0ae982b9"
key_pair_name     = "dev-keys"
#infinia_ami_id   = "ami-020cba7c55df1f615" #clean
infinia_ami_id = "ami-01eb4635e82858e09"      # cloud-init
subnet_ids     = ["subnet-06c1a6ccde3dec102"] #private
#subnet_ids            = ["subnet-0bcc62fd072a08b7e"] #public
infinia_version       = "2.2.37"
enable_public_ip      = "false"
root_device_size      = 256
num_infinia_instances = "6"
#instance_type_infinia = "i3en.2xlarge"
instance_type_infinia   = "m7a.2xlarge"
ebs_volume_size         = 128
infinia_deployment_name = "raidr"
bucket_name             = "terraform-dev-raid"
ebs_volumes_per_vm      = 4
use_ebs_volumes         = true



