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

Render IDs are configured in `[deploy.<env>.provider]`:

```toml
[deploy.uat.provider]
adapter = "render"
project_id = "prj-..."
environment_id = "env-..."
services = { front = "srv-...", admin = "srv-...", api = "srv-..." }
```

For service-subset smoke testing:

```toml
[deploy.uat.provider]
adapter = "render"
project_id = "prj-..."
environment_id = "env-..."
service_scope = ["front"]
skip_domains = true
services = { front = "srv-..." }
```

For an Acowtancy-style model with `front`, `admin`, `api`, and `jobs` services:

```text
RENDER_API_KEY=...
```

## Environment-Only Smoke

Before services exist, you can validate API access and project/environment IDs
without pretending a deploy can run:

```text
RENDER_API_KEY=...
```

And configure:

```toml
[deploy.uat.provider]
project_id = "prj-..."
environment_id = "env-..."
preflight_scope = "environment"
```

Then run:

```sh
effigy deploy plan uat
effigy deploy status uat
```

`apply.rhai` remains blocked in environment-only scope. Create services and
configure their service ID variables before testing live deployment.

## One-Service Smoke

After creating a single Render service in the `uat` environment, test it before
building the full deployment shape:

```text
RENDER_API_KEY=...
```

And configure:

```toml
[deploy.uat.provider]
adapter = "render"
project_id = "prj-..."
environment_id = "env-..."
service_scope = ["front"]
skip_domains = true
services = { front = "srv-..." }
```

Then run:

```sh
effigy deploy plan uat
effigy deploy status uat
```

Do not set `preflight_scope = "environment"` for this phase. `apply` will
trigger a deploy for the selected service only.

`skip_domains = true` is for smoke services that do not carry the real app
domains yet. Remove it for UAT/production validation.

## API Surface

- Preflight checks `curl`, API authentication, service access, required
  service-level env var names, and configured custom domains. If project and
  environment IDs are configured, it verifies those too.
- Status lists the latest deploy for each configured service.
- Apply re-runs the same basic access checks and triggers a Render deploy for
  each configured service.

This package validates existing Render setup. It does not provision missing
setup or print secret values.
