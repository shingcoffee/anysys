# AGENTS.md

Cursor project instructions for Anysys. Supporting harness:

| Path | Purpose |
|------|---------|
| `.cursor/rules/` | Always-on and glob-scoped project rules |
| `.cursor/skills/` | Workflow skills (`new-module`, audits, etc.) |
| `.cursor/agents/` | SDLC subagents (PO, UX, backend, frontend, …) |
| `.cursor/hooks.json` | Stop hook nudging convention review |
| `.cursorignore` | Files excluded from AI context |

## Tech Stack
- Ruby v3.2.8
- Rails v8.1.2
- TailwindCSS
- StimulusJS
- ViewComponent
- Reform (contract validation)
- Trailblazer Activity (`trailblazer-activity`, `trailblazer-developer`) — flowchart source-code generation only (see Coding Guidelines)
- dry-rb family
- Rspec

## UI/UX Guidelines
- Rely on the shadcn/ui plugin (the `shadcn` skill + `plugin-shadcn-shadcn` MCP server tools: search/view/get examples from registries) for ANY UI/UX design or change — always consult it first to select, style, and compose components before writing code, then deliver the result through project ViewComponent + Tailwind + Stimulus conventions
- For UI/UX design or change, follow project ViewComponent + Tailwind + Stimulus conventions and prefer the anysys-ux-designer subagent for new surfaces
- All backend admin pages should have consistent layout and styling
- All pages (admin, member, and public) MUST be responsive — layouts must adapt cleanly across mobile, tablet, and desktop breakpoints using Tailwind's responsive utilities. Do NOT ship a fixed-width or desktop-only layout.
- Any displayed label or wording (button text, headings, placeholders, flash/error messages, tooltips, table headers, nav items, etc.) MUST be I18n — never hard-code user-facing strings in views, components, controllers, or models. Every such string MUST have translations for BOTH English (`en`) and Simplified Chinese (`zh-CN`); do NOT add a key in one locale without adding the matching key in the other.
- **Going forward this is a hard rule with ZERO exceptions**: no new code may introduce a hard-coded user-facing string or wording anywhere — always route it through the I18n framework. This applies to every layer:
  - Views / ViewComponents / controllers / helpers / mailers / models → `t("...")` (models and other non-controller contexts use `I18n.t("...")`). Never bake `t()`/`I18n.t()` into a Ruby constant (it freezes at load-time locale) — keep stable keys in the constant and translate in the accessor at call time.
  - JavaScript / Stimulus → text is NEVER written as a literal in JS. Declare it as a Stimulus Value with an English `default:` and read `this.xxxValue`; the server passes the translated string via `data-<controller>-<name>-value="<%= t("key") %>"` on the mount element (use a JSON value attribute for label maps). Interpolated strings use an ICU-style `{token}` template default plus `.replace()`. This keeps `app/javascript/**` at 100% Vitest coverage with no data attributes in tests.
  - Place keys in the matching area file under `config/locales/` (see the area-prefixed `*.en.yml` / `*.zh-CN.yml` split), reuse an existing key when the identical English text is already keyed, keep `en`/`zh-CN` key sets and interpolation variables in parity, and write idiomatic professional zh-CN (terse, full-width punctuation, canonical terms) — never a literal word-for-word translation.
  - The English (`en`) value MUST be exactly the string that would otherwise have been hard-coded (byte-identical), so existing specs keep passing; only the delivery changes.
  - **Existing locale keys are frozen unless the user explicitly asks**: do NOT edit, reword, rename, or delete any existing key or value under `config/locales/` as a side effect of other work — even when a key becomes unused or its copy no longer fits a redesigned UI. Only add the new keys (in both `en` and `zh-CN`) that new user-facing strings require; propose copy changes to the user instead of making them.

