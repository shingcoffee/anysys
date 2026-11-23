# Flowchart Code Generators — Gem-Backed Runtime Refactor (Slice A)

**Date:** 2026-08-03  
**Status:** Approved — implementation plan written  
**Scope:** Protocol / I/O + crypto + archive process step generators  
**Approach:** Phased batches (Approach 2) sharing one runtime-service architecture

---

## 1. Context

The flowchart builder drives ~117 code generators under `app/services/code_generators/element_types/` (104 process step actions). Mechanical UI/config audits currently report zero defects (`scripts/audit_generators.rb`, `scripts/audit_step_action_config.rb`), but many generators still **emit hand-rolled protocol/crypto plumbing** (`Net::HTTP`, multi-line `OpenSSL::Cipher`, optional `defined?(Zip)` guards) even though the app already prefers mature gems behind thin services (e.g. Faraday via `OutboundHttp`).

This slice replaces those hand-rolls for the highest-risk generators. Later slices (barcode/QR/templates/model ops/etc.) are out of scope here.

### Decisions already locked

| Decision | Choice |
|----------|--------|
| First slice | A — HTTP / JWT / cipher / archive |
| Emission style | Thin app wrappers at runtime; stdlib OK for CSV / Base64 / plain Digest |
| Compatibility | Breaking OK if activities are regenerated |
| Delivery | Phased batches, same end-state architecture |

---

## 2. Goals

1. Generated step bodies call thin app services — never `Net::HTTP`, never multi-line OpenSSL cipher choreography, never `defined?(Gem)` fail-open for required deps.
2. Prefer mature Ruby/Rails gems (Faraday, jwt, rubyzip) wrapped once; swap without editing every generator.
3. Fix known generator bugs uncovered while rewriting (SSL-verify-none paths, config-into-source injection on PBKDF2 salts, Net::HTTP redirect loops, optional-zip no-ops).
4. Keep Railway step semantics (truthy success / failure + existing retry/timeout/guard wrappers).
5. After each batch: generator specs green, wrapper specs green, audit scripts at 0 defects (or intentional baseline update).

### Non-goals

- Barcode / QR / template / geolocation product redesign beyond routing their HTTP through `OutboundHttp` when they still inline `Net::HTTP`.
- Replacing CSV / Base64 / Digest with gems.
- Changing Trailblazer topology of non-slice-A elements.
- Property-editor visual redesign (except config key add/remove/rename required by breaks).

---

## 3. Architecture

```
Flowchart step config
        │
        ▼
CodeGenerators::*Generator#generate_body   (emits short Ruby)
        │
        ▼
Generated Trailblazer step body
        │
        ├── OutboundHttp.request(...)              # Faraday
        ├── FlowchartRuntime::Jwt.encode/decode    # jwt gem
        ├── FlowchartRuntime::Cipher.encrypt/decrypt
        └── FlowchartRuntime::Archive.compress/decompress  # rubyzip (+ Zlib behind same façade)
```

### New / extended runtime services

| Service | Backing | Responsibility |
|---------|---------|----------------|
| `OutboundHttp` (existing) | Faraday | All outbound HTTP from generated activities; timeouts; `TransportError` |
| `FlowchartRuntime::Jwt` | `jwt` gem (direct Gemfile dep) | Encode/decode with algorithm allow-list; single `Error` type |
| `FlowchartRuntime::Cipher` | `ActiveSupport::MessageEncryptor` and/or tightly wrapped OpenSSL | Encrypt/decrypt, IV/auth-tag packaging, encoding; key resolution helpers |
| `FlowchartRuntime::Archive` | `rubyzip` (direct Gemfile dep) + stdlib `Zlib` | compress/decompress for `zip` / `gzip` / `tar_gz` |

Generators and `Shared::HttpRequestBuilder` emit calls to these services only.

---

## 4. Batches

### Batch 1 — HTTP

**Touch:** `Shared::HttpRequestBuilder`, `api_call`, `send_webhook`, `notify`, `download_file`, plus any utility generators still inlining `Net::HTTP` that share the same builder patterns (`currency_convert`, `geolocation_lookup`, `ai_inference`).

**Emission shape:**

```ruby
response = OutboundHttp.request(
  :post, url,
  headers: { ... },
  body: payload, # or form: ...
  open_timeout: ...,
  read_timeout: ...
)
ctx[:result] = JSON.parse(response.body, symbolize_names: true) # when format=json
response.success?
```

**Breaks:**

- Remove insecure `verifySsl: false` → `OpenSSL::SSL::VERIFY_NONE` path (drop knob or map only to a still-verifying Faraday SSL option; default remains verify-on).
- Success checks move from `response.is_a?(Net::HTTPSuccess)` to `response.success?`.
- Redirect following: Faraday middleware or small `OutboundHttp` helper; no hand-rolled redirect loops in generators.
- Webhook HMAC remains OpenSSL HMAC (stdlib, appropriate); POST uses `OutboundHttp`.

### Batch 2 — JWT / token auth

