# Infinia Node Setup

A bash script for deploying and configuring realm entry and non-realm entry nodes.

## Prerequisites

- Ubuntu 24.04
- `sudo` privileges
- Internet connectivity to access the package repository
- `wget` and `dpkg` installed

## Installation

1. Download the scripts from Google Cloud Storage:
```bash
wget https://storage.googleapis.com/ddn-redsetup-public/deployment-scripts/infinia-node-setup.sh
wget https://storage.googleapis.com/ddn-redsetup-public/deployment-scripts/infinia-cluster-configure.sh
```

2. Make them executable:
```bash
chmod +x infinia-node-setup.sh infinia-cluster-configure.sh
```

## Usage

```bash
./infinia-node-setup.sh [-r|--realm-entry] [-n|--non-realm-entry] [-i|--ip IP_ADDRESS] [-v|--version VERSION] [-s|--realm-secret SECRET] [-p|--admin-password PASSWORD]
```

### Options

- `-r, --realm-entry`: Configure as realm entry node
- `-n, --non-realm-entry`: Configure as non-realm entry node
- `-i, --ip`: Realm entry IP address (mandatory with --non-realm-entry)
- `-v, --version`: RedSetup version (mandatory for both realm entry and non-realm entry nodes)
- `-s, --realm-secret`: Realm entry secret (optional, default: PA-ssW00r^d)
- `-p, --admin-password`: Admin password (optional, default: PA-ssW00r^d)
- `--skip-reboot`: Skip automatic reboot after installation (optional)

### Examples

1. Deploy a realm entry node with default passwords:
```bash
./infinia-node-setup.sh --realm-entry --version 1.3.37
# or
./infinia-node-setup.sh -r -v 1.3.37
```

2. Deploy a realm entry node with custom passwords:
```bash
./infinia-node-setup.sh -r -v 1.3.37 --realm-secret "MySecret123" --admin-password "AdminPass456"
```

3. Deploy a non-realm entry node:
```bash
./infinia-node-setup.sh --non-realm-entry --ip 172.31.37.198 --version 1.3.37
# or
./infinia-node-setup.sh -n -i 172.31.37.198 -v 1.3.37
```

## Validation Rules

- Cannot specify both realm-entry and non-realm-entry options
- Must specify either realm-entry or non-realm-entry option
- IP address is mandatory when using non-realm-entry option
- Version is mandatory for both realm entry and non-realm entry nodes

## What the Script Does

1. Validates input parameters
2. Sets up common environment variables
3. Downloads and installs redsetup package
4. Configures the node based on the specified type:
   - For realm entry nodes: Downloads template, configures with realm entry settings
   - For non-realm entry nodes: Configures with provided realm entry IP

## Error Handling

The script will display usage information and exit if:
- Required parameters are missing
- Conflicting options are provided
- Invalid options are used

## Default Values

- Base Package URL: `https://storage.googleapis.com/ddn-redsetup-public`
- Distribution Path: `ubuntu/24.04`
- Architecture: Automatically detected using `dpkg`
- Realm Entry Secret: PA-ssW00r^d (if not specified)
- Admin Password: PA-ssW00r^d (if not specified)

# Cluster Configuration

After setting up a realm entry node using `infinia-node-setup.sh`, use the following script to configure the cluster:

## Cluster Configuration Script

The `infinia-cluster-configure.sh` script handles post-deployment cluster configuration.

### Prerequisites

- Node must be successfully deployed using `infinia-node-setup.sh`
- Valid license key required

### Usage

```bash
./infinia-cluster-configure.sh [-h|--help]
```

### Options

- `-h, --help`: Display help message

The script will interactively prompt for:
- Realm admin password
- License key

### What the Script Does

1. Prompts for credentials:
   - Realm admin password (hidden input)
   - License key
2. Performs cluster configuration:
   - Logs in as realm admin
   - Generates and updates realm configuration
   - Installs the provided license
   - Creates and configures the cluster
   - Displays cluster information

### Note

This script must only be run once after successful deployment.
