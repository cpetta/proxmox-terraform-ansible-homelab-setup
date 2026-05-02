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
    kubectl = {
      source  = "alekc/kubectl"
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

variable "admin_email" {}
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
variable "cloudflare_api_email" {}
variable "cloudflare_token" {}

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
  talos_default_patch = {
    machine = {
      install = {
        disk  = "/dev/sda"
        image = data.talos_image_factory_urls.this.urls.installer
      }
    }
  }
  talos_storage_patch = {
    machine = {
      install = {
        disk  = "/dev/sda"
        image = data.talos_image_factory_urls.storage.urls.installer
      }
      disks = [
        {
          device = "/dev/sdb"
          partitions = [
            {
              mountpoint = "/var/lib/longhorn"
              size       = 0
            }
          ]
        },
      ]
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
          { name = "vfio_pci" },
          { name = "nfsd" }
        ]
      }
    }
  }
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

provider "kubectl" {
  config_path = local_file.kubeconfig.filename
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
# resource "proxmox_virtual_environment_download_file" "mint_iso_1" {
#   content_type        = "iso"
#   datastore_id        = "local"
#   node_name           = "pm1"
#   url                 = "https://mirrors.edge.kernel.org/linuxmint/stable/22.3/linuxmint-22.3-xfce-64bit.iso"
#   file_name           = "linuxmint-22.3-xfce-64bit.iso"
#   overwrite           = false
#   overwrite_unmanaged = true
#   checksum            = "45a835b5dddaf40e84d776549e0b19b3fbd49673b6cc6434ebddbfcd217df776"
#   checksum_algorithm  = "sha256"
# }

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
  talos_version        = "v1.12.6" // local.talos_version_latest
}

data "talos_image_factory_extensions_versions" "this" {
  talos_version = local.talos_version
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
  talos_version = local.talos_version
  schematic_id  = talos_image_factory_schematic.this.id
  platform      = "nocloud"
}

resource "proxmox_virtual_environment_download_file" "talos_boot_image" {
  for_each                = toset(distinct(var.k8_control_plain_list[*].host_node))
  content_type            = "iso"
  datastore_id            = "local"
  node_name               = each.value
  url                     = data.talos_image_factory_urls.this.urls.disk_image
  file_name               = "talos-${local.talos_version}-nocloud-amd64.iso"
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
  talos_version = local.talos_version
  filters = {
    names = [
      "siderolabs/qemu-guest-agent",
      "siderolabs/iscsi-tools",
      "siderolabs/util-linux-tools",
      "siderolabs/nfs-utils",
      "siderolabs/nfsd",
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
  talos_version = local.talos_version
  schematic_id  = talos_image_factory_schematic.storage.id
  platform      = "nocloud"
}

resource "proxmox_virtual_environment_download_file" "talos_boot_image_storage" {
  for_each                = local.storage_host_list
  content_type            = "iso"
  datastore_id            = "local"
  node_name               = each.value
  url                     = data.talos_image_factory_urls.storage.urls.disk_image
  file_name               = "talos-${local.talos_version}-nocloud-amd64-storage.iso"
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
  config_patches              = [yamlencode(local.talos_default_patch)]
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
  config_patches              = [yamlencode(local.talos_default_patch)]
}

resource "local_file" "talosconfig" {
  content  = data.talos_client_configuration.controlplane.talos_config
  filename = "${path.module}/../talosconfig"
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
  for_each                    = { for i, v in var.k8_storage_node_list : i => v }
  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.storage.machine_configuration
  node                        = each.value.ip_address
  config_patches              = [yamlencode(local.talos_storage_patch)]

  lifecycle {
    replace_triggered_by = [
      proxmox_virtual_environment_vm.k8s[each.key]
    ]
  }
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
    floating  = each.value.ram # set equal to dedicated to enable ballooning
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
      # started,
      startup,
    ]
  }
}

#-------------------------------------------------------
# Kubernetes - MetalLB (ingress)
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
# Kubernetes - Traefik PVC
#-------------------------------------------------------
resource "kubernetes_manifest" "traefik_data_longhorn_volume" {
  manifest = {
    apiVersion = "longhorn.io/v1beta2"
    kind       = "Volume"

    metadata = {
      name      = "traefik-data-volume"
      namespace = "longhorn-system"
    }

    spec = {
      size             = "1073741824" # 1Gi in bytes
      numberOfReplicas = 3
      frontend         = "blockdev"
      accessMode       = "rwx" // "rwo"
      dataLocality     = "disabled"
    }
  }
}

