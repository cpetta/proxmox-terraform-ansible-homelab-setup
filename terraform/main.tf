terraform {
	required_providers {
		dns = {
			source = "hashicorp/dns"
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
	}
}

variable "local" {
	type = bool
	default = true
}

variable "dns_zone" {}
variable "dns_tsig_secret" {}
variable "cipassword" {}
variable "cipassword_hash" {}
variable "ssh_public_key" {}
variable "pm_api_token" {}
variable "pm_api_url" {}
variable "pm_api_url_remote" {}
variable "pm_pasword" {}
variable "tailscale_auth_key" {}

variable "gateway_ip" {}

variable "pm_node_list" {}
variable "dns_server_list" {}
variable "reverse_proxy_list" {}

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

#-------------------------------------------------------
# Cloud Image Resources
#-------------------------------------------------------
resource "proxmox_virtual_environment_download_file" "ubuntu_cloud_image" {
	count        = length(var.pm_node_list)
	content_type = "import"
	datastore_id = "local"
	node_name    = var.pm_node_list[count.index].name
	url          = "https://cloud-images.ubuntu.com/minimal/releases/noble/release/ubuntu-24.04-minimal-cloudimg-amd64.img"
	file_name    = "ubuntu-24.04-minimal-cloudimg-amd64.img.qcow2" # rename to *.qcow2 for import
	overwrite    = false
	overwrite_unmanaged = true
	checksum = "5afe95f6ba186d6e6c7b1582ee34001ac20f609a79b1c68a1c09e5a63f18a460"
	checksum_algorithm = "sha256"
}

#-------------------------------------------------------
# Testing VM
#-------------------------------------------------------
// Reference https://atxfiles.netgate.com/mirror/downloads/
resource "proxmox_virtual_environment_download_file" "mint_iso_1" {
	content_type = "iso"
	datastore_id = "local"
	node_name    = "pm1"
	url          = "https://mirrors.edge.kernel.org/linuxmint/stable/22.3/linuxmint-22.3-xfce-64bit.iso"
	file_name    = "linuxmint-22.3-xfce-64bit.iso"
	overwrite    = false
	overwrite_unmanaged = true
	checksum = "45a835b5dddaf40e84d776549e0b19b3fbd49673b6cc6434ebddbfcd217df776"
	checksum_algorithm = "sha256"
}

#-------------------------------------------------------
# DNS
#-------------------------------------------------------
resource "local_file" "dns_snippet" {
	count = length(var.dns_server_list)
	content = templatefile("${path.module}/cloud-init/templates/common.tftpl", {
		hostname           = "dns${count.index+1}"
		tailscale_auth_key = var.tailscale_auth_key
		cipassword_hash    = var.cipassword_hash
		ssh_public_key     = var.ssh_public_key
	})
	filename = "${path.module}/cloud-init/tmp/cloud_config_dns${count.index+1}.yml"
}

resource "proxmox_virtual_environment_file" "dns_cloud_config" {
	count = length(var.dns_server_list)
	depends_on  = [resource.local_file.dns_snippet]
	content_type = "snippets"
	datastore_id = "local"
	node_name    = var.dns_server_list[count.index].host_node
	source_file {
		path = resource.local_file.dns_snippet[count.index].filename
	}
}

resource "proxmox_virtual_environment_vm" "dns" {
	count       = length(var.dns_server_list)
	# vm_id       = 101
	name        = "dns${count.index+1}"
	node_name   = var.dns_server_list[count.index].host_node
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
		import_from  = proxmox_virtual_environment_download_file.ubuntu_cloud_image[1].id
		interface    = "scsi0"
		discard      = "on"
		size         = 10
	}
	
	initialization {
		datastore_id = "local-lvm"
		user_data_file_id   = proxmox_virtual_environment_file.dns_cloud_config[count.index].id

		ip_config {
			ipv4 {
				address = "${var.dns_server_list[count.index].ip_address}/24"
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

resource "proxmox_virtual_environment_vm" "pfs1" {
	vm_id        = 110
	name        = "pfs1"
	node_name   = "pm2"
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

		ip_config {
			ipv4 {
				address = "${var.pfs1_ip}/24"
				gateway = var.gateway_ip
			}
		}
		dns {
			servers = [for server in var.dns_server_list : server.ip_address]
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
			# ipv4_addresses,
			# ipv6_addresses,
			startup,
		]
	}
}

#-------------------------------------------------------
# Reverse Proxy - traefik
#-------------------------------------------------------
resource "local_file" "reverse_proxy_snippet" {
	count = length(var.reverse_proxy_list)
	content = templatefile("${path.module}/cloud-init/templates/common.tftpl", {
		hostname           = "rp${count.index+1}"
		tailscale_auth_key = var.tailscale_auth_key
		cipassword_hash    = var.cipassword_hash
		ssh_public_key     = var.ssh_public_key
	})
	filename = "${path.module}/cloud-init/tmp/cloud_config_reverse_proxy${count.index+1}.yml"
}

resource "proxmox_virtual_environment_file" "reverse_proxy_cloud_config" {
	count = length(var.reverse_proxy_list)
	depends_on  = [resource.local_file.reverse_proxy_snippet]
	content_type = "snippets"
	datastore_id = "local"
	node_name    = var.reverse_proxy_list[count.index].host_node
	source_file {
		path = resource.local_file.reverse_proxy_snippet[count.index].filename
	}
}

resource "proxmox_virtual_environment_vm" "reverse_proxy" {
	count = length(var.reverse_proxy_list)
	name        = "rp${count.index+1}"
	node_name   = var.reverse_proxy_list[count.index].host_node
	description = "Managed by Terraform"
	tags        = ["terraform"]
	started = true
	on_boot = true
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
		datastore_id = "local-lvm"
		user_data_file_id   = proxmox_virtual_environment_file.reverse_proxy_cloud_config[count.index].id

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
			started,
			startup,
		]
	}
}