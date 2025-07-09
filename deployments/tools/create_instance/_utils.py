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