resource "kubernetes_persistent_volume_v1" "traefik_data" {
  depends_on = [kubernetes_manifest.traefik_data_longhorn_volume]
  metadata {
    name = "traefik-data"
  }

  spec {
    storage_class_name = "longhorn"
    access_modes       = ["ReadWriteMany"] // ["ReadWriteOnce"]

    capacity = {
      storage = "1Gi"
    }

    persistent_volume_source {
      csi {
        driver        = "driver.longhorn.io"
        volume_handle = kubernetes_manifest.traefik_data_longhorn_volume.manifest.metadata.name
      }
    }
  }
  lifecycle {
    ignore_changes = [
      metadata
    ]
  }
}

resource "kubernetes_persistent_volume_claim_v1" "traefik_data" {
  depends_on = [kubernetes_persistent_volume_v1.traefik_data]
  metadata {
    name      = "traefik-data-pvc"
    namespace = kubernetes_namespace_v1.traefik.id
  }
  spec {
    volume_name = kubernetes_persistent_volume_v1.traefik_data.metadata.0.name
    # storage_class_name = "longhorn"
    access_modes = ["ReadWriteMany"] // ["ReadWriteOnce"]
    resources {
      requests = {
        storage = "1Gi"
      }
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
    dns_zone             = var.dns_zone,
    admin_email          = var.admin_email,
    password             = var.traefik_password,
    cloudflare_api_email = var.cloudflare_api_email,
    cloudflare_token     = var.cloudflare_token,
  })
  filename = "${path.module}/helm/tmp/traefik.yml"
}

resource "helm_release" "traefik" {
  # depends_on = [kubernetes_persistent_volume_claim_v1.traefik_data]
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
# Cert Manager - helm
#-------------------------------------------------------
resource "kubernetes_namespace_v1" "cert-manager" {
  metadata {
    name = "cert-manager"
    labels = {}
  }
}

resource "helm_release" "cert_manager" {
  name             = "cert-manager"
  repository       = "oci://quay.io/jetstack/charts"
  chart            = "cert-manager"
  namespace        = kubernetes_namespace_v1.cert-manager.id
  version          = "v1.20.2"

  set = [
    {
      name  = "crds.enabled"
      value = "true"
    },
    {
      name = "extraArgs"
      value = "{--dns01-recursive-nameservers-only,--dns01-recursive-nameservers=1.1.1.1:53,1.0.0.1:53}"
    }
  ]
}

#-------------------------------------------------------
# Cert Manager - Cluster Issuer
#-------------------------------------------------------
resource "kubectl_manifest" "cert_manager_cluster_issuer_cloudflare_staging" {
  yaml_body = yamlencode({
    apiVersion = "cert-manager.io/v1"
    kind = "ClusterIssuer"
    metadata = {
      name = "cloudflare-staging"
    }
    spec = {
      acme = {
        email = var.admin_email
        privateKeySecretRef = {
          name = "cert-manager-private-key"
        }
        server = "https://acme-v02.api.letsencrypt.org/directory"
        solvers = [
          {
            dns01 = {
              cloudflare = {
                apiKeySecretRef = {
                  key = "api-token"
                  name = "cloudflare-api-key-secret"
                }
                email = var.cloudflare_api_email
              }
            }
          },
        ]
      }
    }
  })
}

resource "kubectl_manifest" "cert_manager_cluster_issuer_cloudflare" {
  yaml_body = yamlencode({
    apiVersion = "cert-manager.io/v1"
    kind = "ClusterIssuer"
    metadata = {
      name = "cloudflare"
    }
    spec = {
      acme = {
        email = var.admin_email
        # preferredChain = "ISRG Root X1"
        privateKeySecretRef = {
          name = "cloudflare-private-key"
        }
        server = "https://acme-v02.api.letsencrypt.org/directory"
        solvers = [
          {
            dns01 = {
              cloudflare = {
                apiKeySecretRef = {
                  key = var.cloudflare_token
                  name = "cloudflare-api-key-secret"
                }
                email = var.cloudflare_api_email
              }
            }
            # selector = {
            #   dnsZones = [
            #     "*.${var.dns_zone}",
            #     var.dns_zone,
            #   ]
            # }
          },
        ]
      }
    }
  })
}

#-------------------------------------------------------
# Cert Manager - Cloudflare provider
#-------------------------------------------------------
resource "kubernetes_secret_v1" "cloudflare_api_key" {
  depends_on = [ helm_release.cert_manager ]
  metadata {
    name = "cloudflare-api-token-secret"
    namespace = kubernetes_namespace_v1.traefik.id
  }
  type = "Opaque"
  data = {
    api-token = var.cloudflare_token
  }
}

resource "kubernetes_manifest" "cloudflare_le_staging_cert_issuer" {
  depends_on = [ kubernetes_secret_v1.cloudflare_api_key ]
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "Issuer"
    metadata = {
      name      = "cloudflare-staging"
      namespace = kubernetes_namespace_v1.traefik.id
    }
    spec = {
      acme = {
        server = "https://acme-staging-v02.api.letsencrypt.org/directory" # staging
        email  = var.admin_email
        privateKeySecretRef = {
          name = "cloudflare-staging-key"
        }
        solvers = [
          {
            dns01 = {
              cloudflare = {
                apiTokenSecretRef = {
                  name = kubernetes_secret_v1.cloudflare_api_key.metadata.0.name
                  key  = "api-token"
                }
              }
              recursiveNameservers = [
                "1.1.1.1:53",
                "1.0.0.1:53",
              ]
              recursiveNameserversOnly = true
            }
          }
        ]
      }
    }
  }
}