## Coding Guidelines
- CSS Style: Only use TailwindCSS for styling, no customer css or other css framework
- JavaScript: Only use StimulusJS for javascript, no customer javascript or other javascript framework
- Naming and Project Structure: Following Rails v8.1.2 conventions and best practices
- Encapsulate the views(include CSS style) into ViewComponent across the application, that it can be more testable and re-useable
- Avoid redundant code and code spaghetti, organize the code in a professional manner for readability and high maintainability
- Prefer a mature, well-maintained gem or library over a hand-rolled implementation whenever a suitable one exists (e.g. DKIM email signing → the `dkim` gem; never hand-roll crypto/protocol code). Only implement something by hand when no established library covers the need, and document why in the code. Wrap the chosen library behind a thin app-level service (single public interface) so it can be swapped without touching callers.
- Trailblazer (`trailblazer-activity`, `Trailblazer::Activity::Railway`, `trailblazer-developer`) is used ONLY by the flowchart source-code generator and the flowchart code it generates (`ActivityGenerator`, `app/services/code_generators/**`, `ActivityClassBuilder`, `app/services/activity_steps/**`). Do NOT write new Trailblazer activities anywhere else, and convert any other Trailblazer activity you substantially change to plain Ruby.
- Business logic lives in plain Ruby service objects under `app/services/<domain>/` (e.g. `app/services/<domain>/activities/<verb>.rb`): a class with `def self.call(...) = new(...).call` that returns a small `Result` (Struct or `Data`), with transactions and locks written out explicitly (see `Pages::Submit`, `Journeys::Activities::Save`). Keep models thin; validation goes in Reform contracts under `app/services/<domain>/contracts/<noun>.rb`.
- For code generator, you can use ruby meta programming and other Ruby/Rails advanced features to make the code more concise and professional, avoid code spaghetti
- Do NOT take backward compatibility into consideration to avoid coding complexity, just think this is a brand new application
- This is a multi-tenant application, most of the Rails models should have a customer_id field which distinguish the records that belong to the customers from each other
- Customer 81721200 is the platform owner. Users with owner role under this customer can access all resources across all customers

## Documentation — Update Only When Explicitly Requested

**Hard rule: do not create, update, or delete documentation unless the user explicitly asks for documentation changes.** Code changes alone do not authorize documentation changes or require matching docs updates. This includes every file under `doc/` (developer references in `doc/reference/<locale>/`, audit notes, etc.), README files, and saved design/spec/implementation-plan documents. Keep planning and design notes in the conversation unless the user explicitly requests a document. Preserve any pre-existing documentation edits made by the user. This rule takes precedence over any workflow, skill, or subagent instruction to write or synchronize docs automatically.

The developer reference at `/81721200/admin/maintenance/platform/developer_docs` is generated from Markdown files under `doc/reference/<locale>/<slug>.md` (locales: `en`, `zh-CN`), rendered by `DeveloperDocs::Repository` + `DeveloperDocs::Renderer`, and grouped/routed by `DeveloperDocs::Catalog`.

When the user explicitly requests developer-reference updates:

- **Behavioral / API / config changes** → update the requested affected page under `doc/reference/en/<slug>.md` AND `doc/reference/zh-CN/<slug>.md` so the description, examples, and callouts match the behavior.
- **New module / new gateway / new vendor / new surface** → add a new `<slug>.md` under both `doc/reference/en/` and `doc/reference/zh-CN/`, register the slug in `DeveloperDocs::Catalog` so it appears in the contents nav, and cross-link from any related pages.
- **Removed surface** → delete the page from both locales and remove the slug from `DeveloperDocs::Catalog`; scrub inbound links from other pages.
- **Renames** (class names, module keys, URL paths, config keys, role names) → grep `doc/reference/` for the old name and update every reference in both locales.
- **Locale parity**: `en` and `zh-CN` pages must stay in lockstep — same sections, same examples, same callouts. Never update one locale without the other. zh-CN must be idiomatic (terse, full-width punctuation, canonical terms), not a word-for-word translation.
- **Front-matter** (`title`, `summary`) is the source of truth for the nav label and the page header — keep it accurate as the feature evolves.
- Docs edits are cached by `mtime`, so saving the `.md` file is enough; no server restart needed.

## Default model
Grok 4.6 is the only model for this application and every session/subagent. Do not switch to another model.

- Parent / chat sessions: Grok 4.6
- Custom subagents in `.cursor/agents/` are pinned with `model: grok-4.6`
- Task / Explore / generalPurpose / review / bugbot / security-review launches: omit `model` or pass `inherit`
- Never pass Claude, GPT, Gemini, Composer, Kimi, Grok 4.5, or any other model slug

## Workflow — Use Agent Teams for Complex Tasks
For any non-trivial work (new features, new modules, multi-file refactors, anything spanning model + controller + view + spec), drive the task through the anysys-* SDLC subagents in `.cursor/agents/` instead of editing inline. The pipeline is:

1. **anysys-product-owner** — turns a vague request into a structured brief (user stories, acceptance criteria, edge cases, out-of-scope)
2. **brainstorming** (`superpowers:brainstorming`) — explores intent and design before code
3. **anysys-ux-designer** — produces mockups / layout specs for any new or changed UI surface; return them in the conversation unless the user explicitly requests saved documentation
4. **writing-plans** (`superpowers:writing-plans`) — captures the implementation plan in the conversation unless the user explicitly requests a saved plan
5. **Parallel build** — dispatch in a single message with multiple Task/subagent calls:
   - **anysys-backend-developer** (model + migration + plain-Ruby service + Reform contract)
   - **anysys-frontend-developer** (ViewComponent + ERB + Stimulus + component spec)
   - **anysys-security-engineer** (routes + controller skeleton + auth guards + tenant scoping)
