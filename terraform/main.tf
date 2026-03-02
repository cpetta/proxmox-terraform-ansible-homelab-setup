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

resource "proxmox_virtual_environment_download_file" "ubuntu_cloud_image" {
  content_type = "import"
  datastore_id = "local"
  node_name    = "pm1"
  url          = "https://cloud-images.ubuntu.com/minimal/releases/noble/release/ubuntu-24.04-minimal-cloudimg-amd64.img"
  file_name    = "ubuntu-24.04-minimal-cloudimg-amd64.img.qcow2" # rename to *.qcow2 for import
  overwrite    = true
  overwrite_unmanaged = true
}

#-------------------------------------------------------
# DNS01
#-------------------------------------------------------
variable "dns01_snippet_filename" {
  type    = string
  default = "dns01.yml"
}

resource "local_file" "dns01_snippet" {
  content = templatefile("${path.module}/cloud-init/templates/dns01.tftpl", {
    tailscale_auth_key = var.tailscale_auth_key
    cipassword_hash    = var.cipassword_hash
    ssh_public_key     = var.ssh_public_key
  })
  filename = "${path.module}/cloud-init/tmp/${var.dns01_snippet_filename}"
}

resource "proxmox_virtual_environment_file" "dns01_cloud_config" {
  depends_on  = [resource.local_file.dns01_snippet]
  content_type = "snippets"
  datastore_id = "local"
  node_name    = "pm1"
  source_file {
    path = resource.local_file.dns01_snippet.filename
  }
}

resource "proxmox_virtual_environment_vm" "dns01" {
  vm_id        = 101
  name        = "dns01"
  node_name   = "pm1"
  description = "Managed by Terraform"
  tags        = ["terraform", "ubuntu"]
  started = true
  on_boot = true
  reboot_after_update = true
  
  # depends_on  = [null_resource.upload_dns01_snippet]

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
    import_from  = proxmox_virtual_environment_download_file.ubuntu_cloud_image.id
    interface    = "scsi0"
    iothread     = true
    discard      = "on"
    size         = 10
  }
  
  initialization {
    datastore_id = "local-lvm"
    user_data_file_id   = proxmox_virtual_environment_file.dns01_cloud_config.id

    ip_config {
      ipv4 {
        address = "${var.dns1_ip}/24"
        gateway = var.gateway_ip
      }
    }
    dns {
      servers = ["1.1.1.1",  "1.0.0.1", "9.9.9.9"]
    }
  }

  network_device {
    bridge = "vmbr0"
    model = "virtio"
  }
  startup {
    order      = -1
    down_delay = -1
    up_delay   = -1
  }
}
