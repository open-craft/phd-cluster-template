locals {
  harmony_terraform_module_version   = "{{ cookiecutter.harmony_module_version }}"
  opencraft_terraform_module_version = "{{ cookiecutter.opencraft_module_version }}"
}

module "main_vpc" {
  source = "git::https://github.com/openedx/openedx-k8s-harmony.git//terraform/modules/digitalocean/vpc?ref=${local.harmony_terraform_module_version}"

  region       = var.region
  environment  = var.environment

  vpc_ip_range = var.vpc_ip_range
}

module "kubernetes_cluster" {
  source = "git::https://github.com/openedx/openedx-k8s-harmony.git//terraform/modules/digitalocean/doks?ref=${local.harmony_terraform_module_version}"

  region      = var.region
  environment = var.environment
  vpc_id      = module.main_vpc.vpc_id

  cluster_name       = var.kubernetes_cluster_name
  kubernetes_version = var.kubernetes_version
}

module "kubernetes_cert_manager" {
  depends_on = [module.kubernetes_cluster]

  source = "git::https://gitlab.com/opencraft/ops/terraform-modules.git//modules/k8s-cert-manager?ref=${local.opencraft_terraform_module_version}"

  namespace                       = "kube-system"
  lets_encrypt_notification_inbox = var.lets_encrypt_notification_inbox
}

module "kubernetes_ingress" {
  depends_on = [module.kubernetes_cluster]

  source = "git::https://gitlab.com/opencraft/ops/terraform-modules.git//modules/k8s-nginx-ingress?ref=${local.opencraft_terraform_module_version}"

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

resource "digitalocean_project" "project" {
  name        = var.kubernetes_cluster_name
  description = "{{ cookiecutter.short_description }}"
  purpose     = "Open edX Instance Hosting"

  resources = [
    module.kubernetes_cluster.cluster_urn,
    module.mysql_database.cluster_urn,
    module.mongodb_database.cluster_urn,
  ]
}

resource "local_sensitive_file" "kubeconfig" {
  filename        = "${path.cwd}/.kubeconfig"
  content         = data.digitalocean_kubernetes_cluster.cluster.kube_config[0].raw_config
  file_permission = "0400"
}

# Output kubeconfig content for GitHub Actions
output "kubeconfig_content" {
  description = "Kubernetes configuration content for cluster access"
  value       = data.digitalocean_kubernetes_cluster.cluster.kube_config[0].raw_config
  sensitive   = true
}

# Output cluster endpoint for reference
output "cluster_endpoint" {
  description = "Kubernetes cluster endpoint"
  value       = data.digitalocean_kubernetes_cluster.cluster.endpoint
}

# Output cluster name for reference
output "cluster_name" {
  description = "Kubernetes cluster name"
  value       = data.digitalocean_kubernetes_cluster.cluster.name
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
