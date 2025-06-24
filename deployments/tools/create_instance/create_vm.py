#!/usr/bin/env python

import argparse
import os


from Terraform import TerraformManager,TerraformRunner
from _utils import terrafrom_cleanup

def parse_args():
    parser = argparse.ArgumentParser(description="Generate terraform.tfvars from variables.tf or user input")
    parser.add_argument(
        "provider",
        choices=["gcp", "aws"],
        help="Target cloud provider (gcp or aws)"
    )
    parser.add_argument(
        "--var",
        action="append",
        help='Define variable like --var "key=value"',
        default=[]
    )
    parser.add_argument(
        "--list-vars",
        action="store_true",
        help="List available variables from variables.tf"
    )
    parser.add_argument(
        "--deploy",
        action="store_true",
        help="Deploy target cluster"
    )
    parser.add_argument(
        "--destroy",
        action="store_true",
        help="Destroy cluster"
    )

    return parser.parse_args()

def parse_user_vars(var_args):
    variables = {}
    for var in var_args:
        if "=" not in var:
            raise ValueError(f"Invalid format for variable: '{var}'. Expected format is key=value.")
        key, value = var.split("=", 1)
        variables[key.strip()] = value.strip()
    return variables

if __name__ == "__main__":
    try:
        args = parse_args()
        provider = args.provider
        provider_paths = {
            'gcp': os.path.join('..', '..', 'gcp'),
            'aws': os.path.join('..', '..', 'aws')
        }
        directory = provider_paths[provider]

        if args.list_vars:
            checker = TerraformManager(provider)
            available_vars = checker.list_variables()
        if args.var: 
            user_variables = parse_user_vars(args.var)
            tfvars_creator = TerraformManager(provider)
            tf_vars = tfvars_creator.create_tfvars_file(user_variables)
 
        if args.deploy:
            runner = TerraformRunner(directory)

            out, err = runner.run("init")
            print(out)
            if err:
                print("Init Error:", err)

            out, err = runner.run("plan", "-input=false", "-out=tfplan", "-var-file=terraform.tfvars")
            print(out)
            if err:
                print("Plan Error:", err)

            print("Deploying cluster")
            out, err = runner.run("apply", "-input=false", "tfplan")
            print(out)
            if err:
                print("Apply Error:", err)
        if args.destroy:
            runner = TerraformRunner(directory)
            print("Destroying cluster")
            out, err = runner.run("destroy", "-auto-approve", "-input=false")
            print(out)
            if err:
                print("Apply Error:", err)
            else:
                terrafrom_cleanup(directory)

    except Exception as e:
        print(f"Error: {e}")

