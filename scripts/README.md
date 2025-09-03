# PHD Scripts

This directory contains Bash scripts used to install and configure ArgoCD and Argo Workflows and to manage related utilities for the PHD cluster template.

Public commands are exposed by `phd-commands.sh`. Functions without a `__` prefix are intended for users; functions starting with `__` are internal helpers.

## Prerequisites

- `bash`, `curl`, `envsubst` (optional but preferred)
- `kubectl`
- `python3` (required)
- Python module `bcrypt` (used for password hashing)
- `base64` (GNU coreutils)
- `jq` (for loading context)

## How to load commands

The commands are automatically loaded by the `activate` script after sourcing. When sourced, it will automatically fetch the latest (or specified) `phd-commands.sh` script and sources it.

The `phd-commands.sh` automatically loads `ROOT_DIR/context.json` (set by `activate` script) into environment variables prefixed with `PHD_`.

Example context.json entry `{ "cluster_domain": "example.com" }` becomes `PHD_CLUSTER_DOMAIN=example.com`.

Then, all necessary scripts will be fetched and sourced upon usage, ensuring that no scripts are duplicated (or altered) across the cluster repos and the template repository remains the single source of truth.

## Environment variables

- `PHD_CLUSTER_DOMAIN`: cluster domain (required for installs)
- `PHD_ARGO_ADMIN_PASSWORD`: optional plaintext admin password
- `PHD_ARGO_ADMIN_PASSWORD_BCRYPT`: optional bcrypt hash of the admin password
- `PHD_ARGOCD_ADMIN_PASSWORD_MTIME`: optional RFC3339 timestamp; set automatically when not provided
- `ARGOCD_VERSION`, `ARGO_WORKFLOWS_VERSION`: versions to install (defaults to `stable`)
- `OPENCRAFT_MANIFESTS_VERSION`: version of this repo's manifests (defaults to `main`)
- `USE_LOCAL_SCRIPTS=true` and `SCRIPTS_DIR=/abs/path` to prefer local scripts over remote

## Authentication and Security

Default setup uses hardened local authentication for both ArgoCD and Argo Workflows following security best practices:

### Security Features

- **Anonymous Access**: Completely disabled in both ArgoCD (`users.anonymous.enabled: false`) and Argo Workflows (`policy.default: reject` + explicit deny rules)
- **Authentication**: Both systems require authentication - no unauthenticated access allowed
- **Secure Defaults**: Workflows run with hardened security contexts (non-root, dropped capabilities, read-only filesystem)
- **RBAC**: Strict role-based access control with principle of least privilege
- **TLS**: Secure HTTPS communication enabled by default

### ArgoCD Security
- Local `admin` user with bcrypt-hashed password
- Anonymous access explicitly disabled per CVE-2022-29165
- Password configured via `argocd-secret` (`admin.password`, `admin.passwordMtime`)

### Argo Workflows Security
- `--auth-mode=client` with local users, Kubernetes RBAC enforcement, and service account tokens
- Anonymous users explicitly denied via `p, system:unauthenticated, *, *, *, deny`
- Hardened workflow defaults: non-root execution, dropped capabilities, secure service accounts
- Only `emissary` executor supported (most secure option)
- **Integrated access tokens**: Users get automatically generated Kubernetes service account tokens

### Password Management
If neither `PHD_ARGO_ADMIN_PASSWORD` nor `PHD_ARGO_ADMIN_PASSWORD_BCRYPT` is set, a strong password is generated during ArgoCD install and printed **once** as a `[WARNING]`. The same bcrypt hash is used for both ArgoCD and Argo Workflows admin users.

## Public commands

### phd_install_all

Installs ArgoCD, then Argo Workflows, and applies default workflow templates.

Usage:

```bash
phd_install_all
```

Behavior:

- Resolves `admin` user password (generate, use plaintext, or accept bcrypt)
- Applies `argocd-admin-password.yml` (ArgoCD) and `argo-server-auth.yml` (Workflows)
- Prints the generated plaintext password once **if and only if** it was auto-generated

