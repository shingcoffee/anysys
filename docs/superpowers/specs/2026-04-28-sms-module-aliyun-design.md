# SMS Module — Aliyun (China)

**Date:** 2026-04-28
**Branch:** `feature-send-text`
**Status:** Approved design; implementation to follow.

## 1. Goal

Let customers send **transactional SMS to mainland-China phone numbers** via **Aliyun SMS (Dysmsapi)**. Scope is verification codes, order/payment receipts, shipping notifications, password resets. No ad-hoc admin compose, no marketing campaigns, no opt-in lists.

Credentials and the template catalog are **application-scoped** and configured by the platform owner — not per-tenant. Customers enable the `sms` FeatureModule; the module's per-tenant config carries only a daily-send cap. The module is callable from:

1. Host Ruby code via `Sms::Gateway.send(...)` (flowchart step actions, cron jobs, internal services).
2. A FeatureModule handoff endpoint `POST /:customer_id/sms/send` (no-code flowcharts hand off here using the generic module-handoff mechanism).

Both paths resolve to the same Trailblazer activity (`Sms::Activities::Send`).

## 2. Non-goals

- No non-China vendors (Twilio, MessageBird, etc.). Aliyun only.
- No international SMS (different Aliyun endpoint + pricing).
- No marketing/campaign SMS. No list management, opt-in tracking, unsubscribe handling.
- No admin compose-one-off UI.
- No background delivery-status poller. Delivery status is on-demand via `Sms::Gateway.query`.
- No MNS delivery-receipt subscriber.

## 3. Architecture

```
Host code / Flowchart step
        │
        ▼
  Sms::Gateway.send(customer:, to:, template_key:, vars:, idempotency_key: nil, mode: nil)
        │
        └──► Sms::Activities::Send
                 │
                 ├─ Sms::Contracts::Send.validate
                 ├─ idempotency lookup on SmsMessage [customer_id, idempotency_key]
                 ├─ per-phone rate-limit check (1/min, 5/hr, 10/day)
                 ├─ per-tenant daily-cap check (CustomerFeatureModule.configuration["daily_send_cap"])
                 ├─ SmsMessage.create!(status: "pending")
                 ├─ Sms::CredentialResolver.call(mode:) → SmsCredential
                 ├─ Sms::Adapters::Aliyun#send_message
                 └─ persist result (sent / failed)
```

### 3.1 Unit responsibilities

| Unit | Does | Used by | Depends on |
|---|---|---|---|
| `Sms::Gateway` | Single public entry — `send` and `query`. Thin delegator. | Host code, `Sms::SendsController` | `Sms::Activities::Send`, `Sms::Adapters::Aliyun`, `CredentialResolver` |
| `Sms::Adapters::Aliyun` | HTTP + RPC-style HMAC-SHA1 signing + response mapping for `SendSms` and `QuerySendDetails`. | `Sms::Gateway` | Aliyun Dysmsapi |
| `Sms::CredentialResolver` | `(mode:) → SmsCredential`; raises `Sms::Errors::CredentialsMissing`. | `Sms::Gateway` | `SmsCredential` |
| `Sms::Activities::Send` | Trailblazer activity: contract, idempotency, rate-limit, daily-cap, persist, vendor call. | `Sms::Gateway`, `Sms::SendsController` | `Sms::Contracts::Send`, `SmsMessage`, `SmsTemplate`, `Sms::Gateway` |
| `Sms::Contracts::Send` | Reform form validating `to`, `template_key`, `vars` shape vs template's variable schema. | `Sms::Activities::Send` | `SmsTemplate` |
| `FeatureModules::Sms::Registration` | FeatureModule DSL: `input_contract`, `entry_path`, `default_exit`, `sidebar_contributions`, `entries_for`. | Framework | `Sms::Activities::Send` |
| `Sms::SendsController` | Tenant-scoped handoff endpoint — validates contract, calls `Sms::Gateway.send`, returns JSON. | Flowchart handoff / host | `Sms::Gateway` |
| `Sms::Admin::MessagesController` | Tenant-scoped audit log. | Dashboard shell | `SmsMessage.for_current_customer` |
| `Platform::Sms::CredentialsController` | Platform-owner CRUD on `SmsCredential`. | Platform zone | `SmsCredential` |
| `Platform::Sms::TemplatesController` | Platform-owner CRUD on `SmsTemplate`. | Platform zone | `SmsTemplate` |

