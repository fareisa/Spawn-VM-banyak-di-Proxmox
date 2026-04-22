terraform {
    required_providers {
        proxmox = {
        source = "bpg/proxmox"
        }
    }
}

provider "proxmox" {
    endpoint  = "$endpoint"
    api_token = "$api_token"
    insecure  = true
}

locals {
    vms = $vms_json
}

resource "proxmox_virtual_environment_vm" "vm" {
    for_each = { for vm in local.vms : vm.name => vm }

    name      = each.value.name
    node_name = "$node"

    clone {
        vm_id = $template_id
    }

    cpu {
       cores = each.value.cores
    }

    memory {
        dedicated = each.value.memory
    }

    dynamic "disk" {
        for_each = each.value.disks
        content {
            datastore_id = disk.value.datastore
            interface    = disk.value.interface
            size         = disk.value.size
        }
    }

    dynamic "network_device" {
        for_each = each.value.network
        content {
            bridge = network_device.value.bridge
        }
    }

    initialization {
        user_account {
            username = each.value.user
            password = try(each.value.password, null)
            keys = try(each.value.ssh_keys, [])
        }

        dynamic "ip_config" {
            for_each = [
                for net in each.value.network : net
                if try(net.ip, null) != null
            ]
            content {
                ipv4 {
                    address = ip_config.value.ip
                    gateway = try(ip_config.value.gateway, null)
                }
            }
        }
    }


    agent {
        enabled = true
    }

    lifecycle {
        ignore_changes = [
        initialization
        ]
    }
}