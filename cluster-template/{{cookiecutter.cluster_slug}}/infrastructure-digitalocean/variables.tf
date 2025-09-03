variable "access_token" {
  type        = string
  description = "DitialOcean access token."
  sensitive   = true
}

variable "access_key_id" {
  type        = string
  description = "DigitalOcean Spaces access key ID."
  sensitive   = true
}

variable "secret_access_key" {
  type        = string
  description = "DigitalOcean Spaces secret access key."
  sensitive   = true
}

variable "region" {
  type        = string
  default     = "nyc3"
  description = "DigitalOcean region to create the resources in."
  validation {
    condition = contains([
      "ams3",
      "blr1",
      "fra1",
      "lon1",
      "nyc3",
      "sfo2",
      "sfo3",
      "sgp1",
      "syd1",
      "tor1",
    ], var.region)
    error_message = "The DigitalOcean region must be in the acceptable region list."
  }
}

variable "vpc_ip_range" {
  type        = string
  default     = "10.12.0.0/24"
  description = "CIDR block for the VPC network."
  validation {
    condition = can(cidrhost(var.vpc_ip_range, 0))
    error_message = "The VPC IP range must be a valid CIDR block."
  }
}

variable "kubernetes_cluster_name" {
  type        = string
  default     = "{{ cookiecutter.cluster_slug|replace('_', '-') }}"
  description = "Name of the Kubernetes cluster to create."
}

variable "kubernetes_version" {
  type        = string
  default     = "1.33.1-do.3"
  description = "Kubernetes version for the cluster."
}

variable "environment" {
  type        = string
  default     = "{{ cookiecutter.environment }}"
  description = "The project environment. (for example: production, staging, development, etc.)"
}

variable "lets_encrypt_notification_inbox" {
  type        = string
  default     = "dev@example.com"
  description = "The email address to receive notifications from Let's Encrypt."
}

variable "mysql_version" {
  type        = string
  default     = "8"
  description = "MySQL version to use for the database cluster."
}

variable "mysql_instance_size" {
  type        = string
  default     = "db-s-1vcpu-1gb"
  description = "MySQL instance size to use for the database cluster."
  validation {
    condition = can(regex("^db-[sm]-[0-9]+vcpu-[0-9]+gb$", var.mysql_instance_size))
    error_message = "MySQL instance size must be a valid DigitalOcean database instance type."
  }
}

variable "mysql_cluster_instances" {
  type        = number
  default     = 1
  description = "MySQL cluster instances to use for the database cluster."
  validation {
    condition = var.mysql_cluster_instances >= 1 && var.mysql_cluster_instances <= 10
    error_message = "MySQL cluster instances must be between 1 and 10."
  }
}

variable "mongodb_version" {
  type        = string
  default     = "7"
  description = "MongoDB version to use for the database cluster."
}

variable "mongodb_instance_size" {
  type        = string
  default     = "db-s-1vcpu-2gb"
  description = "MongoDB instance size to use for the database cluster."
  validation {
    condition = can(regex("^db-[sm]-[0-9]+vcpu-[0-9]+gb$", var.mongodb_instance_size))
    error_message = "MongoDB instance size must be a valid DigitalOcean database instance type."
  }
}

variable "mongodb_cluster_instances" {
  type        = number
  default     = 3
  description = "MongoDB cluster instances to use for the database cluster."
  validation {
    condition = var.mongodb_cluster_instances >= 1 && var.mongodb_cluster_instances <= 10
    error_message = "MongoDB cluster instances must be between 1 and 10."
  }
}
