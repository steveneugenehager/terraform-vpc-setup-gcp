variable "net_host_projects" {
  description = <<-EOT
    Net-host projects keyed by a short name. Each project gets one VPC per
    environment listed under it, each with its own subnets.
  EOT
  type = map(object({
    project_id         = string
    enable_shared_vpc  = optional(bool, true)
    environments = map(object({
      routing_mode = optional(string, "GLOBAL")
      enable_nat   = optional(bool, true)
      subnets = map(object({
        region                = string
        ip_cidr_range         = string
        private_google_access = optional(bool, true)
        flow_logs             = optional(bool, false)
        secondary_ranges      = optional(map(string), {}) # name => CIDR (e.g. GKE pods/services)
      }))
    }))
  }))

  validation {
    condition = alltrue(flatten([
      for p in values(var.net_host_projects) : [
        for e in values(p.environments) : [
          for s in values(e.subnets) : concat(
            [can(cidrhost(s.ip_cidr_range, 0))],
            [for r in values(s.secondary_ranges) : can(cidrhost(r, 0))]
          )
        ]
      ]
    ]))
    error_message = "Every ip_cidr_range and secondary range must be a valid CIDR block."
  }

  validation {
    condition = alltrue(flatten([
      for p in values(var.net_host_projects) : [
        for e in values(p.environments) : contains(["GLOBAL", "REGIONAL"], e.routing_mode)
      ]
    ]))
    error_message = "routing_mode must be GLOBAL or REGIONAL."
  }
}

variable "name_prefix" {
  description = "Prefix for resource names, e.g. vpc-<env>-<host>."
  type        = string
  default     = "vpc"
}

variable "iap_ssh_enabled" {
  description = "Create a firewall rule allowing SSH from Google's IAP range in every VPC."
  type        = bool
  default     = true
}
