variable "env" {
  description = "Environment folder name; must be a key of the projects stage's host_project_ids output."
  type        = string
}

variable "state_bucket" {
  description = "GCS bucket holding Terraform state."
  type        = string
}

variable "projects_state_prefix" {
  description = "State prefix of the stage that created the net-host projects."
  type        = string
}

variable "terraform_sa" {
  description = "Service Account used to execute terraform operations."
  type        = string
}

variable "subnets" {
  description = "Subnets for this environment's VPC, keyed by short name."
  type = map(object({
    region                = string
    ip_cidr_range         = string
    private_google_access = optional(bool, true)
    flow_logs             = optional(bool, false)
    secondary_ranges      = optional(map(string), {})
  }))
}

variable "enable_nat" {
  type    = bool
  default = true
}
