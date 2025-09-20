variable "aws_access_key_id" {
  type        = string
  description = "AWS access key ID."
  sensitive   = true
}

variable "aws_secret_access_key" {
  type        = string
  description = "AWS secret access key."
  sensitive   = true
}

variable "aws_region" {
  type        = string
  description = "AWS region to create the resources in."
}

variable "region" {
  type        = string
  default     = "us-east-1"
  description = "AWS region to create the resources in."
}

variable "vpc_cidr" {
  type        = string
  default     = "10.0.0.0/16"
  description = "CIDR block for the VPC network."
  validation {
    condition = can(cidrhost(var.vpc_cidr, 0))
    error_message = "The VPC CIDR block must be valid."
  }
}

variable "private_subnets" {
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  description = "List of private subnet CIDR blocks for the VPC."
  validation {
    condition = alltrue([
      for subnet in var.private_subnets : can(cidrhost(subnet, 0))
    ])
    error_message = "All private subnet CIDR blocks must be valid."
  }
}

variable "public_subnets" {
  type        = list(string)
  default     = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
  description = "List of public subnet CIDR blocks for the VPC."
  validation {
    condition = alltrue([
      for subnet in var.public_subnets : can(cidrhost(subnet, 0))
    ])
    error_message = "All public subnet CIDR blocks must be valid."
  }
}

variable "kubernetes_cluster_name" {
  type        = string
  default     = "{{ cookiecutter.cluster_slug|replace('_', '-') }}"
  description = "Name of the Kubernetes cluster to create."
}

variable "kubernetes_version" {
  type        = string
  default     = "1.33"
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
  default     = "db.t3.micro"
  description = "MySQL instance size to use for the database cluster."
  validation {
    condition = can(regex("^db\\.[a-z0-9]+\\.[a-z0-9]+$", var.mysql_instance_size))
    error_message = "MySQL instance size must be a valid AWS RDS instance type."
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
  default     = "db.t3.medium"
  description = "MongoDB instance size to use for the database cluster."
  validation {
    condition = can(regex("^db\\.[a-z0-9]+\\.[a-z0-9]+$", var.mongodb_instance_size))
    error_message = "MongoDB instance size must be a valid AWS DocumentDB instance type."
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
