import { execFileSync } from "node:child_process"
import { existsSync, realpathSync } from "node:fs"
import { dirname, resolve } from "node:path"
import { fileURLToPath } from "node:url"

export const PROJECT_ROOT = fileURLToPath(new URL("../../..", import.meta.url))

export function isolatedEnvironment(input = process.env) {
  const database = resolve(PROJECT_ROOT, input.E2E_DATABASE_PATH || "")
  const storage = realpathSync(resolve(PROJECT_ROOT, "storage"))
  if (!input.E2E_DATABASE_PATH || dirname(database) !== storage ||
      !/^(browser|e2e)[\w.-]*\.sqlite3$/.test(database.split("/").at(-1)) ||
      (existsSync(database) && realpathSync(database) !== database)) {
    throw new Error("E2E_DATABASE_PATH must name a dedicated app-local storage/browser*.sqlite3 or storage/e2e*.sqlite3 file")
  }
  const databaseUrl = `sqlite3:${database}`
  if (input.DATABASE_URL && input.DATABASE_URL !== databaseUrl) throw new Error("DATABASE_URL does not match E2E_DATABASE_PATH")
  if (input.RAILS_ENV && !["development", "test"].includes(input.RAILS_ENV)) throw new Error("E2E requires development or test")
  if (input.E2E_STUB_ASSISTANT === "1") throw new Error("Use the local HTTP provider, not E2E_STUB_ASSISTANT")
  return { ...input, E2E_DATABASE_PATH: database, DATABASE_URL: databaseUrl, RAILS_ENV: input.RAILS_ENV || "development" }
}

// db_config is inspected before asking ActiveRecord for a connection. The same
// preamble guards every subprocess, including cleanup and fixture exporters.
export const DATABASE_ASSERTION = `
  expected = File.expand_path(ENV.fetch("E2E_DATABASE_PATH"))
  config = ActiveRecord::Base.configurations.configs_for(env_name: Rails.env, name: "primary")
  actual = File.expand_path(config.database.to_s, Rails.root)
  abort "E2E database configuration mismatch" unless config.adapter == "sqlite3" && actual == expected
  abort "E2E environment required" unless Rails.env.development? || Rails.env.test?
`

export function runRails(script, { env = process.env, ...options } = {}) {
  const isolated = isolatedEnvironment(env)
  verifyDatabaseConfiguration(isolated)
  return execFileSync("bin/rails", ["runner", DATABASE_ASSERTION + script], {
    cwd: PROJECT_ROOT, env: isolated, encoding: "utf8", ...options
  })
}

export function verifyDatabaseConfiguration(env = isolatedEnvironment()) {
  // Loading application.rb (not environment.rb) avoids after_initialize hooks
  // which can connect/register rows before a Rails runner's first line executes.
  return execFileSync("bundle", ["exec", "ruby", "-e", `
    require_relative "config/application"
    ActiveRecord::Base.configurations = Rails.application.config.database_configuration
    ${DATABASE_ASSERTION}
    puts "E2E_DATABASE=#{actual} environment=#{Rails.env}"
  `], { cwd: PROJECT_ROOT, env, encoding: "utf8" })
}
