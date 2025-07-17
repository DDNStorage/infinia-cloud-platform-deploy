# AMI Access Request

To provide you with access to the Infinia AMI, please provide:

1. **AWS Account ID**: Your 12-digit AWS account ID
2. **Deployment Region**: AWS region (e.g., us-east-1, us-west-2)
3. **Contact Email**: Contact DDN Sales

## After AMI Access is Granted

1. The AMI ID will be: `ami-xxxxxxxxx`
2. Update your `terraform.tfvars`:
   ```hcl
   infinia_ami_id = "ami-xxxxxxxxx"
   client_ami_id  = "ami-xxxxxxxxx"
   ```
3. Follow deployment instructions in `deployments/aws/README.md`

## Support
Contact: Contact DDN Sales