6. **anysys-qa-engineer** — RSpec coverage with focus on multi-tenant isolation and authorization
7. **anysys-release-engineer** — runs RSpec, rebuilds assets, restarts dev server with `SKIP_AUTH=1`, smoke-tests
8. **Parallel review** — dispatch in a single message with multiple Task/subagent calls:
   - **anysys-tech-lead** (AGENTS.md convention compliance)
   - **anysys-code-reviewer** (correctness + security)

For module-scoped work, prefer the matching skill (`new-module`, `new-payment-gateway`, `new-captcha-provider`) which already orchestrates this pipeline.

Inline edits are reserved for trivial single-file tweaks (typo fix, copy change, single-line config). When in doubt, route through the team.

## Test Framework
- rspec, TDD, test cases should be generated for the changes.
- **Scoping which specs to run**: do NOT run the full RSpec suite for every change. Match the run scope to the change scope:
  - **Trivial change or bug fix** (single file, narrow blast radius): run ONLY the specs covering the changed files/behavior — e.g. `bundle exec rspec spec/path/to/affected_spec.rb` or a targeted line/example
  - **Moderate change** (a feature slice — one model + its service/contract + one view/component): run the specs for each touched layer (model spec + service spec + contract spec + component spec + relevant request specs)
  - **Tremendous change** (cross-cutting refactor, large module addition, auth/tenant scoping changes, anything that could regress many areas): run the full suite
- **Full suite = parallel when applicable**: whenever you run the entire RSpec suite, use `bin/rails parallel:prepare && bin/rails parallel:spec` if the environment has enough cores and parallel setup is available. Fall back to `bundle exec rspec` only when parallel is unavailable. Do not use parallel for a targeted/narrow spec run — the prepare overhead is not worth it.
- Always run the targeted specs and confirm they pass BEFORE claiming a change is complete — never assert "tests pass" without evidence from a real run

### JavaScript Test Coverage (MANDATORY 100%)
- All JavaScript source code under `app/javascript/**` MUST have **100% test-suite coverage — both lines AND branches** (functions too). This is a hard requirement, not a target.
- The JS harness is two layers (see `spec/javascript/AGENT_GUIDE.md`):
  - **Layer 1 — Vitest** (`spec/javascript/**` mirrors `app/javascript/**`): run `npx vitest run --coverage`. This is where the 100% is measured.
  - **Layer 2 — Playwright** (`spec/e2e/**`): real-browser tests for geometry/pointer/drag engines that happy-dom cannot exercise.
- **Whenever ANY JavaScript is added or changed**, its test suite MUST be added or updated in the same change so that lines and branches stay at 100%. A JS change is NOT complete until `npx vitest run --coverage` shows the touched files at 100% lines/branches (verify with real output — never claim it without a run).
- The ONLY code permitted to fall short of Vitest 100% is genuinely browser-only geometry/pointer code that cannot run in happy-dom; such files must be (a) covered by Playwright in `spec/e2e/**` and (b) listed in the `coverage.exclude` array of `config/javascript/vitest.config.js` with a comment explaining why. Do NOT use `/* v8 ignore */` pragmas to fake coverage of testable logic.

## Development Server
- Before restarting the server, always remove `public/assets/.manifest.json` first to load the latest asset changes
- In development, use `SKIP_AUTH=1` environment variable to bypass authentication
- Command sequence: `rm -f public/assets/.manifest.json && SKIP_AUTH=1 bin/rails server -b 0.0.0.0 -p 3000`
- Asset-shadowing gotcha: if a previous `assets:precompile` left digested files under `public/assets/` (e.g. `public/assets/controllers/*-<hash>.js`), they shadow `app/javascript`/`app/assets` source even though dev uses importmap — and deleting only the manifest is NOT enough. In that case run `bin/rails assets:clobber` before restarting. NOTE: `assets:clobber` also deletes the tracked `app/assets/builds/tailwind.css`; regenerate it afterward with `bin/rails tailwindcss:build`.

## Reserved Roles & Access Rules
The application has exactly three reserved roles. Every authenticated user MUST be assigned exactly one of these. Do NOT introduce additional roles.

