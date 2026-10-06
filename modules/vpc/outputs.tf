output "network" {
  description = "The VPC."
  value = {
    id        = google_compute_network.this.id
    name      = google_compute_network.this.name
    self_link = google_compute_network.this.self_link
  }
}

output "subnets" {
  description = "Subnets keyed by short name."
  value = {
    for k, s in google_compute_subnetwork.this : k => {
      self_link = s.self_link
      region    = s.region
      cidr      = s.ip_cidr_range
    }
  }
}
