# Multi-Domain Setup

Multi-domain setup can be configured with the
[`grove-tenants`](https://gitlab.com/opencraft/dev/tutor-contrib-grove/-/tree/main) Tutor plugin.

Append the following entries to the existing `PICASSO_EXTRA_COMMANDS` list in
`instances/<instance-name>/config.yml`:

```yaml
PICASSO_EXTRA_COMMANDS:
  # Keep the existing entries and add:
  - pip install git+https://gitlab.com/opencraft/dev/tutor-contrib-grove
  - tutor plugins enable grove-tenants
```

Rebuild the Open edX image and deploy the updated instance configuration. Then configure
multi-domain support using `eox-tenant`.

The [`eox-tenant`](https://github.com/eduNEXT/eox-tenant) plugin overrides Django settings for
individual tenants, including settings that are not site-configuration aware. This overcomes
limitations of the basic site-configuration approach.

!!! warning "Important"
    `eox-tenant` also proxies the Site Configuration model, so it fetches configuration
    values from tenant settings. Tenant settings inherit the base settings, so common settings can
    be placed under `GROVE_LMS_ENV` or `GROVE_CMS_ENV`, depending on the environment.

To enable it, set `GROVE_USE_EOX_TENANT` to `true` and define your domains under
`GROVE_ADDITIONAL_DOMAINS` in the instance's `config.yml`:

```yaml
LMS_HOST: example.com
CMS_HOST: studio.example.com
GROVE_USE_EOX_TENANT: true
GROVE_ADDITIONAL_DOMAINS:
- domain: example.net
  external_key: example.net
  proxy: lms:8000
  site_configuration:
    PLATFORM_NAME: example.net
    SITE_NAME: example.net
- domain: studio.example.net
  external_key: example.net
  proxy: cms:8000
  site_configuration:
    PLATFORM_NAME: example.net Studio
- domain: university.example.com
  external_key: university.example.com
  proxy: lms:8000
- domain: studio.university.example.com
  external_key: university.example.com
  proxy: cms:8000
```

The `external_key` is a unique identifier for a tenant configuration that links it to one
or more routes. In the example, `example.net` (external_key `example.net`) is linked to
LMS (`example.net`) and Studio (`studio.example.net`). Likewise, `university.example.com`
(external_key `university.example.com`) is linked to LMS (`university.example.com`) and Studio
(`studio.university.example.com`).

Settings can be scoped per environment. For instance, `PLATFORM_NAME` differs for the `example.net`
LMS and Studio tenants above. Common tenant settings can be placed under `GROVE_LMS_ENV` or
`GROVE_CMS_ENV` depending on the environment.

## Related Documentation

- [User Guides Overview](index.md) -  All user guides
- [Instance Configuration](../instances/configuration.md) -  Tutor and hosts
- [Infrastructure Overview](../infrastructure/index.md) -  Ingress and TLS
- [Instances Overview](../instances/index.md) -  Instance lifecycle

## See Also

- [Using AWS WAF and ALB](using-aws-waf-and-alb.md) -  ALB and ingress
- [Instance Provisioning](../instances/provisioning.md) -  Instance setup
- [Cluster Configuration](../cluster/configuration.md) -  Cluster settings
