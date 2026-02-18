# Instance Maintenance Mode

Maintenance mode for an instance can be toggled while working locally. Make you're set up to work with instances on you machine before running any of the commands below.

Maintenance pages are set up to work from any S3-compatible bucket in order to allow operators to change the content without needing to modify the cluster. The maintenance mode requires [tutor-contrib-grove](https://gitlab.com/opencraft/dev/tutor-contrib-grove) to be set up.

To deploy a maintenance page:

1. Create an S3-compatible bucket and make sure that it's not publicly readable. In the bucket place a file, named `maintenance-mode.html`. When maintenance mode is enabled, this file will be served instead of your LMS or Studio pages.
2. Once done, add the configuration `GROVE_MAINTENANCE_S3_BUCKET_ROOT_URL` to your `config.yml`. The value should be your bucket's fully qualified URL (eg. `https://grove-maintenance.ams3.digitaloceanspaces.com/`).
3. Maintenance mode can then be enable with the command: `./tutor [instance-name] maintenance-mode --enable`, executed from the `./control` directory.
   1. Disabling maintenance mode is similar and can be accomplished by executing `./tutor [instance-name] maintenance-mode --disable` within the `./control` directory.

## 404 pages

When an instance is being provisioned for the first time, this page will display. The default 404 page can be found in `provider-modules/harmony/ingress-404.html`.

To serve a customer file, you may change the `TF_VAR_global_404_html_path` to point to your HTML file.

Note that Grove tools run within Docker, so you'll need to place the file within a path where Grove can find it. By default your `my-cluster` directory is mounted in the `/workspace` directory in the Grove container.

What this means is, if you place your file (`404.html`) in the root of your `my-cluster` repo you can then deploy it as part of Grove by adding the variable to `cluster.yml` or to you CI/CD vars:

`TF_VAR_global_404_html_path="/workspace/404.html"`
[Redeploy the changes](../pipelines/infrastructure.md). If you try and access an instance that has not yet been provisioned, the HTML file will be rendered.

When your if your instance is ready, this page will not be rendered for any 404's, but rather the Open edX platform will render an appropriately styled page.

!!! note
    If your changes do not reflect, you might need to restart the container that serves these pages:

    ```bash
    ./kubectl rollout restart deployment -nkube-system ingress-nginx-defaultbackend
    ```

## 5xx error pages

These pages work like the maintenance pages in that they have to point to an S3 bucket.

In order to enable custom error pages, just set the `GROVE_SERVER_ERROR_S3_BUCKET_ROOT_URL` to your S3 bucket's URL. Once added, the file `server-error.html` will be displayed for any 5xx error that cannot be handled by the LMS/CMS.

## Related Documentation

- [User Guides Overview](index.md) -  All user guides
- [Instance Configuration](../instances/configuration.md) -  Config and manifests
- [Instance Provisioning](../instances/provisioning.md) -  Instance layout and ArgoCD
- [Instances Overview](../instances/index.md) -  Instance lifecycle

## See Also

- [Auto-scaling](../instances/auto-scaling.md) -  Scaling replicas
- [Cluster Overview](../cluster/index.md) -  Cluster operations
- [Debugging](../instances/debugging.md) -  Troubleshooting
