
# Terraform and provider version requirements.

terraform {
  required_version = ">= 1.3.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 8.0"
    }

    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 8.0"
    }

    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

# Main Google Cloud provider.
provider "google" {
  project = var.project_id
  region  = var.region
}

# Beta provider required by the GKE Autopilot module.
provider "google-beta" {
  project = var.project_id
  region  = var.region
}