- **a) owner** — the platform owner
  - May ONLY be assigned to the user with email `lingercoffee@gmail.com` under customer `81721200`
  - Has unrestricted access to all resources across all customers (cross-tenant)
  - The role assignment is fixed: no UI or admin action may grant `owner` to any other user or any other customer

- **b) admin** — super administrator of a single customer
  - Scoped strictly to the customer they belong to (`customer_id`)
  - May access ANY resource within that customer (all admin URLs, all module entries, all customer-specific settings, the maintenance/modules toggle, etc.)
  - May NOT access resources belonging to other customers, and may NOT access the platform-owner-only Maintenance / Platform / Module Settings area

- **c) member** — self-signed-up member
  - Scoped strictly to their own user record within their customer
  - May access ONLY member-facing resources tied to themselves: e.g. CRU on their own profile, reset their own password, create/manage payments attached to their own card or profile, view their own records
  - May NOT access any admin URL, any other member's data, or any cross-tenant resource
  - Sign-in is required for every member action

Authorization enforcement: controllers MUST guard admin routes with an admin-or-owner check, member routes with a member check scoped to the current user, and ownership checks (record `customer_id` matches `current_user.customer_id`, and for member-owned records `user_id` matches `current_user.id`) on every record-level action. Do NOT rely on UI hiding alone.

## URL Categorization & Authorization
All URLs across this application MUST and may ONLY be categorized into exactly three categories. Any new URL or resource added going forward MUST also fall into one of these three categories:

- **a) admin** — paths starting with `/:cid/admin/`
  - Authorization: protected; accessible ONLY to users with the `admin` or `owner` role
- **b) member** — paths starting with `/:cid/member/`
  - Authorization: protected; accessible ONLY to users with the `member` role
  - Documented exception: a member controller may call `allow_admin_member_preview!` (RouteAuthorization) to additionally admit same-tenant `admin`/`owner` users on GET/HEAD only — a read-only preview of the member experience (e.g. `Member::PagesController`, so admins can open a page's member render directly). Writes remain member-only and cross-tenant access stays blocked.
- **c) public** — any path not categorized as admin or member
  - Authorization: not required (open to anonymous and authenticated users alike)

Both `admin` and `member` URLs/resources MUST enforce authorization at the controller layer (e.g., via `before_action` filters such as `require_admin_or_owner!` for admin routes and the equivalent member check for member routes). Do NOT introduce admin or member URLs without an authorization guard.

## Module URL & Resource Categorization
Every developed module MUST have its URLs and resources categorized into the following four navigation areas. When building a new module, ensure each surface lives in the correct place:

- **a) Entries & Records** → `Modules / <module name>`
  - Customer-facing data: the actual entries, records, or content created/managed within the module
  - Path: `/:customer_id/modules/<module_key>` (and nested entry routes)
  - Audience: any customer user with module access

- **b) Customer-Specific Settings** → `Settings / <module name>`
  - Per-tenant configuration that customers can tune for their own usage of the module
  - Path: `/:customer_id/settings/modules/<module_key>`
  - Audience: customer admins

- **c) Enable / Disable Toggle** → `Maintenance / Modules`
  - Whether the module is turned on for the customer
  - Path: `/:customer_id/maintenance/modules`
  - Audience: customer owner/admin

- **d) Global (Platform) Settings** → `Maintenance / Platform / Module Settings`
  - Platform-wide configuration that applies across all tenants
  - Path: `/:customer_id/maintenance/module_settings` (visible only under platform owner customer `81721200`)
  - Audience: platform owner only

When adding routes, controllers, sidebar contributors, or views for a new module, place each piece into the matching area above. Do NOT introduce module surfaces outside these four categories.

## Payment Module — Adding a New Gateway
The Payment module is vendor-agnostic by design (Alipay and WeChat Pay are the first two gateways; Stripe / PayPal / etc. are expected to follow). To add a new gateway, the ONLY required change is a single new file at `app/services/payments/gateways/<vendor>.rb`. Do NOT change schema, controllers, the Settings UI, or the webhook dispatcher — they pick the new gateway up automatically.

