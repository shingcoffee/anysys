import { test } from "node:test"
import assert from "node:assert/strict"
import { existsSync } from "node:fs"
import { execFileSync } from "node:child_process"
import { createHash } from "node:crypto"
import { providerBackend, providerSchemas, TRANSCRIPT } from "./provider_backend.js"
import { isolatedEnvironment, verifyDatabaseConfiguration, PROJECT_ROOT } from "./rails_runner.js"

let schemas
const actualSchemas = () => schemas ||= providerSchemas()

// Exercise the very validator used before HTTP/SSE serialization, with the
// resolved operation schema. JSONSchemer owns $refs, conditions and union semantics.
function validate(document, contract) {
  const output = execFileSync("bundle", ["exec", "ruby", "-e", `
    require_relative "spec/e2e/support/provider_server"
    input = JSON.parse($stdin.read)
    begin
      BrowserProviderFixture.validate_completion!(input.fetch("document"), schema: input.fetch("schema"))
      puts({ valid: true }.to_json)
    rescue BrowserProviderFixture::InvalidCompletion => error
      puts({ valid: false, error: error.message }.to_json)
    end
  `], { cwd: PROJECT_ROOT, encoding: "utf8", input: JSON.stringify({ schema: actualSchemas()[contract], document }) })
  return JSON.parse(output)
}

function toolCall(completion) {
  return completion.choices[0].message.tool_calls[0]
}

function parseArguments(completion) {
  return JSON.parse(toolCall(completion).function.arguments)
}

test("database guard rejects missing paths, shared databases and mismatched inherited URLs", () => {
  for (const env of [{}, { E2E_DATABASE_PATH: "storage/development.sqlite3" },
    { E2E_DATABASE_PATH: "storage/browser-test.sqlite3", DATABASE_URL: "sqlite3:storage/test.sqlite3" },
    { E2E_DATABASE_PATH: "storage/browser-test.sqlite3", RAILS_ENV: "production" },
    { E2E_DATABASE_PATH: "storage/browser-test.sqlite3", E2E_STUB_ASSISTANT: "1" }]) {
    assert.throws(() => isolatedEnvironment(env))
  }
})

test("Rails database configuration can be read without creating a database", () => {
  const env = isolatedEnvironment({ ...process.env, DATABASE_URL: "", RAILS_ENV: "development",
    // This configuration-only probe deliberately names a nonexistent file.
    // A daemon-specific RUBYOPT preload may require the existing final DB.
    RUBYOPT: "", E2E_DATABASE_PATH: `storage/e2e-readonly-probe-${process.pid}.sqlite3` })
  assert.equal(existsSync(env.E2E_DATABASE_PATH), false)
  assert.equal(verifyDatabaseConfiguration(env).trim(), `E2E_DATABASE=${env.E2E_DATABASE_PATH} environment=development`)
  assert.equal(existsSync(env.E2E_DATABASE_PATH), false)
})

