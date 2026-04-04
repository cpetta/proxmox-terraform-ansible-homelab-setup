terraform {
  required_providers {
    dns = {
      source  = "hashicorp/dns"
      version = " ~> 3.5.0"
    }
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.97.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "2.4.0"
    }
    talos = {
      source  = "siderolabs/talos"
      version = "0.11.0-beta.1"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "3.0.1"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "3.1.1"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "4.2.1"
    }
    htpasswd = {
      source  = "loafoe/htpasswd"
      version = "2.1.0"
    }
  }
}

#-------------------------------------------------------
# Variables
#-------------------------------------------------------
variable "local" {
  type    = bool
  default = true
}

variable "dns_zone" {}
variable "dns_tsig_secret" {}
variable "ssh_public_key" {}
variable "pm_api_token" {}
variable "pm_api_url" {}
variable "pm_api_url_remote" {}

variable "tailscale_auth_key" {}

variable "pm_pasword" {}
variable "cipassword" {}
variable "cipassword_hash" {}
variable "traefik_password" {}
variable "longhorn_password" {}

variable "gateway_ip" {}

variable "pm_node_list" {}
variable "dns_server_list" {}
variable "reverse_proxy_list" {}
variable "k8_control_plain_list" {}
variable "k8_storage_node_list" {}
variable "k8_service_list" {}


locals {
  k8_cluster_config = {
    kubernetes_version = "1.35.2"
    name               = "Chloes_Cluster"
    endpoint           = "https://${var.k8_control_plain_list[0].ip_address}:6443"
  }
  talos_default_patch = [
    yamlencode({
      machine = {
        install = {
          disk  = "/dev/sda"
          image = data.talos_image_factory_urls.this.urls.installer
        }
      }
    })
  ]
  talos_storage_patch = [
    yamlencode({
      machine = {
        install = {
          disk  = "/dev/sda"
          image = data.talos_image_factory_urls.storage.urls.installer
        }
        kubelet = {
          extraMounts = [
            {
              destination = "/var/lib/longhorn"
              type        = "bind"
              source      = "/var/lib/longhorn"
              options = [
                "bind",
                "rshared",
                "rw",
              ]
            }
          ]
        }
        sysctls = {
          "vm.nr_hugepages" = "1024"
        }
        kernel = {
          modules = [
            { name = "nvme_tcp" },
            { name = "vfio_pci" }
          ]
        }
      }
    })
  ]

}

variable "pfs1_ip" {}

#-------------------------------------------------------
# Providers
#-------------------------------------------------------
provider "proxmox" {
  endpoint  = var.local ? var.pm_api_url : var.pm_api_url_remote
  api_token = var.pm_api_token
  username  = "root@pam"
  password  = var.pm_pasword
  insecure  = true

  ssh {
    username    = "root"
    password    = var.pm_pasword
    private_key = file("../ssh/private_key")
    agent       = true

    node {
      name    = var.pm_node_list[0].name
      address = var.local ? var.pm_node_list[0].ip_address : var.pm_node_list[0].name
    }
    node {
      name    = var.pm_node_list[1].name
      address = var.local ? var.pm_node_list[1].ip_address : var.pm_node_list[1].name
    }
    node {
      name    = var.pm_node_list[2].name
      address = var.local ? var.pm_node_list[2].ip_address : var.pm_node_list[2].name
    }
  }
}

provider "kubernetes" {
  config_path = local_file.kubeconfig.filename
}

provider "helm" {
  kubernetes = {
    config_path = local_file.kubeconfig.filename
  }
}

provider "talos" {}
provider "tls" {}
provider "htpasswd" {}

#-------------------------------------------------------
# Cloud Image Resources
#-------------------------------------------------------
resource "proxmox_virtual_environment_download_file" "ubuntu_cloud_image" {
  count               = length(var.pm_node_list)
  content_type        = "import"
  datastore_id        = "local"
  node_name           = var.pm_node_list[count.index].name
  url                 = "https://cloud-images.ubuntu.com/minimal/releases/noble/release/ubuntu-24.04-minimal-cloudimg-amd64.img"
  file_name           = "ubuntu-24.04-minimal-cloudimg-amd64.img.qcow2" # rename to *.qcow2 for import
  overwrite           = false
  overwrite_unmanaged = true
  checksum            = "5afe95f6ba186d6e6c7b1582ee34001ac20f609a79b1c68a1c09e5a63f18a460"
  checksum_algorithm  = "sha256"
}

