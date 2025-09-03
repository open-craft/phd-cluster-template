# {{ cookiecutter.cluster_name }}

{% if cookiecutter.short_description -%}
> {{ cookiecutter.short_description }}
{%- endif %}

This repository serves as the home for the {{ cookiecutter.cluster_name }} cluster. All the necessary infrastructure, cluster, and instance configuration are living in this repository.

{% if cookiecutter.cloud_provider == "aws" -%}
## AWS

{% elif cookiecutter.cloud_provider == "digitalocean" -%}
## DigitalOcean

{%- endif %}

## Cluster

## Build
