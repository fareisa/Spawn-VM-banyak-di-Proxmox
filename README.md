# Multiple VM spawn with Terraform on Proxmox

This project is created because i have issue with proxmox for spawning multiple vm. Its awful even with terminal execution. This script using Terraform as tool for generate a vm as code and use bpg/proxmox latest version for provider (last trying with version v0.103.0). For base vm itself, i use template because it can be more costumizable, example for qemu agent is need a service that installed in client side, so we need to download it in vm first and after its installed we can make it as a template, so vm-template already have `qemu-guest-agent` pre-installed.

## Project Structure

- **main-tf.tpl** - Terraform template with placeholders for Proxmox provider and VM resources
- **tfgen.sh** - Default template generator (automated, quick setup)
- **tfgen-1.sh** - Interactive template generator (manual configuration with validation support)
- **vm.yaml** - Example configuration file for VM definitions

## Quick Start

### Prerequisites

- Terraform installed
- `yq` CLI tool for YAML parsing
- `envsubst` for template substitution
- Proxmox API credentials
- Vm template

### Option 1: Default Generator (tfgen.sh)

The simplest. Reads `vm.yaml` and generates Terraform automatically.

```bash
chmod +x tfgen.sh
./tfgen.sh
```

**How it works:**
1. Reads `vm.yaml` in the current directory
2. Extracts Proxmox configuration and VM definitions
3. Renders `main-tf.tpl` with the extracted values
4. Outputs `main.tf` in a project-named subdirectory

**Output:**
```
./[project_name]/main.tf
```

**Default values**
- INPUT="vm.yaml"
- OUTPUT_DIR="."
- TEMPLATE="main.tf.tpl"

### Option 2: Interactive Generator (tfgen-1.sh)

Other option with validation and flexibility. Allows specifying custom input/output paths and other things.

```bash
chmod +x tfgen-1.sh
./tfgen-1.sh -i vm.yaml -f
```

**Command-line Options:**

| Option | Description |
| --- | --- |
| `-i, --input FILE` | Path to input YAML file (required) |
| `-o, --output DIR` | Output directory (default: `./`) |
| `-t, --template FILE` | Template file (default: `./main.tf.tpl`) |
| `-f, --force` | Overwrite output without ask for confirmation |
| `-h, --help` | Show help message |

**Example with custom template:**
```bash
./tfgen-1.sh -i config.yaml -t custom.tpl -f
```

**How it works:**
1. Parses and validates entire YAML structure
2. Checks all required fields per VM
3. Detects duplicate VM names
4. Validates disk interfaces (no duplicates)
5. Validates network configuration (max 1 gateway per VM, multiple DHCP, DHCP mix with gateway)
6. Ask for confirmation before overwriting existed directory-project-name
7. Renders template with validated values
8. Outputs `./[project_name]/main.tf`

**Default values**
- INPUT=""
- OUTPUT_DIR="."
- FORCE=false
- TEMPLATE="main.tf.tpl"

## Configuration File (vm.yaml)

### Top-level Fields

```yaml
project_name: <project-name>        # Directory name for generated `main.tf`

proxmox:
  endpoint: "https://<host>:8006/api2/json"  # Proxmox API endpoint
  api_token: "root@pam!<id>=<token>"         # API token from Proxmox
  node: "pve-core"                           # Proxmox node name
  template_id: <id>                          # VM template ID to clone

vms: []                              # Array of VM definitions
```

### VM Definition Fields

```yaml
vms:
  - name: vm-name                    # VM name (must be unique)
    cores: 2                         # vCPU cores
    memory: 2048                     # RAM in MB
    user: ubuntu                     # Default user account
    password: ubuntu                 # user password for console access
    ssh_keys:                        # SSH public keys (required for remote access)
      - "<ssh-pubKey>"
    
    disks:                           # Disk interfaces
      - datastore: local-lvm         # Datastore ID (From Proxmox resource target)
        interface: scsi0             # Disk interface (must be unique per VM)
        size: 20                     # Size in GB
    
    network:                         # Network interfaces
      - bridge: vmbr0                # Available virtual bridge
        ip: dhcp                     # IP config (dhcp, IP/CIDR, Max 1 DHCP per VM)
        gateway: 192.168.1.1         # Gateway (max 1 per VM)
```

### Available Fields per VM

- `name` - VM name (unique)
- `cores` - Number of CPU cores
- `memory` - RAM in GB
- `user` - Default system user
- `disks` - Array of disk configurations (unique per disk-interface)
- `network` - Array of network configurations (unique per network-interface)
- `password` - User password
- `ssh_keys` - Array of SSH public keys
- `ip` - IP configuration (DHCP, CIDR, default value null)
- `gateway` - Default gateway (max 1 per VM)

