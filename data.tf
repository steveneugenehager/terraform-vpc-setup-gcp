# Host project IDs come from the projects stage, since they include a random suffix.
data "terraform_remote_state" "projects" {
  backend = "gcs"
  config = {
    bucket = var.state_bucket
    prefix = var.projects_state_prefix
  }
}

locals {
  host_projects = data.terraform_remote_state.projects.outputs.host_projects
}
