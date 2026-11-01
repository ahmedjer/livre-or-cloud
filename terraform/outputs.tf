
# Terraform outputs for the deployed GKE cluster.

output "cluster_name" {
  description = "Name of the GKE Autopilot cluster."
  value       = module.gke.name
}

output "cluster_id" {
  description = "Unique ID of the GKE cluster."
  value       = module.gke.cluster_id
}

output "cluster_location" {
  description = "Region hosting the GKE cluster."
  value       = module.gke.location
}

output "cluster_endpoint" {
  description = "Kubernetes API endpoint."
  value       = module.gke.endpoint
  sensitive   = true
}

output "release_channel" {
  description = "Configured GKE release channel."
  value       = module.gke.release_channel
}
