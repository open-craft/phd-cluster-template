# PHD Cluster Template

A cookiecutter template for creating production-ready Open edX hosting clusters with automated instance management using GitOps principles.

## Project Intent

This project provides a complete solution for hosting multiple Open edX instances on Kubernetes clusters with:

- **Automated Infrastructure**: Terraform modules for AWS and DigitalOcean
- **GitOps Workflows**: ArgoCD and Argo Workflows for declarative deployments
- **Instance Management**: GitHub Actions for automated instance lifecycle
- **Multi-tenancy**: Secure RBAC and namespace isolation
- **Scalability**: Support for multiple instances per cluster

## Architecture

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   GitHub        │    │   Kubernetes     │    │   ArgoCD        │
│   Actions       │───▶│   Cluster        │───▶│   + Workflows   │
└─────────────────┘    └──────────────────┘    └─────────────────┘
         │                       │                       │
         │                       │                       │
         ▼                       ▼                       ▼
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Instance      │    │   Namespace      │    │   Open edX      │
│   Lifecycle     │    │   Management     │    │   Instances     │
│   Management    │    │   + RBAC         │    │   Deployment    │
└─────────────────┘    └──────────────────┘    └─────────────────┘
```

## Repository Structure

```
phd-cluster-template/
├── cluster-template/           # Cookiecutter template for clusters
│   ├── {{cookiecutter.cluster_slug}}/
│   │   ├── activate           # Cluster activation script
│   │   ├── infrastructure/    # Terraform infrastructure modules
│   │   └── instances/         # Instance configurations
│   └── hooks/                  # Cookiecutter post-generation hooks
├── instance-template/          # Cookiecutter template for instances
│   └── {{cookiecutter.instance_slug}}/
│       ├── application.yml     # ArgoCD Application manifest
│       └── config.yml          # Instance configuration
├── manifests/                  # Kubernetes manifests
│   ├── argocd-*.yml            # ArgoCD configuration
│   ├── argo-*.yml              # Argo Workflows configuration
│   ├── openedx-*.yml           # Open edX RBAC
│   └── phd-*-template.yml      # Provision/deprovision workflows
├── scripts/                     # PHD helper scripts
│   ├── phd-commands.sh         # Main command interface
│   ├── create-instance.sh      # Instance creation logic
│   ├── delete-instance.sh      # Instance deletion logic
│   └── *.sh                    # Utility scripts
├── .github/workflows/          # GitHub Actions workflows
│   ├── create-instance.yml     # Instance creation workflow
│   └── delete-instance.yml     # Instance deletion workflow
└── requirements/               # Python dependencies
```

## Quick Start

### 1. Generate a Cluster

```bash
# Install cookiecutter
pip install -r https://raw.githubusercontent.com/open-craft/phd-cluster-template/refs/heads/main/requirements/base.txt

# Generate cluster template
cookiecutter https://github.com/open-craft/phd-cluster-template.git --directory cluster-template
```

### 2. Set Up Infrastructure

```bash
# Navigate to your cluster's directory
cd your-cluster-name

# Navigate to the infrastructure directory
cd infrastructure

# Deploy infrastructure
tofu init
tofu plan
tofu apply
```

### 3. Install GitOps Tools

```bash
# Navigate to your cluster's directory
cd your-cluster-name

# Load PHD commands
source ./activate

# Install ArgoCD and Argo Workflows
phd_install_all
```

### 4. Configure ArgoCD

The PHD commands will generate `application.yml` files for every instance with a project set to `phd-{{ environment }}`, so different instance environments within the same cluster can use different project or repository settings.

However, this means one have to configure each and every `phd-{{ environment }}` with repository settings per environment. For example, if the instance has the `project: phd-production` set, a `phd-production` project must exist in ArgoCD as well.

This is a manual work.

## Usage

### Instance Management

#### Creating Instances

Use GitHub Actions or command line:

**GitHub Actions**:
1. Go to your cluster repository's Actions tab
2. Select "Create Instance" workflow
3. Provide instance configuration
4. Monitor the workflow execution

**Command Line**:
```bash
# Create instance
phd_create_instance my-instance \
  "https://github.com/your-org/your-cluster.git" \
  "My Open edX Platform" \
  "https://github.com/openedx/edx-platform.git" \
  "release/teak" \
  "v20.0.1"
