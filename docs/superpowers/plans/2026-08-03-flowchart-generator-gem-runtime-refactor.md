# Flowchart Generator Gem-Runtime Refactor (Slice A) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **Commits:** Project rule is do not auto-commit. Perform each "Commit" step only when the human explicitly asks to commit; otherwise stop after tests pass and report.

**Goal:** Replace hand-rolled `Net::HTTP` / OpenSSL-cipher / optional-zip emission in slice-A flowchart code generators with thin runtime wrappers over Faraday (`OutboundHttp`), `jwt`, and `rubyzip`, delivered in four regeneratable batches.

**Architecture:** Generators emit short Ruby that calls app services. `OutboundHttp` (Faraday) owns all outbound HTTP. New `FlowchartRuntime::Jwt`, `FlowchartRuntime::Cipher`, and `FlowchartRuntime::Archive` own JWT, encrypt/decrypt, and zip/gzip. Activities regenerate on `Flowchart` save.

**Tech Stack:** Rails 8.1.2, Faraday (`OutboundHttp`), `jwt` gem, `rubyzip`, `ActiveSupport::MessageEncryptor` (cipher), RSpec + WebMock, Trailblazer Railway activities.

**Spec:** `docs/superpowers/specs/2026-08-03-flowchart-generator-gem-runtime-refactor-design.md`

## Global Constraints

- Emission style: thin app wrappers at runtime; stdlib OK for CSV / Base64 / plain Digest.
- Breaking config/emission OK; flowcharts must be saved to regenerate `activity`.
- Never emit `Net::HTTP`, multi-line `OpenSSL::Cipher` soups, or `defined?(Zip)` fail-open for required deps.
- Drop insecure `verifySsl: false` → `VERIFY_NONE` paths (remove UI/schema knobs).
- I18n: any new/changed property-editor labels need `en` + `zh-CN`.
- After each batch: touched specs green; `bundle exec rake audit:generators` and `bundle exec ruby scripts/audit_step_action_config.rb` exit 0.
- Do not auto-commit unless the human asks.

## File map

| Path | Role |
|------|------|
| `app/services/outbound_http.rb` | Extend with `follow_redirects:` (and keep TLS verify-on) |
| `app/services/code_generators/shared/http_request_builder.rb` | Emit `OutboundHttp` + headers Hash (not Net::HTTP request objects) |
| `app/services/code_generators/element_types/process/communication/api_call_generator.rb` | Batch 1 |
| `app/services/code_generators/element_types/process/communication/send_webhook_generator.rb` | Batch 1 |
| `app/services/code_generators/element_types/process/communication/notify_generator.rb` | Batch 1 |
| `app/services/code_generators/element_types/process/file_operations/download_file_generator.rb` | Batch 1 (replace open-uri) |
| `app/services/code_generators/element_types/process/utility/{currency_convert,geolocation_lookup,ai_inference}_generator.rb` | Batch 1 HTTP only |
| `spec/support/config_schemas.rb` | Drop `verifySsl` UI fields for api_call / download_file |
| `config/locales/flowchart_actions.{en,zh-CN}.yml` | Remove/adjust verifySsl copy if present |
| `Gemfile` | Direct `jwt`, `rubyzip` |
| `app/services/flowchart_runtime/jwt.rb` | Batch 2 |
| `app/services/flowchart_runtime/cipher.rb` | Batch 3 |
| `app/services/flowchart_runtime/archive.rb` | Batch 4 |
| Matching `spec/services/**` | TDD counterparts |
| Optional `lib/tasks/flowchart_regenerate_activities.rake` | Post-deploy regenerate helper |

---

### Task 1: Extend OutboundHttp with follow_redirects

**Files:**
- Modify: `app/services/outbound_http.rb`
- Modify: `spec/services/outbound_http_spec.rb`

**Interfaces:**
- Consumes: existing `OutboundHttp.request(method, url, headers:, body:, form:, open_timeout:, read_timeout:)`
- Produces: `OutboundHttp.request(..., follow_redirects: false, max_redirects: 5)` — when `follow_redirects: true`, follows 3xx `Location` up to `max_redirects`, returns final response; never disables TLS verification

