#-------------------------------------------------------
# Talos Control Plain Image Patch
#-------------------------------------------------------
locals {
  talos_metal_control_patch = {
    for i, each in var.k8_metal_control_list : i => {
      machine = {
        install = {
          disk  = "/dev/sda"
          image = data.talos_image_factory_urls.this.urls.installer
        }
        network = {
          interfaces = [
            {
              interface = "eth0"
              dhcp      = false

              # HA Layer 2 VIP configuration
              vip = {
                ip = "192.168.0.227"
              }
            }
          ]
        }
        kubelet = {
          extraArgs = {
            rotate-server-certificates = true
          }
        }
      }
      cluster = {
        etcd = {
          extraArgs = {
            listen-metrics-urls = "http://0.0.0.0:2381"
          }
        }
      }
    }
  }
  talos_metal_control_patch_hostname = {
    for i, each in var.k8_metal_control_list : i => {
        apiVersion = "v1alpha1"
        kind       = "HostnameConfig"
        hostname   = each.hostname
        auto       = "off"
    }
  }
}