let context = deploy::provider_context();

deploy::provider_report(#{
    schema: "effigy.deploy-provider.report.v1",
    phase: "status",
    provider: "render",
    status: "planned",
    checks: [],
    warnings: ["Live Render status is not implemented in this provider package yet."],
    blockers: [],
    files: [],
})
