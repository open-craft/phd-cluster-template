locals {
  shared_module_version = "{{ cookiecutter.harmony_module_version }}"
}

module "main_vpc" {
  source = "git::https://github.com/openedx/openedx-k8s-harmony.git//terraform/modules/digitalocean/vpc?ref=${local.shared_module_version}"

  region       = var.region
  environment  = var.environment

  vpc_ip_range = var.vpc_ip_range
}

module "kubernetes_cluster" {
  source = "git::https://github.com/openedx/openedx-k8s-harmony.git//terraform/modules/digitalocean/doks?ref=${local.shared_module_version}"

  region      = var.region
  environment = var.environment
  vpc_id      = module.main_vpc.vpc_id

  cluster_name       = var.kubernetes_cluster_name
  kubernetes_version = var.kubernetes_version
}

module "kubernetes_cert_manager" {
  depends_on = [module.kubernetes_cluster]

  source = "git::https://github.com/openedx/openedx-k8s-harmony.git//terraform/modules/digitalocean/cert-manager?ref=${local.shared_module_version}"

  namespace                       = "kube-system"
  lets_encrypt_notification_inbox = var.lets_encrypt_notification_inbox
}

module "kubernetes_ingress" {
  depends_on = [module.kubernetes_cluster]

  source = "git::https://github.com/openedx/openedx-k8s-harmony.git//terraform/modules/digitalocean/nginx-ingress?ref=${local.shared_module_version}"

  ingress_namespace = "kube-system"
}

module "mysql_database" {
  source = "git::https://github.com/openedx/openedx-k8s-harmony.git//terraform/modules/digitalocean/database?ref=${local.shared_module_version}"

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
  source = "git::https://github.com/openedx/openedx-k8s-harmony.git//terraform/modules/digitalocean/database?ref=${local.shared_module_version}"

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
