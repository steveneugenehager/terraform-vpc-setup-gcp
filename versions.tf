terraform {
  required_version = ">= 1.5"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 6.0, < 8.0"
    }
  }

  # State lives in the bucket created by your bootstrap/seed project.
  backend "gcs" {
    bucket = "REPLACE-with-your-tfstate-bucket"
    prefix = "networking/vpcs"
  }
}

provider "google" {}