```

#### Deleting Instances

**GitHub Actions**:
1. Go to your cluster repository's Actions tab
2. Select "Delete Instance" workflow
3. Provide instance name
4. Monitor the cleanup process

**Command Line**:
```bash
# Delete instance
phd_delete_instance my-instance
```

### PHD Commands

The project provides a comprehensive set of commands:

```bash
# GitOps Tools
phd_install_argocd              # Install ArgoCD
phd_install_argo_workflows      # Install Argo Workflows
phd_install_all                 # Install both

# User Management
phd_create_argo_user <username> [role] [password]
phd_delete_argo_user <username>
phd_update_argo_user_permissions <username> [role]

# Instance Management
phd_create_instance <name> [template_repo] [platform_name] [edx_repo] [edx_version] [tutor_version]
phd_delete_instance <name>
```

## Security & RBAC

- **Namespace Isolation**: Each instance runs in its own namespace
- **RBAC**: Proper role-based access control for all resources
- **Secret Management**: Secure handling of database credentials
- **Network Policies**: Isolated network access between instances

### User Roles

The system supports three user roles with different permission levels:

#### Admin Role
- **ArgoCD**: Full access to all applications and projects
- **Argo Workflows**: Full cluster-wide access to all workflow resources
- **Permissions**: Create, read, update, delete all workflows, templates, and cron workflows

#### Developer Role  
- **ArgoCD**: Access to assigned applications and projects
- **Argo Workflows**: Full cluster-wide access to workflow resources
- **Permissions**: Create, read, update, delete workflows, templates, and cron workflows

#### Readonly Role
- **ArgoCD**: Read-only access to applications and projects
- **Argo Workflows**: Read-only access to workflow resources
- **Permissions**: View workflows, templates, and cron workflows only

### Updating User Permissions

If you need to update a user's permissions after creation:

```bash
# Update user to admin role
phd_update_argo_user_permissions username admin

# Update user to developer role  
phd_update_argo_user_permissions username developer

# Update user to readonly role
phd_update_argo_user_permissions username readonly
```

### RBAC Manifest Files

User roles are defined in separate YAML manifest files in the `manifests/` directory:

- `argo-user-admin-role.yml`: Admin role and cluster role definitions
- `argo-user-developer-role.yml`: Developer role and cluster role definitions  
- `argo-user-readonly-role.yml`: Readonly role and cluster role definitions
- `argo-user-bindings.yml`: Role and cluster role bindings
- `argo-user-token-secret.yml`: Service account token secret

These manifests use template variables (`{{PHD_ARGO_USERNAME}}`, `{{PHD_ARGO_ROLE}}`) and are applied using the `__phd_kubectl_apply_from_url` function, following the established pattern for remote manifest management.

### Workflow Manifest Files

Instance workflows are defined in separate YAML manifest files in the `manifests/` directory:

**Provision Workflows:**
- `phd-mysql-provision-workflow.yml`: MySQL database provision workflow
- `phd-mongodb-provision-workflow.yml`: MongoDB database provision workflow  
- `phd-storage-provision-workflow.yml`: Storage bucket provision workflow

**Deprovision Workflows:**
- `phd-mysql-deprovision-workflow.yml`: MySQL database deprovision workflow
- `phd-mongodb-deprovision-workflow.yml`: MongoDB database deprovision workflow
- `phd-storage-deprovision-workflow.yml`: Storage bucket deprovision workflow

These manifests use template variables with the `PHD_INSTANCE_` prefix (e.g., `{{PHD_INSTANCE_NAME}}`, `{{PHD_INSTANCE_MYSQL_DATABASE}}`) and are applied using the `__phd_kubectl_apply_from_url` function, following the established pattern for remote manifest management.

This is particularly useful when:
- Fixing permission issues for existing users
- Upgrading user access levels
- Applying new permission policies

## Cloud Support

### DigitalOcean
- **Kubernetes**: DigitalOcean Kubernetes (DOKS)
- **Databases**: Managed MySQL and MongoDB
- **Storage**: DigitalOcean Spaces
- **Networking**: VPC with private/public subnets

### AWS
- **Kubernetes**: Amazon EKS
- **Databases**: RDS MySQL and DocumentDB
- **Storage**: S3 buckets
- **Networking**: VPC with private/public subnets

## Database Provider Support

### MongoDB Providers

The system supports multiple MongoDB providers with automatic detection:

- **`mongodb_direct`**: Direct connection to any MongoDB (self-hosted, Atlas, managed DBs)
- **`digitalocean_api`**: DigitalOcean API-based database management
- **`atlas`**: MongoDB Atlas (uses mongodb_direct, API support planned)

**Provider is automatically detected** based on your configuration.

#### Quick Configuration

**Self-hosted or DigitalOcean Managed (Recommended)**:
```bash
export PHD_MONGODB_HOST="mongodb.example.com"
export PHD_MONGODB_PORT="27017"
export PHD_MONGODB_ADMIN_USER="admin"
export PHD_MONGODB_ADMIN_PASSWORD="secure_password"
```

**MongoDB Atlas**:
```bash
export PHD_MONGODB_HOST="cluster0.abc123.mongodb.net"
export PHD_MONGODB_ADMIN_USER="atlas-admin"
export PHD_MONGODB_ADMIN_PASSWORD="atlas_password"
```

**DigitalOcean via API** (optional):
```bash
export PHD_MONGODB_CLUSTER_ID="abc12345-xyz67890"  # Forces API provider
export PHD_DIGITALOCEAN_TOKEN="dop_v1_your_token"
```

📖 **See [MONGODB_PROVIDERS.md](MONGODB_PROVIDERS.md) for detailed provider configuration, troubleshooting, and migration guide.**

### Storage Providers

The system automatically computes storage endpoint URLs based on provider type:

- **DigitalOcean Spaces**: Automatic endpoint formatting (`https://{region}.digitaloceanspaces.com`)
- **AWS S3**: Uses AWS default endpoints
- **Extensible**: Easy to add new providers

