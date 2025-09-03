locals {
  harmony_terraform_module_version = "{{ cookiecutter.harmony_module_version }}"
}

data "aws_caller_identity" "current" {}
data "aws_availability_zones" "available" {}

module "main_vpc" {
  source = "git::https://github.com/openedx/openedx-k8s-harmony.git//terraform/modules/aws/vpc?ref=${local.harmony_terraform_module_version}"

  availability_zones     = data.aws_availability_zones.available.names
  one_nat_gateway_per_az = false
  single_nat_gateway     = true

  region       = var.region
  environment  = var.environment

  vpc_ip_range = var.vpc_cidr
  private_subnets = var.private_subnets
  public_subnets  = var.public_subnets

  public_subnet_tags = {
    "Tier"                   = "Public"
    "kubernetes.io/role/elb" = "1"
  }

  private_subnet_tags = {
    "Tier"                            = "Private"
    "kubernetes.io/role/internal-elb" = "1"
  }
}

module "kubernetes_cluster" {
  source = "git::https://github.com/openedx/openedx-k8s-harmony.git//terraform/modules/aws/doks?ref=${local.harmony_terraform_module_version}"

  environment = var.environment
  vpc_id      = module.main_vpc.vpc_id

  cluster_name       = var.kubernetes_cluster_name
  kubernetes_version = var.kubernetes_version
}

module "kubernetes_cert_manager" {
  depends_on = [module.kubernetes_cluster]

  source = "git::https://gitlab.com/opencraft/ops/terraform-modules.git//modules/k8s-cert-manager?ref=v1.0.1"

  namespace                       = "kube-system"
  lets_encrypt_notification_inbox = var.lets_encrypt_notification_inbox
}

module "kubernetes_ingress" {
  depends_on = [module.kubernetes_cluster]

  source = "git::https://gitlab.com/opencraft/ops/terraform-modules.git//modules/k8s-nginx-ingress?ref=v1.0.1"

  ingress_namespace = "kube-system"
}

module "mysql_database" {
  source = "git::https://github.com/openedx/openedx-k8s-harmony.git//terraform/modules/digitalocean/database?ref=${local.harmony_terraform_module_version}"

  region                  = var.region
  environment             = var.environment
  access_token            = var.access_token
  vpc_id                  = module.main_vpc.vpc_id
  kubernetes_cluster_name = var.kubernetes_cluster_name

  database_engine                  = "mysql"
  database_engine_version          = var.mysql_version
  database_cluster_instances       = var.mysql_cluster_instances
  database_cluster_instance_size   = var.mysql_instance_size
  database_maintenance_window_day  = "sunday"
  database_maintenance_window_time = "01:00:00"

  # Database cluster firewalls cannot use VPC CIDR, therefore the access is
  # limited to the k8s cluster
  firewall_rules = [
    {
      type  = "k8s"
      value = module.kubernetes_cluster.cluster_id
    },
  ]
}

module "mongodb_database" {
  source = "git::https://github.com/openedx/openedx-k8s-harmony.git//terraform/modules/digitalocean/database?ref=${local.harmony_terraform_module_version}"

  region                  = var.region
  environment             = var.environment
  access_token            = var.access_token
  vpc_id                  = module.main_vpc.vpc_id
  kubernetes_cluster_name = var.kubernetes_cluster_name

  database_engine                  = "mongodb"
  database_engine_version          = var.mongodb_version
  database_cluster_instances       = var.mongodb_cluster_instances
  database_cluster_instance_size   = var.mongodb_instance_size
  database_maintenance_window_day  = "sunday"
  database_maintenance_window_time = "1:00"

  # Database cluster firewalls cannot use VPC CIDR, therefore the access is
  # limited to the k8s cluster
  firewall_rules = [
    {
      type  = "k8s"
      value = module.kubernetes_cluster.cluster_id
    },
  ]
}

# Output kubeconfig content for GitHub Actions
output "kubeconfig_content" {
  description = "Kubernetes configuration content for cluster access"
  value       = module.kubernetes_cluster.kubeconfig
  sensitive   = true
}

# Output cluster endpoint for reference
output "cluster_endpoint" {
  description = "Kubernetes cluster endpoint"
  value       = module.kubernetes_cluster.cluster_endpoint
}

# Output cluster name for reference
output "cluster_name" {
  description = "Kubernetes cluster name"
  value       = module.kubernetes_cluster.cluster_name
}

# Output MySQL database credentials
output "mysql_host" {
  description = "MySQL database host"
  value       = module.mysql_database.host
}

output "mysql_port" {
  description = "MySQL database port"
  value       = module.mysql_database.port
}

output "mysql_root_user" {
  description = "MySQL root username"
  value       = module.mysql_database.user
}

output "mysql_root_password" {
  description = "MySQL root password"
  value       = module.mysql_database.password
  sensitive   = true
}

# Output MongoDB database credentials
output "mongodb_host" {
  description = "MongoDB database host"
  value       = module.mongodb_database.host
}

output "mongodb_port" {
  description = "MongoDB database port"
  value       = module.mongodb_database.port
}

output "mongodb_admin_user" {
  description = "MongoDB admin username"
  value       = module.mongodb_database.user
}

output "mongodb_admin_password" {
  description = "MongoDB admin password"
  value       = module.mongodb_database.password
  sensitive   = true
}