#-------------------------------------------------------
# Testing VM Image
#-------------------------------------------------------
// Reference https://atxfiles.netgate.com/mirror/downloads/
resource "proxmox_virtual_environment_download_file" "mint_iso_1" {
  content_type        = "iso"
  datastore_id        = "local"
  node_name           = "pm1"
  url                 = "https://mirrors.edge.kernel.org/linuxmint/stable/22.3/linuxmint-22.3-xfce-64bit.iso"
  file_name           = "linuxmint-22.3-xfce-64bit.iso"
  overwrite           = false
  overwrite_unmanaged = true
  checksum            = "45a835b5dddaf40e84d776549e0b19b3fbd49673b6cc6434ebddbfcd217df776"
  checksum_algorithm  = "sha256"
}

#-------------------------------------------------------
# Talos Linux Kubernetes Image
#-------------------------------------------------------
data "talos_image_factory_versions" "this" {
  filters = {
    stable_versions_only = true
  }
}

locals {
  talos_version_latest = element(data.talos_image_factory_versions.this.talos_versions, length(data.talos_image_factory_versions.this.talos_versions) - 1)
}

data "talos_image_factory_extensions_versions" "this" {
  talos_version = local.talos_version_latest
  filters = {
    names = [
      "qemu",
      # "iscsi-tools",
      # "util-linux-tools",
      # "tailscale",
    ]
  }
}

resource "talos_image_factory_schematic" "this" {
  schematic = yamlencode({
    customization = {
      systemExtensions = {
        officialExtensions = data.talos_image_factory_extensions_versions.this.extensions_info.*.name
      }
    }
  })
}

data "talos_image_factory_urls" "this" {
  talos_version = local.talos_version_latest
  schematic_id  = talos_image_factory_schematic.this.id
  platform      = "nocloud"
}

resource "proxmox_virtual_environment_download_file" "talos_boot_image" {
  for_each                = toset(distinct(var.k8_control_plain_list[*].host_node))
  content_type            = "iso"
  datastore_id            = "local"
  node_name               = each.value
  url                     = data.talos_image_factory_urls.this.urls.disk_image
  file_name               = "talos-${local.talos_version_latest}-nocloud-amd64.iso"
  decompression_algorithm = "zst"
  overwrite               = false
  overwrite_unmanaged     = true
}

#-------------------------------------------------------
# Talos Storage Image
#-------------------------------------------------------
locals {
  storage_host_list = toset(distinct(var.k8_storage_node_list[*].host_node))
}

data "talos_image_factory_extensions_versions" "storage" {
  talos_version = local.talos_version_latest
  filters = {
    names = [
      "siderolabs/qemu-guest-agent",
      "siderolabs/iscsi-tools",
      "siderolabs/util-linux-tools",
    ]
  }
}

resource "talos_image_factory_schematic" "storage" {
  schematic = yamlencode({
    customization = {
      systemExtensions = {
        officialExtensions = data.talos_image_factory_extensions_versions.storage.extensions_info.*.name
      }
    }
  })
}

data "talos_image_factory_urls" "storage" {
  talos_version = local.talos_version_latest
  schematic_id  = talos_image_factory_schematic.storage.id
  platform      = "nocloud"
}

resource "proxmox_virtual_environment_download_file" "talos_boot_image_storage" {
  for_each                = local.storage_host_list
  content_type            = "iso"
  datastore_id            = "local"
  node_name               = each.value
  url                     = data.talos_image_factory_urls.storage.urls.disk_image
  file_name               = "talos-${local.talos_version_latest}-nocloud-amd64-storage.iso"
  decompression_algorithm = "zst"
  overwrite               = false
  overwrite_unmanaged     = true
}

#-------------------------------------------------------
# Talos Control Plain Bootstrap
#-------------------------------------------------------
resource "talos_machine_secrets" "this" {}

