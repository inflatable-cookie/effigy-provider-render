let context = deploy::provider_context();

deploy::provider_report(#{
    schema: "effigy.deploy-provider.report.v1",
    phase: "checklist",
    provider: "render",
    status: "planned",
    checks: [
        #{ name: "project", status: "manual", target: context["deploy_plan"]["app"]["project_name"] },
        #{ name: "services", status: "manual", target: "front,admin,api,jobs" },
        #{ name: "variables", status: "manual", target: "DATABASE_URL" },
        #{ name: "domains", status: "manual", target: "front,admin,api" },
    ],
    warnings: [],
    blockers: [],
    files: [],
})