The new file must define a class under `Payments::Gateways` that extends `Payments::Gateways::Base` and declares:
- `key` — stable string identifier used as `Payments::MerchantAccount#provider` and in webhook URLs (e.g. `"stripe"`)
- `display_name` — human-readable name shown in the Settings UI dropdown
- `credential_fields` — array of `{ name:, label:, type:, encrypted: }` hashes describing vendor-specific credentials. Stored in the encrypted `credentials` JSON blob on `MerchantAccount`. `type` is `:string`, `:password`, or `:text`. The Settings form renders these fields automatically.
- `supported_flows` — subset of `[:qr, :h5, :jsapi]`
- `jsapi_user_agent_pattern` (optional) — regex matched against the request UA to route in-app (e.g. WeChat / Alipay) browsers to JSAPI
- `extract_merchant_id(headers, body)` — vendor-specific webhook body parser; returns the merchant_id used to look up the right tenant. Runs BEFORE signature verification, so it must not trust the body cryptographically.
- Implement the API surface used by `Payments::Activities::*`: `charge`, `query`, `refund`, `close`, `subscribe`, `cancel_subscription`, `charge_subscription`, `download_bill`, `verify_notification`. Read vendor-specific credentials with `account.credential(:key)`.
- Call `register!` at the end of the class body (outside the `class << self` block).

Customer gateway selection: each customer has one `Payments::MerchantAccount` row per (provider, mode) auto-seeded by the provisioner. The customer enables a gateway by setting that row's `status = "active"` and entering credentials in `Settings / Payments`. The checkout flow filters by `status: "active"`, so disabling a gateway is a single toggle and does not delete its credentials. Do NOT introduce a separate join table for "selected gateways" — that is what the row's status already represents.

Vendor-specific credentials go into `Payments::MerchantAccount#credentials` (encrypted JSON blob) — never add typed columns to `payment_merchant_accounts`. Read with `account.credential(:key)`; write with `account.write_credentials(key: value)` (blank values are treated as "keep existing", which is what the form needs to avoid clobbering encrypted secrets).

The (customer, provider, mode) row is auto-created by `FeatureModules::Payment::Provisioner` when the customer enables the Payments module. Do NOT write a per-vendor migration. If the vendor has an in-page checkout widget (e.g. JSAPI), pair it with a Stimulus controller named `payments_<vendor>_<flow>_controller.js`.

## Captcha Module — Adding a New Vendor
The Captcha module is vendor-agnostic by design (Aliyun is the first provider; Turnstile/hCaptcha/etc. are expected to follow). To add a new vendor, the ONLY required change is a single new file at `app/services/captcha/providers/<vendor>.rb`. Do NOT change schema, controllers, the platform settings UI, or the Stimulus rendering layer — they pick the new vendor up automatically.

The new file must define a class under `Captcha::Providers` that extends `Captcha::Providers::Base` and declares:
- `key` — stable string identifier used as the DB row key (e.g. `"turnstile"`)
- `display_name` — human-readable name shown in the UI
- `config_fields` — array of `{ name:, label:, type:, default: }` hashes describing vendor-specific config; the platform-owner edit form renders these in order. `type` is `:string` or `:password`.
- `configured?(settings)` — readiness check; returning false makes the verify activity treat the request as `:disabled` (fail-open)
- `verify(verify_param:)` (instance method) — must return `{ outcome:, http_status:, raw: }` where `outcome` is one of `:success`, `:invalid`, `:configuration_error`, `:unreachable`
- `widget(settings)` (optional, class method) — returns Stimulus + SDK metadata `{ stimulus_controller:, sdk_url:, data: {...} }` consumed by `Captcha::WidgetComponent`. Return nil to skip in-page rendering.
- Call `register!` at the end of the class body (outside the `class << self` block). Optionally call `default!` if this should become the default provider.

Vendor-specific configuration goes into `Captcha::ProviderSettings#config` (JSON blob) — never add typed columns to `captcha_provider_settings`. Read with `settings.config_value(:key)`; write with `settings.write_config(key: value)`. Pair the new provider with a matching Stimulus controller named after `widget(...)[:stimulus_controller]` (e.g. `app/javascript/controllers/captcha_<vendor>_controller.js`) if the vendor has an in-page widget.

The vendor-keyed row in `captcha_provider_settings` is created automatically on first access via `Captcha::ProviderSettings.for_provider(key)`. Do NOT write a per-vendor migration.

## Email Module — Adding a New Vendor
The Email module is vendor-agnostic by design (SMTP is the self-hosted MTA; AWS SES and Aliyun DirectMail are the API vendors). To add a new vendor, the ONLY required change is a single new file at `app/services/email/providers/<vendor>.rb`. Do NOT change schema, the webhook route, or the platform credential form — they pick the new vendor up automatically. SMTP typed columns are the historical exception; new vendors use the JSON `config` blob.

