let context = deploy::provider_context();

let checks = [];
let warnings = [];
let blockers = [];

let provider = context["provider"];

fn config_string(provider_config, key) {
    if provider_config.type_of() != "map" {
        return "";
    }

    if !provider_config.contains(key) {
        return "";
    }

    provider_config[key].to_string()
}

fn service_id_for(provider_config, service_name) {
    if provider_config.type_of() != "map" {
        return "";
    }

    if !provider_config.contains("services") {
        return "";
    }

    let services = provider_config["services"];
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

fn render_api_key() {
    let api_key = env("RENDER_API_KEY");
    if api_key != "" {
        return api_key;
    }

    try {
        if secrets::has("render_api_key") {
            return secrets::get("render_api_key");
        }
    } catch (error) {
        return "";
    }

    ""
}

fn service_selected(provider, service_name) {
    if provider.type_of() != "map" {
        return true;
    }

    if provider.contains("service_scope") {
        let scope = provider["service_scope"];
        if scope.type_of() == "string" {
            return scope.to_string() == service_name || str::contains("," + scope.to_string() + ",", "," + service_name + ",");
        }

        for selected in scope {
            if selected.to_string() == service_name {
                return true;
            }
        }

        return false;
    }

    if provider.contains("services") && provider["services"].type_of() == "map" {
        return provider["services"].contains(service_name);
    }

    true
}

let curl = process::run("curl", ["--version"]);
if curl["success"] {
    checks.push(#{ name: "curl", status: "ok", target: "curl" });
} else {
    blockers.push("Render provider requires curl on PATH.");
}

let api_key = render_api_key();
if api_key == "" {
    blockers.push("Render API credentials are required via Effigy secret `render_api_key` or compatibility env `RENDER_API_KEY`.");
} else {
    checks.push(#{ name: "auth-token", status: "configured", target: "render_api_key" });
}

if curl["success"] && api_key != "" {
    let auth_result = api_get(api_key, "/owners?limit=1");
    if auth_result["success"] {
        checks.push(#{ name: "api-auth", status: "ok", target: "Render API" });
    } else {
        blockers.push("RENDER_API_KEY could not authenticate with the Render API.");
    }

    let project_id = config_string(provider, "project_id");
    if project_id != "" {
        let project_result = api_get(api_key, "/projects/" + project_id);
        if project_result["success"] {
            checks.push(#{
                name: "project",
                status: "ok",
                target: context["provider_project"] + " (" + project_id + ")",
            });
        } else {
            blockers.push("Render project '" + context["provider_project"] + "' is not accessible with provider.project_id.");
        }
    } else {
        blockers.push("Render provider requires `project_id`.");
    }

    let environment_id = config_string(provider, "environment_id");
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
        blockers.push("Render provider requires `environment_id`.");
    }

    if config_string(provider, "preflight_scope") == "environment" {
        warnings.push("provider.preflight_scope=environment set; service deploy status checks skipped.");
    } else {
        if provider.type_of() == "map" && provider.contains("service_scope") {
            warnings.push("provider.service_scope set; checking only selected services.");
        }

        for service in context["model"]["services"] {
            let service_name = service["name"].to_string();
            if !service_selected(provider, service_name) {
                continue;
            }

            let service_id = service_id_for(provider, service_name);

            if service_id == "" {
                blockers.push("Render provider is missing services." + service_name + ".");
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
