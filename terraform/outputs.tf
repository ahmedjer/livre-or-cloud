# Informations affichées après terraform apply (terraform output).
# Les valeurs viennent des outputs du module, pas des variables.

# Le module ne donne pas le projet directement. On le récupère dans
# cluster_id qui a la forme projects/<projet>/locations/<region>/clusters/<nom>.
locals {
  cluster_project_id = split("/", module.gke.cluster_id)[1]
}

output "cluster_name" {
  description = "Nom du cluster GKE."
  value       = module.gke.name
}

output "cluster_id" {
  description = "Identifiant complet du cluster."
  value       = module.gke.cluster_id
}

output "cluster_location" {
  description = "Région du cluster."
  value       = module.gke.location
}

output "project_id" {
  description = "Projet GCP du cluster."
  value       = local.cluster_project_id
}

output "cluster_endpoint" {
  description = "Adresse de l'API Kubernetes (sensible : terraform output -raw cluster_endpoint pour la voir)."
  value       = module.gke.endpoint
  sensitive   = true
}

output "kubernetes_version" {
  description = "Version de Kubernetes du cluster."
  value       = module.gke.master_version
}

output "release_channel" {
  description = "Canal de mise à jour appliqué."
  value       = module.gke.release_channel
}

output "gke_connection_command" {
  description = "Commande à copier pour connecter kubectl au cluster."
  value       = "gcloud container clusters get-credentials ${module.gke.name} --location ${module.gke.location} --project ${local.cluster_project_id}"
}
