import argparse
from Terraform import TerraformVariableChecker, TerraformTfvarsGenerator, TerraformRunner

def parse_args():
    parser = argparse.ArgumentParser(description="Generate terraform.tfvars from variables.tf or user input")
    parser.add_argument("directory", help="Path to Terraform directory (must contain variables.tf)")
    parser.add_argument("--var", action="append", help='Define variable like --var "key=value"', default=[])
    parser.add_argument("--var-file", help="Use a custom tfvars file instead of generating one")
    parser.add_argument("--list-vars", action="store_true", help="List available variables from variables.tf")
    parser.add_argument("--run-terraform", action="store_true", help="Run terraform init and plan")
    parser.add_argument("--apply", action="store_true", help="Run terraform apply using plan output")
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

        if args.list_vars:
            checker = TerraformVariableChecker(args.directory)
            available_vars = checker.list_variables()
        else:
            tfvars_path = args.var_file

            if not tfvars_path:
                user_variables = parse_user_vars(args.var) if args.var else None
                tfvars_creator = TerraformTfvarsGenerator(args.directory)
                tfvars_path = tfvars_creator.create_tfvars_file(user_variables)

            runner = TerraformRunner(args.directory)

            if args.run_terraform:
                print("Running: terraform init")
                out, err = runner.run("init")
                print(out)
                if err:
                    print("Init Error:", err)

                print("Running: terraform plan")
                out, err = runner.run("plan", "-input=false", f"-var-file={tfvars_path}", "-out=tfplan")
                print(out)
                if err:
                    print("Plan Error:", err)
 
            if args.apply:
                print("Running: terraform apply")
                out, err = runner.run("apply", "-input=false", "tfplan")
                print(out)
                
                if "Saved plan is stale" in err:
                    print("⚠️ Plan is stale. Re-running plan and apply...")

                    print("Re-running: terraform plan")
                    out, err = runner.run("plan", "-input=false", f"-var-file={tfvars_path}", "-out=tfplan")
                    print(out)
                    if err:
                        print("Plan Error (retry):", err)
                        raise Exception("Re-plan failed")

                    print("Re-running: terraform apply")
                    out, err = runner.run("apply", "-input=false", "tfplan")
                    print(out)
                    if err:
                        print("Apply Error (retry):", err)
                        raise Exception("Re-apply failed")

                elif err:
                    print("Apply Error:", err)
                    raise Exception("Initial apply failed")


    except Exception as e:
        print(f"Error: {e}")

