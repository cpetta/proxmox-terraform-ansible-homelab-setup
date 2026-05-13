#-------------------------------------------------------
# Talos Control Plain Nodes
#-------------------------------------------------------
resource "proxmox_virtual_environment_vm" "k8cp" {
  for_each            = { for i, v in var.k8_control_plain_list : i => v }
  name                = each.value.name
  node_name           = each.value.host_node
  description         = "Managed by Terraform"
  tags                = ["terraform"]
  started             = true
  on_boot             = true
  reboot_after_update = true
  bios                = "ovmf"
  machine             = "q35,viommu=virtio"

  cpu {
    cores = each.value.cpu
    type  = "host"
  }
  rng {
    max_bytes = 1024
    period    = 1000
    source    = "/dev/urandom"
  }
  memory {
    dedicated = each.value.ram
    floating  = 0
  }
  disk {
    datastore_id = "local-lvm"
    file_format  = "raw"
    file_id      = "local:iso/talos-v${each.value.talos_v}-nocloud-amd64.iso"
    interface    = "scsi0"
    discard      = "on"
    size         = 20
  }
  efi_disk {
    datastore_id      = "local-lvm"
    file_format       = "raw"
    pre_enrolled_keys = false
    type              = "4m"
  }
  tpm_state {
    datastore_id = "local-lvm"
    version      = "v2.0"
  }

  initialization {
    datastore_id      = "local-lvm"
    user_data_file_id = proxmox_virtual_environment_file.k8cp_cloud_config[each.key].id

    ip_config {
      ipv4 {
        address = "${each.value.ip_address}/24"
        gateway = var.gateway_ip
      }
    }
    dns {
      servers = [for server in var.dns_server_list : server.ip_address]
    }
  }

  network_device {
    bridge = "vmbr0"
    model  = "virtio"
  }

  agent {
    enabled = true
  }

  startup {
    down_delay = -1
    order      = -1
    up_delay   = -1
  }

  lifecycle {
    ignore_changes = [
      initialization,
      started,
      startup,
    ]
  }
}

#-------------------------------------------------------
# Talos Storage Nodes
#-------------------------------------------------------
resource "proxmox_virtual_environment_vm" "k8s" {
  for_each            = { for i, v in var.k8_storage_node_list : i => v }
  name                = each.value.name
  node_name           = each.value.host_node
  description         = "Managed by Terraform"
  tags                = ["terraform"]
  started             = true
  on_boot             = true
  reboot_after_update = true
  bios                = "ovmf"
  machine             = "q35,viommu=virtio"

  cpu {
    cores = each.value.cpu_cores
    type  = "host"
  }
  rng {
    max_bytes = 1024
    period    = 1000
    source    = "/dev/urandom"
  }
  memory {
    dedicated = each.value.ram
    floating  = 0 # set equal to dedicated to enable ballooning
  }
  disk {
    datastore_id = "local-lvm"
    file_format  = "raw"
    file_id      = proxmox_virtual_environment_download_file.talos_boot_image_storage[each.value.host_node].id
    interface    = "scsi0"
    discard      = "on"
    size         = each.value.disk_space
    ssd          = true
    replicate    = false
  }
  dynamic "disk" {
    for_each = { for i, v in each.value.extra_disks : i => v }
    iterator = disk
    content {
      datastore_id = disk.value["datastore_id"]
      size         = disk.value["size"]
      ssd          = disk.value["ssd"]
      interface    = "scsi${disk.key + 1}"
      replicate    = false
    }
  }
  efi_disk {
    datastore_id      = "local-lvm"
    file_format       = "raw"
    pre_enrolled_keys = false
    type              = "4m"
  }

  initialization {
    datastore_id      = "local-lvm"
    user_data_file_id = proxmox_virtual_environment_file.k8w_cloud_config_storage[each.key].id

    ip_config {
      ipv4 {
        address = "${each.value.ip_address}/24"
        gateway = var.gateway_ip
      }
    }
    dns {
      servers = [for server in var.dns_server_list : server.ip_address]
    }
  }

  network_device {
    bridge = "vmbr0"
    model  = "virtio"
  }

  agent {
    enabled = true
  }

  startup {
    down_delay = -1
    order      = -1
    up_delay   = -1
  }

  lifecycle {
    ignore_changes = [
      started,
      startup,
    ]
  }
}