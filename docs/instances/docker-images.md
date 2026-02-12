# Docker Images

Open edX instances use container images for the LMS/CMS (openedx), MFEs, and other services. These images are built with Picasso and stored in a container registry (e.g. GHCR).

## Overview

- **Picasso** provides GitHub Actions workflows to build Docker images from the instance configuration and Tutor/Picasso setup.
- Image names and tags are typically set in the instance `config.yml` (e.g. `DOCKER_IMAGE_OPENEDX`, `MFE_DOCKER_IMAGE`) and automatically updated by Picasso after a build.
- Builds are **not** automatic on config change; they are triggered manually or by your automation (e.g. “Build Image” workflow in the cluster repo or the PR sandbox automation).

## Building Images

1. In the cluster repository, use the “Build Image” workflow.
2. Provide inputs such as instance name, service (`openedx`, `mfe`), branch, and Picasso version.
3. The workflow runs the Picasso build, pushes the image to the configured registry, and updates the image tag in the instance `config.yml`.

Ensure `LAUNCHPAD_DOCKER_REGISTRY_CREDENTIALS` is set in the environment so the cluster can pull private images.

## Image Sources

- **Open edX core** -  Built from the repository and version specified in config (e.g. `EDX_PLATFORM_REPOSITORY`, `EDX_PLATFORM_VERSION`).
- **MFE** -  Built according to the Picasso/MFE build steps configured for the instance.
- **Plugins** -  Tutor plugins (e.g. Drydock, forum, mfe) are installed during the image build as defined in `PICASSO_EXTRA_COMMANDS` in `config.yml`.

## Related Documentation

- [Instances Overview](index.md) -  Instance lifecycle
- [Infrastructure Overview](../infrastructure/index.md) -  Picasso and Drydock
- [Configuration](configuration.md) -  Instance config and image names
- [Provisioning](provisioning.md) -  How config is generated for a new instance

## See Also

- [Deprovisioning](deprovisioning.md) -  Instance cleanup
- [Debugging](debugging.md) -  Image pull and tag issues
- [User Guides: Pull Request Sandboxes](../user-guides/pull-request-sandboxes.md) -  Building from PR branches