- [ ] **Step 1: Write the failing tests**

Append to `spec/services/outbound_http_spec.rb`:

```ruby
it "follows redirects when follow_redirects: true" do
  stub_request(:get, "https://api.example.com/old")
    .to_return(status: 302, headers: { "Location" => "https://api.example.com/new" }, body: "")
  stub_request(:get, "https://api.example.com/new")
    .to_return(status: 200, body: "ok")

  res = described_class.request(:get, "https://api.example.com/old", follow_redirects: true)

  expect(res.status).to eq(200)
  expect(res.body).to eq("ok")
end

it "does not follow redirects by default" do
  stub_request(:get, "https://api.example.com/old")
    .to_return(status: 302, headers: { "Location" => "https://api.example.com/new" }, body: "")

  res = described_class.request(:get, "https://api.example.com/old")

  expect(res).to be_redirect
  expect(res.status).to eq(302)
end

it "stops after max_redirects and returns the last redirect response" do
  stub_request(:get, "https://api.example.com/a")
    .to_return(status: 302, headers: { "Location" => "https://api.example.com/b" }, body: "")
  stub_request(:get, "https://api.example.com/b")
    .to_return(status: 302, headers: { "Location" => "https://api.example.com/c" }, body: "")

  res = described_class.request(:get, "https://api.example.com/a", follow_redirects: true, max_redirects: 1)

  expect(res.status).to eq(302)
  expect(res.headers["location"] || res.headers["Location"]).to include("api.example.com/c").or include("api.example.com/b")
end
```

(Adjust the last expectation to match the implementation’s “last response after N hops” semantics — document the chosen semantics in the method comment: after exhausting hops, return the redirect response that was not followed.)

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec rspec spec/services/outbound_http_spec.rb -e "follow_redirects" --format documentation`

Expected: FAIL (unknown keyword `follow_redirects` or examples fail)

- [ ] **Step 3: Implement follow_redirects on OutboundHttp**

In `app/services/outbound_http.rb`, extend `.request`:

```ruby
def request(method, url, headers: {}, body: nil, form: nil,
            open_timeout: DEFAULT_OPEN_TIMEOUT, read_timeout: DEFAULT_READ_TIMEOUT,
            follow_redirects: false, max_redirects: 5)
  remaining = follow_redirects ? Integer(max_redirects) : 0
  current_method = method.to_s.downcase.to_sym
  current_url = url
  current_body = encode_body(body, form)
  current_headers = request_headers(headers, form)
  response = nil

  loop do
    response = connection(open_timeout:, read_timeout:).run_request(
      current_method, current_url, current_body, current_headers
    )
    break unless follow_redirects && remaining.positive? && (300..399).cover?(response.status)

    location = response.headers["location"] || response.headers["Location"]
    break if location.blank?

    current_url = AbsoluteUrl.join(current_url, location) # or URI.join
    current_method = :get
    current_body = nil
    remaining -= 1
  end

  Response.new(status: response.status, headers: response.headers.to_h, body: response.body.to_s)
rescue Faraday::TimeoutError, Faraday::ConnectionFailed, Faraday::SSLError => e
  raise TransportError, e.message
end
```

Prefer a tiny private `redirect_location(base_url, location)` using `URI.join` — do not add a new public class unless needed. Keep TLS verification on (Faraday default). Do **not** add a `verify_ssl: false` option.

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec rspec spec/services/outbound_http_spec.rb --format documentation`

Expected: PASS

- [ ] **Step 5: Commit (only if human asked)**

```bash
git add app/services/outbound_http.rb spec/services/outbound_http_spec.rb
git commit -m "$(cat <<'EOF'
feat(http): support follow_redirects on OutboundHttp

EOF
)"
```

---

### Task 2: Rewrite Shared::HttpRequestBuilder to emit OutboundHttp

**Files:**
- Modify: `app/services/code_generators/shared/http_request_builder.rb`
- Modify: `spec/services/code_generators/shared/http_request_builder_spec.rb`

