#-------------------------------------------------------
# Cloud Image Resources
#-------------------------------------------------------
resource "proxmox_virtual_environment_download_file" "ubuntu_cloud_image" {
  for_each            = toset(distinct(var.pm_node_list[*].name))
  content_type        = "import"
  datastore_id        = "local"
  node_name           = each.value
  url                 = "https://cloud-images.ubuntu.com/minimal/releases/noble/release/ubuntu-24.04-minimal-cloudimg-amd64.img"
  file_name           = "ubuntu-24.04-minimal-cloudimg-amd64.img.qcow2" # rename to *.qcow2 for import
  overwrite           = false
  overwrite_unmanaged = true
  checksum            = "7cbfa215a3774c46c6dc29b457f4e9667acda85fc04c7971e1e592b5056e7573"
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
# data "talos_image_factory_versions" "this" {
#   filters = {
#     stable_versions_only = true
#   }
# }

locals {
  # talos_version_latest = element(data.talos_image_factory_versions.this.talos_versions, length(data.talos_image_factory_versions.this.talos_versions) - 1)
  talos_version = "v1.13.0" // local.talos_version_latest // "v1.12.6"
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
# Talos Worker Image for Bare Metal Installations
#-------------------------------------------------------
data "talos_image_factory_extensions_versions" "metal_worker" {
  talos_version = local.talos_version
  filters = {
    names = [
      "siderolabs/iscsi-tools",
      "siderolabs/util-linux-tools",
      "siderolabs/nfs-utils",
      "siderolabs/nfsd",
    ]
  }
}

resource "talos_image_factory_schematic" "metal_worker" {
  schematic = yamlencode({
    customization = {
      systemExtensions = {
        officialExtensions = data.talos_image_factory_extensions_versions.metal_worker.extensions_info.*.name
      }
    }
  })
}

data "talos_image_factory_urls" "metal_worker" {
  talos_version = local.talos_version
  schematic_id  = talos_image_factory_schematic.metal_worker.id
  platform      = "metal"
}

output "iso_file_download" {
  value = data.talos_image_factory_urls.metal_worker.urls.iso_secureboot
}