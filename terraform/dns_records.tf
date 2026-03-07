provider "dns" {
  update {
    server        = var.dns_server_list[0].ip_address
    key_name      = "home."
    key_algorithm = "hmac-sha256"
    key_secret    = "eCewkZDFPdnB1+9YeDfvEFLbVwVTZgoLaJZjJh7M+KI="
  }
}

resource "dns_a_record_set" "www" {
  zone = "home.net."
  name = "dns1"
  addresses = [
    var.dns_server_list[0].ip_address,
  ]
#   ttl = 300
}