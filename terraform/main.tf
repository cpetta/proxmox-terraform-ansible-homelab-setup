terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.97.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "2.4.0"
    }
  }
}

variable "local" {
  type = bool
  default = false
}

variable "cipassword" {}
variable "cipassword_hash" {}
variable "ssh_public_key" {}
variable "pm_api_token" {}
variable "pm_api_url" {}
variable "pm_api_url_remote" {}
variable "pm_pasword" {}
variable "tailscale_auth_key" {}

variable "gateway_ip" {}

variable "pm1_ip" {}
variable "pm2_ip" {}
variable "pm3_ip" {}

variable "dns1_ip" {}
variable "dns2_ip" {}
variable "dns3_ip" {}

variable "pfs1_ip" {}

provider "proxmox" {
  endpoint = var.local ? var.pm_api_url : var.pm_api_url_remote
  api_token = var.pm_api_token
  username = "root@pam"
  password = var.pm_pasword
  insecure = true
  
  ssh {
    username = "root"
    password = var.pm_pasword
    private_key = file("../ssh/private_key")
    agent    = true

    node {
      name    = "pm1"
      address = var.local ? var.pm1_ip : "pm1"
    }
    node {
      name    = "pm2"
      address = var.local ? var.pm2_ip : "pm2"
    }
    node {
      name    = "pm3"
      address = var.local ? var.pm3_ip : "pm3"
    }
  }
}

#-------------------------------------------------------
# Cloud Image Resources
#-------------------------------------------------------
resource "proxmox_virtual_environment_download_file" "ubuntu_cloud_image_1" {
  content_type = "import"
  datastore_id = "local"
  node_name    = "pm1"
  url          = "https://cloud-images.ubuntu.com/minimal/releases/noble/release/ubuntu-24.04-minimal-cloudimg-amd64.img"
  file_name    = "ubuntu-24.04-minimal-cloudimg-amd64.img.qcow2" # rename to *.qcow2 for import
  overwrite    = false
  overwrite_unmanaged = true
}

resource "proxmox_virtual_environment_download_file" "ubuntu_cloud_image_2" {
  content_type = "import"
  datastore_id = "local"
  node_name    = "pm2"
  url          = "https://cloud-images.ubuntu.com/minimal/releases/noble/release/ubuntu-24.04-minimal-cloudimg-amd64.img"
  file_name    = "ubuntu-24.04-minimal-cloudimg-amd64.img.qcow2" # rename to *.qcow2 for import
  overwrite    = false
  overwrite_unmanaged = true
}

resource "proxmox_virtual_environment_download_file" "ubuntu_cloud_image_3" {
  content_type = "import"
  datastore_id = "local"
  node_name    = "pm3"
  url          = "https://cloud-images.ubuntu.com/minimal/releases/noble/release/ubuntu-24.04-minimal-cloudimg-amd64.img"
  file_name    = "ubuntu-24.04-minimal-cloudimg-amd64.img.qcow2" # rename to *.qcow2 for import
  overwrite    = false
  overwrite_unmanaged = true
}

#-------------------------------------------------------
# dns1
#-------------------------------------------------------
variable "dns1_target" {
  type = string
  default = "pm2"
}

resource "local_file" "dns1_snippet" {
  content = templatefile("${path.module}/cloud-init/templates/dns.tftpl", {
    hostname           = "dns1"
    tailscale_auth_key = var.tailscale_auth_key
    cipassword_hash    = var.cipassword_hash
    ssh_public_key     = var.ssh_public_key
  })
  filename = "${path.module}/cloud-init/tmp/dns1.yml"
}

resource "proxmox_virtual_environment_file" "dns1_cloud_config" {
  depends_on  = [resource.local_file.dns1_snippet]
  content_type = "snippets"
  datastore_id = "local"
  node_name    = var.dns1_target
  source_file {
    path = resource.local_file.dns1_snippet.filename
  }
}

resource "proxmox_virtual_environment_vm" "dns1" {
  vm_id        = 101
  name        = "dns1"
  node_name   = var.dns1_target
  description = "Managed by Terraform"
  tags        = ["terraform", "ubuntu"]
  started = true
  on_boot = true
  reboot_after_update = true

  cpu {
    cores = 1
    type  = "host"
  }
  memory {
    dedicated = 2048
    floating  = 2048 # set equal to dedicated to enable ballooning
  }
  disk {
    datastore_id = "local-lvm"
    import_from  = proxmox_virtual_environment_download_file.ubuntu_cloud_image_2.id
    interface    = "scsi0"
    discard      = "on"
    size         = 10
  }
  
  initialization {
    datastore_id = "local-lvm"
    user_data_file_id   = proxmox_virtual_environment_file.dns1_cloud_config.id

    ip_config {
      ipv4 {
        address = "${var.dns1_ip}/24"
        gateway = var.gateway_ip
      }
    }
    dns {
      servers = ["9.9.9.9", "1.1.1.1",  "1.0.0.1"]
    }
  }

  network_device {
    bridge = "vmbr0"
    model = "virtio"
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
      startup
    ]
  }
}