The new file must define a class under `Email::Providers` that extends `Email::Providers::Base` and declares:
- `key` — stable string identifier used as `Emails::Credential#provider` and in webhook URLs (e.g. `"ses"`)
- `default_display_name` — English fallback shown when no i18n name exists
- `config_fields` — array of `{ name:, label:, type:, default: }` hashes; the platform-owner credential form renders these in order. `type` is `:string` or `:password`.
- `configured?(credential)` — readiness check; an `active` credential that fails this cannot send
- `delivery_mechanism` — `:none` (no async receipt; status stops at `sent`) or `:webhook` (vendor pushes delivery/bounce/complaint to `POST /email/webhooks/:provider`)
- `uses_webhook_secret?` — defaults to true for `:webhook` vendors. Return false when the vendor verifies with something other than the encrypted `webhook_secret` column (e.g. SES SNS certificates)
- instance `deliver(message:)` — must return `{ provider_message_id:, raw: }` and raise `Email::Errors::ApiError` / `TransportError` on failure
- For `:webhook` vendors: `verify_webhook!(request)` and `parse_events(request)` → `[{ type: :delivered|:bounced|:complained, provider_message_id:, email:, code:, message:, suppress:, raw: }]`
- Call `register!` at the end of the class body (outside the `class << self` block). Optionally call `default!` if this should become the default provider.

Vendor-specific configuration goes into `Emails::Credential#config` (JSON blob) — never add typed columns to `email_credentials`. Secrets go in the encrypted `password` or `webhook_secret` columns. Read with `credential.config_value(:key)` / `credential.password`. Prefer a mature gem (e.g. `aws-sdk-sesv2`) wrapped inside the provider; Aliyun RPC signing must go through `Vendor::AliyunRpc`.

Credentials are platform-wide (one row per provider × mode), not per-tenant. Tenant admins do not pick a vendor per send — `Email::CredentialResolver` prefers the `default!` provider if it is active, else any active credential for the mode.

## Operations API — Adding a New Operation
Operations are the versioned, schema-described units of work the AI assistant calls as tools (`create_domain`, `create_entity`, `update_entity`, `get_entity`, `list_journey_options`, `generate_journeys`, `set_page_processing` and `start_subsystem_build` today). To add one, the required changes are a class file at `app/services/operations/<key>.rb` and its input contract at `app/services/operations/schemas/<key>.json`, plus the I18n messages and specs below. Do NOT change `Tools::OperationTool`, `Operations::Activities::Execute` / `Confirm`, `PendingConfirmation`, or the `operation_invocations` table: tool exposure, validation and violation triage, the retry budget, idempotency, approval and audit come from the `Operations` registry automatically. Assistant-side additions are feature-specific:
- **Prompt guidance** — add a domain document and section under `app/services/ai_assistant/assistant/prompt/` (how to model the feature, plus `{"tool": …, "arguments": …}` examples, which `tool_examples_contract_spec` validates against the schema), and list it together with `Sections::OperationTools` in the prompt mode that handles the feature in `Prompt::Composer::OUTLINES` (the operations section ships in the `entity` mode).
- **Plan rows** (parked operations only) — `plan(input)` returns `[{ "name", "breaking", "rows" => [{ "kind", "action", "name", "field", "before", "after", "breaking" }] }]`. Add new row kinds to `AiAssistant::ProposedChangesComponent::ACTIONS` with `ai_assistant.assistant.plan.rows.<kind>_<action>` labels in both locales; an unknown row falls back to the entity-worded `plan.rows.other` label ("Another change to this entity").
- **Progress label** (optional) — map the key to a progress step in `Tools::Session`.

Non-entity operations are summarised by the model's final reply and the generic `operation_applied` / `operation_stale` approval replies; page generation and the entity change list apply to `Tools::Session::ENTITY_OPERATIONS` only. Full reference: `doc/reference/en/operations-api.md`.

The class must extend `Operations::Base` and declare:
- `key` — stable `verb_noun` string matching `/\A[a-z][a-z0-9_]{2,63}\z/`; it is both the tool name and the audit key (e.g. `"create_flowchart"`)
- `version` — contract version (default 1). Bump it when the contract changes meaning; `Confirm` refuses a proposal parked under another version
- `title` and `summary` — `summary` is the tool description the model reads: say when to use the operation and what it does not do
- `schema "<key>.json"`, optionally `shared_defs "<area>.defs.json"`, and `vocabulary <Area>::Api::Vocabulary` when the contract uses vocabulary slots
- `insert_defaults false` when the input carries merge patches (as `update_entity` does), so schema defaults are not inserted into a patch where they would overwrite stored values
- `annotations read_only:, destructive:, idempotent:, confirmation:` — every destructive change declares `destructive: true, confirmation: :always` so an administrator approves a reviewable plan before anything is written
- `self.available?(context)` (optional) — hides the tool from callers who must not see it (e.g. `FlowchartVisibility.allowed?(context.actor)`)
- Instance hooks: `validate(input)` returns `[Operations::Violation]` for cross-field, reference and quota rules; `perform(input)` returns an `Operations::Outcome`; operations with `confirmation: :always` also implement `plan(input)`, `snapshot(input)` and `stale?(snapshot)`
- Call `register!` at the end of the class body (outside any `class << self` block).

