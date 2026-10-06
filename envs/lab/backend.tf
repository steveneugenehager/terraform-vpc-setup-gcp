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
    bucket = "REPLACE-with-your-tfstate-bucket"
    prefix = "network/test"
  }
}

provider "google" {}
