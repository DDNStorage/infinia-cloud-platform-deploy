# Infinia Setup and Configuration - Ansible Playbook

This Ansible playbook automates the setup and configuration of Infinia nodes and clusters. It includes tasks for downloading scripts, setting up realm and non-realm nodes, and configuring the Infinia cluster.

---

## Prerequisites

Before using this playbook, ensure you have the following:

- **Ansible (Version 2.9 or Higher)**
📌 [Installation Guide](https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html)  

- **Python (Version 3.x Recommended)**
📌 [Official Download](https://www.python.org/downloads/)  
📌 [Installation Guide](https://realpython.com/installing-python/)  

-  **Session Manager Plugin for the AWS CLI (Version 1.2.694.0 or Higher)**
📌 [Installation Guide](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html)  
- Access to the target hosts (via SSH or AWS SSM).
- Required scripts (`infinia-node-setup.sh` and `infinia-cluster-configure.sh`) available locally or via URLs.

---

## Project Structure

The project directory should look like this:
```
.
├── README.md
├── main.yml # Main playbook
├── aws_ec2.yml # Inventory file
├── vars.yml # Non-sensitive variables
├── secret.yml # Sensitive variables (encrypted with Ansible Vault)
├── infinia-cluster-configure.sh # Local script for cluster configuration
```

---

## Variables

### `vars.yml`
This file contains non-sensitive variables used in the playbook. Example:

```yaml
infinia_version: 1.3.36
ansible_aws_ssm_bucket_name: red-ansible-scripts
ansible_aws_ssm_region: us-east-1
ansible_aws_ssm_timeout: 3600

### `secret.yml`
This file contains sensitive variables encrypted with Ansible Vault. Example:

```yaml
realm_secret: "PA-ssW00r^d"
admin_password: "PA-ssW00r^d"
license_key: "XXXXXXXXXXXXXXXXXXX"
```

## Usage

### 1. Update Inventory
The `aws_ec2.yml` file does not require specific IP addresses or hostnames to be filled in. Instead, it automatically searches for inventory hosts based on the tag Role.

```yaml
plugin: aws_ec2
regions:
  - us-east-1
filters:
  tag:Role: ['realm', 'nonrealm']  # Include only instances with these roles
keyed_groups:
  - prefix: role
    key: tags['Role']
hostnames:
  - instance-id
```

### 2. Run the Playbook
```bash
ansible-playbook main.yml -i aws_ec2.yml --ask-vault-pass
```

### Tags
You can run specific parts of the playbook using tags
- **Download scripts**:
  ```bash
  ansible-playbook main.yml -i inventory.yml --tags download
  ```
- **Setup nodes**:
  ```bash
  ansible-playbook main.yml -i inventory.yml --tags setup
  ```
- **Configure cluster**:
  ```bash
  ansible-playbook main.yml -i inventory.yml --tags configure
  ```

## Encryption with Ansible Vault
Sensitive data in secret.yml is encrypted using Ansible Vault. To edit the encrypted file, use:

```bash
ansible-vault edit secret.yml
```
To decrypt the file (e.g., for debugging):
```bash
ansible-vault decrypt secret.yml
```