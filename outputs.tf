output "networks" {
  description = "VPC per environment."
  value = {
    for k, v in google_compute_network.vpc : k => {
      project_id = v.project
      name       = v.name
      self_link  = v.self_link
    }
  }
}

output "subnets" {
  description = "Subnets keyed by <env>-<subnet>."
  value = {
    for k, v in google_compute_subnetwork.subnet : k => {
      self_link = v.self_link
      region    = v.region
      cidr      = v.ip_cidr_range
    }
  }
}
