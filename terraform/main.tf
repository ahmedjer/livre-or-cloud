
# =============================================
# GKE Autopilot Cluster
# =============================================
# Uses the specific Terraform module required
# by the Cloud Guestbook project.

module "gke" {
  source  = "terraform-google-modules/kubernetes-engine/google//modules/beta-autopilot-public-cluster"
  version = "~> 46.0"

  project_id = var.project_id
  name       = var.cluster_name
  region     = var.region

  network    = var.network
  subnetwork = var.subnetwork

  ip_range_pods     = var.ip_range_pods
  ip_range_services = var.ip_range_services

  release_channel = var.release_channel

  deletion_protection = var.deletion_protection
}
