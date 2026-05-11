let context = deploy::provider_context();

let checks = [];
let warnings = [];
let blockers = [];
let files = [];

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

if curl["success"] && api_key != "" {
    for service in context["model"]["services"] {
        let service_name = service["name"].to_string();
        let service_id = service_id_for(service_name);

        if service_id == "" {
            blockers.push("Missing " + service_id_env_name(service_name) + " for Render service '" + service_name + "'.");
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