data "talos_client_configuration" "k8_bootstrap_node" {
  cluster_name         = local.k8_cluster_config.name
  client_configuration = talos_machine_secrets.this.client_configuration
  endpoints            = [var.k8_control_plain_list[0].ip_address]
}

data "talos_machine_configuration" "k8_bootstrap_node" {
  depends_on         = [proxmox_virtual_environment_vm.k8cp[0]]
  cluster_name       = local.k8_cluster_config.name
  machine_type       = "controlplane"
  cluster_endpoint   = local.k8_cluster_config.endpoint
  machine_secrets    = talos_machine_secrets.this.machine_secrets
  kubernetes_version = local.k8_cluster_config.kubernetes_version
}

resource "talos_machine_configuration_apply" "k8_bootstrap_node" {
  depends_on                  = [proxmox_virtual_environment_vm.k8cp[0]]
  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.k8_bootstrap_node.machine_configuration
  node                        = var.k8_control_plain_list[0].ip_address
  config_patches              = local.talos_default_patch
}

resource "talos_machine_bootstrap" "k8_bootstrap_node" {
  depends_on           = [talos_machine_configuration_apply.k8_bootstrap_node]
  node                 = var.k8_control_plain_list[0].ip_address
  client_configuration = talos_machine_secrets.this.client_configuration
}

resource "talos_cluster_kubeconfig" "k8_bootstrap_node" {
  depends_on           = [talos_machine_bootstrap.k8_bootstrap_node]
  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = var.k8_control_plain_list[0].ip_address
}

resource "local_file" "kubeconfig" {
  content  = talos_cluster_kubeconfig.k8_bootstrap_node.kubeconfig_raw
  filename = "${path.module}/../kubeconfig"
}

#-------------------------------------------------------
# Talos Control Plain Nodes
#-------------------------------------------------------
data "talos_machine_configuration" "controlplane" {
  cluster_name       = local.k8_cluster_config.name
  machine_type       = "controlplane"
  cluster_endpoint   = local.k8_cluster_config.endpoint
  machine_secrets    = talos_machine_secrets.this.machine_secrets
  kubernetes_version = local.k8_cluster_config.kubernetes_version
}

data "talos_client_configuration" "controlplane" {
  cluster_name         = local.k8_cluster_config.name
  client_configuration = talos_machine_secrets.this.client_configuration
  endpoints            = [var.k8_control_plain_list[0].ip_address]
}

resource "talos_machine_configuration_apply" "controlplane" {
  for_each                    = { for i, v in var.k8_control_plain_list : i => v if i > 0 }
  depends_on                  = [proxmox_virtual_environment_vm.k8cp]
  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.controlplane.machine_configuration
  node                        = each.value.ip_address
  config_patches              = local.talos_default_patch
}


#-------------------------------------------------------
# Talos Worker Nodes
#-------------------------------------------------------
data "talos_machine_configuration" "storage" {
  cluster_name       = local.k8_cluster_config.name
  machine_type       = "worker"
  cluster_endpoint   = local.k8_cluster_config.endpoint
  machine_secrets    = talos_machine_secrets.this.machine_secrets
  kubernetes_version = local.k8_cluster_config.kubernetes_version
}

data "talos_client_configuration" "storage" {
  cluster_name         = local.k8_cluster_config.name
  client_configuration = talos_machine_secrets.this.client_configuration
  endpoints            = [var.k8_storage_node_list[0].ip_address]
}

resource "talos_machine_configuration_apply" "storage" {
  depends_on                  = [proxmox_virtual_environment_vm.k8s]
  count                       = length(var.k8_storage_node_list)
  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.storage.machine_configuration
  node                        = var.k8_storage_node_list[count.index].ip_address
  config_patches              = local.talos_storage_patch
}


#-------------------------------------------------------
# DNS
#-------------------------------------------------------
resource "local_file" "dns_snippet" {
  count = length(var.dns_server_list)
  content = templatefile("${path.module}/cloud-init/templates/common.tftpl", {
    hostname           = "dns${count.index + 1}"
    tailscale_auth_key = var.tailscale_auth_key
    cipassword_hash    = var.cipassword_hash
    ssh_public_key     = var.ssh_public_key
  })
  filename = "${path.module}/cloud-init/tmp/cloud_config_dns${count.index + 1}.yml"
}

