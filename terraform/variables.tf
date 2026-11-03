# Variables de la configuration Terraform.
# project_id et region changent à chaque session de lab :
# elles n'ont pas de valeur par défaut, on les met dans terraform.tfvars.

variable "project_id" {
  description = "ID du projet GCP donné par le lab (exemple : qwiklabs-gcp-01-xxxxxxxx)."
  type        = string
}

variable "cluster_name" {
  description = "Nom du cluster GKE."
  type        = string
  default     = "autopilot-cluster-1"
}

variable "region" {
  description = "Région GCP donnée par le lab (exemple : us-central1). Une région, pas une zone."
  type        = string

  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]+$", var.region))
    error_message = "La région doit ressembler à us-central1 ou europe-west1 (pas une zone comme us-central1-a)."
  }
}

variable "network" {
  description = "Nom du réseau VPC existant."
  type        = string
  default     = "default"
}

variable "subnetwork" {
  description = "Nom du sous-réseau existant dans la région."
  type        = string
  default     = "default"
}

variable "ip_range_pods" {
  description = "Plage IP secondaire pour les pods. null = gérée automatiquement par GKE."
  type        = string
  default     = null
}

variable "ip_range_services" {
  description = "Plage IP secondaire pour les services. null = gérée automatiquement par GKE."
  type        = string
  default     = null
}

variable "release_channel" {
  description = "Canal de mise à jour de GKE : RAPID, REGULAR ou STABLE."
  type        = string
  default     = "REGULAR"

  validation {
    condition     = contains(["RAPID", "REGULAR", "STABLE"], var.release_channel)
    error_message = "Le canal doit être RAPID, REGULAR ou STABLE."
  }
}

variable "deletion_protection" {
  description = "Protection contre la suppression du cluster. false pour pouvoir faire terraform destroy à la fin du lab."
  type        = bool
  default     = false
}
