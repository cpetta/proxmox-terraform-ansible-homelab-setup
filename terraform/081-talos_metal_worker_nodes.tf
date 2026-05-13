#-------------------------------------------------------
# Talos Metal Nodes
#-------------------------------------------------------
data "talos_machine_configuration" "metal_worker" {
  for_each = var.k8_metal_worker_list
  cluster_name       = local.k8_cluster_config.name
  machine_type       = "worker"
  cluster_endpoint   = local.k8_cluster_config.endpoint
  machine_secrets    = talos_machine_secrets.this.machine_secrets
  kubernetes_version = local.k8_cluster_config.kubernetes_version
  config_patches     = [
    yamlencode(local.talos_metal_worker_patch[each.key]),
    yamlencode(local.talos_metal_worker_patch_hostname[each.key])
  ]
}

data "talos_client_configuration" "metal_worker" {
  cluster_name         = local.k8_cluster_config.name
  client_configuration = talos_machine_secrets.this.client_configuration
  endpoints            = [ for node in var.k8_metal_worker_list : node.ip_address ]
}

resource "local_file" "metal_worker_machine_config" {
  for_each = var.k8_metal_worker_list
  content  = data.talos_machine_configuration.metal_worker[each.key].machine_configuration
  filename = "${path.module}/../backups/talos/metal_worker_machine_config_${each.key}.yaml"
}