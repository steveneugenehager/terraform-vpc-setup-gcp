env                   = "lab" # REPLACE with the environment folder name
state_bucket          = "shv-cld-admn-btstrp-4329-tfstate"
projects_state_prefix = "projects/network-hosts"
terraform_sa          = "terraform@shv-cld-admn-btstrp-4329.iam.gserviceaccount.com"

#flow_logs should be enabled (true) in production. False here in a lower environment.
subnets = {
  use1 = { region = "us-east1", ip_cidr_range = "10.20.0.0/20", flow_logs = false }
  usc1 = { region = "us-central1", ip_cidr_range = "10.20.16.0/20", flow_logs = false }
}
