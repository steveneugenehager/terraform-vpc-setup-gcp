output "networks" {
  description = "VPC self links keyed by <host>-<env>."
  value       = { for k, v in google_compute_network.vpc : k => v.self_link }
}

output "subnets" {
  description = "Subnet details keyed by <host>-<env>-<subnet>."
  value = {
    for k, v in google_compute_subnetwork.subnet : k => {
      self_link = v.self_link
      region    = v.region
      cidr      = v.ip_cidr_range
    }
  }
}
