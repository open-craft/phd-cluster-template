# PHD Tooling

The PHD (Picasso, Harmony, Drydock) tooling provides a Python CLI for managing Open edX clusters and instances. This tooling automates the creation, configuration, and management of Kubernetes-based Open edX deployments.

## Overview

The PHD tooling consists of several command-line utilities that work together to:

- **Create and manage clusters**: Bootstrap new Kubernetes clusters with ArgoCD and Argo Workflows installed
- **Deploy Open edX instances**: Automate the creation of isolated Open edX instances with proper RBAC
- **Manage Argo users**: Create, update, and delete ArgoCD/Argo Workflows users with appropriate permissions
- **Handle infrastructure**: Support for AWS and DigitalOcean cloud providers

## Installation

### Prerequisites

- Python 3.12 or higher
- `kubectl` configured to access your Kubernetes cluster
- `uv` package manager (recommended) or `pip`

### Install from source

```bash
# Clone the repository
git clone https://github.com/open-craft/phd-cluster-template.git
cd phd-cluster-template/tooling

# Install using uv (recommended)
uv sync --all-groups

# Or install using pip
pip install -e .
```

## Available Commands

Commands can be executed using uvx as follows:

```bash
# using remote source (recommended)

uvx --from git+https://github.com/open-craft/phd-cluster-template/tooling command

# or using local repository
uvx --from ./phd-cluster-template/tooling command
```

### Cluster Management

#### `phd_create_cluster`
Creates a new cluster configuration using cookiecutter templates.

```bash
phd_create_cluster "My Production Cluster" "cluster.example.com" \
  --environment production \
  --cloud-provider aws \
  --output-dir ./clusters
```

**Options:**
- `--environment`: Environment name (default: production)
- `--cloud-provider`: Cloud provider - aws or digitalocean (default: aws)
- `--harmony-module-version`: Harmony module version/commit hash
- `--opencraft-module-version`: OpenCraft module version
- `--picasso-version`: Picasso version
- `--template-version`: PHD cluster template version
- `--git-organization`: Git organization name
- `--git-repository`: Git repository URL (auto-generated if not provided)
- `--output-dir`: Directory where cluster config will be created

### Instance Management

#### `phd_create_instance`
Creates a new Open edX instance with all required resources.

```bash
phd_create_instance my-instance \
  --platform-name "My Learning Platform" \
  --edx-platform-version "release/teak" \
  --tutor-version "v20.0.1"
```

**Options:**
- `--template-repository`: Git URL of the instance template repository
- `--platform-name`: Display name for the platform
- `--edx-platform-repository`: Git URL of the edx-platform repository
- `--edx-platform-version`: Version/branch of edx-platform to use
- `--tutor-version`: Version of Tutor to use

#### `phd_delete_instance`
Deletes an Open edX instance and cleans up all associated resources.

```bash
phd_delete_instance my-instance
```

### Argo Management

#### `phd_install_argo`
Installs ArgoCD and/or Argo Workflows in the Kubernetes cluster.

```bash
# Install both ArgoCD and Argo Workflows
phd_install_argo

# Install only ArgoCD
phd_install_argo --argocd-only

# Install only Argo Workflows
phd_install_argo --workflows-only
```

#### `phd_create_argo_user`
Creates a new ArgoCD/Argo Workflows user with specified permissions.

```bash
phd_create_argo_user john.doe \
  --role admin \
  --password "secure-password"
```

#### `phd_update_argo_user`
Updates an existing ArgoCD/Argo Workflows user.

```bash
phd_update_argo_user john.doe \
  --role developer \
  --password "new-password"
```

#### `phd_delete_argo_user`
Deletes an ArgoCD/Argo Workflows user.

```bash
phd_delete_argo_user john.doe
```

## Configuration

The tooling uses environment variables and configuration files for cluster-specific settings. Key configuration options include:

### Environment Variables

- `PHD_ARGO_ADMIN_PASSWORD`: Admin password for ArgoCD/Argo Workflows (optional, auto-generated if not provided)
- `KUBECONFIG`: Path to your Kubernetes configuration file

### Configuration Files

The tooling automatically detects and uses configuration from:
- Terraform/OpenTofu outputs (if available)
- Environment variables
- Configuration files in the cluster directory

## Architecture

The tooling follows a modular architecture:

```
phd/
├── cli/                    # Command-line interfaces
│   ├── argo_install.py     # ArgoCD/Workflows installation
│   ├── cluster_create.py   # Cluster creation
│   ├── instance_create.py  # Instance creation
│   ├── instance_delete.py  # Instance deletion
│   └── argo_user_*.py      # User management
├── config.py              # Configuration management
├── kubernetes.py          # Kubernetes client wrapper
├── kubeconfig.py          # Kubeconfig management
├── password.py            # Password handling utilities
└── utils.py               # Common utilities
```

## Development

### Setup Development Environment

```bash
# Install development dependencies
uv sync --all-groups

# Run tests
uv run pytest -v --cov=phd

# Run linting
uv run pylint phd/

# Format code
uv run black phd/
uv run isort phd/
```

### Testing

The project includes comprehensive tests for all modules:

```bash
# Run all tests
uv run pytest

# Run tests with coverage
uv run pytest --cov=phd --cov-report=html

# Run specific test file
uv run pytest tests/test_kubernetes.py
```

### Code Quality

The project enforces code quality through:

- **Black**: Code formatting
- **isort**: Import sorting
- **pylint**: Static analysis
- **pytest**: Testing framework
- **pytest-cov**: Coverage reporting

## Security Considerations

- **Password Management**: Admin passwords are automatically generated if not provided and stored securely
- **RBAC**: All instances are created with proper Role-Based Access Control
- **Namespace Isolation**: Each instance runs in its own namespace
- **Secret Management**: Sensitive data is handled through Kubernetes secrets

## Troubleshooting

### Common Issues

1. **Kubeconfig not found**: Ensure `kubectl` is configured and `KUBECONFIG` environment variable is set
2. **Permission denied**: Verify your Kubernetes user has sufficient permissions
3. **Network issues**: Check cluster connectivity and DNS resolution
4. **Resource conflicts**: Ensure no existing resources conflict with the new instance

### Debug Mode

Enable debug logging by setting the log level:

```bash
export PHD_LOG_LEVEL=DEBUG
phd_create_instance my-instance
```

### Log Files

By default, PHD writes logs to the system temp directory:
- **macOS/Linux**: `/tmp/phd.log` (or `/var/folders/.../phd.log` on macOS)
- **Windows**: `%TEMP%\phd.log`

You can customize the log file location:

```bash
export PHD_LOG_FILE=/path/to/my-logs.log
phd_create_instance my-instance
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests for new functionality
5. Ensure all tests pass
6. Submit a pull request

## License

This project is licensed under the AGPL-v3.0 License - see the [LICENSE](../LICENSE) file for details.

## Support

For support and questions:
- Create an issue in the GitHub repository
- Check the [main project README](../README.md) for additional documentation
- Review the [GitHub Actions workflows](../.github/workflows/) for usage examples
