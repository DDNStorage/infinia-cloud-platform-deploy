import os
import re

import subprocess


class TerraformVariableChecker:
    def __init__(self, directory_path):
        if not os.path.isdir(directory_path):
            raise FileNotFoundError(f"Directory '{directory_path}' not found.")
        self.directory_path = directory_path
        self.variables_file = os.path.join(directory_path, "variables.tf")

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

class TerraformTfvarsGenerator:
    def __init__(self, directory_path):
        if not os.path.isdir(directory_path):
            raise FileNotFoundError(f"Directory '{directory_path}' not found.")
        self.directory_path = directory_path
        self.tfvars_file = os.path.join(directory_path, "terraform.tfvars")

    def create_tfvars_file(self, variables: dict = {}):
        lines = []

        if variables:
            for key, value in variables.items():
                lines.append(f'{key} = "{value}"')
        else:
            dir_lower = self.directory_path.lower()
            if "aws" in dir_lower:
                lines.append('aws_region = "us-east-1"')
            elif "gcp" in dir_lower:
                lines.append('zone = "us-central1"')
            else:
                lines.append('# No variables provided and no default cloud detected')

        with open(self.tfvars_file, 'w') as f:
            f.write('\n'.join(lines))

        print(f"terraform.tfvars created at {self.tfvars_file}")


class TerraformRunner:
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