### phd_install_argocd

Installs ArgoCD core components, ingress, and sets the admin password (local auth).

Usage:

```bash
phd_install_argocd
```

Environment:

- `PHD_ARGO_ADMIN_PASSWORD` or `PHD_ARGO_ADMIN_PASSWORD_BCRYPT` (optional)
- `PHD_CLUSTER_DOMAIN` (required)

### phd_install_argo_workflows

Installs Argo Workflows core components, ingress, and configures local auth with no anonymous access.

Usage:

```bash
phd_install_argo_workflows
```

Environment:

- Reuses `PHD_ARGO_ADMIN_PASSWORD_BCRYPT` from the ArgoCD step or from your environment
- `PHD_CLUSTER_DOMAIN` (required)

### phd_create_argo_user

Creates a local user in both ArgoCD and Argo Workflows with the specified RBAC role. The user can authenticate to both systems using the same credentials and gets an automatically generated Kubernetes service account token for Argo Workflows API access.

Usage:

```bash
phd_create_argo_user <username> [role] [password]
```

Parameters:

- username: required
- role: optional, defaults to `developer`
- password: optional; if omitted, you will be prompted

What gets created:

1. **ArgoCD user**: Login account with matching role and password
2. **Argo Workflows user**: SSO account with matching role and password
3. **Kubernetes service account**: Service account in the `argo` namespace
4. **RBAC role**: Namespace-scoped Kubernetes role for workflow resources
5. **Cluster RBAC role**: Cluster-scoped role for cluster workflow templates (if needed)
6. **Role binding**: Binds service account to namespace-scoped role
7. **Cluster role binding**: Binds service account to cluster-scoped role
8. **Access token**: Service account token that can be used with Argo Workflows API

After creation, you'll see output like:
```
Argo Workflows access token created successfully for user 'john'
Argo Workflows API Token for user 'john':
  eyJhbGciOiJSUzI1NiIsImtpZCI6Ikxvd...

Token configured for UI and programmatic access - user can login with token:
UI Access Options for user 'john':
  1. ArgoCD UI: Username: john, Password: [the password you set]
  2. Argo Workflows UI: Token: Bearer [token] (as-is on the login page for token field)"
  2. Argo Workflows API: curl -H \"Authorization: Bearer [token]\" ...

Restart the argo-server pod to apply UI token changes:"
  kubectl delete pod -n argo -l app=argo-server"

This token can be used with:
  curl -H "Authorization: Bearer $TOKEN" https://workflows.$DOMAIN/api/v1/workflows/argo
  argo --server=https://workflows.$DOMAIN --token=$TOKEN list
```

Note: After creating a user, restart both ArgoCD and Argo Workflows servers to apply changes:
```bash
kubectl -n argocd delete pod -l app.kubernetes.io/name=argocd-server
kubectl -n argo delete pod -l app=argo-server
```

### phd_delete_argo_user

Removes a user from both ArgoCD and Argo Workflows and cleans up all associated Kubernetes resources including service accounts, roles, role bindings, cluster roles, cluster role bindings, and tokens.

Usage:

```bash
phd_delete_argo_user <username>
```

Parameters:

- username: required

What gets removed:

1. **ArgoCD user**: Removed from argocd-cm and argocd-secret
2. **Argo Workflows user**: Removed from SSO secret and RBAC policies
3. **Kubernetes service account**: Deleted from the `argo` namespace
4. **RBAC role**: Namespace-scoped role deleted
5. **Cluster RBAC role**: Cluster-scoped role deleted (if it exists)
6. **Role bindings**: Both namespace and cluster role bindings deleted
7. **Access token**: Service account token secret deleted

After deletion, restart both servers to apply changes:
```bash
kubectl -n argocd delete pod -l app.kubernetes.io/name=argocd-server
kubectl -n argo delete pod -l app=argo-server
```

**⚠️ Warning**: This operation is permanent and will revoke all access for the user.

## Argo Workflows API Access