Each unit is individually testable. `Sms::Adapters::Aliyun` is stubbed via WebMock; activities mock the gateway.

## 4. Data model

### 4.1 `sms_credentials` (app-scoped)

```
id                  bigint
mode                string   -- "sandbox" | "production"
access_key_id       string
access_key_secret   text     -- encrypted (ActiveRecord encrypts)
sign_name           string   -- the 【xxx】 prefix pre-registered in the Aliyun console
region              string   default: "cn-hangzhou"
status              string   -- "active" | "disabled"
created_at / updated_at

unique [mode]
```

No `customer_id`. Platform-owned, one row per mode.

### 4.2 `sms_templates` (app-scoped)

```
id                   bigint
key                  string  -- stable id host code passes, e.g. "verify_code"
aliyun_template_code string  -- vendor-side code, e.g. "SMS_12345678"
description          string
variables            json    -- ordered array of required variable names, e.g. ["code", "minutes"]
status               string  -- "active" | "retired"
created_at / updated_at

unique [key]
```

Retired templates stay in the table (historical `sms_messages` reference them) but can't be selected for new sends.

### 4.3 `sms_messages` (tenant-scoped — `include TenantScoped`)

```
id                 bigint
customer_id        bigint  not null
sms_template_id    bigint  -- FK to sms_templates (nullable: template may have been deleted hard, though we prefer retire)
to                 string  not null
template_key       string  not null  -- denormalized snapshot
vars               json
idempotency_key    string
status             string  not null  default "pending"  -- pending | sent | delivered | failed | unknown
vendor_message_id  string
failure_code       string
failure_message    string
raw_response       json
sent_at            datetime
delivered_at       datetime
created_at / updated_at

unique [customer_id, idempotency_key] where idempotency_key IS NOT NULL
index  [to, template_key, created_at]       -- per-phone rate-limit pre-check
index  [customer_id, created_at]            -- per-tenant daily-cap pre-check
```

State transitions:

```
pending ──(adapter 200)──────► sent ──(query: delivered)──► delivered
pending ──(adapter error)────► failed
sent    ──(query: failed)────► failed
sent    ──(query: unknown)───► unknown     -- timed out or vendor gave no terminal status
```

### 4.4 Per-customer daily cap — no new table

The per-tenant daily-send cap lives at `CustomerFeatureModule.configuration["daily_send_cap"]`, integer, default `1000`. Edited on the customer's module-config page under Settings → Modules → SMS. Enforced by `Sms::Activities::Send` before the vendor call.

## 5. Public interface — `Sms::Gateway`

```ruby
Sms::Gateway.send(customer:, to:, template_key:, vars:, idempotency_key: nil, mode: nil)
  # → SmsMessage

Sms::Gateway.query(message:)
  # → SmsMessage  (status updated in place)
```

`mode` defaults to `Rails.env.production? ? "production" : "sandbox"`.

## 6. Aliyun adapter

`Sms::Adapters::Aliyun` does the RPC-style HMAC-SHA1 signing (POST-form `SendSms` / `QuerySendDetails` against `https://dysmsapi.aliyuncs.com`). Minimum signing rules (the three Aliyun gotchas):

- Each param percent-encoded per RFC 3986 (`CGI.escape` + `+`→`%20`, `*`→`%2A`, `%7E`→`~`).
- Params sorted by key, joined with `&`.
- Signature string: `"POST&%2F&" + pct(sorted_params)`.
- HMAC-SHA1 with key = `access_key_secret + "&"`, Base64-strict-encoded.

Response mapping:

