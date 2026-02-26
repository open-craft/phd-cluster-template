# Setting Up Cron Jobs

This guide describes how to set up cron jobs for Open edX instances on the cluster using CronJob resource for custom tasks.

## Kubernetes CronJob

For custom cron jobs:

1. **Define a CronJob** -  Create a CronJob manifest (schedule, job template, image, command). Use an image that has the required tools (e.g. openedx image or a minimal runner).
2. **Place in instance manifests** -  Add the CronJob to the instance’s manifest directory so ArgoCD syncs it.
3. **Secrets and config** -  Mount any required secrets (e.g. DB, API keys) into the CronJob’s job template so the job can connect to services.

Example (conceptual):

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: my-custom-job
  namespace: <instance-name>
spec:
  schedule: "0 2 * * *"   # 2 AM daily
  jobTemplate:
    spec:
      template:
        spec:
          containers:
            - name: job
              image: <your-image>
              command: ["/path/to/script.sh"]
          restartPolicy: OnFailure
```

## Deploying with ArgoCD

CronJobs are deployed via ArgoCD from the cluster repository. The instance’s ArgoCD Application must include the path where the CronJob manifests live, and a sync must be triggered after changes.

1. **Update `application.yml`** so ArgoCD also sees the cron manifests:
   ```yaml
   # ...
   spec:
    project: default

    sources:
      - path: "instances/<instance-name>/env"
        repoURL: "git@github.com:open-craft/<cluster-repo-name>"
        targetRevision: "main"

      - path: "instances/<instance-name>/manifests"
        repoURL: "git@github.com:open-craft/<cluster-repo-name>"
        targetRevision: "main"
   # ...
   ```

2. **Add the CronJob manifest** in the `manifests` directory. Use the instance’s namespace in the CronJob `metadata.namespace`.

3. **Commit and push** the CronJob YAML and any change to `application.yml` to the cluster repo.

4. **Trigger a sync** for the instance’s ArgoCD Application (UI or CLI). A sync is required for the new or updated CronJobs to be applied.

5. **Verify** in the ArgoCD application view or with `kubectl get cronjob -n <instance-name>`.

Any change to the CronJob (schedule, image, command) should be made in the manifest in the repo and committed; direct edits with `kubectl` will be reverted on the next ArgoCD sync.

## Related Documentation

- [User Guides Overview](index.md) -  All user guides
- [Instance Configuration](../instances/configuration.md) -  Where manifests live
- [Instances Overview](../instances/index.md) -  Instance lifecycle

## See Also

- [Instance Provisioning](../instances/provisioning.md) -  Instance layout
- [Docker Images](../instances/docker-images.md) -  Custom images for cron
- [Instance Debugging](../instances/debugging.md) -  Troubleshooting jobs