**Interfaces:**
- Consumes: Task 1 `OutboundHttp.request`
- Produces: `build_http_request(...)` and `build_headers_hash_code(...)` emitting Ruby that builds `_headers = {}` and calls `OutboundHttp.request`; `build_headers_code` may remain as a deprecated alias that builds hash assignments if still referenced — prefer migrating callers to hash builder

- [ ] **Step 1: Rewrite failing expectations**

Replace Net::HTTP expectations in `spec/services/code_generators/shared/http_request_builder_spec.rb`:

```ruby
it "generates GET request code via OutboundHttp" do
  code = http_request(response_var: "api_response")
  expect(code).to include("OutboundHttp.request")
  expect(code).to include(":get")
  expect(code).to include("ctx[:api_response]")
  expect(code).to include("JSON.parse")
  expect(code).not_to include("Net::HTTP")
end

it "generates POST request code via OutboundHttp" do
  code = http_request(method: "POST", response_var: "result", body_expr: '{ key: "value" }')
  expect(code).to include("OutboundHttp.request")
  expect(code).to include(":post")
  expect(code).to include("body:")
  expect(code).not_to include("Net::HTTP")
end

it "includes bearer auth header on the headers hash" do
  code = http_request(response_var: "r", auth_type: "bearer", auth_config: { "authToken" => "ctx[:token]" })
  expect(code).to include("Authorization")
  expect(code).to include("Bearer")
end

it "includes custom headers on the headers hash" do
  code = http_request(response_var: "r", headers: [{ "key" => "X-Custom", "value" => "test" }])
  expect(code).to include('_headers["X-Custom"] = "test"').or include("_headers[\"X-Custom\"]")
end
```

Update `#build_headers_code` examples to expect `_headers[...] =` assignments (or rename method to `build_headers_hash_lines` and update examples accordingly). Keep CRLF / quote-escaping examples — they must still pass.

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec rspec spec/services/code_generators/shared/http_request_builder_spec.rb --format documentation`

Expected: FAIL against old Net::HTTP emission

- [ ] **Step 3: Implement OutboundHttp emission**

Replace private builders in `http_request_builder.rb` with emission like:

```ruby
def build_get_request_code(url_expr, headers, auth_type, auth_config, response_var)
  header_lines = build_headers_hash_lines(headers, auth_type, auth_config)
  [
    "_headers = {}",
    *header_lines,
    "response = OutboundHttp.request(:get, #{url_expr}, headers: _headers)",
    "ctx[:#{response_var}] = JSON.parse(response.body, symbolize_names: true)",
    "response.success?"
  ].join("\n")
end

def build_mutating_request_code(method, url_expr, headers, auth_type, auth_config, body_expr, response_var)
  header_lines = build_headers_hash_lines(headers, auth_type, auth_config)
  body = body_expr || "{}"
  verb = method.to_s.downcase
  [
    "_headers = {}",
    '_headers["Content-Type"] = "application/json"',
    *header_lines,
    "response = OutboundHttp.request(:#{verb}, #{url_expr}, headers: _headers, body: #{body})",
    "ctx[:#{response_var}] = JSON.parse(response.body, symbolize_names: true)",
    "response.success?"
  ].join("\n")
end
```

For basic auth, emit an Authorization Basic header (Base64) into `_headers` — do not call `request.basic_auth`. Preserve control-char stripping via `strip_control_chars` / `safe_string_literal`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec rspec spec/services/code_generators/shared/http_request_builder_spec.rb --format documentation`

Expected: PASS

- [ ] **Step 5: Commit (only if human asked)**

```bash
git add app/services/code_generators/shared/http_request_builder.rb spec/services/code_generators/shared/http_request_builder_spec.rb
git commit -m "$(cat <<'EOF'
refactor(generators): emit OutboundHttp from HttpRequestBuilder

EOF
)"
```

---

### Task 3: Migrate ApiCallGenerator off Net::HTTP; drop verifySsl

**Files:**
- Modify: `app/services/code_generators/element_types/process/communication/api_call_generator.rb`
- Modify: `spec/services/code_generators/element_types/process/communication/api_call_generator_spec.rb`
- Modify: `spec/support/config_schemas.rb` (remove `verifySsl` field from `"API_call"` / `"api_call"` entries)
- Modify: `config/locales/flowchart_actions.en.yml` and `.zh-CN.yml` if they key `verifySsl` for this action