resource "proxmox_virtual_environment_file" "dns_cloud_config" {
  count        = length(var.dns_server_list)
  depends_on   = [resource.local_file.dns_snippet]
  content_type = "snippets"
  datastore_id = "local"
  node_name    = var.dns_server_list[count.index].host_node
  source_file {
    path = resource.local_file.dns_snippet[count.index].filename
  }
}

resource "proxmox_virtual_environment_vm" "dns" {
  count = length(var.dns_server_list)
  # vm_id       = 101
  name                = "dns${count.index + 1}"
  node_name           = var.dns_server_list[count.index].host_node
  description         = "Managed by Terraform"
  tags                = ["terraform", "ubuntu"]
  started             = true
  on_boot             = true
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
    import_from  = proxmox_virtual_environment_download_file.ubuntu_cloud_image[1].id
    interface    = "scsi0"
    discard      = "on"
    size         = 10
  }

  initialization {
    datastore_id      = "local-lvm"
    user_data_file_id = proxmox_virtual_environment_file.dns_cloud_config[count.index].id

    ip_config {
      ipv4 {
        address = "${var.dns_server_list[count.index].ip_address}/24"
        gateway = var.gateway_ip
      }
    }
    dns {
      servers = ["9.9.9.9", "1.1.1.1", "1.0.0.1"]
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
      startup,
      initialization,
    ]
  }
}

#-------------------------------------------------------
# PF Sense 1
#-------------------------------------------------------
// Reference https://atxfiles.netgate.com/mirror/downloads/
resource "proxmox_virtual_environment_download_file" "pf_sense_iso_2" {
  content_type            = "iso"
  datastore_id            = "local"
  node_name               = "pm2"
  url                     = "https://atxfiles.netgate.com/mirror/downloads/pfSense-CE-2.7.2-RELEASE-amd64.iso.gz"
  file_name               = "pfSense-CE-2.7.2-RELEASE-amd64.iso" # rename to *.iso for import
  overwrite               = false
  overwrite_unmanaged     = true
  checksum                = "883fb7bc64fe548442ed007911341dd34e178449f8156ad65f7381a02b7cd9e4"
  checksum_algorithm      = "sha256"
  decompression_algorithm = "gz"
}

# resource "proxmox_virtual_environment_vm" "pfs1" {
#   vm_id               = 110
#   name                = "pfs1"
#   node_name           = "pm2"
#   description         = "Managed by Terraform"
#   tags                = ["terraform"]
#   started             = true
#   on_boot             = true
#   reboot_after_update = true

#   cpu {
#     cores = 1
#     type  = "host"
#   }
#   memory {
#     dedicated = 2048
#     floating  = 2048 # set equal to dedicated to enable ballooning
#   }
#   disk {
#     datastore_id = "local-lvm"
#     interface    = "scsi0"
#     discard      = "on"
#     size         = 50
#   }
#   cdrom {
#     file_id = proxmox_virtual_environment_download_file.pf_sense_iso_2.id
#   }

#   initialization {
#     datastore_id = "local-lvm"

#     ip_config {
#       ipv4 {
#         address = "${var.pfs1_ip}/24"
#         gateway = var.gateway_ip
#       }
#     }
#     dns {
#       servers = [for server in var.dns_server_list : server.ip_address]
#     }
#   }

#   network_device {
#     bridge = "vmbr0"
#     model  = "virtio"
#   }

#   network_device {
#     bridge   = "vmbr1"
#     model    = "virtio"
#     firewall = false
#     vlan_id  = 100
#   }

#   agent {
#     enabled = true
#   }

#   startup {
#     down_delay = -1
#     order      = -1
#     up_delay   = -1
#   }

#   lifecycle {
#     ignore_changes = [
#       started,
#       cdrom,
#       # ipv4_addresses,
#       # ipv6_addresses,
#       startup,
#     ]
#   }
# }

#-------------------------------------------------------
# Reverse Proxy - traefik
#-------------------------------------------------------
resource "local_file" "reverse_proxy_snippet" {
  count = length(var.reverse_proxy_list)
  content = templatefile("${path.module}/cloud-init/templates/common.tftpl", {
    hostname           = "rp${count.index + 1}"
    tailscale_auth_key = var.tailscale_auth_key
    cipassword_hash    = var.cipassword_hash
    ssh_public_key     = var.ssh_public_key
  })
  filename = "${path.module}/cloud-init/tmp/cloud_config_reverse_proxy${count.index + 1}.yml"
}

