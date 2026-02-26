# Custom Resources

Harmony provides the core cluster resources by default, but you often need extra infrastructure or applications, for example, PR sandbox automation or a dedicated S3 bucket for a plugin. The cluster repository supports adding these as custom Terraform and ArgoCD resources.

## Infrastructure Resources

The `infrastructure` directory in the cluster repository is standard Terraform: Harmony’s modules are used to set up the cluster, and the rest is regular Terraform code. You can define any additional Terraform resources required for your operation in this directory (e.g. extra buckets, IAM, or other cloud resources).

## ArgoCD Resources

Once the cluster is set up, ArgoCD has access to the cluster repository over SSH. You can register any ArgoCD Application, not only Open edX instances. That allows you to deploy other services, such as PR sandbox automation, while keeping everything in code and under version control.

ArgoCD can load configuration from any directory in the repo. For clarity and consistency, use a dedicated `manifests` directory for non–Open-edX applications and shared manifests.

## Related Documentation

- [Infrastructure Overview](index.md) -  Core components (Argo Workflows, ArgoCD)
- [Infrastructure Provisioning](provisioning.md) -  How provision workflows and templates are applied
- [Infrastructure Deprovisioning](deprovisioning.md) -  Deprovision workflows and cleanup

## See Also

- [Instance Provisioning](../instances/provisioning.md) -  Instance-level provisioning
- [Instance Deprovisioning](../instances/deprovisioning.md) -  Instance resource cleanup
- [Instance Configuration](../instances/configuration.md) -  Instance manifests and config