**Interfaces:**
- Consumes: Task 1–2 (`OutboundHttp`, headers hash emission)
- Produces: `generate_body` emitting `OutboundHttp.request` with `follow_redirects:` from config; no `verifySsl` field in `config_schema`

- [ ] **Step 1: Update specs to the new contract**

In `api_call_generator_spec.rb`:

- Change Net::HTTP examples to expect `OutboundHttp.request` and `:get` / `:post`.
- Delete or rewrite the `verifySsl` describe block: expect **no** `VERIFY_NONE` and **no** `verifySsl` schema acceptance (validation should ignore or reject unknown — prefer remove field so unknown values are simply unused; remove the “rejects unknown verifySsl” example or change to “does not emit VERIFY_NONE for any config”).
- Rewrite `followRedirects` examples to expect `follow_redirects: true/false` in the emitted `OutboundHttp.request` call, not `Net::HTTPRedirection`.

Example:

```ruby
it "emits OutboundHttp GET" do
  expect(body("url" => '"https://api.example.com"', "httpMethod" => "GET"))
    .to include("OutboundHttp.request(:get")
  expect(body("url" => '"https://api.example.com"', "httpMethod" => "GET"))
    .not_to include("Net::HTTP")
end

it "passes follow_redirects: true by default" do
  expect(body).to include("follow_redirects: true")
end

it "passes follow_redirects: false when configured" do
  expect(body("followRedirects" => "false")).to include("follow_redirects: false")
end

it "never emits VERIFY_NONE" do
  expect(body("verifySsl" => "false")).not_to include("VERIFY_NONE")
end
```

- [ ] **Step 2: Run specs — expect FAIL**

Run: `bundle exec rspec spec/services/code_generators/element_types/process/communication/api_call_generator_spec.rb --format documentation`

Expected: FAIL

- [ ] **Step 3: Rewrite ApiCallGenerator#generate_body**

- Remove `field :verifySsl` from `config_schema`.
- Replace Net::HTTP construction / redirect loop with a single `OutboundHttp.request` emission (method, URL expression, headers hash, body/form by `bodyFormat`, `open_timeout`/`read_timeout` from timeout support, `follow_redirects:` from `followRedirects`).
- Success line: `response.success?`.
- Keep responseFormat parsing (`json`/`text`/`binary`) against `response.body`.
- Keep status-retry wrapper behavior but base retries on `response.success?` / status code from `response.status`.

- [ ] **Step 4: Sync UI schema + locales**

In `spec/support/config_schemas.rb`, remove the `verifySsl` select from API_call. Grep locales for `verifySsl` under api_call and remove matching keys in both `en` and `zh-CN`.

- [ ] **Step 5: Run specs + audits**

```bash
bundle exec rspec spec/services/code_generators/element_types/process/communication/api_call_generator_spec.rb
bundle exec rake audit:generators
bundle exec ruby scripts/audit_step_action_config.rb
```

Expected: all PASS / 0 defects

- [ ] **Step 6: Commit (only if human asked)**

```bash
git add app/services/code_generators/element_types/process/communication/api_call_generator.rb \
  spec/services/code_generators/element_types/process/communication/api_call_generator_spec.rb \
  spec/support/config_schemas.rb config/locales/flowchart_actions.en.yml config/locales/flowchart_actions.zh-CN.yml
git commit -m "$(cat <<'EOF'
refactor(generators): api_call uses OutboundHttp; drop verifySsl

EOF
)"
```

---

### Task 4: Migrate send_webhook + notify generators

**Files:**
- Modify: `app/services/code_generators/element_types/process/communication/send_webhook_generator.rb`
- Modify: `app/services/code_generators/element_types/process/communication/notify_generator.rb`
- Modify: matching specs under `spec/services/code_generators/element_types/process/communication/`

**Interfaces:**
- Consumes: Task 2 header/hash helpers and/or direct `OutboundHttp.request` emission
- Produces: webhook/notify bodies with HMAC header still via OpenSSL HMAC (stdlib) into `_headers`, POST via `OutboundHttp`

