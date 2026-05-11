# effigy-provider-render

Render deployment provider package for Effigy.

This repository is intentionally package-shaped first:

- `provider.toml` declares provider identity, phase scripts, and safety policy.
- `scripts/*.rhai` emit `effigy.deploy-provider.report.v1` reports.
- Core Effigy owns the deployment transaction, safety gates, and report
  persistence. This package owns Render-specific provider behavior.

The package uses Render's public REST API from Rhai. It does not create Render
projects, services, databases, variables, or domains. `apply.rhai` only triggers
deploys for services that already exist.

## Runtime Requirements

Set these environment variables before running `effigy deploy plan`,
`effigy deploy status`, or `effigy deploy apply` for a Render target:

- `RENDER_API_KEY`: Render API key. The scripts never write it to reports.
- `EFFIGY_RENDER_SERVICE_<service>_ID`: Render service ID for each service in
  `deploy.model.v1`.

For an Acowtancy-style model with `front`, `admin`, `api`, and `jobs` services:

```text
RENDER_API_KEY=...
EFFIGY_RENDER_SERVICE_front_ID=srv-...
EFFIGY_RENDER_SERVICE_admin_ID=srv-...
EFFIGY_RENDER_SERVICE_api_ID=srv-...
EFFIGY_RENDER_SERVICE_jobs_ID=srv-...
```

The service suffix is the exact service name from the Effigy deploy model. A
fallback `RENDER_SERVICE_<service>_ID` name is also accepted.

## API Surface

- Preflight checks `curl`, API authentication, service access, required
  service-level env var names, and configured custom domains.
- Status lists the latest deploy for each configured service.
- Apply re-runs the same basic access checks and triggers a Render deploy for
  each configured service.

This package validates existing Render setup. It does not provision missing
setup or print secret values.
