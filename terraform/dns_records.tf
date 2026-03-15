provider "dns" {
  update {
    server        = var.dns_server_list[0].ip_address
    key_name      = "home."
    key_algorithm = "hmac-sha256"
    key_secret    = var.dns_tsig_secret
  }
}

# gateway
resource "dns_a_record_set" "gateway" {
  zone = "${var.dns_zone}."
  name = "gateway"
  addresses = [
    var.reverse_proxy_list[0].ip_address,
  ]
}

# load balanced dns
resource "dns_a_record_set" "dns_lb" {
  zone = "${var.dns_zone}."
  name = "dns"
  addresses = [
    var.reverse_proxy_list[0].ip_address,
  ]
}

# dns servers
resource "dns_a_record_set" "dns" {
  count = length(var.dns_server_list)
  zone = "${var.dns_zone}."
  name = "dns${count.index+1}"
  addresses = [
    var.reverse_proxy_list[0].ip_address,
  ]
}

# Reverse Proxy
resource "dns_a_record_set" "rp" {
  count = length(var.reverse_proxy_list)
  zone = "${var.dns_zone}."
  name = var.reverse_proxy_list[count.index].name
  addresses = [
    var.reverse_proxy_list[count.index].ip_address,
  ]
}

# load balanced proxmox
resource "dns_a_record_set" "pm_lb" {
  zone = "${var.dns_zone}."
  name = "pm"
  addresses = [
    var.reverse_proxy_list[0].ip_address,
  ]
}

# proxmox servers
resource "dns_a_record_set" "pm" {
  count = length(var.pm_node_list)
  zone = "${var.dns_zone}."
  name = var.pm_node_list[count.index].name
  addresses = [
    var.reverse_proxy_list[0].ip_address,
  ]
}