resource "kubernetes_manifest" "cloudflare_le_prod_cert_issuer" {
  depends_on = [ kubernetes_secret_v1.cloudflare_api_key ]
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "Issuer"
    metadata = {
      name      = "cloudflare-prod"
      namespace = kubernetes_namespace_v1.traefik.id
    }
    spec = {
      acme = {
        server = "https://acme-v02.api.letsencrypt.org/directory"
        email  = var.admin_email
        privateKeySecretRef = {
          name = "cloudflare-prod-key"
        }
        solvers = [
          {
            dns01 = {
              cloudflare = {
                apiTokenSecretRef = {
                  name = kubernetes_secret_v1.cloudflare_api_key.metadata.0.name
                  key  = "api-token"
                }
              }
              recursiveNameservers = [
                "1.1.1.1:53",
                "1.0.0.1:53",
              ]
              recursiveNameserversOnly = true
            }
          }
        ]
      }
    }
  }
}

#-------------------------------------------------------
# Cert Manager - TLS Certificate
#-------------------------------------------------------
resource "kubectl_manifest" "wildcard_certificate" {
  # wait_for {
  #   field {
  #     key = "status.containerStatuses.[0].ready"
  #     value = "true"
  #   }
  #   field {
  #     key = "status.phase"
  #     value = "Running"
  #   }
  #   field {
  #     key = "status.podIP"
  #     value = "^(\\d+(\\.|$)){4}"
  #     value_type = "regex"
  #   }
  #   condition {
  #     type = "ContainersReady"
  #     status = "True"
  #   }
  #   condition {
  #     type = "Ready"
  #     status = "True"
  #   }
  # }
  yaml_body = yamlencode({
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"

    metadata = {
      name      = "wildcard-cert"
      namespace = kubernetes_namespace_v1.traefik.id
    }

    spec = {
      secretName = "wildcard-cert"
      commonName = "*.${var.dns_zone}"
      dnsNames = [
        var.dns_zone,
        "*.${var.dns_zone}",
      ]
      issuerRef = {
        name = kubernetes_manifest.cloudflare_le_prod_cert_issuer.manifest.metadata.name
        kind = "Issuer"
      }
    }
  })
}

#-------------------------------------------------------
# NFS - For Debug
#-------------------------------------------------------
locals {
  // Jellyfin Media
  # nfs_namespace = kubernetes_namespace_v1.jellyfin.id
  # nfs_export = "/etc/jellyfin-media *(rw,sync,no_subtree_check,no_acl,no_root_squash,fsid=0)"
  # nfs_volume_name = kubernetes_persistent_volume_claim_v1.jellyfin_media.metadata.0.name
  # nfs_mount = "/etc/jellyfin-media"

  // Jellyfin Config
  # nfs_namespace = kubernetes_namespace_v1.jellyfin.id
  # nfs_export = "/etc/jellyfin-config *(rw,sync,no_subtree_check,fsid=0)"
  # nfs_volume_name = kubernetes_persistent_volume_claim_v1.jellyfin_config.metadata.0.name
  # nfs_mount = "/etc/jellyfin-config"

  // Traefik Data
  nfs_namespace   = kubernetes_namespace_v1.traefik.id
  nfs_export      = "/mnt/traefik *(rw,sync,no_subtree_check,no_acl,fsid=0)"
  nfs_volume_name = kubernetes_persistent_volume_claim_v1.traefik_data.metadata.0.name // "traefik-data-pvc"
  nfs_mount       = "/mnt/traefik"
}

