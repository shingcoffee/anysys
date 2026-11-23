# Module Handoff & Exit Landing Page — Design

**Date:** 2026-04-25
**Status:** Draft for review
**Scope:** A single, focused feature for the module management subsystem.

## Problem

The app already lets a customer enable feature modules (payment, notification, authentication…) via `FeatureModule` + `CustomerFeatureModule`. Modules can expose their own pages/routes, but two capabilities are missing:

1. A customer's business flow cannot **hand off** to a module's own pages and receive control back. Today a customer-authored page can only redirect to a flowchart after submission (`form_settings.flowchart_id`); there is no way to route through a module's business process and resume the customer's flow afterwards.
2. There is no configuration for an **exit landing page** that a module should return the user to once its business process is done. Each module would otherwise have to hardcode a destination, which breaks multi-tenancy.

This spec covers both requirements.

## Requirements

- **R1 — Integration.** A customer-authored page shall be able to hand off, on submit, to an enabled feature module. The module's pages shall run as part of the business flow (not as a standalone silo), with input data supplied by the triggering page.
- **R2 — Exit landing.** After the module's business process completes, the user shall be redirected to a customer-configured landing page. The landing page is configured per entry point (i.e., on the triggering page), with a per-customer override and a module-declared default as fallbacks.
- **R3 — Multi-tenancy.** Handoff state and exit configuration shall be strictly scoped to the current customer. Cross-tenant access shall be refused and logged.
- **R4 — Test coverage.** Full pyramid: unit, request, and system specs.

## Non-Requirements

- Cross-device / cross-session continuation (session-only state is deliberate).
- A persistent `ModuleInvocation` audit record (we use the existing `FeatureModuleLog` for audit).
- Making modules first-class flowchart nodes (the flowchart-native integration is a future extension; see "Future work").
- Retries / dead-lettering of abandoned invocations.

## Approach summary

- A triggering `Page` declares a handoff in its `form_settings.handoff` JSON.
- On submit, `FeatureModules::Invocation.begin!` stashes `{module_key, customer_id, triggering_page_id, entity_entry_id, input, exit_target, started_at}` in `session[:feature_module_invocation]`, validates the input against the module's declared input contract, logs the event, and redirects to the module's `entry_path`.
- The module's controllers run its own pages. A shared concern exposes the live invocation to module code.
- When the module reaches its terminal state, it calls `FeatureModules::Complete.call(customer:, module_key:, output:)`. The activity validates the output against the module's output contract, resolves the exit URL via `FeatureModules::ExitResolver` (with fallback chain), clears session state, sets `flash[:feature_module_result]`, logs the event, and returns the redirect URL.
- `ExitResolver` supports four target kinds (`page`, `flowchart`, `url`, `route`) with a strict named-route allowlist.

## Architecture & components

### New components

| Component | Type | Location | Purpose |
|---|---|---|---|
| `FeatureModules::Invocation` | PORO service | `app/services/feature_modules/invocation.rb` | Starts/reads/completes/abandons a module run. Sole owner of `session[:feature_module_invocation]`. |
| `FeatureModules::ExitResolver` | PORO service | `app/services/feature_modules/exit_resolver.rb` | Resolves the redirect URL from an `exit_target` hash with a four-step fallback chain. |
| `FeatureModules::BaseModule` *(extend existing)* | Abstract class | `app/services/feature_modules/base_module.rb` | DSL for `entry_path`, `default_exit`, `input_contract`, `output_contract` is added to the existing base. Parent of all module registrations. |
| `FeatureModules::Payment::Registration` | Class | `app/services/feature_modules/payment/registration.rb` | Hypothetical demo module with concrete contracts. |
| `FeatureModules::InvocationContext` | Controller concern | `app/controllers/concerns/feature_modules/invocation_context.rb` | Included by module controllers; exposes `current_invocation` and `invocation_input`. |
| `Pages::HandoffSettingsComponent` | ViewComponent | `app/components/pages/handoff_settings_component.rb` + `.html.erb` | New branch of the post-submit picker in the page editor. |
| `FeatureModuleHandoffContract` | Reform contract | `app/contracts/feature_module_handoff_contract.rb` | Validates `form_settings.handoff` JSON on page save. |
| `FeatureModules::Complete` | Trailblazer activity | `app/services/feature_modules/complete.rb` | Validates output → writes log → resolves exit → returns redirect URL. |

