terraform {
  required_version = ">= 1.5"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 6.0, < 8.0"
    }
  }

  # One state file per environment. Backend blocks can't use variables,
  # so the prefix is fixed here.
  backend "gcs" {
    bucket = "shv-cld-admn-btstrp-4329-tfstate"
    prefix = "network/lab"
    impersonate_service_account = "terraform@shv-cld-admn-btstrp-4329.iam.gserviceaccount.com"
  }
}

provider "google" {
    impersonate_service_account = "terraform@shv-cld-admn-btstrp-4329.iam.gserviceaccount.com"
}
