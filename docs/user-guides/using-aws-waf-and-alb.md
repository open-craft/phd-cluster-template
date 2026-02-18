# Using AWS WAF and ALB

By default, in AWS, Harmony uses an NGINX ingress. This ingress is backed by AWS ELB load balancers.

That ingress setup works for most use cases, but in case you need to use a feature that is only supported by the Application Load Balancer type, such as a WAF, you can configure it with the following setup:

## 1. Cluster Configuration

The ALB ingress controller requires some extra permissions added to the Kubernetes cluster. You can declare a policy that provides those permissions by adding the following statements to a Terraform file inside the `infrastructure` folder:

```hcl
variable "cluster_self_managed_node_groups" {}

resource "aws_iam_policy" "alb_policy" {
  name        = "alb-policy"
  description = "Policy required for alb creation."
  policy      = file("${path.module}/alb-role.json")
}

# Optional policy that makes it posible to use ALB ingress
resource "aws_iam_policy_attachment" "alb-policy-attachment" {
  name       = "${var.cluster_name}-alb-attachment"
  roles      = [var.cluster_self_managed_node_groups["worker_group"].iam_role_name]
  policy_arn = aws_iam_policy.alb_policy.arn
}

resource "helm_release" "alb_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = "1.7.2" # NOTE: set the latest version
  namespace  = "kube-system"
  depends_on = [
    aws_iam_policy_attachment.alb-policy-attachment
  ]

  set {
    name  = "clusterName"
    value = var.kubernetes_cluster_name
  }

  set {
    name  = "region"
    value = var.region
  }

  set {
    name  = "vpcId"
    value = var.vpc_id
  }
}
```

You'll also need to download the iam policy role json definition into the `infrastructure/alb-role.json`
from [Kubernetes SIGs aws-load-balancer-controller's repo](https://raw.githubusercontent.com/kubernetes-sigs/aws-alb-ingress-controller/main/docs/install/iam_policy.json).

## 2. Declare Ingress

Now you can declare an ALB Ingress in the `infrastructure` folder. Here's an example of one:

```hcl
resource "kubernetes_manifest" "alb_ingress" {
  depends_on = [helm_release.alb_controller]
  manifest   = {
    "apiVersion" = "networking.k8s.io/v1"
    "kind" = "Ingress"
    "metadata" = {
      "annotations" = {
        "alb.ingress.kubernetes.io/scheme" = "internet-facing"
        "alb.ingress.kubernetes.io/target-type": "ip"
      }
      "labels" = {
        "app.kubernetes.io/part-of" = "openedx"
      }
      "name" = "alb-ingress"
      "namespace" = "<INSTANCE-NAMESPACE>"
    }
    "spec" = {
      "ingressClassName" = "alb"
      "rules" = [
        # Repeat this rule for all the hostnames you'll point to this ingress.
        {
          "host" = "<HOSTNAME>"
          "http" = {
            "paths" = [
              {
                "backend" = {
                  "service" = {
                    "name" = "caddy"
                    "port" = {
                      "number" = 80
                    }
                  }
                }
                "path" = "/"
                "pathType" = "Prefix"
              },
            ]
          }
        }
      ]
    }
  }
}
```

As an alternative, you may use Kubernetes manifests, deployed using ArgoCD.

## 3. Setup DNS

The last step is adding a CNAME record pointing to the ALB domain for any domain you want to configure. You can find the
ALB domain in the AWS console. You may also want to remove any records pointing to the old NGINX Ingress.

## Optional: Disable default Ingress

In order to avoid having double the ammount of Load Balancers, you can disable the default load balancer as needed in the
harmony [helm values file](https://gitlab.com/opencraft/dev/grove/-/blob/main/provider-modules/harmony/values.yml?ref_type=heads#L4)

## Optional: Enable WAF

An example of a resource that requires ALB is Amazon's Web Application Firewall (WAF).
Once you have completed the above setup you can either add a WAF manually to the generated ingress
in the AWS console, or declare it in the `infrastructure` directory with the following terraform code:

```hcl
resource "aws_wafv2_web_acl" "alb_waf" {
  name  = "alb-waf"
  scope = "REGIONAL"

  default_action {
    allow {}
  }


  # This is an example rule. Create one based on your needs.
  rule {
    name     = "RateLimit"
    priority = 1

    action {
      block {}
    }

    statement {

      rate_based_statement {
        aggregate_key_type = "IP"
        limit              = 500
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "RateLimit"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = false
    metric_name                = "alb-waf"
    sampled_requests_enabled   = false
  }
}
```

You also need to update your ingress tags:

```hcl
resource "kubernetes_manifest" "alb_ingress" {
  manifest = {
    "apiVersion" = "networking.k8s.io/v1"
    "kind" = "Ingress"
    "metadata" = {
      "annotations" = {
        "alb.ingress.kubernetes.io/scheme" = "internet-facing"
        "alb.ingress.kubernetes.io/target-type": "ip"
        "alb.ingress.kubernetes.io/wafv2-acl-arn": aws_wafv2_web_acl.alb_waf.arn
```

> NOTE: If you set up WAF manually you need disable the contoller's WAF capabilities by
  setting controller command line flags `--enable-waf=false` or `--enable-wafv2=false`. If
  the controller is also managing WAF, it'll make sure that the annotation matches exactly
  the waf acl linked to the Load Balancer. This means that it will delete the waf acl if it
  doesn't match with the Ingress annotations.

## Related Documentation

- [User Guides Overview](index.md) -  All user guides
- [Infrastructure Overview](../infrastructure/index.md) -  Ingress and Harmony
- [Cluster Configuration](../cluster/configuration.md) -  Cluster and Terraform settings
- [Instances Overview](../instances/index.md) -  Instance lifecycle

## See Also

- [Infrastructure Provisioning](../infrastructure/provisioning.md) -  Cluster setup
- [Instance Configuration](../instances/configuration.md) -  Instance manifests
- [Multi-Domain Setup](multi-domain-setup.md) -  Multiple domains and ingress