- [ ] **Step 1: Update specs**

Replace `Net::HTTP::Post` expectations with `OutboundHttp.request(:post`. Keep HMAC signature expectations (`OpenSSL::HMAC`).

- [ ] **Step 2: Run — expect FAIL**

```bash
bundle exec rspec \
  spec/services/code_generators/element_types/process/communication/send_webhook_generator_spec.rb \
  spec/services/code_generators/element_types/process/communication/notify_generator_spec.rb
```

- [ ] **Step 3: Implement**

Rewrite POST assembly to:

```ruby
_headers = {}
_headers["Content-Type"] = "application/json"
# ... auth/custom headers ...
# optional: _headers["X-Signature"] = ... OpenSSL::HMAC ...
response = OutboundHttp.request(:post, url, headers: _headers, body: payload_json)
ctx[:result] = JSON.parse(response.body, symbolize_names: true) rescue response.body.to_s
response.success?
```

Preserve notify channels that are non-HTTP (email/etc.) unchanged; only HTTP branches move.

- [ ] **Step 4: Run — expect PASS + audits**

Same rspec command + both audit scripts → 0 defects

- [ ] **Step 5: Commit (only if human asked)**

```bash
git commit -m "$(cat <<'EOF'
refactor(generators): webhook and notify POST via OutboundHttp

EOF
)"
```

---

### Task 5: Migrate download_file off open-uri; drop verifySsl

**Files:**
- Modify: `app/services/code_generators/element_types/process/file_operations/download_file_generator.rb`
- Modify: `spec/services/code_generators/element_types/process/file_operations/download_file_generator_spec.rb`
- Modify: `spec/support/config_schemas.rb` (remove download_file `verifySsl`)
- Locales if needed

**Interfaces:**
- Consumes: `OutboundHttp.request` with `follow_redirects:` / `max_redirects:`
- Produces: download body that stores `response.body` into ctx/tempfile/ActiveStorage/S3 branches; checksum via Digest stdlib unchanged

- [ ] **Step 1: Update specs**

- Expect `OutboundHttp.request` and `follow_redirects:`.
- Remove VERIFY_NONE examples; assert never emitted.
- Remove/adjust verifySsl validation examples.
- Keep checksum / destination / maxSizeBytes examples, updating only the fetch mechanism assertions.

- [ ] **Step 2: Run — FAIL**

```bash
bundle exec rspec spec/services/code_generators/element_types/process/file_operations/download_file_generator_spec.rb
```

- [ ] **Step 3: Implement**

Replace `require "open-uri"` emission with OutboundHttp. Example emission core:

```ruby
response = OutboundHttp.request(
  :get, url,
  headers: _headers,
  follow_redirects: true,
  max_redirects: 5,
  open_timeout: 5,
  read_timeout: 120
)
raise OutboundHttp::TransportError, "download failed" unless response.success?
_payload = response.body
# then existing max size / checksum / destination branching on _payload
```

Remove `ssl_verify_mode` / `verifySsl` / `sslVerify` handling. Keep `followRedirects` + `maxRedirects` mapped to OutboundHttp kwargs.

- [ ] **Step 4: PASS + audits**

- [ ] **Step 5: Commit (only if human asked)**

```bash
git commit -m "$(cat <<'EOF'
refactor(generators): download_file uses OutboundHttp; drop verifySsl

EOF
)"
```

---

### Task 6: Route utility Net::HTTP callers through OutboundHttp

**Files:**
- Modify: `app/services/code_generators/element_types/process/utility/currency_convert_generator.rb`
- Modify: `app/services/code_generators/element_types/process/utility/geolocation_lookup_generator.rb`
- Modify: `app/services/code_generators/element_types/process/utility/ai_inference_generator.rb`
- Modify: matching specs

**Interfaces:**
- Consumes: `OutboundHttp.request`
- Produces: no `Net::HTTP` in these three generators’ emission

- [ ] **Step 1: Update specs** to expect `OutboundHttp.request` instead of `Net::HTTP.get_response` / `Net::HTTP.post`

- [ ] **Step 2: Run — FAIL**