resource "proxmox_virtual_environment_file" "reverse_proxy_cloud_config" {
  count        = length(var.reverse_proxy_list)
  depends_on   = [resource.local_file.reverse_proxy_snippet]
  content_type = "snippets"
  datastore_id = "local"
  node_name    = var.reverse_proxy_list[count.index].host_node
  source_file {
    path = resource.local_file.reverse_proxy_snippet[count.index].filename
  }
}

resource "proxmox_virtual_environment_vm" "reverse_proxy" {
  count               = length(var.reverse_proxy_list)
  name                = "rp${count.index + 1}"
  node_name           = var.reverse_proxy_list[count.index].host_node
  description         = "Managed by Terraform"
  tags                = ["terraform"]
  started             = true
  on_boot             = true
  reboot_after_update = true

  cpu {
    cores = 2
    type  = "host"
  }
  memory {
    dedicated = 2048
    floating  = 2048 # set equal to dedicated to enable ballooning
  }
  disk {
    datastore_id = "local-lvm"
    import_from  = proxmox_virtual_environment_download_file.ubuntu_cloud_image[1].id
    interface    = "scsi0"
    discard      = "on"
    size         = 10
  }

  initialization {
    datastore_id      = "local-lvm"
    user_data_file_id = proxmox_virtual_environment_file.reverse_proxy_cloud_config[count.index].id

    ip_config {
      ipv4 {
        address = "${var.reverse_proxy_list[count.index].ip_address}/24"
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

#-------------------------------------------------------
# Talos Control Plain Nodes
#-------------------------------------------------------
resource "local_file" "k8cp_snippet" {
  for_each = { for i, v in var.k8_control_plain_list : i => v }
  content = templatefile("${path.module}/cloud-init/templates/talos.tftpl", {
    hostname    = each.value.name
    mac_address = ""
  })
  filename = "${path.module}/cloud-init/tmp/cloud_config_${each.value.name}.yml"
}

resource "proxmox_virtual_environment_file" "k8cp_cloud_config" {
  for_each     = { for i, v in var.k8_control_plain_list : i => v }
  depends_on   = [resource.local_file.k8cp_snippet]
  content_type = "snippets"
  datastore_id = "local"
  node_name    = each.value.host_node
  source_file {
    path = resource.local_file.k8cp_snippet[each.key].filename
  }
}

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
    cores = 2
    type  = "host"
  }
  rng {
    max_bytes = 1024
    period    = 1000
    source    = "/dev/urandom"
  }
  memory {
    # dedicated = 2048
    dedicated = 4096
    floating  = 0
  }
  disk {
    datastore_id = "local-lvm"
    file_format  = "raw"
    file_id      = proxmox_virtual_environment_download_file.talos_boot_image[each.value.host_node].id
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
      # started,
      startup,
    ]
  }
}

#-------------------------------------------------------
# Talos Storage Nodes
#-------------------------------------------------------
resource "local_file" "k8w_snippet_storage" {
  for_each = { for i, v in var.k8_storage_node_list : i => v }
  content = templatefile("${path.module}/cloud-init/templates/talos.tftpl", {
    hostname    = each.value.name
    mac_address = ""
  })
  filename = "${path.module}/cloud-init/tmp/cloud_config_k8s-${each.key}.yml"
}

resource "proxmox_virtual_environment_file" "k8w_cloud_config_storage" {
  for_each     = { for i, v in var.k8_storage_node_list : i => v }
  depends_on   = [resource.local_file.k8w_snippet_storage]
  content_type = "snippets"
  datastore_id = "local"
  node_name    = each.value.host_node
  source_file {
    path = local_file.k8w_snippet_storage[each.key].filename
  }
}

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
    cores = 2
    type  = "host"
  }
  rng {
    max_bytes = 1024
    period    = 1000
    source    = "/dev/urandom"
  }
  memory {
    dedicated = each.value.ram
    floating  = each.value.ram # set equal to dedicated to enable ballooning
  }
  disk {
    datastore_id = "local-lvm"
    file_format  = "raw"
    # file_id      = proxmox_virtual_environment_download_file.talos_boot_image_storage[each.value.host_node].id
    file_id   = "local:iso/talos-v1.12.6-nocloud-amd64-storage.iso"
    interface = "scsi0"
    discard   = "on"
    size      = 20
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
      # started,
      startup,
    ]
  }
}