Every property and every enum value is described — the contract is the model's manual. `Operations::SchemaLint` enforces this and `spec/services/operations/contract_lint_spec.rb` fails on any issue: root `title` / `description`, a `description` on every property, `$defs` entry and array `items`, an `x-enum-descriptions` entry for every `enum` value, a `description` on every conditional `allOf` item, `additionalProperties: false` on every object, valid root `examples`, and a projected tool schema within `Operations::SchemaProjection::DEFAULT_BUDGET` (32,000 bytes). Registry-backed enums use `"x-vocabulary": "<slot>"` (and `"x-vocabulary-max"` for registry maximums), never a literal list. Descriptions, titles and summaries are model-facing English API documentation, not user-facing UI strings, so they are not translated.

`perform` delegates to the existing domain writer (e.g. `EntityDefinitions::Persist`) through a thin mapper, scoped to `context.customer`; never re-implement the write. It already runs inside the customer lock, and a non-ok outcome rolls the transaction back.

Every violation code gets a message at `operations.violations.<code>` in `config/locales/operations_<area>.en.yml` AND `config/locales/operations_<area>.zh-CN.yml`, with identical keys and `%{...}` variables; pass every variable in the violation's `details`. The parity specs name their files explicitly, so add a parity check for the new locale files alongside the existing one in `contract_lint_spec.rb`.

Specs drive the operation through `Operations::Activities::Execute.call`: success, each violation code, `forbidden` for members and other tenants' admins, tenant isolation, idempotent replay and `dry_run`. Operations that park also cover `Operations::Activities::Confirm`: approval, `conflict` after a concurrent edit, and `operation.version_changed`. Update `doc/reference/{en,zh-CN}/operations-api.md` only when the user explicitly requests documentation changes.

## Flowcharts — platform owner only
Flowcharts process page submissions. Every page binds exactly one flowchart (`pages.flowchart_id`, `PageProcessing`), and every submit runs it unconditionally:
- **Submit path:** `Pages::Submit` runs the bound flowchart through `FlowchartRuntime::PageRun` inside one savepoint. The flowchart owns validation, writes, side effects and the outcome; a module handoff it asks for begins inside the same savepoint, so a refusal anywhere rolls everything back. Records it writes still go through `Entries::Save` (via `FlowchartRuntime::Entries`), the one entry writer every surface uses. A page whose flowchart is missing or not launched refuses submissions as offline.
- **Default binding:** a new page binds the shared "Save page record" flowchart (`Flowcharts::DefaultPageFlowchart`). Platform singletons like it (also `Flowcharts::SignUpPageFlowchart`, which generated public sign-up pages bind) are created on first use and stay deleted once the owner deletes them.
- **Rebinding:** the owner rebinds a page on its Processing card (`PATCH /:cid/admin/maintenance/pages/:page_id/flowchart`; shared pages on the platform prefix only). A customer-owned page may bind that customer's flowcharts or a shared one; a shared page binds only a shared one, and a tenant customises a shared page's processing through its flowchart override, never a rebind. Tenant admins never see the Processing card; the assistant's `set_page_processing` operation and a sub-system build's binding stage rebind a customer-owned page through the same contract (`Pages::Activities::BindFlowchart` → `Pages::ProcessingContract`).
- **No automations:** flowcharts do not run on record changes. Triggers (`trigger_timing`, the "Runs automatically" card) and the automation dispatcher are retired.
- **Visibility:** customers never see the editor, sidebar, grants catalog, assistant mentions/prompts, or the word “flowchart”, but their bound pages still execute. Tenant `/:cid/admin/maintenance/flowcharts` (and every `flowchart*` controller, including page bindings) is owner-gated like the platform namespace. Ask `FlowchartVisibility.allowed?(user)` before contributing chrome, assistant mentions, or editor links.
- **Assistant-managed processing (exception):** tenant admins may have the AI assistant write processing flowcharts for their own pages and bind them, through `start_subsystem_build` (the background `AiAssistant::Subsystems::Build`) and `set_page_processing`. These surfaces say "form processing", never "flowchart": their contracts, prompt sections, violation messages and build messages stay free of the word (specs assert it), and a refused binding shows `BindFlowchart` `reasons` to a tenant admin, never the owner-only detailed `errors`. Secrets are never collected in chat (steps that need one are left out and listed as needing setup), and a destination URL or email must appear word for word in the admin's own messages. The editor, sidebar, catalog UI, mentions and the chat flowchart pass stay owner-only.