```bash
bundle exec rspec \
  spec/services/code_generators/element_types/process/utility/currency_convert_generator_spec.rb \
  spec/services/code_generators/element_types/process/utility/geolocation_lookup_generator_spec.rb \
  spec/services/code_generators/element_types/process/utility/ai_inference_generator_spec.rb
```

- [ ] **Step 3: Replace HTTP emission only** (keep rate math, provider URL construction, caching keys)

- [ ] **Step 4: PASS + audits; grep guard**

```bash
rg -n 'Net::HTTP' app/services/code_generators/element_types/process/communication \
  app/services/code_generators/element_types/process/file_operations/download_file_generator.rb \
  app/services/code_generators/element_types/process/utility/{currency_convert,geolocation_lookup,ai_inference}_generator.rb \
  app/services/code_generators/shared/http_request_builder.rb
```

Expected: no matches (HMAC OpenSSL in webhook is fine and lives outside this grep if needed — webhook must not contain `Net::HTTP`)

- [ ] **Step 5: Commit (only if human asked)** — message: `refactor(generators): utility HTTP steps use OutboundHttp`

---

### Task 7: Batch 2 — FlowchartRuntime::Jwt + token generators

**Files:**
- Create: `app/services/flowchart_runtime/jwt.rb`
- Create: `spec/services/flowchart_runtime/jwt_spec.rb`
- Modify: `Gemfile` (add `gem "jwt", "~> 3.2"`)
- Modify: `generate_token_generator.rb`, `verify_token_generator.rb`, `authenticate_generator.rb` (JWT paths only)
- Modify: matching specs

**Interfaces:**
- Consumes: `jwt` gem
- Produces:

```ruby
module FlowchartRuntime
  module Jwt
    class Error < StandardError; end
    ALLOWED_ALGS = %w[HS256 HS384 HS512 RS256].freeze

    module_function

    def encode(payload, secret, algorithm: "HS256", headers: {})
      raise Error, "unsupported algorithm" unless ALLOWED_ALGS.include?(algorithm.to_s)
      ::JWT.encode(payload, secret, algorithm.to_s, headers)
    rescue ::JWT::EncodeError => e
      raise Error, e.message
    end

    def decode(token, secret, algorithms: ["HS256"], verify: true, required_claims: [])
      algs = Array(algorithms).map(&:to_s)
      raise Error, "unsupported algorithm" unless algs.all? { |a| ALLOWED_ALGS.include?(a) }
      payload, = ::JWT.decode(token, secret, verify, { algorithms: algs, required_claims: Array(required_claims) })
      payload
    rescue ::JWT::DecodeError => e
      raise Error, e.message
    end
  end
end
```

- [ ] **Step 1:** `bundle add jwt --version '~> 3.2'` (or edit Gemfile + `bundle install`)
- [ ] **Step 2:** Write `jwt_spec.rb` (encode/decode round-trip, bad alg, tampered token → Error)
- [ ] **Step 3:** Implement `flowchart_runtime/jwt.rb`; run jwt_spec → PASS
- [ ] **Step 4:** Update generator specs to expect `FlowchartRuntime::Jwt.encode/decode` and `FlowchartRuntime::Jwt::Error` (not raw `JWT.decode` / `JWT::DecodeError`)
- [ ] **Step 5:** Rewrite JWT emission paths in the three generators
- [ ] **Step 6:** Run generator specs + audits → PASS
- [ ] **Step 7:** Commit (only if human asked) — `feat(flowchart): Jwt runtime wrapper for token step generators`

---

### Task 8: Batch 3 — FlowchartRuntime::Cipher + encrypt/decrypt generators

**Files:**
- Create: `app/services/flowchart_runtime/cipher.rb`
- Create: `spec/services/flowchart_runtime/cipher_spec.rb`
- Modify: `encrypt_data_generator.rb`, `decrypt_data_generator.rb`
- Modify: matching specs
- Optionally touch `hash_data_generator.rb` only if encoding helpers are duplicated incorrectly

**Interfaces:**
- Produces:

