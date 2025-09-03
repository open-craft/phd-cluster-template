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

## Infrastructure Setup

### Backend Configuration

This cluster uses Terraform/OpenTofu with S3-compatible backends for state storage. **Backend credentials must be provided via environment variables** to avoid storing sensitive information in state files.

#### Create Terraform State Bucket

The backend uses a `tfstate-phd-{{ cookiecutter.cluster_slug_normalized }}-cluster-{{ cookiecutter.environment }}` bucket to store its state. In case of `My Production Cluster`, it will be `tfstate-phd-my-cluster-production`.

Ensure the user the Access Key belongs to has access to the bucket.

#### Set Environment Variables

**For AWS S3 backend:**
```bash
export AWS_ACCESS_KEY_ID="your-aws-access-key"
export AWS_SECRET_ACCESS_KEY="your-aws-secret-key"
```

**For DigitalOcean Spaces backend:**
```bash
export AWS_ACCESS_KEY_ID="your-spaces-access-key"
export AWS_SECRET_ACCESS_KEY="your-spaces-secret-key"
```

#### Deploy Infrastructure

```bash
# Navigate to infrastructure directory
cd infrastructure-{{ cookiecutter.cloud_provider }}

# Initialize and deploy
tofu init
tofu plan
tofu apply
```

## Build
