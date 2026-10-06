env                   = "test" # REPLACE with the environment folder name
state_bucket          = "REPLACE-with-your-tfstate-bucket"
projects_state_prefix = "REPLACE-with-projects-stage-prefix"

subnets = {
  use1 = { region = "us-east1",    ip_cidr_range = "10.20.0.0/20" }
  usc1 = { region = "us-central1", ip_cidr_range = "10.20.16.0/20" }
}