| Aliyun `Code` | Our status | Our exception |
|---|---|---|
| `OK` | `sent` | — |
| anything else | `failed` | `Sms::Errors::ApiError` |

Transport failures (`Net::OpenTimeout`, `ECONNREFUSED`, 5xx) raise `Sms::Errors::TransportError` for caller-side retry.

## 7. Error taxonomy (`Sms::Errors`)

```ruby
module Sms
  module Errors
    class Error              < StandardError; end
    class CredentialsMissing < Error; end   # no active SmsCredential for mode
    class TemplateNotFound   < Error; end   # unknown or retired template_key
    class TemplateVarsInvalid < Error; end  # vars hash missing required keys
    class RateLimited        < Error; end   # per-phone window exceeded (:minute, :hour, :day)
    class DailyCapExceeded   < Error; end   # per-tenant daily cap
    class ApiError           < Error; end   # vendor terminal rejection
    class TransportError     < Error; end   # retryable
    class SignatureInvalid   < Error; end   # not used in v1 (no inbound webhooks)
  end
end
```

Contract violations surface via Reform errors, not exceptions.

## 8. Routes

```ruby
# inside scope "/:customer_id", constraints: { customer_id: /\d{8}/ }
scope "sms", as: :sms do
  post "send", to: "sms/sends#create"     # FeatureModule handoff endpoint

  namespace :admin, module: "sms/admin" do
    resources :messages, only: %i[index show]
  end
end

# platform zone (root namespace)
namespace :platform do
  namespace :sms do
    resources :credentials, only: %i[index new create edit update]
    resources :templates,   only: %i[index new create edit update destroy]
  end
end
```

All paths live under `/platform/sms/...` and `/:customer_id/sms/...`, placing the module inside the existing dashboard zone / section inference.

## 9. FeatureModule registration

```ruby
module FeatureModules::Sms
  class Registration < FeatureModules::BaseModule
    def self.module_key         = "sms"
    def self.module_name        = "SMS (Aliyun / China)"
    def self.module_description = "Transactional SMS to China phone numbers via Aliyun"

    def self.provision!(customer)   = Provisioner.call(customer)
    def self.deprovision!(customer) = Provisioner.revoke(customer)

    entry_path   { |c| "/#{c.id}/sms/admin/messages" }
    default_exit kind: "route", name: "customer_home"

    input_contract do
      property :to,             validates: { presence: true, format: { with: /\A\+?\d{7,15}\z/ } }
      property :template_key,   validates: { presence: true }
      property :vars,           validates: { presence: true }
      property :idempotency_key
    end

    output_contract do
      property :message_id, validates: { presence: true }
      property :status,     validates: { inclusion: { in: %w[sent failed] } }
    end

    def self.sidebar_contributions(_c)
      {
        entries: [Dashboard::ModuleContribution.new(label: "Messages", entry_key: "messages")],
        settings: [Dashboard::ModuleContribution.new(label: "Daily cap", entry_key: "daily_cap")],
        metadata: { order: 60 }
      }
    end

    def self.entries_for(entry_key:, params:)
      case entry_key
      when "messages" then messages_entry_config
      else raise ArgumentError, "unknown entry_key: #{entry_key}"
      end
    end

    private

    def self.messages_entry_config
      {
        title: "SMS Messages",
        columns: [
          { key: :created_at,   label: "At",       sortable: true },
          { key: :to,           label: "To",       searchable: true },
          { key: :template_key, label: "Template" },
          { key: :status,       label: "Status",   sortable: true }
        ],
        scope: SmsMessage.for_current_customer.includes(:sms_template).order(created_at: :desc)
      }
    end
  end
end
```

`Sms::Provisioner.call(customer)` and `.revoke(customer)` are no-ops — nothing per-tenant needs creating (templates and credentials are global; the daily cap lives in `CustomerFeatureModule.configuration` and falls back to the default).

## 10. Activity guards (order matters)

```ruby
Sms::Activities::Send.call(customer:, to:, template_key:, vars:, idempotency_key: nil, mode: nil)
```