### Existing components that change

| Component | Change |
|---|---|
| `Page` | New `handoff?` helper; `form_settings.handoff` round-trips through JSON attributes; save-time validation via the new Reform contract. |
| `CustomerFeatureModule` | `configuration.exit_landing_page` is read as a fallback target. No schema change — it is just a recognized JSON key. |
| `PublicPagesController#submit` | New branch: when `form_settings.after_submit == "handoff"`, call `Invocation.begin!` and redirect to the module's `entry_path`. Handoff and `flowchart_id` redirect are mutually exclusive. |
| `FeatureModule` | `registration_class` always returns an object that supports the new DSL. The existing `NullRegistration` is extended with no-op `default_exit`, `input_contract`, `output_contract` so legacy callers still work. |
| `FeatureModulesController#show` and its view | Displays the module's `default_exit` and a form to set/clear the customer-level override on `customer_feature_module.configuration.exit_landing_page`. |
| `FeatureModules::Authentication::Registration` | Becomes a subclass of `BaseModule`; declares `entry_path` and `default_exit`; no input/output contracts (empty defaults). |
| `config/locales/feature_modules.en.yml` | New/extended — user-facing error strings. |

### Boundaries

- `Invocation` is the only component that reads or writes `session[:feature_module_invocation]`. Controllers and activities call it; they never touch the session key directly.
- `ExitResolver` is the only component that knows the fallback chain. It accepts `(customer, module_key, session_exit_target)` and returns a URL string.
- Registration classes are the only place a module declares its contract/default_exit/entry_path. Host code reads those declarations; modules do not reach into host code.
- The completion flow is `module controller → FeatureModules::Complete → redirect`. Modules never construct redirect URLs themselves.

## Data shapes

### `form_settings.handoff` (stored on `Page`)

```json
{
  "form_settings": {
    "after_submit": "handoff",
    "handoff": {
      "module_key": "payment",
      "input_mapping": {
        "amount":   { "source": "field",   "path": "fields.total_amount" },
        "currency": { "source": "literal", "value": "USD" },
        "order_id": { "source": "entity",  "path": "id" }
      },
      "exit_target": {
        "kind": "page",
        "page_id": 42
      }
    }
  }
}
```

`input_mapping` sources:
- `"field"` — reads from the submitted form payload at `path` (dot-notation).
- `"literal"` — uses `value` as-is.
- `"entity"` — reads `path` from the bound `EntityEntry`'s attributes (dot-notation).

### `exit_target` kinds — all four supported