#-------------------------------------------------------
# Kubernetes MetalLB - for ingress
#-------------------------------------------------------
resource "kubernetes_namespace_v1" "metallb" {
  metadata {
    name = "metallb-system"
    labels = {
      "pod-security.kubernetes.io/enforce" = "privileged"
      "pod-security.kubernetes.io/audit"   = "privileged"
      "pod-security.kubernetes.io/warn"    = "privileged"
    }
  }
}

resource "local_file" "metallb_values" {
  content  = templatefile("${path.module}/helm/templates/metallb.tftpl", {})
  filename = "${path.module}/helm/tmp/metallb.yml"
}

resource "helm_release" "metallb" {
  name              = "metallb"
  namespace         = kubernetes_namespace_v1.metallb.id
  create_namespace  = false
  dependency_update = true
  repository        = "https://metallb.github.io/metallb"
  chart             = "metallb"

  # values = [
  #   local_file.metallb_values.content
  # ]
}

resource "terraform_data" "metallb_configs" {
  # count      = 0
  depends_on = [helm_release.metallb]
  input      = local_file.metallb_values.content
  provisioner "local-exec" {
    when        = destroy
    command     = "echo '${self.input}' | kubectl delete -f -"
    interpreter = ["/bin/bash", "-c"]
  }
}

# To comment out when setting count = 0 on terraform_data.metallb_configs
resource "terraform_data" "apply_metallb_configs" {
  depends_on = [terraform_data.metallb_configs]
  lifecycle {
    replace_triggered_by = [terraform_data.metallb_configs]
  }
  provisioner "local-exec" {
    command     = "echo '${terraform_data.metallb_configs.output}' | kubectl apply -f -"
    interpreter = ["/bin/bash", "-c"]
  }
}

#-------------------------------------------------------
# Kubernetes Dashboard - Currently installed desktop
#-------------------------------------------------------
# resource "helm_release" "headlamp" {
#   name              = "headlamp"
#   namespace         = "kube-system"
#   dependency_update = true
#   repository        = "https://kubernetes-sigs.github.io/headlamp/"
#   chart             = "headlamp"
# }

#-------------------------------------------------------
# Kubernetes - Metrics
#-------------------------------------------------------
resource "kubernetes_namespace_v1" "metrics" {
  metadata {
    name = "metrics"
    labels = {
      "pod-security.kubernetes.io/enforce" = "privileged"
    }
  }
}

resource "helm_release" "kube_prometheus_stack" {
  name              = "kube-prometheus-stack"
  namespace         = kubernetes_namespace_v1.metrics.id
  dependency_update = true
  repository        = "https://prometheus-community.github.io/helm-charts/"
  chart             = "kube-prometheus-stack"
}

#-------------------------------------------------------
# Kubernetes - Storage
#-------------------------------------------------------
resource "kubernetes_namespace_v1" "storage" {
  metadata {
    name = "longhorn-system"
    labels = {
      "pod-security.kubernetes.io/enforce" = "privileged"
      "pod-security.kubernetes.io/enforce-version" =  "latest"
      "pod-security.kubernetes.io/audit" =  "privileged"
      "pod-security.kubernetes.io/audit-version" =  "latest"
      "pod-security.kubernetes.io/warn" =  "privileged"
      "pod-security.kubernetes.io/warn-version" =  "latest"
    }
  }
}

resource "helm_release" "longhorn" {
  name              = "longhorn"
  namespace         = kubernetes_namespace_v1.storage.id
  create_namespace  = false
  dependency_update = true
  repository        = "https://charts.longhorn.io"
  chart             = "longhorn"
  version           = "1.9.0"

  # atomic          = true
  # cleanup_on_fail = true
}

