let context = deploy::provider_context();

let checks = [];
let warnings = [];
let blockers = [];

let provider_config = context["provider_config"];

fn config_string(config, key) {
    if config.type_of() != "map" {
        return "";
    }

    if !config.contains(key) {
        return "";
    }

    config[key].to_string()
}

fn service_id_for(config, service_name) {
    if config.type_of() != "map" {
        return "";
    }

    if !config.contains("services") {
        return "";
    }

    let services = config["services"];
    if services.type_of() != "map" || !services.contains(service_name) {
        return "";
    }

    services[service_name].to_string()
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

fn service_selected(service_name) {
    if provider_config.type_of() != "map" || !provider_config.contains("service_scope") {
        return true;
    }

    for selected in provider_config["service_scope"] {
        if selected.to_string() == service_name {
            return true;
        }
    }

    false
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

    let project_id = config_string(provider_config, "project_id");
    if project_id != "" {
        let project_result = api_get(api_key, "/projects/" + project_id);
        if project_result["success"] {
            checks.push(#{
                name: "project",
                status: "ok",
                target: context["provider_project"] + " (" + project_id + ")",
            });
        } else {
            blockers.push("Render project '" + context["provider_project"] + "' is not accessible with provider_config.project_id.");
        }
    } else {
        blockers.push("Render provider config requires `project_id`.");
    }

    let environment_id = config_string(provider_config, "environment_id");
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
    } else {
        blockers.push("Render provider config requires `environment_id`.");
    }

    if config_string(provider_config, "preflight_scope") == "environment" {
        warnings.push("provider_config.preflight_scope=environment set; service deploy status checks skipped.");
    } else {
        if provider_config.type_of() == "map" && provider_config.contains("service_scope") {
            warnings.push("provider_config.service_scope set; checking only selected services.");
        }

        for service in context["model"]["services"] {
            let service_name = service["name"].to_string();
            if !service_selected(service_name) {
                continue;
            }

            let service_id = service_id_for(provider_config, service_name);

            if service_id == "" {
                blockers.push("Render provider config is missing services." + service_name + ".");
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