**Touch:** `generate_token`, `verify_token`, `authenticate` (JWT paths).

**Emission:** `FlowchartRuntime::Jwt.encode` / `.decode`; rescue `FlowchartRuntime::Jwt::Error`.

**Breaks:** algorithm / claim option surface trimmed to wrapper allow-list; specs updated to assert wrapper calls.

### Batch 3 — Cipher

**Touch:** `encrypt_data`, `decrypt_data`; simplify `hash_data` only where it incorrectly reimplements encoding that belongs in a helper (plain Digest hashes stay stdlib).

**Emission:** `FlowchartRuntime::Cipher.encrypt/decrypt`.

**Breaks:** algorithm enum trimmed to what the wrapper supports; key/encoding config simplified; PBKDF2 / salt handling moves into the wrapper so config values are never interpolated unsafely into generated source.

### Batch 4 — Archive

**Touch:** `compress_files`, `decompress_files`.

**Emission:** `FlowchartRuntime::Archive.compress/decompress` with format enum `zip|gzip|tar_gz`.

**Breaks:** drop `defined?(Zip)` / `defined?(Zlib)` fail-open branches; passworded zip only if rubyzip supports it cleanly — otherwise remove password UI/config rather than keep optional guards. `rubyzip` becomes a direct Gemfile dependency.

---

## 5. Config & I/O conventions

- Prefer keeping `resultVar` / `sourceVariable` / `targetVariable` names when already established.
- When a batch's audit shows a dead, colliding, or reserved key (`retryCount`, `retryBackoff`, `timeout`, `guardCondition`), rename/remove and update property-editor schema + `en` / `zh-CN` locales together.
- Update `docs/superpowers/specs/2026-04-19-generator-ui-audit-data.yml` / baselines only when an intentional schema change requires it; audits must exit 0 after each batch.

---

## 6. Error handling

- HTTP: rescue `OutboundHttp::TransportError` into the existing step failure path (`ctx[:_last_error]` / railway failure).
- JWT / Cipher / Archive: one namespaced error class each; generated bodies rescue that type only.
- Railway wrappers on `BaseGenerator` (retry / timeout / guard) remain unchanged.

---

## 7. Regeneration ops

`Flowchart` already regenerates stored activity Ruby on save (`before_save :generate_activity` → `ActivityGenerator`).

After deploy of any batch:

1. Any flowchart using touched step actions must be **saved** (or draft → edit → re-launch) so the `activity` column picks up new bodies.
2. Optional follow-up: a rake task to regenerate all launched flowcharts' activities (belt-and-suspenders). Include in the implementation plan if cheap; not a blocker for batch 1.

Document this in the release notes / plan checklist. No DB migration of activity text is required if ops regenerate via save.

---

## 8. Testing strategy

| Layer | What |
|-------|------|
| Wrapper unit specs | Success, transport/timeout, bad input for each new/extended service |
| Generator specs | Assert emitted wrapper / `OutboundHttp` calls; forbid `Net::HTTP`, raw cipher soups, `defined?(Zip)` |
| Shared examples | `code_generator_interface` stays green |
| Audits | `bundle exec rake audit:generators` and `bundle exec ruby scripts/audit_step_action_config.rb` → 0 defects |
| HTTP stubbing | WebMock (already used with Faraday) |
| Suite scope | Per batch: touched generator + wrapper specs; after batch 4: broader smoke / full suite as needed |

---

## 9. Gemfile changes

| Gem | Action |
|-----|--------|
| `faraday` | Already present; keep using via `OutboundHttp` |
| `jwt` | Add as **direct** dependency (currently transitive via Twilio) |
| `rubyzip` | Add as **direct** dependency |
| lockbox | **Not required** if `FlowchartRuntime::Cipher` uses `ActiveSupport::MessageEncryptor` / controlled OpenSSL wrap; revisit only if MessageEncryptor cannot cover the retained algorithm enum |

---

## 10. Success criteria

1. Slice-A generators emit zero `Net::HTTP` and zero multi-line `OpenSSL::Cipher` bodies.
2. No `defined?(Zip)` / `defined?(Zlib)`-style optional guards remain in batch-4 archive generators for required deps.
3. New runtime wrappers are the only place Faraday / JWT / zip details live for flowchart steps.
4. All touched specs pass; audits at 0 defects.
5. Regenerating a flowchart that uses these steps produces activities that call the wrappers.

---

## 11. Follow-up slices (explicitly deferred)

- Utility: barcode (Barby), QR (`rqrcode` already in Gemfile), template render, currency/geo product options beyond HTTP routing.
- File: generate/parse CSV/file (stdlib CSV stays).
- Security: sanitize/mask/authorize polish unrelated to cipher/JWT.
- Remaining process categories and non-process elements (decision, saga, etc.) unless they share HTTP/crypto helpers.

---

## 12. Implementation next step

After user approval of this written spec, invoke `writing-plans` to produce a batch-by-batch implementation plan under `docs/superpowers/plans/` (or project plan convention), then execute Batch 1 first.