resource "kubernetes_deployment_v1" "nfs_server" {
  metadata {
    name      = "nfs-server"
    namespace = local.nfs_namespace
  }

  spec {
    replicas = 1
    selector {
      match_labels = {
        app = "nfs-server"
      }
    }

    template {
      metadata {
        labels = {
          app = "nfs-server"
        }
      }

      spec {
        container {
          name  = "nfs-server"
          image = "erichough/nfs-server"

          env {
            name  = "NFS_PORT"
            value = "32049"
          }

          # env {
          #   name  = "NFS_LOG_LEVEL"
          #   value = "DEBUG"
          # }

          env { // Traefik Data
            name  = "NFS_EXPORT_0"
            value = local.nfs_export
          }

          port {
            name           = "nfs-tcp"
            container_port = 32049
            protocol       = "TCP"
          }

          port {
            name           = "nfs-udp"
            container_port = 32049
            protocol       = "UDP"
          }

          # Enable these ports for NFSv3 support
          # port {
          #   name = "mountd-tcp"
          #   container_port = 111
          #   protocol = "TCP"
          # }

          # port {
          #   name = "mountd-udp"
          #   container_port = 111
          #   protocol = "UDP"
          # }

          # port {
          #   name = "statd-in-tcp"
          #   container_port = 32765
          #   protocol = "TCP"
          # }

          # port {
          #   name = "statd-in-udp"
          #   container_port = 32765
          #   protocol = "UDP"
          # }

          # port {
          #   name = "statd-out-tcp"
          #   container_port = 32767
          #   protocol = "TCP"
          # }

          # port {
          #   name = "statd-out-udp"
          #   container_port = 32767
          #   protocol = "UDP"
          # }

          security_context {
            # privileged = true

            capabilities {
              add = [
                "SYS_ADMIN",
                "CAP_SYS_ADMIN",
              ]
            }
          }

          volume_mount {
            name       = local.nfs_volume_name
            mount_path = local.nfs_mount
          }

        }

        volume {
          name = local.nfs_volume_name
          persistent_volume_claim {
            claim_name = local.nfs_volume_name
          }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "nfs_service" {
  metadata {
    name      = "nfs"
    namespace = local.nfs_namespace
  }

  spec {
    selector = {
      app = "nfs-server"
    }

    port {
      name        = "nfs-tcp"
      port        = 2049
      protocol    = "TCP"
      target_port = 32049
    }

    port {
      name        = "nfs-udp"
      port        = 2049
      protocol    = "UDP"
      target_port = 32049
    }

    # Enable these ports for NFSv3 support  
    # port {
    #   name = "mountd-tcp"
    #   port = 111
    #   protocol = "TCP"
    # }

    # port {
    #   name = "mountd-udp"
    #   port = 111
    #   protocol = "UDP"
    # }

    # port {
    #   name = "statd-in-tcp"
    #   port = 32765
    #   protocol = "TCP"
    # }

    # port {
    #   name = "statd-in-udp"
    #   port = 32765
    #   protocol = "UDP"
    # }

    # port {
    #   name = "statd-out-tcp"
    #   port = 32767
    #   protocol = "TCP"
    # }

    # port {
    #   name = "statd-out-udp"
    #   port = 32767
    #   protocol = "UDP"
    # }

    type             = "LoadBalancer"
    load_balancer_ip = "192.168.0.246"
  }
  lifecycle {
    ignore_changes = [
      metadata
    ]
  }
}

#-------------------------------------------------------
# Kubernetes - Metrics
#-------------------------------------------------------
# resource "kubernetes_namespace_v1" "metrics" {
#   metadata {
#     name = "metrics"
#     labels = {
#       "pod-security.kubernetes.io/enforce" = "privileged"
#     }
#   }
# }

# resource "helm_release" "kube_prometheus_stack" {
#   name              = "kube-prometheus-stack"
#   namespace         = kubernetes_namespace_v1.metrics.id
#   dependency_update = true
#   repository        = "https://prometheus-community.github.io/helm-charts/"
#   chart             = "kube-prometheus-stack"
# }

#-------------------------------------------------------
# Kubernetes - Storage
#-------------------------------------------------------
resource "kubernetes_namespace_v1" "storage" {
  metadata {
    name = "longhorn-system"
    labels = {
      "pod-security.kubernetes.io/enforce"         = "privileged"
      "pod-security.kubernetes.io/enforce-version" = "latest"
      "pod-security.kubernetes.io/audit"           = "privileged"
      "pod-security.kubernetes.io/audit-version"   = "latest"
      "pod-security.kubernetes.io/warn"            = "privileged"
      "pod-security.kubernetes.io/warn-version"    = "latest"
    }
  }
}

resource "helm_release" "longhorn" {
  name              = "longhorn"
  namespace         = kubernetes_namespace_v1.storage.id
  create_namespace  = false
  repository        = "https://charts.longhorn.io"
  chart             = "longhorn"
  version           = "1.9.0"
  dependency_update = true
  force_update      = true
  take_ownership    = true
  reset_values      = true
  # atomic          = true
  # cleanup_on_fail = true
}

resource "htpasswd_password" "longhorn" {
  password = var.longhorn_password
}

resource "kubernetes_manifest" "longhorn_buffering_middleware" {
  depends_on = [kubernetes_namespace_v1.storage]
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
  depends_on = [kubernetes_namespace_v1.storage]
  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "IngressRoute"

    metadata = {
      name      = "longhorn-ingress"
      namespace = "longhorn-system"

      annotations = {
        "traefik.ingress.kubernetes.io/router.middlewares" = "longhorn-system-longhorn-auth@kubernetescrd,longhorn-system-longhorn-buffering@kubernetescrd"
        "cert-manager.io/cluster-issuer" = "cloudflare-staging"
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
# Jellyfin - Kubernetes Namespace
#-------------------------------------------------------
resource "kubernetes_namespace_v1" "jellyfin" {
  metadata {
    name = "jellyfin"
    labels = {
      "pod-security.kubernetes.io/enforce" = "privileged"
      # "pod-security.kubernetes.io/enforce"         = "privileged"
      # "pod-security.kubernetes.io/enforce-version" = "latest"
      # "pod-security.kubernetes.io/audit"           = "privileged"
      # "pod-security.kubernetes.io/audit-version"   = "latest"
      # "pod-security.kubernetes.io/warn"            = "privileged"
      # "pod-security.kubernetes.io/warn-version"    = "latest"
    }
  }
}

#-------------------------------------------------------
# Jellyfin - Config Volume
#-------------------------------------------------------
resource "kubernetes_manifest" "jellyfin_config_longhorn_volume" {
  depends_on = [helm_release.longhorn]
  manifest = {
    apiVersion = "longhorn.io/v1beta2"
    kind       = "Volume"

    metadata = {
      name      = "jellyfin-config-volume-rwo"
      namespace = "longhorn-system"
    }

    spec = {
      size             = "10737418240" # 10Gi in bytes
      numberOfReplicas = 2
      frontend         = "blockdev"
      accessMode       = "rwo"
      dataLocality     = "disabled"
    }
  }
}

resource "kubernetes_persistent_volume_v1" "jellyfin_config" {
  depends_on = [kubernetes_manifest.jellyfin_config_longhorn_volume]
  metadata {
    name = "jellyfin-config"
  }

  spec {
    storage_class_name = "longhorn"
    access_modes       = ["ReadWriteOnce"]

    capacity = {
      storage = "10Gi"
    }

    persistent_volume_source {
      csi {
        driver        = "driver.longhorn.io"
        volume_handle = kubernetes_manifest.jellyfin_config_longhorn_volume.manifest.metadata.name
      }
    }
  }
  lifecycle {
    ignore_changes = [
      metadata
    ]
  }
}

resource "kubernetes_persistent_volume_claim_v1" "jellyfin_config" {
  depends_on = [kubernetes_persistent_volume_v1.jellyfin_config]
  metadata {
    name      = "jellyfin-config-pvc"
    namespace = kubernetes_namespace_v1.jellyfin.id
  }
  spec {
    volume_name = kubernetes_persistent_volume_v1.jellyfin_config.metadata.0.name
    # storage_class_name = "longhorn"
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = "10Gi"
      }
    }
  }
}

#-------------------------------------------------------
# Jellyfin - Media Volume
#-------------------------------------------------------
resource "kubernetes_manifest" "jellyfin_media_longhorn_volume" {
  depends_on = [helm_release.longhorn]
  manifest = {
    apiVersion = "longhorn.io/v1beta2"
    kind       = "Volume"

    metadata = {
      name      = "jellyfin-media-volume-rwo"
      namespace = "longhorn-system"
    }

    spec = {
      size             = "1099511627776" # 10Gi in bytes
      numberOfReplicas = 1
      frontend         = "blockdev"
      accessMode       = "rwo"
      dataLocality     = "disabled"
    }
  }
}

resource "kubernetes_persistent_volume_v1" "jellyfin_media" {
  depends_on = [kubernetes_manifest.jellyfin_media_longhorn_volume]
  metadata {
    name = "jellyfin-media"
  }

  spec {
    storage_class_name = "longhorn"
    access_modes       = ["ReadWriteOnce"]

    capacity = {
      storage = "1024Gi"
    }

    persistent_volume_source {
      csi {
        driver        = "driver.longhorn.io"
        volume_handle = kubernetes_manifest.jellyfin_media_longhorn_volume.manifest.metadata.name
      }
    }
  }
  lifecycle {
    ignore_changes = [
      metadata
    ]
  }
}

resource "kubernetes_persistent_volume_claim_v1" "jellyfin_media" {
  metadata {
    name      = "jellyfin-media-pvc"
    namespace = kubernetes_namespace_v1.jellyfin.id
  }
  spec {
    volume_name = kubernetes_persistent_volume_v1.jellyfin_media.metadata.0.name
    # storage_class_name = "longhorn"
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        # storage = "1024Gi"
        storage = "1Ti"
      }
    }

  }
}

#-------------------------------------------------------
# Jellyfin - Helm & Config
#-------------------------------------------------------
resource "local_file" "jellyfin_values" {
  content = templatefile("${path.module}/helm/templates/jellyfin.tftpl", {
    config_pvc = kubernetes_persistent_volume_claim_v1.jellyfin_config.metadata.0.name
    media_pvc  = kubernetes_persistent_volume_claim_v1.jellyfin_media.metadata.0.name
  })
  filename = "${path.module}/helm/tmp/jellyfin.yml"
}

# https://github.com/jellyfin/jellyfin-helm/tree/master/charts/jellyfin
resource "helm_release" "jellyfin" {
  name              = "jellyfin"
  namespace         = kubernetes_namespace_v1.jellyfin.id
  create_namespace  = false
  repository        = "https://jellyfin.github.io/jellyfin-helm"
  chart             = "jellyfin"
  version           = "3.2.0"
  dependency_update = true

  values = [
    local_file.jellyfin_values.content
  ]
}

#-------------------------------------------------------
# Jellyfin - Ingress
#-------------------------------------------------------
resource "kubernetes_manifest" "jellyfin_http_route" {
  manifest = {
    apiVersion = "gateway.networking.k8s.io/v1"
    kind = "HTTPRoute"
    metadata = {
      name = "jellyfin"
      namespace = "traefik"
    }
    spec = {
      hostnames = [
        "media.${var.dns_zone}",
      ]
      parentRefs = [
        {
          name = "traefik-gateway"
        },
      ]
      rules = [
        {
          backendRefs = [
            {
              name = "jellyfin"
              namespace = "jellyfin"
              port = 8096
            },
          ]
          matches = [
            {
              path = {
                type = "PathPrefix"
                value = "/"
              }
            },
          ]
        },
      ]
    }
  }
}

resource "kubernetes_manifest" "referencegrant_jellyfin_http_route" {
  manifest = {
    apiVersion = "gateway.networking.k8s.io/v1beta1"
    kind = "ReferenceGrant"
    metadata = {
      name = "jellyfin"
      namespace = "jellyfin"
    }
    spec = {
      from = [
        {
          group = "gateway.networking.k8s.io"
          kind = "HTTPRoute"
          namespace = "traefik"
        },
      ]
      to = [
        {
          group = ""
          kind = "Service"
          name = "jellyfin"
        },
      ]
    }
  }
}
