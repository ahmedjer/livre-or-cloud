# Création du cluster GKE Autopilot avec le module imposé.
# Terraform crée seulement le cluster. L'application est
# installée ensuite avec Helm.

module "gke" {
  # Module imposé : cluster GKE Autopilot avec un accès public à l'API.
  source = "terraform-google-modules/kubernetes-engine/google//modules/beta-autopilot-public-cluster"
  # Version 46.x du module. source et version ne peuvent pas être des variables.
  version = "~> 46.0"

  # Projet GCP donné par le lab (il change à chaque session).
  project_id = var.project_id

  # Nom du cluster : autopilot-cluster-1.
  name = var.cluster_name

  # Région donnée par le lab. Un cluster Autopilot est toujours régional.
  region = var.region

  # Réseau et sous-réseau "default", qui existent déjà dans le projet du lab.
  network    = var.network
  subnetwork = var.subnetwork

  # null : GKE crée lui-même les plages d'adresses IP des pods et des services.
  ip_range_pods     = var.ip_range_pods
  ip_range_services = var.ip_range_services

  # Canal de mise à jour de GKE (REGULAR = versions déjà testées).
  release_channel = var.release_channel

  # false : sinon terraform destroy ne peut pas supprimer le cluster.
  deletion_protection = var.deletion_protection
}
