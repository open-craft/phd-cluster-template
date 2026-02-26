# Launchpad Documentation

Welcome to the documentation for the **Launchpad** stack -  a solution for hosting Open edX instances on Kubernetes with GitOps-based deployment and automated instance management.

## What is Launchpad?

Launchpad combines open-source tools to run and operate Open edX at scale:

- **Picasso** -  Builds Docker images for Open edX services via GitHub Actions
- **Harmony** -  Open edX Terraform and Kubernetes infrastructure (ingress, optional monitoring, backups)
- **Drydock** -  Tutor plugin for ArgoCD-friendly Kubernetes deployments

Together with **Kubernetes**, **ArgoCD**, **Argo Workflows**, and **Tutor**, the stack supports multiple isolated Open edX instances per cluster, each with its own databases, storage, and configuration.

## Documentation sections

The documentation is split into four major and some minor sections. The four major sections are the following.

| Section | Description |
|--------|-------------|
| [**Infrastructure**](infrastructure/index.md) | Cluster components, provisioning, deprovisioning, and custom resources |
| [**Cluster**](cluster/index.md) | Operating a cluster: authentication, configuration, upgrade, backup, restore, monitoring |
| [**Instances**](instances/index.md) | Open edX instance lifecycle: provisioning, configuration, images, scaling, logs, monitoring, debugging |
| [**User Guides**](user-guides/index.md) | Task-based guides: AWS WAF/ALB, maintenance mode, cron jobs, PR sandboxes, multi-domain, private plugins |

## What's next?

The Open edX platform and related tooling can be complex.

To get started, it is recommended to read the "Overview" of all major sections to familiarize yourself with all the concepts, components, and reasoning behind choices.

You can easily navigate there by clicking any of the section links in the table above.
