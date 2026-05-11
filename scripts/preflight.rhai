let context = deploy::provider_context();

let checks = [];
let warnings = [];
let blockers = [];

let provider = context["provider"];

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

fn service_needs_secret(secret, service_name) {
    for target in secret["services"] {
        if target.to_string() == service_name {
            return true;
        }
    }

    false
}

fn service_selected(provider, service_name) {
    if provider.type_of() != "map" || !provider.contains("service_scope") {
        return true;
    }

    for selected in provider["service_scope"] {
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
    blockers.push("RENDER_API_KEY is required for Render API checks.");
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
        warnings.push("provider.preflight_scope=environment set; service, env-var, and domain checks skipped.");
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
            let service_target = service_name + " (" + service_id + ")";

            if service_id == "" {
                blockers.push("Render provider is missing services." + service_name + ".");
                continue;
            }

            let service_result = api_get(api_key, "/services/" + service_id);
            if service_result["success"] {
                checks.push(#{ name: "service", status: "ok", target: service_target });
            } else {
                blockers.push("Render service '" + service_name + "' is not accessible with the configured service ID.");
                continue;
            }

            for secret in context["model"]["secrets"] {
                let secret_name = secret["name"].to_string();
                if service_needs_secret(secret, service_name) {
                    let env_result = api_get(api_key, "/services/" + service_id + "/env-vars/" + secret_name);
                    if env_result["success"] {
                        checks.push(#{ name: "env-var", status: "ok", target: service_name + ":" + secret_name });
                    } else {
                        blockers.push("Render service '" + service_name + "' is missing required env var name '" + secret_name + "'.");
                    }
                }
            }

            for domain in context["model"]["domains"] {
                if domain["service"].to_string() == service_name {
                    let host = domain["host"].to_string();
                    let domain_result = api_get(api_key, "/services/" + service_id + "/custom-domains/" + host);
                    if domain_result["success"] {
                        checks.push(#{ name: "domain", status: "ok", target: service_name + ":" + host });
                    } else {
                        blockers.push("Render service '" + service_name + "' is missing configured custom domain '" + host + "'.");
                    }
                }
            }
        }
    }
}

let status = "planned";
if blockers.len() > 0 {
    status = "blocked";
}

deploy::provider_report(#{
    schema: "effigy.deploy-provider.report.v1",
    phase: "preflight",
    provider: "render",
    status: status,
    checks: checks,
    warnings: warnings,
    blockers: blockers,
    files: [],
})
