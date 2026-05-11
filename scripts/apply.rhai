let context = deploy::provider_context();

deploy::provider_report(#{
    schema: "effigy.deploy-provider.report.v1",
    phase: "apply",
    provider: "render",
    status: "blocked",
    checks: [],
    warnings: [],
    blockers: ["Render apply is intentionally unavailable until the provider package has live API/CLI support and core Effigy passes explicit mutation approval."],
    files: [],
})
