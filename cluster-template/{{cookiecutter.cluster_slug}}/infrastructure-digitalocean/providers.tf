terraform {
  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = ">=2.61"
    }

    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">=2.38"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">=1.19"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "2.17.0"
    }
  }
}

# Pre-declare data sources that we can use to get the cluster ID and auth info,
# once it's created. Set the `depends_on` so that the data source doesn't try
# to read from a cluster that doesn't exist, causing failures when trying to
# run a `terraform plan`.
data "digitalocean_kubernetes_cluster" "cluster" {
  name       = module.kubernetes_cluster.cluster_name
  depends_on = [module.kubernetes_cluster.cluster_id]
}

provider "digitalocean" {
  token             = var.access_token
  spaces_access_id  = var.access_key_id
  spaces_secret_key = var.secret_access_key
}

provider "kubernetes" {
  host                   = data.digitalocean_kubernetes_cluster.cluster.endpoint
  token                  = data.digitalocean_kubernetes_cluster.cluster.kube_config[0].token
  cluster_ca_certificate = base64decode(data.digitalocean_kubernetes_cluster.cluster.kube_config[0].cluster_ca_certificate)
}

provider "helm" {
  kubernetes {
    host                   = data.digitalocean_kubernetes_cluster.cluster.endpoint
    token                  = data.digitalocean_kubernetes_cluster.cluster.kube_config[0].token
    cluster_ca_certificate = base64decode(data.digitalocean_kubernetes_cluster.cluster.kube_config[0].cluster_ca_certificate)
  }
}

provider "kubectl" {
  host                   = data.digitalocean_kubernetes_cluster.cluster.endpoint
  token                  = data.digitalocean_kubernetes_cluster.cluster.kube_config[0].token
  cluster_ca_certificate = base64decode(data.digitalocean_kubernetes_cluster.cluster.kube_config[0].cluster_ca_certificate)
  load_config_file       = false
}
