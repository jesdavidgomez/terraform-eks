variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "vpc_id" {
  description = "Vpc Id"
  type        = string
  default     = ""
}

variable "availability_zone_1" {
  description = "Availability zone 1"
  type        = string
  default     = ""
}

variable "availability_zone_2" {
  description = "Availability zone 2"
  type        = string
  default     = ""
}

variable "cidr_private_1" {
  description = "Cidr_1"
  type        = string
  default     = ""
}

variable "cidr_private_2" {
  description = "Cidr_2"
  type        = string
  default     = ""
}

variable "cidr_public_1" {
  description = "Cidr public 1"
  type        = string
  default     = ""
}

variable "cidr_public_2" {
  description = "Cidr public 2"
  type        = string
  default     = ""
}

variable "igw_id" {
  description = "IGW Id"
  type        = string
  default     = ""
}

variable "solg_project" {
  description = "value"
  type        = string
  default     = ""
}

variable "environment" {
  description = "value"
  type        = string
  default     = ""
}

variable "cluster_name" {
  description = "cluster_name"
  type        = string
  default     = ""
}