```ruby
module FlowchartRuntime
  module Cipher
    class Error < StandardError; end
    # Public:
    #   encrypt(plaintext, key:, purpose: :flowchart_data) -> String (Base64)
    #   decrypt(ciphertext, key:, purpose: :flowchart_data) -> String
    # Internals: ActiveSupport::MessageEncryptor with key length normalized to 32 bytes
    # (SHA-256 of provided key material). Do not interpolate config into source.
  end
end
```

Config break: trim generator algorithm enum to what the wrapper supports (document supported set as MessageEncryptor default aes-256-gcm). Key source resolution (credentials/env/ctx) stays in the **generator emission** as Ruby that computes `key = ...` then calls `FlowchartRuntime::Cipher.encrypt(plaintext, key: key)`. PBKDF2/salt must be computed in wrapper methods like `Cipher.key_from_passphrase(passphrase, salt:, iterations:)` — generators pass expressions for passphrase/salt, never paste raw config into OpenSSL source strings.

- [ ] **Step 1:** Failing cipher_spec (round-trip, bad key → Error, encoding stable)
- [ ] **Step 2:** Implement Cipher wrapper → PASS
- [ ] **Step 3:** Update encrypt/decrypt generator specs to forbid multi-line `OpenSSL::Cipher.new` emission; expect `FlowchartRuntime::Cipher`
- [ ] **Step 4:** Rewrite generators; simplify config_schema enums; sync `config_schemas.rb` + locales
- [ ] **Step 5:** Specs + audits → PASS
- [ ] **Step 6:** Commit (only if human asked) — `feat(flowchart): Cipher runtime wrapper for encrypt/decrypt steps`

---

### Task 9: Batch 4 — FlowchartRuntime::Archive + compress/decompress

**Files:**
- Create: `app/services/flowchart_runtime/archive.rb`
- Create: `spec/services/flowchart_runtime/archive_spec.rb`
- Modify: `Gemfile` (`gem "rubyzip", "~> 3.0"` or current Gemfile.lock-compatible version)
- Modify: `compress_files_generator.rb`, `decompress_files_generator.rb` + specs + UI schema/locales for password fields if dropped

**Interfaces:**

```ruby
module FlowchartRuntime
  module Archive
    class Error < StandardError; end
    FORMATS = %i[zip gzip tar_gz].freeze

    module_function

    # compress(entries, format: :zip) -> String binary
    #   entries: Array<{ name: String, content: String }>
    # decompress(payload, format: :zip) -> Array<{ name: String, content: String }>
    # Raises Error on unsupported format or corrupt payload.
  end
end
```

Passworded zip: if rubyzip traditional encryption is awkward/unreliable, **remove** password config from generators + UI rather than emit `defined?(Zip::TraditionalEncrypter)`.

- [ ] **Step 1:** `bundle add rubyzip` (direct dep)
- [ ] **Step 2:** archive_spec covering zip round-trip, gzip round-trip, corrupt payload → Error
- [ ] **Step 3:** Implement Archive → PASS
- [ ] **Step 4:** Update generator specs — forbid `defined?(Zip)` / `defined?(Zlib)`; expect `FlowchartRuntime::Archive`
- [ ] **Step 5:** Rewrite generators; drop password UI if unsupported; sync schemas/locales
- [ ] **Step 6:** Specs + audits → PASS
- [ ] **Step 7:** Commit (only if human asked) — `feat(flowchart): Archive runtime wrapper for compress/decompress steps`

---

### Task 10: Regeneration rake + final verification

**Files:**
- Create (optional but recommended): `lib/tasks/flowchart_regenerate_activities.rake`
- No production model changes required (`Flowchart#generate_activity` already on save)

- [ ] **Step 1: Add rake task**

```ruby
# lib/tasks/flowchart_regenerate_activities.rake
namespace :flowcharts do
  desc "Regenerate stored Trailblazer activity Ruby for all flowcharts (or CUSTOMER_ID=...)"
  task regenerate_activities: :environment do
    scope = Flowchart.all
    scope = scope.where(customer_id: ENV["CUSTOMER_ID"]) if ENV["CUSTOMER_ID"].present?
    scope.find_each do |flowchart|
      flowchart.generate_activity
      flowchart.update_column(:activity, flowchart.activity)
      puts "regenerated #{flowchart.id} #{flowchart.name}"
    end
  end
end
```