## Linked Pages & Journeys
- **Page settings** (`form_settings`): `modes` (`create` / `update`), `inputs` (locked reference fields filled from an earlier step, re-checked server-side on every render and submit — tenant, entity, reachability — and anything posted for them is ignored; a page on a member-owned link entity may add the admin audience only when its owner reference is a locked input, never public), and `success_message` (display copy only: where the visitor goes next is the journey's call, and a message the flowchart sets wins over it).
- **`JourneyRun`** carries records between pages: a DB row storing only a SHA-256 digest of its token, pinned to the user, or to the browser session for anonymous visitors. It is either a walk through a journey or, without a journey, the carrier of a refused submit's typed values and of records pinned into one page's locked inputs (a record page opening a link's page with the record locked in).
- **`Journey`** is customer-owned and built only by the platform owner (`JourneyVisibility`, registered in `OwnerOnlySurfaces`): builder at `/:cid/admin/maintenance/journeys`, the domain browser's Journeys tab, and the page editor's "Used in journeys" panel. Steps reference page action keys (so each audience gets its own page), with kinds `create`, `record` (the existing record the journey starts from, on its admin page) or `user` (an admin creates the sign-in account, then the next `create` step saves the person record) first, then `create` / `relate` steps (only `relate` may repeat; a step may be optional), ending in exactly one `finish`. `Journeys::LaunchChecks` must pass before launch.
- **Assistant-generated journeys (exception):** tenant admins have the AI assistant generate journeys from `EntityDomains::JourneyPlanner` options (`list_journey_options` / `generate_journeys`, or a sub-system build via `start_subsystem_build`). The builder UI stays owner-only.
- **Running:** tenant admins run journeys (e.g. from "New entry") but cannot build them by hand. The public start URL is `/:cid/journeys/:key`.

## Shared Resources — Path-locked CUD and per-customer overrides
Shared resources (`#shared?`, `customer_id` NULL) — Entities, Pages, Flowcharts, and Constants — are created, globally updated, launched, and deleted **only** at `/81721200/admin/maintenance/platform/{constants,entities,flowcharts,pages}` (owner, customer `81721200`). Tenant maintenance (`/:cid/admin/maintenance/{...}`) never mutates the global row — including when the URL customer is `81721200` or the actor is the owner:
- **Create:** platform prefix writes `customer_id` NULL; tenant prefix always creates a customer-owned row.
- **Update identity / launch / visibility / destroy / restore / empty-trash of the shared row:** platform prefix only. Tenant-path attempts are rejected for every role.
- **Override:** tenant-path Save writes **that customer's** definition body (configuration / options / property_schema) — never global identity (`name` / `extended_model` / `entity_id`). The owner on a tenant URL writes an 81721200 override, not the global default. Only the platform owner may open tenant flowchart URLs or save a launched shared flowchart override there without taking the global row offline; launch / take-offline remains platform-prefix only.
- **Read:** resolve via `#resolved_current_version` (Pages/Flowcharts/Entities; uses `Current.customer`) or Constant options overlay: the customer's override head if present, else the global default. Never read `current_version` directly for a shared page/flowchart/entity definition.
- **Storage:** override heads live in `*_customer_heads (resource_id, customer_id, current_version_id)` for versioned resources; Constants use `constant_customer_overrides (constant_id, customer_id, options)`. Override versions are `*_versions` rows with `customer_id = C`; the global default stays in `*.current_version_id`. The mechanism is generic in the `Versionable` concern (opt in with `customer_head_reflection:`).
- **Reset:** `#reset_customer_override!(customer_id)` (exposed at `DELETE /:cid/admin/maintenance/{entities,pages,flowcharts,constants}/:id/override`) drops a customer's override so reads fall back to the global default. Overrides are pinned forks — global-default changes do not flow into an existing override until it is reset.
- **Destroy cascade:** deleting the shared parent on the platform prefix drops override heads; already-copied customer-owned forks remain.
- **Isolation:** the versions UI scopes to `current_line_versions`; a customer never sees or mutates another tenant's override line.

## Ignore Files
- files under app/services/page_layout_templates/templates/ are all page template related, ignore all these files under this directory

## Git & Commit Workflow
- Changes may be made directly on the `master` branch.
- Do NOT auto-commit changes. The human reviewer will commit manually after review.
- You may stage files with `git add` when helpful, but never run `git commit` unless explicitly asked.