test("local provider speaks OpenAI tool_calls, streaming, and multipart transcription", async t => {
  const { url: base, close } = await providerBackend(0, actualSchemas())
  t.after(close)
  const headers = { Authorization: "Bearer e2e-local-dummy-key", "Content-Type": "application/json" }
  const messages = [{ role: "user", content: "Create a PwC12345 entity with a title field." }]
  const post = (payload, authorization = headers) => fetch(`${base}/v1/chat/completions`, { method: "POST", headers: authorization, body: JSON.stringify(payload) })
  assert.equal((await post({ messages }, {})).status, 403)
  assert.equal((await post({ messages }, { ...headers, Authorization: "Bearer live-key-rejected" })).status, 403)
  assert.equal((await fetch(`${base}/v1/unrecognized`, { method: "POST", headers })).status, 404)

  const createReply = await (await post({ messages, model: "gpt-4o-mini" })).json()
  assert.equal(createReply.choices[0].finish_reason, "tool_calls")
  assert.equal(createReply.choices[0].message.content, null)
  const createCall = toolCall(createReply)
  assert.equal(createCall.type, "function")
  assert.equal(createCall.function.name, "create_entity")
  const createArgs = parseArguments(createReply)
  assert.equal(createArgs.entities[0].name, "PwC12345")
  assert.equal(createArgs.entities[0].attributes[0].name, "Title")
  assert.deepEqual(validate(createArgs, "create_entity"), { valid: true })

  const afterCreate = await (await post({
    messages: [
      ...messages,
      createReply.choices[0].message,
      { role: "tool", tool_call_id: createCall.id, content: JSON.stringify({ ok: true, status: "succeeded" }) }
    ],
    model: "gpt-4o-mini"
  })).json()
  const createdDocument = JSON.parse(afterCreate.choices[0].message.content)
  assert.equal(createdDocument.intent, "chat")
  assert.equal(createdDocument.reply, "Creating PwC12345 with a Title field.")

  const notesMessages = [...messages, { role: "user", content: "Add a notes field to PwC12345" }]
  const notesReply = await (await post({ messages: notesMessages, model: "gpt-4o-mini" })).json()
  assert.equal(notesReply.choices[0].finish_reason, "tool_calls")
  const notesCall = toolCall(notesReply)
  assert.equal(notesCall.function.name, "update_entity")
  const notesArgs = parseArguments(notesReply)
  assert.equal(notesArgs.updates[0].entity, "PwC12345")
  assert.equal(notesArgs.updates[0].changes[0].op, "add_attribute")
  assert.deepEqual(validate(notesArgs, "update_entity"), { valid: true })

  const afterNotes = await (await post({
    messages: [
      ...notesMessages,
      notesReply.choices[0].message,
      { role: "tool", tool_call_id: notesCall.id, content: JSON.stringify({ ok: true, status: "confirmation_required" }) }
    ],
    model: "gpt-4o-mini"
  })).json()
  const review = JSON.parse(afterNotes.choices[0].message.content)
  assert.equal(review.intent, "chat")
  assert.match(review.reply, /I can add Notes to PwC12345/)
  assert.match(review.reply, /Proceed\?/)

  const stream = await (await post({ messages, stream: true })).text()
  assert.match(stream, /create_entity/)
  assert.match(stream, /"finish_reason":"tool_calls"/)
  assert.match(stream, /data: \[DONE\]/)

  const flowchart = await (await post({ messages: [
    { role: "developer", content: "Flowchart output contract: apply_flowchart" }, ...messages
  ] })).json()
  const flowchartDocument = JSON.parse(flowchart.choices[0].message.content)
  assert.equal(flowchartDocument.intent, "chat")
  assert.equal(flowchartDocument.flowchart, null)
  assert.deepEqual(validate(flowchartDocument, "flowchart"), { valid: true })

  const audio = new FormData()
  audio.set("model", "whisper-1")
  audio.set("file", new Blob([new Uint8Array(44 + 32000)], { type: "audio/wav" }), "fixture.wav")
  const transcript = await fetch(`${base}/v1/audio/transcriptions`, { method: "POST", headers: { Authorization: headers.Authorization }, body: audio })
  assert.deepEqual(await transcript.json(), { text: TRANSCRIPT })
  const health = await fetch(`${base}/health`)
  assert.equal(health.status, 200)
  const { requests } = await health.json()
  assert.equal(requests.length, 7)
  assert.equal(requests[6].audioBytes, 32044)
  assert.equal(requests[6].audioSha256, createHash("sha256").update(new Uint8Array(32044)).digest("hex"))
  assert.equal(requests.some(entry => "authorization" in entry || "messages" in entry), false)
})

test("fixture validation rejects malformed operation arguments and keeps the flowchart contract", () => {
  const create = { domain: "Academics", entities: [{ name: "PwCSchemaProbe", attributes: [{ name: "Title", html_type: "text" }] }] }
  assert.deepEqual(validate(create, "create_entity"), { valid: true })
  assert.equal(validate({ entities: [{ name: "X", extra: true }] }, "create_entity").valid, false)
  assert.equal(validate({
    entities: [{ name: "X", attributes: [{ name: "Level", html_type: "select" }] }]
  }, "create_entity").valid, false)
  const update = {
    updates: [{
      entity: "PwCSchemaProbe",
      changes: [{ op: "add_attribute", attribute: { name: "Notes", html_type: "textarea" } }]
    }]
  }
  assert.deepEqual(validate(update, "update_entity"), { valid: true })
  assert.equal(validate({ updates: [{ entity: "X", changes: [{ op: "not_an_op" }] }] }, "update_entity").valid, false)
  assert.deepEqual(validate({ intent: "chat", reply: "No changes.", flowchart: null, updates_confirmed: false }, "flowchart"), { valid: true })
})
