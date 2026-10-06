variable "project_id" {
  description = "Net-host project that will own the VPC."
  type        = string
}

variable "env" {
  description = "Environment name, used in resource names."
  type        = string
}

variable "routing_mode" {
  description = "VPC dynamic routing mode."
  type        = string
  default     = "GLOBAL"

  validation {
    condition     = contains(["GLOBAL", "REGIONAL"], var.routing_mode)
    error_message = "routing_mode must be GLOBAL or REGIONAL."
  }
}

variable "subnets" {
  description = "Subnets keyed by a short name (e.g. use1)."
  type = map(object({
    region                = string
    ip_cidr_range         = string
    private_google_access = optional(bool, true)
    flow_logs             = optional(bool, false)
    secondary_ranges      = optional(map(string), {}) # name => CIDR (e.g. GKE pods/services)
  }))

  validation {
    condition = alltrue(flatten([
      for s in values(var.subnets) : concat(
        [can(cidrhost(s.ip_cidr_range, 0))],
        [for r in values(s.secondary_ranges) : can(cidrhost(r, 0))]
      )
    ]))
    error_message = "Every ip_cidr_range and secondary range must be a valid CIDR block."
  }
}

variable "enable_nat" {
  description = "Create a Cloud Router and Cloud NAT in each subnet region."
  type        = bool
  default     = true
}

variable "enable_shared_vpc" {
  description = "Register the project as a Shared VPC host."
  type        = bool
  default     = true
}

variable "iap_ssh_enabled" {
  description = "Allow SSH from Google's IAP range."
  type        = bool
  default     = true
}
