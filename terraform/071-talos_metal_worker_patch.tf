#-------------------------------------------------------
# Talos Worker Node Image Patch
#-------------------------------------------------------
locals {
  talos_metal_worker_patch = {
    for i, each in var.k8_metal_worker_list : i => {
      machine = {
        install = {
          disk       = "/dev/${each.install_disk}"
          image      = data.talos_image_factory_urls.metal_worker.urls.installer_secureboot
          bootloader = true
          wipe       = true
        }
        disks = each.disks
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
          extraArgs = {
            rotate-server-certificates = true
          }
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
  talos_metal_worker_patch_hostname = {
    for i, each in var.k8_metal_worker_list : i => {
        apiVersion = "v1alpha1"
        kind       = "HostnameConfig"
        hostname   = each.hostname
        auto       = "off"
    }
  }
}