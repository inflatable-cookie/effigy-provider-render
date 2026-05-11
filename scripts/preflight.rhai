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

fn service_needs_secret(secret, service_name) {
    for target in secret["services"] {
        if target.to_string() == service_name {
            return true;
        }
    }

    false
}

fn service_selected(service_name) {
    let selected = env("EFFIGY_RENDER_SERVICES");
    if selected == "" {
        return true;
    }

    str::contains("," + selected + ",", "," + service_name + ",")
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
    } else {
        warnings.push("EFFIGY_RENDER_PROJECT_ID is not set; project-level Render validation skipped.");
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
    } else {
        warnings.push("EFFIGY_RENDER_ENVIRONMENT_ID_" + context["env"] + " is not set; environment-level Render validation skipped.");
    }

    if env("EFFIGY_RENDER_PREFLIGHT_SCOPE") == "environment" {
        warnings.push("EFFIGY_RENDER_PREFLIGHT_SCOPE=environment set; service, env-var, and domain checks skipped.");
    } else {
        if env("EFFIGY_RENDER_SERVICES") != "" {
            warnings.push("EFFIGY_RENDER_SERVICES set; checking only selected services: " + env("EFFIGY_RENDER_SERVICES"));
        }

        for service in context["model"]["services"] {
            let service_name = service["name"].to_string();
            if !service_selected(service_name) {
                continue;
            }

            let service_id = service_id_for(service_name);
            let service_target = service_name + " (" + service_id + ")";

            if service_id == "" {
                blockers.push("Missing " + service_id_env_name(service_name) + " for Render service '" + service_name + "'.");
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
