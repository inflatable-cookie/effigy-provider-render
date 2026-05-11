let context = deploy::provider_context();

let checks = [];
let warnings = [];
let blockers = [];

fn service_id_env_name(service_name) {
    "EFFIGY_RENDER_SERVICE_" + service_name + "_ID"
}

fn service_id_for(service_name) {
    let primary = service_id_env_name(service_name);
    let value = env(primary);
    if value != "" {
        return value;
    }

    env("RENDER_SERVICE_" + service_name + "_ID")
}

fn api_get(api_key, path) {
    process::run("curl", [
        "-sS",
        "--fail-with-body",
        "--request",
        "GET",
        "--url",
        "https://api.render.com/v1" + path,
        "--header",
        "Accept: application/json",
        "--header",
        "Authorization: Bearer " + api_key,
    ])
}

fn environment_id_for(env_name) {
    let value = env("EFFIGY_RENDER_ENVIRONMENT_ID_" + env_name);
    if value != "" {
        return value;
    }

    env("EFFIGY_RENDER_ENVIRONMENT_ID")
}

let curl = process::run("curl", ["--version"]);
if curl["success"] {
    checks.push(#{ name: "curl", status: "ok", target: "curl" });
} else {
    blockers.push("Render provider requires curl on PATH.");
}

let api_key = env("RENDER_API_KEY");
if api_key == "" {
    blockers.push("RENDER_API_KEY is required for Render status checks.");
} else {
    checks.push(#{ name: "auth-token", status: "configured", target: "RENDER_API_KEY" });
}

if curl["success"] && api_key != "" {
    let auth_result = api_get(api_key, "/owners?limit=1");
    if auth_result["success"] {
        checks.push(#{ name: "api-auth", status: "ok", target: "Render API" });
    } else {
        blockers.push("RENDER_API_KEY could not authenticate with the Render API.");
    }

    let project_id = env("EFFIGY_RENDER_PROJECT_ID");
    if project_id != "" {
        let project_result = api_get(api_key, "/projects/" + project_id);
        if project_result["success"] {
            checks.push(#{
                name: "project",
                status: "ok",
                target: context["provider_project"] + " (" + project_id + ")",
            });
        } else {
            blockers.push("Render project '" + context["provider_project"] + "' is not accessible with EFFIGY_RENDER_PROJECT_ID.");
        }
    }

    let environment_id = environment_id_for(context["env"]);
    if environment_id != "" {
        let environment_result = api_get(api_key, "/environments/" + environment_id);
        if environment_result["success"] {
            checks.push(#{
                name: "environment",
                status: "ok",
                target: context["env"] + " (" + environment_id + ")",
            });
        } else {
            blockers.push("Render environment '" + context["env"] + "' is not accessible with the configured environment ID.");
        }
    }

    if env("EFFIGY_RENDER_PREFLIGHT_SCOPE") == "environment" {
        warnings.push("EFFIGY_RENDER_PREFLIGHT_SCOPE=environment set; service deploy status checks skipped.");
    } else {
    for service in context["model"]["services"] {
        let service_name = service["name"].to_string();
        let service_id = service_id_for(service_name);

        if service_id == "" {
            blockers.push("Missing " + service_id_env_name(service_name) + " for Render service '" + service_name + "'.");
            continue;
        }

        let deploys = api_get(api_key, "/services/" + service_id + "/deploys?limit=1");
        if deploys["success"] {
            checks.push(#{
                name: "latest-deploy",
                status: "ok",
                target: service_name + " (" + service_id + ")",
                message: deploys["stdout"],
            });
        } else {
            blockers.push("Failed to retrieve latest Render deploy for service '" + service_name + "'.");
        }
    }
    }
}

let status = "ok";
if blockers.len() > 0 {
    status = "blocked";
}

deploy::provider_report(#{
    schema: "effigy.deploy-provider.report.v1",
    phase: "status",
    provider: "render",
    status: status,
    checks: checks,
    warnings: warnings,
    blockers: blockers,
    files: [],
})
