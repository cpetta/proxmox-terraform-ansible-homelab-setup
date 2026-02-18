terraform {
  required_providers {
    proxmox = {
      source  = "telmate/proxmox"
      version = "<version tag>"
    }
  }
}

variable "tailscale_auth_key" {}

provider "proxmox" {
  pm_api_url = "https://prox.tailce4075.ts.net:8006/api2/json"
  pm_debug = true
}