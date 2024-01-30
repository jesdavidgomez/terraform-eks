variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "cluster_name"
  type        = string
  default     = ""
}

variable "argourl" {
  description = "Argocd URL"
  type        = string
  default     = ""
}

variable "host_zone" {
  description = "Host zone"
  type        = string
  default     = ""
}
