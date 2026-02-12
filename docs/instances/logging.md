# Logging

This page outlines logging options for Open edX instances on the cluster.

## Kubernetes Logs

By default, container stdout/stderr are captured by the container runtime and can be viewed with `kubectl logs`.

Log retention is typically limited by node disk and cluster configuration; old logs may be rotated away.

## Application-level Logging

Open edX services write logs to stdout. Log level and format are controlled by application settings (e.g. Django `LOGGING`, Celery, or environment variables). Adjust these in the instance configuration or in custom settings if you need different verbosity or structure.

To get the application logs, use:

```shell
kubectl logs deployments/<service> -n <instance-name>
```

## Related Documentation

- [Instances Overview](index.md) -  Instance lifecycle
- [Tracking Logs](tracking-logs.md) -  Using `kubectl logs` and following logs
- [Cluster Monitoring](../cluster/monitoring.md) -  Grafana and Prometheus
- [Debugging](debugging.md) -  Using logs for troubleshooting

## See Also

- [Instance Monitoring](monitoring.md) -  Metrics and health
- [Configuration](configuration.md) -  Application log settings
- [Infrastructure Overview](../infrastructure/index.md) -  Cluster components
