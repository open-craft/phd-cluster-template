# Cluster Backup

This page describes backup options for the Launchpad cluster.

## Overview

Backups may include:

- **Kubernetes resources** -  Via Velero for cluster-scoped and namespaced resources
- **Persistent volumes** -  Snapshot by Velero or the cloud provider
- **Databases** -  Managed DB snapshots (RDS, DocumentDB, DigitalOcean managed DBs) or application-level dumps
- **Object storage** -  Versioning or replication on S3/Spaces, if configured

## Velero (when enabled)

If Velero was enabled during infrastructure provisioning (Harmony option), it can provide:

- Scheduled backups of cluster resources and volumes
- Backup to S3-compatible storage (e.g. S3, DigitalOcean Spaces)

Typical steps:

1. Verify Velero is installed: `kubectl get pods -n velero`
2. Check schedules: `velero schedule get` (if [Velero CLI](https://velero.io/docs/main/velero-install/) is configured)
3. Create or adjust schedules via Terraform/Harmony configuration or Velero CRDs

Backup location and schedules are defined in the Terraform variables (e.g. `velero_schedules`). For more information, check the [Harmony documentation](https://gitlab.com/opencraft/ops/terraform-modules/-/blob/main/modules/harmony).

## Database Backups

- **Managed MySQL/MongoDB**: Use cloud provider snapshot/backup features (e.g. RDS automated backups, DO managed DB backups). Configure retention and restore procedures in the provider console or Terraform.
- **Application-level**: For Open edX, consider `mysqldump` or MongoDB dump jobs in addition to managed backups.

## Best Practices

- Document what is backed up (cluster state, PVs, DBs, object storage).
- Test restore procedures periodically.
- Keep credentials and backup storage access secure.

## Related Documentation

- [Cluster Overview](index.md) -  Cluster operations
- [Restore](restore.md) -  Restoring from backups
- [Infrastructure Provisioning](../infrastructure/provisioning.md) -  Enabling Velero and backup bucket
- [Infrastructure Deprovisioning](../infrastructure/deprovisioning.md) -  Cleanup and backups

## See Also

- [Cluster Configuration](configuration.md) -  Terraform and variables
- [Instance Provisioning](../instances/provisioning.md) -  Instance resources to back up
- [Monitoring](monitoring.md) -  Metrics and alerting
