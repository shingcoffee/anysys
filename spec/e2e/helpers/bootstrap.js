import { execFileSync } from "node:child_process"
import { existsSync } from "node:fs"
import { fileURLToPath } from "node:url"
import { isolatedEnvironment, PROJECT_ROOT, runRails, verifyDatabaseConfiguration } from "./rails_runner.js"

const env = isolatedEnvironment()
const mode = process.argv[2] || "apply"
if (!["check", "create", "apply", "export"].includes(mode)) throw new Error("Usage: node spec/e2e/helpers/bootstrap.js [check|create|apply|export]")

// This is deliberately a read-before-create operation, not a connection probe.
process.stdout.write(verifyDatabaseConfiguration(env))
if (mode === "create") {
  if (existsSync(env.E2E_DATABASE_PATH)) throw new Error("create requires a new database; apply reuses an already prepared database")
  execFileSync("bin/rails", ["db:schema:load"], { cwd: PROJECT_ROOT, env, stdio: "inherit" })
}
if (["create", "apply"].includes(mode)) {
  process.stdout.write(runRails(`load ${JSON.stringify(fileURLToPath(new URL("../support/bootstrap.rb", import.meta.url)))}`, { env }))
}
if (mode === "export") {
  if (env.RAILS_ENV !== "test") throw new Error("export requires its own RAILS_ENV=test database")
  if (!existsSync(env.E2E_DATABASE_PATH)) throw new Error("Prepare the separate exporter database with create first")
  // Keep unrelated tmp artifacts. Only the exporter's named JSON files change.
  execFileSync("bundle", ["exec", "rspec", "spec/system/admin/settings/customer_settings_browser_fixtures_spec.rb"], {
    cwd: PROJECT_ROOT, stdio: "inherit",
    env: { ...env, TEST_DATABASE: env.E2E_DATABASE_PATH, SETTINGS_BROWSER_FIXTURES: "1",
      EXPORT_CUSTOMER_SETTINGS_FIXTURES: env.EXPORT_CUSTOMER_SETTINGS_FIXTURES || "tmp/playwright-customer-settings/fixtures" }
  })
}