1. **Contract** — `Sms::Contracts::Send` (Reform) rejects bad input shapes. Also looks up `SmsTemplate.active.find_by(key: template_key)` and validates `vars.keys.sort == template.variables.sort` (all required, no extras).
2. **Idempotency** — if `idempotency_key` given, return existing `SmsMessage` by `[customer_id, idempotency_key]` if present.
3. **Per-phone rate-limit** — single query loads recent `created_at` values; bucketed in Ruby into 1-minute / 1-hour / 1-day windows. Over any → `RateLimited(window: :minute|:hour|:day)`.
4. **Per-tenant daily-cap** — `COUNT(*)` since `beginning_of_day` vs `CustomerFeatureModule.configuration["daily_send_cap"]` (default 1000). Over → `DailyCapExceeded`.
5. **Persist** — `SmsMessage.create!(status: "pending", vars:, template_key:, sms_template_id:, ...)`.
6. **Vendor call** — `Sms::CredentialResolver.call(mode:)` → `Sms::Adapters::Aliyun#send_message`. On `Code == "OK"` update to `sent` + `vendor_message_id`, `sent_at`; on `ApiError` update to `failed` + `failure_code`, `failure_message`.

## 11. Testing strategy

- **Models** — validations, uniqueness, encryption of `access_key_secret`, retired-template selection guard.
- **`Sms::Adapters::Aliyun`** — WebMock fixtures under `spec/fixtures/sms/aliyun/`; signing-string golden test; success / business error / transport error paths.
- **`Sms::Activities::Send`** — one branch per guard: success / contract / idempotent re-entry / rate-limited (each window) / daily-cap / ApiError / TransportError.
- **`Sms::Gateway`** — delegation spec (mocks activity + adapter).
- **Controllers** — request specs:
  - `Sms::SendsController`: contract-validated round trip.
  - `Sms::Admin::MessagesController`: cross-tenant leak regression (index, show).
  - `Platform::Sms::CredentialsController`: `require_platform_owner!` redirect for non-owners; encrypted-field-preservation on update (same pattern as payment merchant accounts).
  - `Platform::Sms::TemplatesController`: CRUD + unique-key.
- **ViewComponents** — status-pill rendering, masked placeholder preservation.
- **Integration** — system spec: platform-owner seeds credentials + registers template → customer sends via `POST /:cid/sms/send` → `SmsMessage` created → audit log renders the row.

## 12. Security notes

- `SmsCredential.access_key_secret` is `encrypts`-ed at rest.
- Platform admin UI uses the encrypted-field-preservation pattern (blank submission ⇒ keep existing) — same rule established on `PaymentMerchantAccount` to prevent credential wipe on unrelated edits.
- `Sms::Admin::MessagesController` uses `SmsMessage.for_current_customer` on every lookup — no `SmsMessage.find(id)` without the scope, per the project-wide rule captured in memory (`TenantScoped` does not install a `default_scope`).
- No webhooks in v1 — no inbound-signature verification surface.

## 13. Out of scope for v1

- Background delivery poller.
- MNS receipt subscriber.
- Per-tenant override of credentials (hybrid mode). Purely additive if needed later — `CredentialResolver` grows a per-customer lookup branch; nothing else changes.
- Marketing campaigns, opt-in lists, unsubscribe handling.
- Admin compose-one-off UI.
- International SMS.

## 14. Risks

- **Template approval latency.** Customers can't use a template the platform hasn't registered + had approved by Aliyun (2h–2 business days). Mitigation: out-of-band platform-owner workflow; the module itself just exposes the already-registered catalog.
- **Signing-rule mistakes burn debugging time.** Mitigation: golden signing-string test on the adapter (a known input → known expected signature).
- **Rate-limit pre-check vs vendor's own limits.** Our in-Ruby window check is racy under concurrency but catches 99% of retries and double-clicks. The vendor's own enforcement is the hard backstop.
- **Retired templates + historical messages.** Hard-deleting an `SmsTemplate` would orphan rows. `status: "retired"` keeps history readable while hiding the template from new sends.