resource "htpasswd_password" "longhorn" {
  password = var.longhorn_password
}

resource "kubernetes_secret_v1" "longhorn_auth" {
  metadata {
    name      = "basic-auth"
    namespace = kubernetes_namespace_v1.storage.id
  }

  type = "Opaque"
  data = {
    auth = "admin:${htpasswd_password.longhorn.apr1}"
  }
}

resource "kubernetes_manifest" "longhorn_auth_middleware" {
  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "Middleware"

    metadata = {
      name      = "longhorn-auth"
      namespace = "longhorn-system"
    }

    spec = {
      basicAuth = {
        secret = "basic-auth"
      }
    }
  }
}

resource "kubernetes_manifest" "longhorn_buffering_middleware" {
  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "Middleware"

    metadata = {
      name      = "longhorn-buffering"
      namespace = "longhorn-system"
    }

    spec = {
      buffering = {
        maxRequestBodyBytes = 10485760000
      }
    }
  }
}

resource "kubernetes_manifest" "longhorn_ingressroute" {
  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "IngressRoute"

    metadata = {
    name      = "longhorn-ingress"
    namespace = "longhorn-system"

    annotations = {
      "traefik.ingress.kubernetes.io/router.middlewares" = "longhorn-system-longhorn-auth@kubernetescrd,longhorn-system-longhorn-buffering@kubernetescrd"
    }
  }

    spec = {
      entryPoints = [
        "web",
        "websecure",
      ]

      routes = [
        {
          match = "Host(`longhorn.${var.dns_zone}`)"
          kind  = "Rule"

          services = [
            {
              name = "longhorn-frontend"
              port = 80
            }
          ]
        }
      ]
    }
  }
}


#-------------------------------------------------------
# Kubernetes - Traefik
#-------------------------------------------------------
resource "kubernetes_namespace_v1" "traefik" {
  metadata {
    name = "traefik"
    labels = {
      "pod-security.kubernetes.io/enforce" = "privileged"
    }
  }
}

resource "tls_private_key" "traefik" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "traefik" {
  private_key_pem       = tls_private_key.traefik.private_key_pem
  validity_period_hours = 8760 # 365 days

  subject {
    common_name = "*.docker.localhost"
  }

  allowed_uses = [
    "any_extended",
    "key_encipherment",
    "digital_signature",
    "server_auth",
  ]
}

resource "kubernetes_secret_v1" "traefik_tls_secret" {
  metadata {
    name      = "local-selfsigned-tls"
    namespace = kubernetes_namespace_v1.traefik.id
  }

  data = {
    "tls.crt" = tls_self_signed_cert.traefik.cert_pem
    "tls.key" = tls_private_key.traefik.private_key_pem
  }

  type = "kubernetes.io/tls"
}

resource "local_file" "traefik_values" {
  content = templatefile("${path.module}/helm/templates/traefik.tftpl", {
    dns_zone = var.dns_zone,
    password = var.traefik_password,
  })
  filename = "${path.module}/helm/tmp/traefik.yml"
}

resource "helm_release" "traefik" {
  name              = "traefik"
  namespace         = kubernetes_namespace_v1.traefik.id
  create_namespace  = false
  dependency_update = true
  # force_update      = true
  repository = "https://traefik.github.io/charts"
  chart      = "traefik"
  values = [
    local_file.traefik_values.content
  ]
}

#-------------------------------------------------------
# Kubernetes Config
#-------------------------------------------------------
# resource "kubernetes_persistent_volume_claim" "jellyfin_config" {
#   metadata {
#     name = "jellyfin-config-pvc"
#   }
#   spec {
#     access_modes = ["ReadWriteMany"]
#     resources {
#       requests = {
#         storage = "5Gi"
#       }
#     }
#     volume_name = "${kubernetes_persistent_volume.example.metadata.0.name}"
#   }
# }

# resource "kubernetes_persistent_volume" "jellyfin_config" {
#   metadata {
#     name = "jellyfin-config"
#   }
#   spec {
#     capacity = {
#       storage = "5Gi"
#     }
#     access_modes = ["ReadWriteMany"]
#     persistent_volume_source {
#       gce_persistent_disk {
#         pd_name = "test-123"
#       }
#     }
#   }
# }