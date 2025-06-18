import os
import re

import subprocess

class TerraformVariableChecker(object):
    def __init__(self, provider: str):
        provider_paths = {
            'gcp': os.path.join('..', '..', 'gcp'),
            'aws': os.path.join('..', '..', 'aws')
        }

        if provider not in provider_paths:
            raise ValueError("Provider must be either 'gcp' or 'aws'.")

        self.directory_path = provider_paths[provider]

        if not os.path.isdir(self.directory_path):
            raise FileNotFoundError(f"Directory '{self.directory_path}' not found.")

        self.variables_file = os.path.join(self.directory_path, "variables.tf")

    def list_variables(self):
        if not os.path.isfile(self.variables_file):
            raise FileNotFoundError(f"'variables.tf' not found in directory '{self.directory_path}'")

        with open(self.variables_file, 'r') as file:
            content = file.read()

        pattern = re.compile(r'variable\s+"([^"]+)"')
        variables = pattern.findall(content)

        if not variables:
            print("No variables found in variables.tf.")
        else:
            print("Terraform variables found:")
            for var in variables:
                print(f" - {var}")
        return variables


class TerraformTfvarsGenerator(object):
    def __init__(self, provider: str):
        provider_paths = {
            'gcp': os.path.join('..', '..', 'gcp'),
            'aws': os.path.join('..', '..', 'aws')
        }

        if provider not in provider_paths:
            raise ValueError("Provider must be either 'gcp' or 'aws'.")

        self.directory_path = provider_paths[provider]

        if not os.path.isdir(self.directory_path):
            raise FileNotFoundError(f"Directory '{self.directory_path}' not found.")

        self.tfvars_file = os.path.join(self.directory_path, "terraform.tfvars")
        self.provider = provider
       
    def create_tfvars_file(self, variables: dict={}):
        defaults = {}

        if self.provider == "aws":
            defaults = {
                "aws_region": "us-east-1",
                "vpc_id": "vpc-02adcd19590b5bbd0",
                "security_group": "sg-0de3d39aa32fc75d3",
                "key_pair_name": "red-poc-keys",
                "infinia_ami_id": "ami-08391efc712c82150"
            }
        elif self.provider == "gcp":
            defaults = {
                "zone": "us-central1-a",
                "project_id": "red-101",
                "desired_capacity": "9"
            }

        merged = defaults.copy()
        if variables:
            merged.update(variables)

        # Write to terraform.tfvars
        lines = [f'{key} = "{value}"' for key, value in merged.items()]

        with open(self.tfvars_file, 'w') as f:
            f.write('\n'.join(lines))

        print(f"terraform.tfvars created at {self.tfvars_file}")


    
class TerraformRunner(object):
    def __init__(self, terraform_dir: str):
        self.terraform_dir = terraform_dir

    def run(self, command: str, *args: str):
        """
        Run a terraform command with optional arguments.

        :param command: Terraform command (e.g., 'init', 'plan', 'apply')
        :param args: Additional arguments for the command
        :return: (stdout, stderr)
        """
        full_cmd = ["terraform", f"-chdir={self.terraform_dir}", command] + list(args)

        try:
            result = subprocess.run(
                full_cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=True,
                text=True
            )
            return result.stdout, result.stderr
        except subprocess.CalledProcessError as e:
            return e.stdout, e.stderr


