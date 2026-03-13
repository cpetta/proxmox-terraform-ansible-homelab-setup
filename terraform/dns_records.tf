provider "dns" {
  update {
    server        = var.dns_server_list[0].ip_address
    key_name      = "home."
    key_algorithm = "hmac-sha256"
    key_secret    = var.dns_tsig_secret
  }
}

resource "dns_a_record_set" "dns" {
  count = length(var.dns_server_list)
  zone = "${var.dns_zone}."
  name = "dns${count.index+1}"
  addresses = [
    var.dns_server_list[count.index].ip_address,
  ]
}

resource "dns_a_record_set" "pm" {
  count = length(var.pm_node_list)
  zone = "${var.dns_zone}."
  name = var.pm_node_list[count.index].name
  addresses = [
    var.pm_node_list[count.index].ip_address,
  ]
}