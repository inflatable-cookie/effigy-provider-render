let context = deploy::provider_context();

deploy::provider_report(#{
    schema: "effigy.deploy-provider.report.v1",
    phase: "checklist",
    provider: "render",
    status: "planned",
    checks: [
        #{ name: "project", status: "manual", target: context["provider_project"] },
        #{ name: "services", status: "manual", target: "configure provider_config.services.<service> for each deploy.model.v1 service" },
        #{ name: "variables", status: "manual", target: "configure required deploy.model.v1 secret names on each Render service" },
        #{ name: "domains", status: "manual", target: "configure deploy.model.v1 custom domains on matching Render services" },
    ],
    warnings: [],
    blockers: [],
    files: [],
})
