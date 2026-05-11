let context = deploy::provider_context();

deploy::provider_report(#{
    schema: "effigy.deploy-provider.report.v1",
    phase: "preflight",
    provider: "render",
    status: "planned",
    checks: [
        #{ name: "provider-adapter", status: "planned", target: "render" },
        #{ name: "variables", status: "planned", target: "DATABASE_URL" },
        #{ name: "domains", status: "planned", target: "configured-domain-names" },
    ],
    warnings: ["Live Render API/CLI checks are not implemented in this provider package yet."],
    blockers: [],
    files: [],
})
