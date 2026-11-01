
# ==================================================
# Cloud Guestbook - GKE Autopilot Terraform Outputs
# ==================================================
# Information required for operating and connecting
# to the Kubernetes cluster.

output "cluster_name" {
  description = "Name of the GKE Autopilot cluster."
  value       = module.gke.name
}

output "cluster_id" {
  description = "Unique identifier of the GKE cluster."
  value       = module.gke.cluster_id
}

output "cluster_location" {
  description = "Region where the GKE cluster is deployed."
  value       = module.gke.location
}

output "project_id" {
  description = "Google Cloud project hosting the cluster."
  value       = var.project_id
}

output "cluster_endpoint" {
  description = "Kubernetes API server endpoint."
  value       = module.gke.endpoint
  sensitive   = true
}

output "kubernetes_version" {
  description = "Current Kubernetes control plane version."
  value       = module.gke.master_version
}

output "release_channel" {
  description = "GKE release channel."
  value       = module.gke.release_channel
}

output "gke_connection_command" {
  description = "Command used to configure kubectl access to GKE."
  value       = "gcloud container clusters get-credentials ${module.gke.name} --location ${module.gke.location} --project ${var.project_id}"
}
