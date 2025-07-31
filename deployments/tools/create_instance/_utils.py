#!/usr/bin/env python
import shutil
import os

def terrafrom_cleanup(directory):
    terraform_dir = os.path.join(directory, '.terraform')
    
    if os.path.exists(terraform_dir) and os.path.isdir(terraform_dir):
        try:
            shutil.rmtree(terraform_dir)
            print(f"Removed .terraform directory in {directory}")
        except Exception as e:
            print(f"Failed to remove .terraform directory: {e}")
    else:
        print(f"No .terraform directory found in {directory}")


from jinja2 import Template

def manipulate_terraform_s3_backend(terraform_config_str: str, new_backend_args: dict = {}) -> str:
    terraform_template_str = """
terraform {
  backend "s3" {
    bucket = "{{ bucket }}"
    key    = "{{ key }}"
    region = "{{ region }}"
  }
}
"""
    template = Template(terraform_template_str)

    # Dictionary to store parsed values from the input string
    parsed_config = {}

    # Regex to extract bucket, key, and region from the input Terraform string
    # re.search finds the first match. re.DOTALL makes '.' match newlines.
    bucket_match = re.search(r'bucket\s*=\s*"(.*?)"', terraform_config_str, re.DOTALL)
    key_match = re.search(r'key\s*=\s*"(.*?)"', terraform_config_str, re.DOTALL)
    region_match = re.search(r'region\s*=\s*"(.*?)"', terraform_config_str, re.DOTALL)

    if bucket_match:
        parsed_config['bucket'] = bucket_match.group(1)
    if key_match:
        parsed_config['key'] = key_match.group(1)
    if region_match:
        parsed_config['region'] = region_match.group(1)

    # Merge parsed_config with new_backend_args.
    # Values from new_backend_args will override values from parsed_config if keys are the same.
    final_config = {**parsed_config, **(new_backend_args if new_backend_args else {})}

    # Ensure all required keys for the template are present, even if empty
    # This prevents Jinja2 from throwing errors if a key is missing.
    final_config.setdefault('bucket', 'default-bucket')
    final_config.setdefault('key', 'default/state.tfstate')
    final_config.setdefault('region', 'us-east-1')

    # Render the Jinja2 template with the final configuration
    rendered_terraform = template.render(final_config)

    return rendered_terraform.strip() # .strip() removes leading/trailing whitespace/newlines