**Configuration**:
```bash
export PHD_STORAGE_TYPE="spaces"  # or "s3"
export PHD_STORAGE_REGION="nyc3"  # or "us-east-1"
export PHD_STORAGE_ACCESS_KEY_ID="your_key"
export PHD_STORAGE_SECRET_ACCESS_KEY="your_secret"
```

## GitHub Actions Workflows

### Create Instance Workflow
- Creates namespace with RBAC
- Generates instance configuration using cookiecutter
- Applies provision workflows (MySQL, MongoDB, Storage)
- Creates ArgoCD Application
- Triggers deployment workflows

### Delete Instance Workflow
- Deletes ArgoCD Application
- Triggers deprovision workflows
- Cleans up databases and storage
- Removes namespace and all resources

## Configuration

### Required GitHub Secrets

- `AWS_ACCESS_KEY_ID`: AWS Access Key ID with permissions to read/write ECR
- `AWS_SECRET_ACCESS_KEY`: AWS Secret Access Key pair for the Access Key ID
- `AWS_REGION`: AWS Region
- `SSH_PRIVATE_KEY`: SSH Private Key used to fetch private repositories

### Setting Up Secrets

```bash
# From your cluster repository root
phd_setup_github_secret your-org/your-cluster-repo
```

## Troubleshooting

### Common Issues

1. **Terraform apply fails**: Check cloud provider credentials
2. **kubectl not working**: Verify kubeconfig is set correctly
3. **GitHub Actions fail**: Check that KUBECONFIG_CONTENT secret is set
4. **ArgoCD not accessible**: Check ingress configuration and DNS

### Getting Help

- Check GitHub Actions logs
- Verify terraform outputs
- Check ArgoCD and Argo Workflows status
- Review RBAC permissions

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b your-name/new-feature`)
3. Make your changes
4. Test thoroughly
5. Commit your changes (`git commit -m 'Add new feature'`)
6. Push to the branch (`git push origin your-name/name-feature`)
7. Open a Pull Request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- [Open edX](https://openedx.org/) - The learning platform
- [Tutor](https://docs.tutor.overhang.io/) - The deployment tool
- [Picasso](https://github.com/eduNEXT/picasso) - GitHub Actions for Image building
- [DryDock](https://github.com/eduNEXT/drydock) - Tutor plugins for better OpenedX installations in Kubernetes
- [ArgoCD](https://argo-cd.readthedocs.io/) - GitOps continuous delivery
- [Argo Workflows](https://argoproj.github.io/argo-workflows/) - Workflow engine to provision resources
