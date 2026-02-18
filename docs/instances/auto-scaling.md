# Auto-scaling

This page describes how to scale Open edX instance workloads in the cluster.

## Overview

Scaling can be applied at several levels:

- **Kubernetes Deployments** -  Increase replicas for LMS, Celery workers, or other services by changing the replica count in the manifests (or via HPA).
- **Horizontal Pod Autoscaler (HPA)** -  Automatically scale the number of pods based on CPU, memory, or custom metrics.
- **Cluster autoscaling** -  Node pool autoscaling (configured in Terraform/cloud provider) adds nodes when pods are unschedulable.

## Instance-level Scaling

Tutor-generated manifests define Deployments for each service. To scale:

1. Edit the manifest in the cluster repo (e.g. set `replicas` on the LMS or Celery deployment).
2. Commit and push; ArgoCD will sync the change, or trigger a manual sync.

Alternatively, use `kubectl` for a one-off change (will be overwritten on next ArgoCD sync):

```bash
kubectl scale deployment -n <instance-name> <deployment-name> --replicas=<n>
```

## HPA

To add autoscaling based on metrics:

1. Define an HPA resource in the instance manifests (or apply it separately), targeting the desired Deployment and metric (e.g. CPU utilization).
2. Ensure a metrics pipeline (e.g. Prometheus + metrics-server) is available so the HPA controller can read metrics.

Details depend on your cluster’s metrics setup; see [Cluster Monitoring](../cluster/monitoring.md).

The easiest way to generate the HPA configuration is to use [tutor-contrib-pod-autoscaling](https://github.com/eduNEXT/tutor-contrib-pod-autoscaling). The plugin can be configured from the `config.yaml` of the instance and installed as:

```yaml
PICASSO_EXTRA_COMMANDS:
  - pip install tutor-contrib-pod-autoscaling
```

## Related Documentation

- [Instances Overview](index.md) -  Instance lifecycle
- [Configuration](configuration.md) -  Where instance manifests live
- [Cluster Monitoring](../cluster/monitoring.md) -  Metrics and Prometheus
- [Instance Monitoring](monitoring.md) -  Instance metrics and health

## See Also

- [Provisioning](provisioning.md) -  Instance layout
- [Infrastructure Overview](../infrastructure/index.md) -  Cluster components
- [Cluster Configuration](../cluster/configuration.md) -  Terraform and node pools
