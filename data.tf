# Host project IDs come from the projects stage, since they include a random suffix.
data "terraform_remote_state" "projects" {
  backend = "gcs"
  config = {
    bucket = var.state_bucket
    prefix = var.projects_state_prefix
  }
}

locals {
  # Keyed by environment folder name; that name is also used in resource names.
  host_projects = {
    for env, id in data.terraform_remote_state.projects.outputs.host_project_ids :
    env => { project_id = id, env = env }
  }
}
