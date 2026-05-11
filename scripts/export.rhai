let context = deploy::provider_context();

deploy::provider_report(#{
    schema: "effigy.deploy-provider.report.v1",
    phase: "export",
    provider: "render",
    status: "planned",
    checks: [],
    warnings: ["Render export is currently served by Effigy core compatibility code."],
    blockers: [],
    files: [],
})