## Template File (main-tf.tpl)

The Terraform template uses the following placeholders (replaced by generators and get value from vm.yaml):

| Placeholder | Source | Type |
| --- | --- | --- |
| `$endpoint` | `proxmox.endpoint` | String |
| `$api_token` | `proxmox.api_token` | String |
| `$node` | `proxmox.node` | String |
| `$template_id` | `proxmox.template_id` | Number |
| `$vms_json` | `.vms` array | JSON |

**Dynamic Blocks:**
- `disk` - Iterates over `disks` array per VM
- `network_device` - Iterates over `network` array per VM
- `ip_config` - Iterates over network interfaces with `ip` config

## Example Workflow

1. **Create configuration:**
   ```bash
   cp vm.yaml my-project.yaml
   # Edit my-project.yaml with your values
   ```

2. **Generate Terraform (using the interactive one):**
   ```bash
   ./tfgen-1.sh -i my-project.yaml -o . -f
   ```

3. **Apply Terraform:**
   ```bash
   cd ./my-project
   terraform init
   terraform plan
   terraform apply
   ```

## Proxmox Setup

### Set user for API 

1. Log in to Proxmox web UI
2. Go to **Datacenter** > **Users**
3. Click **Add** and create a new user (example `terraform@pam`)
4. Go to **Datacenter** > **groups**
5. Click **Create** and create a new group (example `terraform`)
6. Go to **Datacenter** AGAIN > **roles**
7. Click **Create** and create a new role (example `terraform`) with these privileges:
   - Datastore.AllocateSpace
   - Datastore.Audit
   - SDN.Use
   - VM.Allocate
   - VM.Audit
   - VM.Clone
   - VM.Config.CDROM
   - VM.Config.CPU
   - VM.Config.Cloudinit
   - VM.Config.Disk
   - VM.Config.HWType
   - VM.Config.Memory
   - VM.Config.Network
   - VM.Config.Options
   - VM.Console
   - VM.GuestAgent.Audit
   - VM.GuestAgent.Unrestricted
   - VM.PowerMgmt
8. Go to **Datacenter** too > **permissions**
9. Click **Add** and set **Path** to `/`, **Group** to `terraform` group, **Role** to `terraform` role, and check **Propagate**
10. Go to **Datacenter** *last > **user**
11. Click on the `terraform` user to open it
12. Click **Add** and add the `terraform` group for user
13. Go to **Datacenter** rill-last > **API Tokens**
14. Click **Add** to create a token for the `terraform@pam` user and set **Token ID** (example `terraform`), uncheck `Privilege Separation`
15. Copy and store the token 

### See VM template

1. In Proxmox web UI, go to **Nodes** → **[node-name]**
2. Find your VM template in the list
3. Note the VMID (numeric ID)

## Validation Rules on interactive generator (tfgen-1.sh)

The `tfgen-1.sh` performs these validation:

| Check | Rule |
| --- | --- |
| Required fields | All top-level and VM fields are required |
| Disk interfaces | Must be unique per VM |
| Gateways | Maximum 1 gateway per VM |
| DHCP | Maximum 1 DHCP and cannot be mixed with gateway |
| VM names | Must be unique across all VMs |
| File existence | Input file and template must exist |


## Advanced Usage

### Custom Template

You can modify `main-tf.tpl` to customize:
- Resource types
- Provider configuration
- Dynamic blocks
- Lifecycle rules

Then use:
```bash
./tfgen-1.sh -i vm.yaml -o . -t custom.tpl

#Or change 'TEMPLATE' variable on non-interactive generator (tfgen.sh)
```

## References

- [Terraform Dynamic Blocks](https://developer.hashicorp.com/terraform/language/expressions/dynamic-blocks)
- [Terraform Proxmox Provider (bpg/proxmox) Documentation](https://registry.terraform.io/providers/bpg/proxmox/latest/docs)
- [Provisioning Proxmox Virtual Machines with Terraform](https://medium.com/@DatBoyBlu3/provisioning-proxmox-virtual-machines-with-terraform-d9e9c549f947)
- [Proxmox VM Template](https://gist.github.com/zidenis/dfc05d9fa150ae55d7c87d870a0306c5)
- [Pipefail Explanation](https://gist.github.com/mohanpedala/1e2ff5661761d3abd0385e8223e16425?permalink_comment_id=3799230)

## For Next

maybe add some intruction for create template?


