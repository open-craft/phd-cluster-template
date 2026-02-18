# Cluster Overview

This section covers operations and configuration for a Launchpad Kubernetes cluster after it has been provisioned.

## Topics

- **[Authentication](authentication.md)** -  Cluster access, kubeconfig, and Argo user management
- **[Configuration](configuration.md)** -  Cluster-wide settings, environment variables, and Terraform variables
- **[Upgrade](upgrade.md)** -  Upgrading cluster components, ArgoCD, Argo Workflows, and node pools
- **[Backup](backup.md)** -  Backup strategies (e.g. Velero) and schedules
- **[Restore](restore.md)** -  Restoring from backups
- **[Monitoring](monitoring.md)** -  Prometheus, Grafana, and alerting

## Prerequisites

- A cluster created via [Infrastructure Provisioning](../infrastructure/provisioning.md)
- `kubectl` and Launchpad CLI configured for the cluster

## Related Documentation

- [Introduction](../index.md) -  Documentation home
- [Infrastructure Overview](../infrastructure/index.md) -  How the cluster is provisioned
- [Infrastructure Provisioning](../infrastructure/provisioning.md) -  Cluster creation and ArgoCD install
- [Instances Overview](../instances/index.md) -  Open edX instance lifecycle

## See Also

- [Authentication](authentication.md) -  kubeconfig and Argo users
- [Configuration](configuration.md) -  Environment variables and Terraform
- [Backup](backup.md) -  Backup strategies
- [Monitoring](monitoring.md) -  Prometheus and Grafana
