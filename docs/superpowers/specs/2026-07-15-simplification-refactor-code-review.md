# Code Review — Simplification Refactor (2026-07-15)

High-effort, workflow-backed review of the uncommitted simplification refactor
(new shared abstractions: `PluginRegistry`, `VendorPlugin`, `CardTableComponent`,
shared base controllers; −6.8k lines, 251 changed files). 15 agents: 4 finders
(3 correctness angles + 1 cleanup), independent verifier per finding, synthesis.
10 candidates → 9 verified → 1 refuted → **8 reported, all 8 fixed in the
working tree** (uncommitted, pending owner review).

## Status

- [x] All 8 findings fixed (details below)
- [x] Targeted RSpec: 118 examples, 0 failures
  (`spec/requests/admin/maintenance/platform/{emails,sms}/credentials_spec.rb`,
  `.../module_settings_spec.rb`,
  `spec/components/billing/admin/subscriptions_table_component_spec.rb`,
  `spec/services/{sms,email}/activities/send_spec.rb`)
- [x] `npx vitest run --coverage spec/javascript/controllers/tabs_controller.test.js`
  → tabs_controller.js 100% lines/branches/functions
- [x] All four registries smoke-tested via `rails runner`
  (payments/sms/email/captcha keys all present)
- [ ] Owner reviews the working-tree diff and commits

## Findings (most severe first) — all FIXED

### 1. CORRECTNESS (confirmed) — `app/services/plugin_registry.rb:41`
`ensure_loaded!` set `@loaded = true` **before** constantizing vendor files, so
one failing plugin file left all four registries (payments, sms, email, captcha)
silently and permanently partial for the process — regressing the old
`@loaded ||= begin ... true end` retry-on-failure semantics of
`Payments::Gateways`. Symptoms: valid providers rejected by inclusion
validations, empty checkout gateway lists, `ArgumentError: unknown payment
gateway` for present vendors, no recovery until restart.
**Fix:** memoize only after the whole `Dir` loop succeeds; a raise leaves the
registry unmemoized so the next call retries.

### 2. Drift risk — `app/views/admin/maintenance/platform/module_settings/show.html.erb:101`
`settings_tab_has_content = @feature_module.key.in?(%w[sms email payment]) || schema.any?`
duplicated the knowledge already in the three per-module card blocks; a future
module card added without extending the list would render its card AND the
"no settings" empty state together.
**Fix:** all settings cards render inside a `capture`; the empty state shows
`if settings_cards.blank?` — new cards count as content automatically.

### 3. Hand-built URL — `app/controllers/admin/maintenance/platform/base_credentials_controller.rb:63`
`index_path` string-built
`"/#{current_customer.id}/admin/maintenance/platform/module_settings/#{url_segment}/credentials"`
bypassing named route helpers (route changes would silently redirect to 404).
**Fix:** `manages_credentials` now takes `index_route:` — a lambda run via
`instance_exec` in controller context (mirrors `BaseRestorationsController`'s
`redirect:` pattern); both subclasses pass the named helper
(`admin_maintenance_platform_module_settings_{sms,emails}_credentials_path(current_customer_id)`).
`url_segment` removed entirely.

### 4. Copy-paste columns — `sms/credentials_controller.rb:21` + `emails/credentials_controller.rb`
provider/mode/status/created_at column hashes were byte-identical in both
subclasses of the base that was created to remove exactly this duplication.
**Fix:** `provider_column` / `mode_column` / `status_column` /
`created_at_column` helpers on `BaseCredentialsController`; SMS uses all four
verbatim, email splices host/username/DKIM columns between them. The email
DKIM nested-ternary badge label became a `dkim_status_label` private method.

### 5. Duplicated tab classes — `module_settings/show.html.erb:106` + `app/javascript/controllers/tabs_controller.js`
Active/inactive tab class strings (`border-indigo-500 text-indigo-600` /
`border-transparent text-gray-500`) were hardcoded in BOTH the ERB and
`tabs_controller#show()`, and used raw palette classes instead of semantic
tokens.
**Fix:** controller now uses the Stimulus Classes API
(`static classes = ["active", "inactive"]`, read via
`this.activeClasses`/`this.inactiveClasses`); ERB is the single source via
`data-tabs-active-class="border-accent text-accent"` /
`data-tabs-inactive-class="border-transparent text-text-muted"` (semantic
tokens). The redundant server-rendered state classes were dropped from the
`<a>` tags (connect() applies them on load; this view is the controller's only
usage). Test updated; coverage 100%.

### 6. View logic in template — `app/components/billing/admin/subscriptions_table_component.html.erb:2`
The platform?-dependent header array was built by mutation in ERB, making the
column set untestable at the component-class level (AGENTS.md ViewComponent
encapsulation rule).
**Fix:** moved to `def headers` on `SubscriptionsTableComponent`; template
passes `headers: headers`.

### 7. Dead ivar — `base_credentials_controller.rb:31`
`#index` assigned both `@credentials` and `@rows` from `result[:rows]`; both
index views only read `@rows`.
**Fix:** dropped `@credentials`.

### 8. Misleading log — `app/services/feature_modules/daily_cap.rb:27` (PLAUSIBLE)
The extracted `DailyCap.for` warning hardcoded the constant name
`DEFAULT_DAILY_CAP` even though the default is a caller-supplied `default:`
parameter — a future caller with a differently-sourced default would produce a
log naming a constant absent from its code path.
**Fix:** message now reads `"falling back to the default cap (#{default})"`.
Existing spec assertions match the unchanged `customer N has a malformed
daily_send_cap` prefix and still pass.

## Refuted candidate (no action)

- **`FlowchartMailer` deletion**: claim was that flowchart Send Email elements
  configured with `mailerClass: "FlowchartMailer"` now reference a missing
  constant. Verifier refuted: `send_email_generator.rb` emits
  `<mailer>.notify(**kwargs).deliver_later` call shapes that never worked
  against `FlowchartMailer`'s actual signature, so no working configuration
  regressed.

## Resume pointers

- Everything is in the uncommitted working tree on `master` (user commits, not Copilot).
- Workflow run: `wf_90857d04-428`; journal at
  `~/.copilot/projects/-home-ec2-user-anysys/010655bb-226a-40c3-a80d-028994df1322/subagents/workflows/wf_90857d04-428/journal.jsonl`.
- If further refactor rounds are wanted: the broader deferred-enrichment
  backlog lives at `docs/superpowers/specs/2026-07-14-deferred-enrichment-backlog.md`.