Users created with `phd_create_argo_user` automatically receive a Kubernetes service account token that can be used to access the Argo Workflows API programmatically.

### Token Usage Examples

#### Using curl
```bash
# Set your token
TOKEN="eyJhbGciOiJSUzI1NiIsImtpZCI6Ikxvd..."

# List workflows
curl -H "Authorization: Bearer $TOKEN" \
  https://workflows.your-domain.com/api/v1/workflows/argo

# Submit a workflow
curl -X POST \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  https://workflows.your-domain.com/api/v1/workflows/argo \
  -d @my-workflow.yaml
```

#### Using Argo CLI
```bash
# Configure CLI
export ARGO_SERVER=https://workflows.your-domain.com
export ARGO_TOKEN=your-token-here

# List workflows
argo list

# Submit workflow
argo submit my-workflow.yaml

# Get workflow logs
argo logs workflow-name

# Delete workflow
argo delete workflow-name
```

#### Docker Usage
```bash
# Run Argo CLI in Docker with your token
docker run --rm -it \
  -e ARGO_SERVER=https://workflows.your-domain.com \
  -e ARGO_TOKEN=your-token-here \
  -e ARGO_HTTP1=true \
  quay.io/argoproj/argocli:latest \
  list
```

### Token Security

- Each user gets their own service account with role-based permissions
- Tokens are scoped to the user's permission level (admin/developer/readonly)
- Tokens can be revoked by deleting the secret: `kubectl delete secret <username>-token -n argo`
- New tokens are automatically generated when the secret is recreated

### Troubleshooting

If you get authentication errors:
1. Verify your token hasn't expired or been revoked
2. Check that the Argo Server is running: `kubectl get pods -n argo`
3. Ensure your user's service account exists: `kubectl get serviceaccounts -n argo`
4. For cluster workflow template errors, ensure cluster roles were created: `kubectl get clusterroles`

If you get "clusterworkflowtemplates is forbidden" errors:
1. Re-run the user creation script to ensure cluster roles are created
2. Verify cluster role binding exists: `kubectl get clusterrolebinding <username>-cluster-binding`
3. Restart the Argo Server: `kubectl delete pod -n argo -l app=argo-server`

### phd_delete_argo_user

Removes a user from both ArgoCD and Argo Workflows and cleans up all associated Kubernetes resources including service accounts, roles, role bindings, cluster roles, cluster role bindings, and tokens.

Usage:

```bash
phd_delete_argo_user <username>
```

Parameters:

- username: required

**⚠️ Warning**: This operation is permanent and will revoke all access for the user.

### phd_set_instance_rbac

Applies RBAC for an Open edX instance namespace.

Usage:

```bash
phd_set_instance_rbac <namespace>
```

Parameters:

- namespace: required target namespace

### phd_generate_config

Renders a file from a template using environment variables.

Usage:

```bash
phd_generate_config <template_file> <output_file> [env_file]
```

Parameters:

- template_file: path to input template (supports `${VAR}` placeholders)
- output_file: path to write the rendered file
- env_file: optional shell file to `source` before rendering (sets variables)

### phd_generate_config_interactive

Same behavior as `phd_generate_config`. Provided as a convenience alias.

### phd_validate_config

Checks a rendered config for unsubstituted `${VAR}` placeholders.

Usage:

```bash
phd_validate_config <config_file>
```

## Scripts overview

- `phd-commands.sh`: public command entry points and shared utilities
- `install-argocd.sh`: installs ArgoCD and sets the admin password
- `install-argo-workflows.sh`: installs Argo Workflows, templates, and server auth
- `create-user.sh`: creates local Argo users and applies RBAC mapping with access tokens
- `delete-user.sh`: removes Argo users and cleans up all associated resources
- `set-admin-password.sh`: helpers to generate a password, bcrypt-hash it, and get an RFC3339 mtime
- `render-template.sh`: template rendering and validation helpers
- `set-instance-rbac.sh`: applies instance RBAC config for a given namespace