| `kind` | Required keys | Resolved URL example |
|---|---|---|
| `"page"` | `page_id` | `/:customer_id/pages/:id` (or the page's public URL if published with `:token`) |
| `"flowchart"` | `flowchart_uuid`, `entity_slug` | `/:customer_id/:flowchart_uuid/:entity_slug` |
| `"url"` | `url` (http/https) | The URL as-is; scheme-validated against an allowlist (`http`, `https`). |
| `"route"` | `name` (named route), optional `params` | `Rails.application.routes.url_helpers.<name>_path(params)` — allowlisted. |

Named routes pass through `FeatureModules::ExitResolver::ALLOWED_ROUTES` so customers cannot redirect to admin/internal routes.

### `CustomerFeatureModule.configuration` fallback key

```json
{ "exit_landing_page": { "kind": "page", "page_id": 99 } }
```

Same schema as `exit_target`. Used only when no session-scoped `exit_target` is present.

### Session state

```ruby
session[:feature_module_invocation] = {
  module_key:          "payment",
  customer_id:         123,
  triggering_page_id:  10,
  entity_entry_id:     456,        # nil if the triggering page did not bind an entity
  input:               { amount: 100, currency: "USD", order_id: 7 },
  exit_target:         { kind: "page", page_id: 42 },
  started_at:          "2026-04-25T10:00:00Z"
}
```

One invocation per session at a time. Beginning a new invocation overwrites any stale one; the old one is logged as `invocation.abandon` with `reason: "superseded"`.

### Module DSL

```ruby
class FeatureModules::Payment::Registration < FeatureModules::BaseModule
  entry_path { |customer| "/#{customer.id}/payment/checkout" }

  default_exit kind: "route", name: "customer_dashboard"

  input_contract do
    property :amount,   type: :integer, validates: { presence: true, numericality: { greater_than: 0 } }
    property :currency, type: :string,  validates: { presence: true, inclusion: { in: %w[USD EUR GBP] } }
    property :order_id, type: :integer, validates: { presence: true }
  end

  output_contract do
    property :payment_reference, type: :string,   validates: { presence: true }
    property :status,            type: :string,   validates: { inclusion: { in: %w[succeeded failed] } }
    property :paid_at,           type: :datetime
  end
end
```

DSL methods compile to Reform contracts. `NullRegistration` returns empty contracts so unregistered modules do not crash.

### Output payload access

`FeatureModules::Complete` writes the validated output payload to `flash[:feature_module_result]`:

```ruby
flash[:feature_module_result] = {
  module_key: "payment",
  output:     { payment_reference: "pi_...", status: "succeeded", paid_at: "2026-04-25T10:03:14Z" }
}
```

The exit landing page can read it without the invocation record persisting.

### Authentication module (real) — empty contracts

```ruby
class FeatureModules::Authentication::Registration < FeatureModules::BaseModule
  entry_path { |customer| "/#{customer.id}/auth/login" }
  default_exit kind: "route", name: "customer_dashboard"
  # no input_contract / output_contract → auto-inherits the empty defaults
end
```

The existing `provision!` / `deprovision!` class methods on `FeatureModules::Authentication::Registration` are preserved.

## Data flow

### Round trip — happy path (Payment example)

```
1. Customer-authored page "Checkout Form" submits
     └─ PublicPagesController#submit
         ├─ Creates/updates EntityEntry as today
         ├─ Sees form_settings.after_submit == "handoff"
         └─ Calls FeatureModules::Invocation.begin!(
              customer:, triggering_page:, entity_entry:, handoff_config:
            )
             ├─ Resolves input_mapping → input_payload
             ├─ Validates input_payload against module's input_contract
             ├─ Writes FeatureModuleLog(action: "invocation.begin", status: "success", ...)
             ├─ Writes session[:feature_module_invocation] = {...}
             └─ Returns registration.entry_path(customer)
         └─ redirect_to entry_path

2. Module's own pages run
     └─ Each module controller includes FeatureModules::InvocationContext
         ├─ Exposes `current_invocation` (reads via Invocation.current)
         └─ Exposes `invocation_input` (the validated input payload)

3. Module reaches its terminal state
     └─ Module controller (e.g., Payment::CheckoutsController#success) calls:
          FeatureModules::Complete.call(
            customer:, module_key: "payment",
            output: { payment_reference: ..., status: "succeeded", paid_at: ... }
          )
         ├─ Loads invocation from Invocation.current
         ├─ Validates output against output_contract
         ├─ Resolves redirect via ExitResolver.call(customer, module_key, invocation.exit_target)
         ├─ Writes FeatureModuleLog(action: "invocation.complete", status: "success", ...)
         ├─ Clears session[:feature_module_invocation]
         ├─ Sets flash[:feature_module_result] = { module_key:, output: }
         └─ Returns { redirect_to: url }
     └─ Module controller: redirect_to result[:redirect_to]

4. Exit landing page renders (e.g., customer-authored "Thank You" page)
     └─ Can read flash[:feature_module_result] to show payment reference, etc.
```

### ExitResolver fallback chain (priority order)

```
1. invocation.exit_target                                    (set by triggering page)
2. customer_feature_module.configuration.exit_landing_page   (customer-level override)
3. registration.default_exit                                 (module-declared default)
4. Tenant-level last-resort: "/#{customer_id}"               (customer home)
```

Any step that yields a resolvable URL wins. If a configured target references a missing record (e.g., page deleted), that step is skipped and the chain continues; a `FeatureModuleLog` warning is recorded.

### Standalone (direct) module access

Users can hit a module's entry route directly without a prior handoff. The invocation service treats this as "no current invocation":

```
User hits /:customer_id/payment/checkout directly (no prior handoff)
  └─ InvocationContext#current_invocation returns nil
      ├─ Module runs with empty input payload
      ├─ Module contract enforces its own required fields via its own pages
      └─ On Complete → ExitResolver skips step 1 (no session target)
                    → falls through to step 2/3/4
```

### Re-entry / stale session

- Starting a new handoff while one is already in progress → old one is logged as `abandoned` (`reason: "superseded"`) and overwritten.
- Completion called with no live invocation (e.g., session expired mid-flow) → `Complete` still validates output, logs it, and resolves exit via steps 2→4. User lands somewhere reasonable.
- Session cleared mid-module → module's own pages behave as in the standalone case.

### Abandonment

- `FeatureModules::Invocation.abandon!(reason:)` clears the session key and writes `FeatureModuleLog(action: "invocation.abandon", status: "warning")`.
- Called explicitly by modules that have a "cancel" button. Not called on session expiry (those are detected on the next `Complete` or `begin!`).

### Multi-tenancy invariants

- `Invocation.begin!` always stamps `customer_id` from `Current.customer_id`.
- `Invocation.current` re-reads `customer_id` and refuses to return an invocation whose `customer_id` does not match `Current.customer_id`.
- `ExitResolver` scopes all DB lookups (page_id → Page, flowchart_uuid → Flowchart) through `TenantScoped`.
- `Complete` refuses to run if `customer_id` mismatch → logs as `security` warning and abandons the invocation.

## Error handling

The completion activity and the invocation service are the only two entry points where user-facing errors can originate. Everything else either cascades from these or is a developer error caught at boot.

### Classification

| Error class | Where | Behavior |
|---|---|---|
| `FeatureModules::Error` | base | All module-flow errors inherit. |
| `ModuleNotEnabled` | `Invocation.begin!` | Triggering page references a module the customer has not enabled. Flash error; redirect back to the triggering page; log `invocation.begin`/`failure`. |
| `InputContractViolation` | `Invocation.begin!` | Input mapping produces a payload that fails the module's input contract. Flash error with contract errors; redirect to triggering page; log `invocation.begin`/`failure`. |
| `OutputContractViolation` | `Complete` | Module called `complete!` with an invalid output payload. This is a module bug, not user error. Raise; hit the generic 500 handler. Log as `invocation.complete`/`failure` with the full payload. |
| `ExitTargetUnresolvable` | `ExitResolver` | Configured exit target references a missing/deleted record. Skip that step (does not raise); final fallback `/:customer_id` always resolves. Warning logged. |
| `CrossTenantViolation` | `Invocation.current`, `Complete` | Session `customer_id` ≠ `Current.customer_id`. Abandon invocation; clear session; render 403. Log as `security`/`failure`. |
| `StaleInvocation` | `Complete` | Called with no live invocation. Not an error: proceed using fallback chain. |
| Registration DSL errors | module boot | `default_exit` references an unknown route; contract is malformed. Raise at class-load time so the app fails fast on deploy, not at runtime. |

### Logging

"Log" means write a `FeatureModuleLog` row with the appropriate `action`, `status`, `request_data`, and `response_data`. `FeatureModuleLog` already exists; no new audit table.

### User-facing copy

Centralized in `config/locales/feature_modules.en.yml`. Controllers never hardcode error text.

### Retry / idempotency

- `Complete` is idempotent within a single invocation: if called twice (e.g., double form submit), the second call sees no live invocation and falls through the fallback chain — same redirect result, second log entry tagged `duplicate`.
- `Invocation.begin!` is not idempotent: each call is a fresh invocation, and any previous live one is abandoned. This matches the session-based, single-active design.

### What we intentionally do not do

- No retry-on-failure inside module pages — modules own their own retries.
- No dead-letter queue for abandoned invocations. `FeatureModuleLog` is the audit trail.
- No custom exception middleware. The Rails default 500 handler covers `OutputContractViolation`.

## Testing

Full pyramid — matches RSpec conventions already in the project.

### Unit specs

| Spec file | Covers |
|---|---|
| `spec/services/feature_modules/invocation_spec.rb` | `begin!` / `current` / `complete!` / `abandon!`; session shape; tenant-scoping; overwrite-on-new-invocation; input-contract validation. |
| `spec/services/feature_modules/exit_resolver_spec.rb` | All four `kind`s (`page`, `flowchart`, `url`, `route`); each fallback-chain step; skip-on-missing-record; route allowlist; tenant scoping on record lookups. |
| `spec/services/feature_modules/base_registration_spec.rb` | DSL — `entry_path`, `default_exit`, `input_contract`, `output_contract`; defaults for modules that declare nothing; boot-time validation errors. |
| `spec/services/feature_modules/payment/registration_spec.rb` | Concrete payment module contracts validate and reject sample payloads. |
| `spec/services/feature_modules/authentication/registration_spec.rb` | Real auth module still provisions correctly under the new `BaseModule` parent. |
| `spec/services/feature_modules/complete_spec.rb` | Trailblazer activity: valid output → redirect URL; invalid output → raises; stale invocation → falls through; cross-tenant → abandons + logs. |
| `spec/contracts/feature_module_handoff_contract_spec.rb` | Reform contract accepts valid `form_settings.handoff`, rejects unknown module keys, bad `exit_target.kind`, missing required keys per kind. |
| `spec/components/pages/handoff_settings_component_spec.rb` | ViewComponent rendering: all four `exit_target` kinds render appropriate inputs; disabled modules do not appear; pre-filled values round-trip. |
| `spec/models/page_spec.rb` (extension) | `page.handoff?` helper; `form_settings.handoff` validation rejects handoffs to modules the customer has not enabled. |

### Request specs

| Spec file | Covers |
|---|---|
| `spec/requests/public_pages_submission_spec.rb` (extension) | When triggering page has `form_settings.handoff`, submission starts invocation (session written) and redirects to module entry instead of flowchart. Handoff and `flowchart_id` are mutually exclusive in the same page submission. |
| `spec/requests/feature_modules_completion_spec.rb` | Integration test exercising a module controller (test-only `FeatureModules::TestModule`) that calls `Complete`: session cleared, redirect resolved, `flash[:feature_module_result]` set. |
| `spec/requests/feature_modules_controller_spec.rb` (extension) | `show` displays `default_exit` and exit-landing override UI; `update_configuration` persists the exit-landing override. |

### System specs

| Spec file | Covers |
|---|---|
| `spec/system/feature_modules/payment_handoff_flow_spec.rb` | End-to-end: customer builds a page → sets after-submit to "hand off to payment" → configures exit landing to another page → submits page → walks through stubbed payment pages → lands on exit page with payment reference visible via `flash[:feature_module_result]`. |
| `spec/system/feature_modules/authentication_handoff_flow_spec.rb` | End-to-end auth handoff: exit target = named route (`customer_dashboard`). Confirms no-contract modules work under the new framework. |
| `spec/system/feature_modules/exit_fallback_chain_spec.rb` | Clear session mid-flow → `Complete` still lands user on customer-level override; delete override → lands on module default; disable module default → lands on `/:customer_id`. |

### Test helpers

- `spec/support/feature_module_registrations.rb` — test-only `FeatureModules::TestModule::Registration` with declared input/output contracts for isolated framework tests.
- `spec/support/invocation_helpers.rb` — `begin_invocation_for(customer:, module_key:, exit_target:, input:)` and `stub_module_pages(module_key)` for request/system specs.

### Coverage targets

- All public methods on `Invocation`, `ExitResolver`, `BaseModule` — 100% branch coverage.
- All four `exit_target` kinds — each tested in isolation and in the system E2E.
- All four fallback-chain steps — each one proven to fire when higher priorities are missing.
- Cross-tenant isolation — explicit spec that sets `Current.customer_id` mismatching the session-stamped id and asserts refusal.

## Security considerations

- **Named-route allowlist.** Only routes in `FeatureModules::ExitResolver::ALLOWED_ROUTES` are resolvable via `kind: "route"`. Admin/internal routes are excluded.
- **URL scheme allowlist.** `kind: "url"` accepts only `http` and `https`. `javascript:`, `data:`, `file:`, etc. are rejected at validation time on the contract and at resolve time as a defense in depth.
- **Cross-tenant refusal.** Every touch of session state or DB lookup is gated on `Current.customer_id`. A mismatch abandons the invocation and returns 403.
- **Module enablement check.** `Invocation.begin!` refuses to start a handoff to a module the customer has not enabled (`CustomerFeatureModule` absent or suspended).
- **No PII in session.** `input` in session is the validated-but-not-yet-processed payload; modules that need to carry PII should persist it to their own records, not extend the session blob.

## Future work

- Persist invocations in a `module_invocations` table for cross-device resume and richer audit.
- Surface modules as first-class flowchart node types so a flowchart can orchestrate module steps directly.
- Admin-side observability: a dashboard of started/completed/abandoned invocations per module per customer.

## Open questions

None at spec time. This document supersedes the discussion in the 2026-04-25 brainstorming session.
