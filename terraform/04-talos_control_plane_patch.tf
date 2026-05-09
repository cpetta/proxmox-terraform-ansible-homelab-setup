#-------------------------------------------------------
# Talos Control Plain Image Patch
#-------------------------------------------------------
locals {
  talos_control_plane_patch = {
    machine = {
      install = {
        disk  = "/dev/sda"
        image = data.talos_image_factory_urls.this.urls.installer
      }
      network = {
        interfaces = [
          {
            interface = "eth0"
            dhcp = false

            # HA Layer 2 VIP configuration
            vip = {
              ip = "192.168.0.227"
            }
          }
        ]
      }
    }
  }
}