(Use a safe persistence path consistent with callbacks — if `update_column` skips needed callbacks, prefer `flowchart.save!` after assigning activity, or call the same private method `before_save` uses. Prefer `flowchart.save!` if it does not create version noise; otherwise `update_columns(activity: ActivityGenerator.new(flowchart).generate)`.)

- [ ] **Step 2: Final grep gates**

```bash
rg -n 'Net::HTTP' app/services/code_generators/shared/http_request_builder.rb \
  app/services/code_generators/element_types/process/communication \
  app/services/code_generators/element_types/process/file_operations/download_file_generator.rb \
  app/services/code_generators/element_types/process/utility/currency_convert_generator.rb \
  app/services/code_generators/element_types/process/utility/geolocation_lookup_generator.rb \
  app/services/code_generators/element_types/process/utility/ai_inference_generator.rb

rg -n 'OpenSSL::Cipher\.new|defined\?\(Zip\)|VERIFY_NONE' \
  app/services/code_generators/element_types/process/security \
  app/services/code_generators/element_types/process/file_operations/compress_files_generator.rb \
  app/services/code_generators/element_types/process/file_operations/decompress_files_generator.rb
```

Expected: no matches for the forbidden patterns in those paths (OpenSSL::HMAC for webhook signatures is allowed outside the Cipher grep).

- [ ] **Step 3: Run batch regression**

```bash
bundle exec rspec \
  spec/services/outbound_http_spec.rb \
  spec/services/flowchart_runtime/jwt_spec.rb \
  spec/services/flowchart_runtime/cipher_spec.rb \
  spec/services/flowchart_runtime/archive_spec.rb \
  spec/services/code_generators/shared/http_request_builder_spec.rb \
  spec/services/code_generators/element_types/process/communication \
  spec/services/code_generators/element_types/process/file_operations/download_file_generator_spec.rb \
  spec/services/code_generators/element_types/process/file_operations/compress_files_generator_spec.rb \
  spec/services/code_generators/element_types/process/file_operations/decompress_files_generator_spec.rb \
  spec/services/code_generators/element_types/process/security/encrypt_data_generator_spec.rb \
  spec/services/code_generators/element_types/process/security/decrypt_data_generator_spec.rb \
  spec/services/code_generators/element_types/process/security/generate_token_generator_spec.rb \
  spec/services/code_generators/element_types/process/security/verify_token_generator_spec.rb \
  spec/services/code_generators/element_types/process/security/authenticate_generator_spec.rb \
  spec/services/code_generators/element_types/process/utility/currency_convert_generator_spec.rb \
  spec/services/code_generators/element_types/process/utility/geolocation_lookup_generator_spec.rb \
  spec/services/code_generators/element_types/process/utility/ai_inference_generator_spec.rb

bundle exec rake audit:generators
bundle exec ruby scripts/audit_step_action_config.rb
```

Expected: all green / 0 defects

- [ ] **Step 4: Commit (only if human asked)** — `chore(flowcharts): regenerate-activities rake + slice A verification`

---

## Spec coverage self-review

| Spec section | Plan task |
|--------------|-----------|
| Batch 1 HTTP / OutboundHttp / drop VERIFY_NONE | Tasks 1–6 |
| Batch 2 JWT wrapper | Task 7 |
| Batch 3 Cipher wrapper | Task 8 |
| Batch 4 Archive / rubyzip direct / drop defined?(Zip) | Task 9 |
| Regeneration ops | Task 10 |
| Audits / testing strategy | Steps inside each task + Task 10 |
| Gemfile jwt + rubyzip | Tasks 7, 9 |
| Breaking regenerate-on-save | Documented in header + Task 10 |
| Deferred slices | Not planned (correct) |

## Placeholder / consistency check

- No placeholder markers left in tasks.
- `OutboundHttp.request(..., follow_redirects:, max_redirects:)` naming is consistent across Tasks 1, 3, 5.
- Runtime modules live under `FlowchartRuntime::` matching existing `ExpressionEvaluator`.
