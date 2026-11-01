
# ==================================================
# Cloud Guestbook - GKE Autopilot Infrastructure
# ==================================================
# Creates the GKE cluster using the mandatory
# Terraform Google Kubernetes Engine module.
# Application deployment is handled separately by Helm.

module "gke" {
  # Official GKE Autopilot public cluster submodule.
  source  = "terraform-google-modules/kubernetes-engine/google//modules/beta-autopilot-public-cluster"
  version = "~> 46.0"

  # Temporary Google Cloud project provided by the lab.
  project_id = var.project_id

  # Required Kubernetes cluster name.
  name = var.cluster_name

  # Regional deployment location.
  region = var.region

  # Existing default VPC and regional subnet.
  network    = var.network
  subnetwork = var.subnetwork

  # Automatic IP range allocation.
  ip_range_pods     = var.ip_range_pods
  ip_range_services = var.ip_range_services

  # Regular channel for managed Kubernetes updates.
  release_channel = var.release_channel

  # Disabled to allow deletion at the end of the lab.
  deletion_protection = var.deletion_protection
}
