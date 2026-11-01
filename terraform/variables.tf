
# =============================================
# Cloud Guestbook - Terraform Input Variables
# =============================================

# Google Cloud project ID assigned by the Skills lab.
variable "project_id" {
  description = "Google Cloud project ID provided by the temporary lab."
  type        = string
}

# Name of the GKE Autopilot cluster.
variable "cluster_name" {
  description = "Name of the GKE Autopilot cluster."
  type        = string
  default     = "autopilot-cluster-1"
}

# Google Cloud region selected for the cluster.
variable "region" {
  description = "GCP region provided or permitted by the lab."
  type        = string
}

# Existing Google Cloud VPC network.
variable "network" {
  description = "Name of the existing VPC network."
  type        = string
  default     = "default"
}

# Existing subnet in the selected region.
variable "subnetwork" {
  description = "Name of the existing GCP subnetwork."
  type        = string
  default     = "default"
}

# Secondary IP range for Kubernetes Pods.
variable "ip_range_pods" {
  description = "Existing Pod secondary range name; null lets the module use automatic allocation."
  type        = string
  default     = null
}

# Secondary IP range for Kubernetes Services.
variable "ip_range_services" {
  description = "Existing Service secondary range name; null uses module defaults."
  type        = string
  default     = null
}

# GKE Kubernetes release channel.
variable "release_channel" {
  description = "GKE release channel."
  type        = string
  default     = "REGULAR"

  validation {
    condition     = contains(["RAPID", "REGULAR", "STABLE"], var.release_channel)
    error_message = "The release channel must be RAPID, REGULAR or STABLE."
  }
}

# Allow Terraform to delete the temporary cluster.
variable "deletion_protection" {
  description = "Disable deletion protection for temporary lab cleanup."
  type        = bool
  default     = false
}
