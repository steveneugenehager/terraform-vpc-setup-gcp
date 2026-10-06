variable "state_bucket" {
  description = "GCS bucket holding Terraform state (from the bootstrap/seed project)."
  type        = string
}

variable "projects_state_prefix" {
  description = "State prefix of the stage that created the net-host projects."
  type        = string
}

variable "networks" {
  description = <<-EOT
    VPC config per environment. Keys must match the keys of var.environments in
    the projects stage; each one becomes the single VPC in that env's host project.
  EOT
  type = map(object({
    routing_mode      = optional(string, "GLOBAL")
    enable_nat        = optional(bool, true)
    enable_shared_vpc = optional(bool, true)
    subnets = map(object({
      region                = string
      ip_cidr_range         = string
      private_google_access = optional(bool, true)
      flow_logs             = optional(bool, false)
      secondary_ranges      = optional(map(string), {}) # name => CIDR (e.g. GKE pods/services)
    }))
  }))

  validation {
    condition = alltrue(flatten([
      for n in values(var.networks) : [
        for s in values(n.subnets) : concat(
          [can(cidrhost(s.ip_cidr_range, 0))],
          [for r in values(s.secondary_ranges) : can(cidrhost(r, 0))]
        )
      ]
    ]))
    error_message = "Every ip_cidr_range and secondary range must be a valid CIDR block."
  }

  validation {
    condition     = alltrue([for n in values(var.networks) : contains(["GLOBAL", "REGIONAL"], n.routing_mode)])
    error_message = "routing_mode must be GLOBAL or REGIONAL."
  }
}

variable "iap_ssh_enabled" {
  description = "Create a firewall rule allowing SSH from Google's IAP range in every VPC."
  type        = bool
  default     = true
}