#-------------------------------------------------------
# DNS2
#-------------------------------------------------------
variable "dns2_target" {
  type = string
  default = "pm3"
}

resource "local_file" "dns2_snippet" {
  content = templatefile("${path.module}/cloud-init/templates/dns.tftpl", {
    hostname           = "dns2"
    tailscale_auth_key = var.tailscale_auth_key
    cipassword_hash    = var.cipassword_hash
    ssh_public_key     = var.ssh_public_key
  })
  filename = "${path.module}/cloud-init/tmp/dns2.yml"
}

resource "proxmox_virtual_environment_file" "dns2_cloud_config" {
  depends_on  = [resource.local_file.dns2_snippet]
  content_type = "snippets"
  datastore_id = "local"
  node_name    = var.dns2_target
  source_file {
    path = resource.local_file.dns2_snippet.filename
  }
}

resource "proxmox_virtual_environment_vm" "dns2" {
  vm_id        = 102
  name        = "dns2"
  node_name   = var.dns2_target
  description = "Managed by Terraform"
  tags        = ["terraform", "ubuntu"]
  started = true
  on_boot = true
  reboot_after_update = true

  cpu {
    cores = 1
    type  = "host"
  }
  memory {
    dedicated = 2048
    floating  = 2048 # set equal to dedicated to enable ballooning
  }
  disk {
    datastore_id = "local-lvm"
    import_from  = proxmox_virtual_environment_download_file.ubuntu_cloud_image_3.id
    interface    = "scsi0"
    discard      = "on"
    size         = 10
  }
  
  initialization {
    datastore_id = "local-lvm"
    user_data_file_id   = proxmox_virtual_environment_file.dns2_cloud_config.id

    ip_config {
      ipv4 {
        address = "${var.dns2_ip}/24"
        gateway = var.gateway_ip
      }
    }
    dns {
      servers = ["9.9.9.9", "1.1.1.1",  "1.0.0.1"]
    }
  }

  network_device {
    bridge = "vmbr0"
    model = "virtio"
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
      startup
    ]
  }
}

#-------------------------------------------------------
# PF Sense 1
#-------------------------------------------------------
// Reference https://atxfiles.netgate.com/mirror/downloads/
resource "proxmox_virtual_environment_download_file" "pf_sense_iso_2" {
  content_type = "iso"
  datastore_id = "local"
  node_name    = "pm2"
  url          = "https://atxfiles.netgate.com/mirror/downloads/pfSense-CE-2.7.2-RELEASE-amd64.iso.gz"
  file_name    = "pfSense-CE-2.7.2-RELEASE-amd64.iso" # rename to *.iso for import
  overwrite    = false
  overwrite_unmanaged = true
  checksum = "883fb7bc64fe548442ed007911341dd34e178449f8156ad65f7381a02b7cd9e4"
  checksum_algorithm = "sha256"
  decompression_algorithm = "gz"
}

variable "pfs1_target" {
  type = string
  default = "pm2"
}

resource "proxmox_virtual_environment_vm" "pfs1" {
  vm_id        = 110
  name        = "pfs1"
  node_name   = var.pfs1_target
  description = "Managed by Terraform"
  tags        = ["terraform"]
  started = true
  on_boot = true
  reboot_after_update = true

  cpu {
    cores = 1
    type  = "host"
  }
  memory {
    dedicated = 2048
    floating  = 2048 # set equal to dedicated to enable ballooning
  }
  disk {
    datastore_id = "local-lvm"
    interface    = "scsi0"
    discard      = "on"
    size         = 50
  }
  cdrom {
    file_id = proxmox_virtual_environment_download_file.pf_sense_iso_2.id
  }
  
  initialization {
    datastore_id = "local-lvm"
    user_data_file_id   = proxmox_virtual_environment_file.pfs1_cloud_config.id

    ip_config {
      ipv4 {
        address = "${var.pfs1_ip}/24"
        gateway = var.gateway_ip
      }
    }
    dns {
      servers = [var.dns1_ip, var.dns2_ip]
    }
  }

  network_device {
    bridge = "vmbr0"
    model = "virtio"
  }

  network_device {
    bridge = "vmbr1"
    model = "virtio"
    firewall = false
    vlan_id = 100
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
      cdrom,
      ipv4_addresses,
      ipv6_addresses,
      startup,
    ]
  }
}