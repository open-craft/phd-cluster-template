# Instance Monitoring

This page describes monitoring options for Open edX instances running on the cluster.

## Overview

Instance health and metrics can be observed via:

- **Kubernetes** -  Pod status, restarts, resource usage
- **Prometheus** -  If the cluster has Prometheus and scrape configs for instance namespaces
- **Grafana** -  Dashboards built on Prometheus (or other datasources)
- **Application health** -  LMS/CMS endpoints, Celery workers, and custom checks

## Kubernetes

Basic health:

```bash
kubectl get pods -n <instance-name>
kubectl describe pod -n <instance-name> <pod-name>
kubectl top pods -n <instance-name>
```

Check events and readiness/liveness probe status in `kubectl describe`.

## Prometheus and Grafana

If the cluster has Prometheus and Grafana enabled (see [Cluster Monitoring](../cluster/monitoring.md)):

- Ensure ServiceMonitors or Prometheus scrape configs include the instance namespace and relevant services.
- Use or create Grafana dashboards for Open edX (e.g. request rate, latency, Celery queue length, Redis).

Metrics depend on what is exposed (e.g. Django metrics, Redis, Celery) and how Prometheus is configured to scrape them.

## Alerts

Define alerts in Alertmanager (or your alerting system) for:

- Pod crashes or not ready
- High error rate or latency
- Queue backlog (Celery)
- Database or Redis connectivity

Configure receivers (email, Slack, etc.) in the cluster’s Alertmanager configuration.

## Related Documentation

- [Instances Overview](index.md) -  Instance lifecycle
- [Cluster Monitoring](../cluster/monitoring.md) -  Cluster-level Prometheus and Grafana
- [Configuration](configuration.md) -  Instance and app settings
- [Debugging](debugging.md) -  Troubleshooting instance issues

## See Also

- [Tracking Logs](tracking-logs.md) -  Accessing logs
- [Logging](logging.md) -  Log aggregation
- [Infrastructure Overview](../infrastructure/index.md) -  Harmony and monitoring
- [Auto-scaling](auto-scaling.md) -  HPA and metrics
