let context = deploy::provider_context();

let checks = [];
let warnings = [];
let blockers = [];
let files = [];

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

fn api_post(api_key, path, body) {
    process::run("curl", [
        "-sS",
        "--fail-with-body",
        "--request",
        "POST",
        "--url",
        "https://api.render.com/v1" + path,
        "--header",
        "Accept: application/json",
        "--header",
        "Content-Type: application/json",
        "--header",
        "Authorization: Bearer " + api_key,
        "--data",
        body,
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
    blockers.push("RENDER_API_KEY is required for Render deploy apply.");
} else {
    checks.push(#{ name: "auth-token", status: "configured", target: "RENDER_API_KEY" });
}

if config_string(provider_config, "preflight_scope") == "environment" {
    blockers.push("provider_config.preflight_scope=environment is for smoke validation only; configure service IDs before deploy apply.");
}

if curl["success"] && api_key != "" {
    let auth_result = api_get(api_key, "/owners?limit=1");
    if auth_result["success"] {
        checks.push(#{ name: "api-auth", status: "ok", target: "Render API" });
    } else {
        blockers.push("RENDER_API_KEY could not authenticate with the Render API.");
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

        let service_result = api_get(api_key, "/services/" + service_id);
        if !service_result["success"] {
            blockers.push("Render service '" + service_name + "' is not accessible with the configured service ID.");
            continue;
        }

        let deploy = api_post(api_key, "/services/" + service_id + "/deploys", "{\"clearCache\":\"do_not_clear\"}");
        if deploy["success"] {
            checks.push(#{
                name: "trigger-deploy",
                status: "queued",
                target: service_name + " (" + service_id + ")",
                message: deploy["stdout"],
            });
        } else {
            blockers.push("Failed to trigger Render deploy for service '" + service_name + "'.");
        }
    }
}

let status = "succeeded";
if blockers.len() > 0 {
    status = "failed";
}

deploy::provider_report(#{
    schema: "effigy.deploy-provider.report.v1",
    phase: "apply",
    provider: "render",
    status: status,
    checks: checks,
    warnings: warnings,
    blockers: blockers,
    files: files,
})
