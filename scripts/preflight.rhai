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

fn service_needs_secret(secret, service_name) {
    for target in secret["services"] {
        if target.to_string() == service_name {
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
    for service in context["model"]["services"] {
        let service_name = service["name"].to_string();
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
