# Cluster Restore

This page describes how to restore cluster state and data from backups.

## Overview

Restore procedures depend on what was backed up:

- **Velero** -  Restore Kubernetes resources and optionally persistent volume snapshots
- **Databases** -  Restore from cloud provider snapshots or from application-level dumps
- **Object storage** -  Restore from versioning or replication if configured

Always follow your organization’s runbooks and test restores in a non-production environment when possible.

## Velero Restore

If Velero is installed and backups exist:

1. Install and configure the Velero CLI and point it at the backup storage.
2. List backups: `velero backup get`
3. Restore a backup: `velero restore create --from-backup <backup-name>` (optionally with filters for namespaces or resources).

Check the [Velero documentation](https://velero.io/docs/) for filters, volume snapshot restores, and cluster-specific considerations.

## Database Restore

- **Managed MySQL/MongoDB**: Use the cloud provider’s restore feature (e.g. restore from RDS snapshot to a new instance, then point the app to it). Adjust connection strings or Kubernetes secrets as needed.
- **Application-level dumps**: Restore using `mysql` or `mongorestore` into the target database, then restart the application if necessary.

## After Restore

- Verify ArgoCD applications and sync status.
- Verify Open edX instances and that DB connectivity and secrets are correct.
- Re-run any provisioning or init jobs if data or resources were recreated.

## Related Documentation

- [Cluster Overview](index.md) -  Cluster operations
- [Backup](backup.md) -  What is backed up and how
- [Infrastructure Provisioning](../infrastructure/provisioning.md) -  Re-provisioning after restore
- [Infrastructure Deprovisioning](../infrastructure/deprovisioning.md) -  If you need to rebuild the cluster

## See Also

- [Cluster Configuration](configuration.md) -  Post-restore configuration
- [Instance Provisioning](../instances/provisioning.md) -  Recreating instances
- [Instance Deprovisioning](../instances/deprovisioning.md) -  Instance cleanup
