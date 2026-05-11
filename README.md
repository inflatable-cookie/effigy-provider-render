# effigy-provider-render

Render deployment provider package for Effigy.

This repository is intentionally package-shaped first:

- `provider.toml` declares provider identity, phase scripts, and safety policy.
- `scripts/*.rhai` emit `effigy.deploy-provider.report.v1` reports.
- Core Effigy still owns the deployment transaction, safety gates, report
  persistence, and built-in compatibility behavior while provider packages
  stabilize.

The package currently contains safe report-only scaffolding. It does not create
Render projects, services, databases, variables, domains, or deployments.
