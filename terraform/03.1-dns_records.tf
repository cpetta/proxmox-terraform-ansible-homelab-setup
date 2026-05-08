provider "dns" {
  update {
    server        = var.dns_server_list[0].ip_address // var.k8_dns_server_list[0].ip_address
    key_name      = "home."
    key_algorithm = "hmac-sha256"
    key_secret    = var.dns_tsig_secret
  }
}

# load balanced dns
resource "dns_a_record_set" "dns_lb" {
  zone = "${var.dns_zone}."
  name = "dns"
  addresses = [
    var.k8_service_list.rp,
  ]
}

# dns servers
resource "dns_a_record_set" "dns" {
  count = length(var.dns_server_list) + length(var.k8_dns_server_list)
  zone  = "${var.dns_zone}."
  name  = "dns${count.index + 1}"
  addresses = [
    var.k8_service_list.rp,
  ]
}

# Kubernetes Resources
resource "dns_a_record_set" "k8_services" {
  for_each = var.k8_service_list
  zone     = "${var.dns_zone}."
  name     = each.key
  addresses = [
    each.value,
  ]
}

# load balanced proxmox
resource "dns_a_record_set" "pm_lb" {
  zone = "${var.dns_zone}."
  name = "pm"
  addresses = [
    var.k8_service_list.rp,
  ]
}