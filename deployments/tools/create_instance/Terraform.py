import os
import re

import subprocess

class TerraformManager(object):
    def __init__(self, provider: str):
        provider_paths = {
            'gcp': os.path.join('..', '..', 'gcp'),
            'aws': os.path.join('..', '..', 'aws')
        }

        if provider not in provider_paths:
            raise ValueError("Provider must be either 'gcp' or 'aws'.")

        self.provider = provider
        self.directory_path = provider_paths[provider]

        if not os.path.isdir(self.directory_path):
            raise FileNotFoundError(f"Directory '{self.directory_path}' not found.")

        self.variables_file = os.path.join(self.directory_path, "variables.tf")
        self.tfvars_file = os.path.join(self.directory_path, "terraform.tfvars")

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

    def create_tfvars_file(self, variables: dict = {}):
        defaults = {}

        if self.provider == "aws":
            defaults = {
                "aws_region": "us-east-1",
                "vpc_id": "vpc-0643ea52b06790437",
                "security_group_id": "sg-0514508ec0ae982b9",
                "key_pair_name": "dev-keys",
                "infinia_ami_id": "ami-055bf27bf881fe1c5",
                "num_ephemeral_device": "0",
                "subnet_ids": ['subnet-0d359ef1e9d5e45be'],
                "infinia_version": "2.2.16",
                "enable_public_ip": "false",
            }
        elif self.provider == "gcp":
            defaults = {
                "zone": "us-central1-a",
                "project_id": "red-101",
                "desired_capacity": "9"
            }

        merged = defaults.copy()
        merged.update(variables)

        lines = []
        for key, value in merged.items():
            if isinstance(value, list):
                formatted_list = "[" + ", ".join(f'"{item}"' for item in value) + "]"
                lines.append(f'{key} = {formatted_list}')
            else:
                lines.append(f'{key} = "{value}"')

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


