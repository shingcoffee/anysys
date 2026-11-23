import { spawn } from "node:child_process"
import { once } from "node:events"
import { createInterface } from "node:readline"
import { fileURLToPath, pathToFileURL } from "node:url"
import { PROJECT_ROOT, runRails } from "./rails_runner.js"

export const TRANSCRIPT = "Browser microphone fixture transcript."

// Export the resolved operation contracts (and the flowchart follow-on
// schema). Vocabulary slots are resolved for the platform customer so the
// fixture validates the same enums the live tools advertise. The guarded
// runner uses the server's exact database; it never loads the schema.
export function providerSchemas() {
  const output = runRails(`
    customer = Customer.find_by(id: Authentication::User::PLATFORM_CUSTOMER_ID) || Customer.first
    abort "E2E customer required" unless customer
    ctx = Operations::Context.new(customer: customer, channel: "assistant")
    puts({
      create_entity: Operations.for("create_entity").input_schema(ctx).document,
      update_entity: Operations.for("update_entity").input_schema(ctx).document,
      get_entity: Operations.for("get_entity").input_schema(ctx).document,
      flowchart: FlowchartDefinitions::StructureSchema.json
    }.to_json)
  `)
  return JSON.parse(output.trim().split("\n").at(-1))
}

// Thin lifecycle wrapper around the project's installed WEBrick HTTP library.
export async function providerBackend(port = 0, schemas = providerSchemas()) {
  const child = spawn("bundle", ["exec", "ruby", fileURLToPath(new URL("../support/provider_server.rb", import.meta.url))], {
    cwd: PROJECT_ROOT, env: { ...process.env, E2E_PROVIDER_PORT: String(port) }, stdio: ["pipe", "pipe", "inherit"]
  })
  child.stdin.end(JSON.stringify(schemas))
  const lines = createInterface({ input: child.stdout })
  const exited = once(child, "exit")
  const result = await Promise.race([
    once(lines, "line").then(([line]) => JSON.parse(line)),
    exited.then(([code]) => { throw new Error(`Local provider exited before readiness (${code})`) })
  ])
  return { ...result, close: async () => { child.kill("SIGTERM"); await exited; lines.close() } }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const provider = await providerBackend(Number(process.env.E2E_PROVIDER_PORT || 3012))
  process.stdout.write(`Local E2E provider: ${provider.url}/v1\n`)
  for (const signal of ["SIGINT", "SIGTERM"]) process.on(signal, async () => { await provider.close(); process.exit(0) })
}
