# Versions de Terraform et des providers.
# Les providers sont ceux demandés par le module GKE 46.x.
# Les versions exactes sont dans .terraform.lock.hcl, qu'on garde
# dans Git pour que tout le monde installe les mêmes versions.

terraform {
  required_version = ">= 1.3.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 8.0"
    }

    # Provider beta, utilisé par le module "beta-autopilot".
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 8.0"
    }

    # Demandé par le module (on ne s'en sert pas pour déployer l'appli).
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }

    # Utilisé par le module pour générer des noms aléatoires.
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

# Projet et région par défaut pour les deux providers Google.
provider "google" {
  project = var.project_id
  region  = var.region
}

provider "google-beta" {
  project = var.project_id
  region  = var.region
}
