terraform {
  required_providers {
    proxmox = {
      source  = "Telmate/proxmox"
      version = "3.0.2-rc07"
    }
    local = {
      source  = "hashicorp/local"
      version = "2.4.0"
    }
  }
}

variable "cipassword" {}
variable "pm_api_token_id" {}
variable "pm_api_token_secret" {}
variable "pm_api_url" {}
variable "pm_url" {}
variable "pm_pasword" {}
variable "tailscale_auth_key" {}

provider "proxmox" {
  pm_api_url          = var.pm_api_url
  pm_api_token_id     = var.pm_api_token_id
  pm_api_token_secret = var.pm_api_token_secret
  pm_tls_insecure     = true
  pm_debug            = true
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
  })
  filename = "${path.module}/cloud-init/tmp/${var.dns01_snippet_filename}"
}

resource "null_resource" "upload_dns01_snippet" {
  depends_on = [local_file.dns01_snippet]

  triggers = {
    content = local_file.dns01_snippet.content
  }

  provisioner "local-exec" {
    #command = <<-EOT
    #      curl -k -X POST "${var.pm_api_url}/nodes/prox/storage/local/upload" \
    #      -F "content=snippets" \
    #      -F "filename=${local_file.tailscale_snippet.filename}" \
    #      -H "Authorization: PVEAPIToken=${var.pm_api_token_id}=${var.pm_api_token_secret}"
    #EOT
    command = <<-EOT
      sshpass -p "${var.pm_pasword}" scp ${local_file.dns01_snippet.filename} root@${var.pm_url}:/var/lib/vz/snippets/
    EOT
  }
}

resource "proxmox_vm_qemu" "dns01" {
  vmid        = 101
  name        = "dns01"
  target_node = "prox"
  depends_on  = [null_resource.upload_dns01_snippet]
  agent       = 1
  cpu {
    cores = 2
    type  = "host"
  }
  memory           = 2048
  boot             = "order=scsi0"      # has to be the same as the OS disk of the template
  clone            = "Ubuntu-24.04-LTS" # The name of the template
  full_clone       = false
  scsihw           = "virtio-scsi-single"
  vm_state         = "running"
  automatic_reboot = true

  # Cloud-Init configuration: use the uploaded snippet
  cicustom   = "user=local:snippets/${var.dns01_snippet_filename}"
  ciupgrade  = true
  nameserver = "192.168.0.221 192.168.0.222"
  ipconfig0  = "ip=192.168.0.221/24,gw=192.168.0.1,ip6=dhcp"
  skip_ipv6  = true

  startup_shutdown {
    order            = -1
    shutdown_timeout = -1
    startup_delay    = -1
  }

  serial {
    id = 0
  }

  disks {
    scsi {
      scsi0 {
        # Specify disk from our template
        disk {
          storage = "local-lvm"
          # The size of the disk should be at least as big as the disk in the template. If it's smaller, the disk will be recreated
          size = "10G"
        }
      }
    }
    ide {
      # Some images require a cloud-init disk on the IDE controller, others on the SCSI or SATA controller
      ide1 {
        cloudinit {
          storage = "local-lvm"
        }
      }
    }
  }

  network {
    id     = 0
    bridge = "vmbr0"
    model  = "virtio"
  }
}
