data "terraform_remote_state" "projects" {
  backend = "gcs"
  config = {
    bucket = var.state_bucket
    prefix = var.projects_state_prefix
    impersonate_service_account = var.terraform_sa
  }
}

module "vpc" {
  source = "../../modules/vpc"

  project_id = data.terraform_remote_state.projects.outputs.host_project_ids[var.env]
  env        = var.env
  subnets    = var.subnets
  enable_nat = var.enable_nat
}
