let context = deploy::provider_context();
let model = context.model;
let export_path = context.export_path;
let plan = context.plan;

let files = [];
let warnings = [];

// Find postgres backing service
let database_name = ();
for bs in model.backing_services {
    if bs.kind == "postgres" && bs.required {
        database_name = model.app.name + "-postgres";
    }
}

let services = [];
for service in model.services {
    if service.volumes.len() > 0 {
        throw("render export does not support persistent app volumes yet (`" + service.name + "`)");
    }

    let env_vars = [];
    for key in service.env.keys() {
        env_vars.push(#{
            key: key,
            value: service.env[key],
        });
    }

    for secret_ref in service.secret_refs {
        if secret_ref == "DATABASE_URL" {
            if database_name == () {
                throw("render export cannot satisfy `DATABASE_URL` for `" + service.name + "` without managed postgres");
            }
            env_vars.push(#{
                key: secret_ref,
                fromDatabase: #{
                    name: database_name,
                    property: "connectionString",
                },
            });
        } else {
            let secret_entry = #{ key: secret_ref };
            secret_entry["sync"] = false;
            env_vars.push(secret_entry);
        }
    }

    let svc = #{};

    if service.role == "static" {
        let output = service.output;
        if output == () {
            throw("render export requires static output metadata for `" + service.name + "`");
        }
        if output.fallback == () {
            throw("render export requires static fallback metadata for `" + service.name + "`");
        }
        let build = service.build;
        if build == () {
            throw("render export requires build metadata for `" + service.name + "`");
        }

        svc.name = service.name;
        svc["type"] = "web";
        svc.runtime = "static";
        svc.rootDir = service.source_root;
        svc.buildCommand = build.command;
        svc.staticPublishPath = service.source_root + "/" + output.path;
        svc.domains = service.domains;
        svc.routes = [#{
            type: "rewrite",
            source: "/*",
            destination: "/" + output.fallback,
        }];
    } else if service.role == "web" {
        let build = service.build;
        if build == () {
            throw("render export requires build metadata for `" + service.name + "`");
        }
        let start = service.start;
        if start == () {
            throw("render export requires start metadata for `" + service.name + "`");
        }

        svc.name = service.name;
        svc["type"] = "web";
        svc.runtime = service.runtime;
        svc.rootDir = service.source_root;
        svc.buildCommand = build.command;
        svc.startCommand = start.command;
        if service.release != () {
            svc.preDeployCommand = service.release.command;
        }
        if service.health != () {
            svc.healthCheckPath = service.health.path;
        }
        svc.domains = service.domains;
    } else if service.role == "worker" {
        let build = service.build;
        if build == () {
            throw("render export requires build metadata for `" + service.name + "`");
        }
        let start = service.start;
        if start == () {
            throw("render export requires start metadata for `" + service.name + "`");
        }

        svc.name = service.name;
        svc["type"] = "worker";
        svc.runtime = service.runtime;
        svc.rootDir = service.source_root;
        svc.buildCommand = build.command;
        svc.startCommand = start.command;
    } else if service.role == "cron" {
        throw("render export does not support `cron` services yet");
    } else {
        throw("render export does not support service role `" + service.role + "` yet");
    }

    svc.envVars = env_vars;
    services.push(svc);
}

let blueprint = #{ services: services };

if database_name != () {
    blueprint.databases = [#{
        name: database_name,
        plan: "basic-256mb",
        databaseName: "app",
    }];
}

if !plan {
    let yaml_str = yaml::stringify(blueprint);
    fs::write_file(export_path + "/render.yaml", yaml_str);
}
files.push("render.yaml");

deploy::provider_report(#{
    schema: "effigy.deploy-provider.report.v1",
    phase: "export",
    provider: "render",
    status: "planned",
    checks: [],
    warnings: warnings,
    blockers: [],
    files: files,
})
