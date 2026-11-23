# Aliyun Captcha Module

**Date:** 2026-05-12
**Status:** Approved design; implementation to follow.

## 1. Goal

Let customers protect their member-facing public forms from bots and abuse with **Aliyun Captcha 2.0** (`captcha.cn-shanghai.aliyuncs.com`, action `VerifyIntelligentCaptcha`). The captcha sits above the submit button on a `Page`; the customer flips a per-page toggle in the page editor to require it. Verification happens server-side on `POST /:customer_id/forms/:token` before any `EntityEntry` is built.

Credentials and the captcha **scene/prefab** are platform-scoped (one set, configured once by the platform owner). Customers don't manage credentials. Customers do enable the `aliyun_captcha` FeatureModule under `/maintenance/modules` to make the per-page toggle appear in the page editor.

## 2. Non-goals

- No protection of the application's own auth forms (sign in / sign up / passwords). Those have their own threat model and remain unchanged in v1.
- No support for non-Aliyun providers (hCaptcha, Geetest, reCAPTCHA). Aliyun only.
- No per-customer credential overrides. Platform-only credentials.
- No captcha for non-Page form submissions (e.g., flowchart handoff endpoints).
- No analytics dashboard. Verification outcomes are logged and emitted via `ActiveSupport::Notifications`; building dashboards on top is a later concern.
- No fallback/secondary provider when Aliyun is unreachable. Fail-open instead.

## 3. Architecture

```
Member submits form
        │  POST /:customer_id/forms/:token
        ▼
PublicPagesController#submit
  before_action :verify_aliyun_captcha!  (from AliyunCaptchaProtectable concern)
        │
        ├─ short-circuit: module disabled for customer  → allow
        ├─ short-circuit: page-level toggle off          → allow
        ├─ short-circuit: platform credentials missing   → allow + log warning
        │
        └──► AliyunCaptcha::Activities::Verify.call
                 │
                 ├─ AliyunCaptcha::Contracts::Verify.validate (presence of token)
                 ├─ AliyunCaptcha::Adapters::Aliyun#verify
                 │     ↳ Net::HTTP POST to captcha.cn-shanghai.aliyuncs.com
                 │     ↳ HMAC-SHA1 RPC-style signing (mirrors Sms::Adapters::Aliyun)
                 └─ map { :success | :invalid | :unreachable | :configuration_error }

Result handling:
  :success                       → continue to original submit action
  :invalid                       → flash.now[:alert] + render :show with prior values
  :unreachable                   → log warning, continue (FAIL OPEN)
  :configuration_error           → log error, continue (FAIL OPEN), surface on platform settings page
```

### 3.1 Unit responsibilities

| Unit | Does | Used by | Depends on |
|---|---|---|---|
| `AliyunCaptcha::PlatformSettings` (model) | Singleton row holding encrypted credentials, scene id, endpoint, kill-switch. | Adapter, controllers | ActiveRecord encryption |
| `AliyunCaptcha::Adapters::Aliyun` | HTTP + RPC-style HMAC-SHA1 signing + response mapping for `VerifyIntelligentCaptcha`. | `Activities::Verify` | Aliyun Captcha API |
| `AliyunCaptcha::Adapters::Base` | Shared HTTP/signing helpers (`pct`, `http_post_form`, `compute_signature`). | `Adapters::Aliyun` | Net::HTTP, OpenSSL |
| `AliyunCaptcha::Activities::Verify` | Trailblazer activity: contract → adapter call → result mapping. Returns `Result` struct with `success?` + `outcome` symbol. | `AliyunCaptchaProtectable`, host code | `Contracts::Verify`, adapter |
| `AliyunCaptcha::Contracts::Verify` | Reform form validating `verify_param` presence + JSON shape. | `Activities::Verify` | — |
| `AliyunCaptcha::Contracts::PlatformSettings` | Reform form for credentials edit (with masked-field-preservation pattern). | Platform controller | — |
| `AliyunCaptcha::Activities::UpdatePlatformSettings` | Trailblazer activity: validates contract, encrypts/preserves secret, persists. | Platform controller | `Contracts::PlatformSettings`, model |
| `AliyunCaptchaProtectable` (concern) | `verify_aliyun_captcha!` before-action; delegates to activity, handles fail-open / fail-closed branches. | `PublicPagesController` | `Activities::Verify` |
| `AliyunCaptcha::WidgetComponent` | ViewComponent that renders the captcha mount point + hidden input + Stimulus controller wiring. | Public form view | `PlatformSettings` |
| `AliyunCaptcha::PageEditorToggleComponent` | ViewComponent for the "Require Aliyun Captcha" switch in the page editor. | `_editor.html.erb` | — |
| `Platform::AliyunCaptcha::IndexComponent` / `FormComponent` | Platform settings UI under `/maintenance/module_settings/aliyun_captcha`. | Platform controller | — |
| `Admin::AliyunCaptcha::CustomerStatusComponent` | Customer status panel under `/settings/modules/aliyun_captcha`. | Customer settings controller | — |
| `Admin::Maintenance::Platform::AliyunCaptchaController` | Platform-owner CRUD on credentials. | Routes | activity + components |
| `Admin::Settings::Modules::AliyunCaptchaController` | Customer admin status page (read-only summary). | Routes | components |
| `aliyun_captcha_controller.js` (Stimulus) | Loads Aliyun JS SDK, mounts widget, copies token into hidden input, gates submit button. | Public form page | Aliyun CDN |
| `FeatureModules::AliyunCaptcha::Registration` | FeatureModule registration so customer can enable/disable under `/maintenance/modules`. | Framework | — |

Each unit is independently testable. The adapter is stubbed via WebMock; activities mock the adapter.

## 4. Data model

### 4.1 `aliyun_captcha_platform_settings` (singleton, app-scoped)

```
id                  bigint
access_key_id       string
access_key_secret   text     -- encrypts ... (AR encryption)
scene_id            string   -- Aliyun "PrefabId" / scene id
endpoint            string   default: "captcha.cn-shanghai.aliyuncs.com"
region              string   default: "cn-shanghai"
enabled             boolean  default: false  -- platform-level kill switch
last_health_check_at      datetime
last_health_check_status  string    -- "ok" | "configuration_error" | "unreachable" | nil
last_health_check_message string

created_at / updated_at

unique [id]   -- enforced by validation that only one row exists
```

Accessed via `AliyunCaptcha::PlatformSettings.instance` (memoized; `find_or_initialize_by(id: 1)`).

No `customer_id`. Truly platform-wide.

### 4.2 No new per-page table

Per-page toggle stored in existing `pages.configuration_json`:

```json
{ "aliyun_captcha": { "enabled": true } }
```

Read via `Page#aliyun_captcha_enabled?` (reads JSON, returns `false` if missing or module disabled for the customer).

### 4.3 Per-customer module enablement

Already covered by the existing `FeatureModules::CustomerAssignment` table. No additional schema. The module's `Provisioner` is a no-op (nothing per-tenant to set up).

## 5. Public interface

```ruby
# Server-side verification (used by the controller concern)
AliyunCaptcha::Activities::Verify.call(verify_param: String)
  # → Result(success?: Boolean, outcome: Symbol, raw: Hash | nil, error: String | nil)
  # outcome ∈ { :success, :invalid, :unreachable, :configuration_error, :disabled }

# Convenience for host code (rare; the controller concern is the normal entry point)
AliyunCaptcha::Gateway.verify(verify_param:)
  # → same Result
```

## 6. Aliyun adapter

`AliyunCaptcha::Adapters::Aliyun` mirrors `Sms::Adapters::Aliyun`'s RPC HMAC-SHA1 signing exactly. Aliyun Captcha 2.0 uses the same v1.0 signing rules:

- Each param percent-encoded: `CGI.escape` + `+`→`%20`, `*`→`%2A`, `%7E`→`~`.
- Params sorted by key, joined with `&`.
- Signature string: `"POST&%2F&" + pct(sorted_params)`.
- HMAC-SHA1 with key = `access_key_secret + "&"`, Base64-strict-encoded.

Endpoint: `https://captcha.cn-shanghai.aliyuncs.com`
API version: `2023-03-05`
Action: `VerifyIntelligentCaptcha`
Required params: `CaptchaVerifyParam` (token+session JSON from the widget), `SceneId`.

**Timeouts:** `open_timeout: 2`, `read_timeout: 3`. The whole verification budget on a member submit is ≤ 3 s.

**Adapter outcomes** (the adapter never returns `:disabled`; that comes from the activity when credentials are missing — see §10 step 2):

| Aliyun response                                  | Adapter outcome          |
|--------------------------------------------------|--------------------------|
| HTTP 200, body `{"Code":"Success","Result":{"VerifyResult":true,...}}`  | `:success` |
| HTTP 200, body `{"Code":"Success","Result":{"VerifyResult":false,...}}` | `:invalid` |
| HTTP 200, body `{"Code":"Success","Result":{"VerifyCode":"VerifyFailed",...}}` | `:invalid` |
| HTTP 5xx, `Net::OpenTimeout`, `Net::ReadTimeout`, `Errno::*`, JSON parse error | `:unreachable` |
| HTTP 4xx (auth, signing, scene mismatch, `InvalidAccessKeyId.NotFound`, etc.) | `:configuration_error` |

## 7. Error taxonomy (`AliyunCaptcha::Errors`)

```ruby
module AliyunCaptcha
  module Errors
    class Error              < StandardError; end
    class CredentialsMissing < Error; end   # PlatformSettings has no credentials yet
    class ConfigurationError < Error; end   # 4xx vendor responses (signing, key, scene)
    class TransportError     < Error; end   # 5xx, timeouts, network
    class InvalidToken       < Error; end   # vendor said "no" — never raised, surfaced as outcome
  end
end
```

The activity raises nothing in the normal path — it returns a `Result` with the outcome. Errors are reserved for the platform-settings update path.

## 8. Routes

```ruby
# inside scope "/:customer_id", constraints: { customer_id: /\d{8}/ }

# (b) per-customer settings page (read-only status)
namespace :admin do
  namespace :settings do
    namespace :modules do
      resource :aliyun_captcha, only: :show, controller: "aliyun_captcha"
    end
  end

  # (d) platform settings (visible only on platform-owner customer 81721200)
  namespace :maintenance do
    namespace :platform do
      resource :aliyun_captcha,
               only: %i[show edit update],
               controller: "aliyun_captcha"
    end
  end
end
```

No (a) Entries & Records — captcha has no customer data entries; that area is intentionally omitted.
No (c) explicit module — the existing `/:cid/admin/maintenance/modules` index handles enable/disable through the FeatureModule registration.

## 9. FeatureModule registration

```ruby
# app/services/feature_modules/aliyun_captcha/registration.rb
module FeatureModules
  module AliyunCaptcha
    class Registration < FeatureModules::BaseModule
      def self.module_key         = "aliyun_captcha"
      def self.module_name        = "Aliyun Captcha"
      def self.module_description = "Protect customer-facing public forms with Aliyun Captcha 2.0"
      def self.module_category    = "security"

      def self.provision!(_customer)   = nil   # nothing per-tenant to set up
      def self.deprovision!(customer)  = Provisioner.deprovision(customer)

      entry_path { |customer| "/#{customer.id}/admin/settings/modules/aliyun_captcha" }
      default_exit kind: "route", name: "customer_home"

      def self.sidebar_contributions(_controller)
        {
          settings: [
            ModuleContribution.new(
              label: "Aliyun Captcha",
              entry_key: "status",
              path: ->(cid) { "/#{cid}/admin/settings/modules/aliyun_captcha" }
            )
          ],
          metadata: { order: 70 }
        }
      end
    end
  end
end
```

`Provisioner.deprovision(customer)` strips `aliyun_captcha.enabled` from each `Page#configuration_json` for that customer (so re-enabling later doesn't silently resurrect old toggle state).

## 10. Activity guards (`AliyunCaptcha::Activities::Verify`)

```ruby
AliyunCaptcha::Activities::Verify.call(verify_param:)
```

1. **Contract** — `Contracts::Verify` requires `verify_param` to be present and parse as JSON. Empty/garbled → `Result(success?: false, outcome: :invalid)`.
2. **Settings lookup** — `PlatformSettings.instance`. Missing credentials → `Result(success?: true, outcome: :disabled)` (caller treats as fail-open with warning).
3. **Adapter call** — `Adapters::Aliyun.new(settings:).verify(verify_param:, scene_id:)`. Timeboxed at 3 s.
4. **Outcome mapping** — see §6.
5. **Notification** — `ActiveSupport::Notifications.instrument("aliyun_captcha.verify", duration:, outcome:, http_status:)`.

## 11. Controller integration (`AliyunCaptchaProtectable`)

```ruby
# app/controllers/concerns/aliyun_captcha_protectable.rb
module AliyunCaptchaProtectable
  extend ActiveSupport::Concern

  private

  def verify_aliyun_captcha!
    return unless captcha_required_for_request?

    result = AliyunCaptcha::Activities::Verify.call(
      verify_param: params[:aliyun_captcha_verify_param]
    )

    case result.outcome
    when :success
      # let the request through
    when :unreachable, :configuration_error, :disabled
      # fail-open: log a warning and let the request through
      Rails.logger.warn("[aliyun_captcha] fail-open: #{result.outcome}")
    when :invalid
      flash.now[:alert] = I18n.t("aliyun_captcha.errors.invalid")
      @captcha_failed = true
      render :show, status: :unprocessable_entity and return
    end
  end

  def captcha_required_for_request?
    @page&.aliyun_captcha_enabled? &&
      FeatureModules::CustomerAssignment.enabled?(customer_id: current_customer_id, key: "aliyun_captcha")
  end
end
```

`PublicPagesController` adds:

```ruby
include AliyunCaptchaProtectable
before_action :verify_aliyun_captcha!, only: :submit
```

## 12. Frontend — Stimulus + Aliyun JS SDK

`aliyun_captcha_controller.js` (auto-loaded by `controllers/index.js`):

- **`connect()`** — if `window.AliyunCaptcha` is undefined, inject `<script src="https://o.alicdn.com/captcha-frontend/aliyunCaptcha/AliyunCaptcha.js" async>`; resolve a per-page promise. Idempotent across multiple widgets on a page.
- **`renderWidget()`** — call `AliyunCaptcha.init({ SceneId, prefab, mode: "embed", element: this.element.querySelector("[data-aliyun-captcha-target='mount']"), captchaVerifyCallback, onBizResultCallback, language: this.localeValue })`.
- **`captchaVerifyCallback(captchaVerifyParam)`** — write `captchaVerifyParam` (string) into `<input type="hidden" name="aliyun_captcha_verify_param">`; enable submit button.
- **Locale** — `this.localeValue` is the Rails `I18n.locale` passed via a `data-aliyun-captcha-locale-value` attribute. Map: `zh-CN` → `cn`, anything else → `en`.

The `WidgetComponent` renders:

```html
<div data-controller="aliyun-captcha"
     data-aliyun-captcha-scene-id-value="<%= scene_id %>"
     data-aliyun-captcha-prefab-value="<%= prefab %>"
     data-aliyun-captcha-locale-value="<%= I18n.locale %>">
  <div data-aliyun-captcha-target="mount"></div>
  <input type="hidden" name="aliyun_captcha_verify_param" value="">
</div>
```

The submit button on the form opts in by adding `data-aliyun-captcha-target="submit"`; the controller flips its `disabled` attribute when the token arrives. If the platform settings are missing or the module is off for this customer, `WidgetComponent` renders nothing — no hidden input either, so the controller never runs.

## 13. Page editor integration

`PageEditorToggleComponent` is rendered inside `_editor.html.erb`'s "Form settings" section (around line 610). It reads/writes `configuration_json["aliyun_captcha"]["enabled"]` through the existing nested-attributes channel that already powers `form_settings`. The toggle is hidden when the module is not enabled for the customer (`FeatureModules::CustomerAssignment.enabled?(...)`).

## 14. Authorization

| Path | Guard |
|---|---|
| `/:cid/admin/maintenance/platform/aliyun_captcha` (and edit/update) | `require_platform_owner!` (owner role + `current_customer_id == 81721200`) |
| `/:cid/admin/settings/modules/aliyun_captcha` | `require_admin_or_owner!`, scoped to current tenant |
| `POST /:cid/forms/:token` | unchanged (public); captcha filter adds protection where toggled on |

`AliyunCaptcha::PlatformSettings` is **not** `TenantScoped` — it's truly app-scoped. Direct ActiveRecord access is allowed only from inside the `AliyunCaptcha::*` namespace (the platform controller); no tenant-scoped controller may read it.

## 15. i18n

```yaml
# config/locales/aliyun_captcha.en.yml
en:
  aliyun_captcha:
    page_editor:
      label: "Require Aliyun Captcha"
      hint:  "Show a captcha challenge above the submit button. Helps block bots and abuse on this form."
    widget:
      loading: "Loading verification..."
      submit_disabled_hint: "Complete the verification to enable submit."
    errors:
      invalid: "Verification failed. Please try again."
      unreachable: "Verification service is temporarily unavailable. Your submission was accepted."
      configuration: "Verification service is misconfigured. Contact your administrator."
    platform_settings:
      title: "Aliyun Captcha — Platform Settings"
      access_key_id:     "Access Key ID"
      access_key_secret: "Access Key Secret"
      scene_id:          "Scene ID"
      endpoint:          "Endpoint"
      enabled:           "Enabled platform-wide"
      health:
        ok: "Last verification: OK"
        configuration_error: "Last verification: 4xx — check credentials"
        unreachable: "Last verification: unreachable"
    customer_status:
      title: "Aliyun Captcha"
      module_disabled: "This module is disabled. Enable it under Maintenance → Modules to use it."
      credentials_missing: "Aliyun Captcha credentials are not configured by the platform owner."
      pages_using:
        zero: "No pages are using captcha yet."
        one: "1 page has captcha enabled."
        other: "%{count} pages have captcha enabled."

# config/locales/aliyun_captcha.zh-CN.yml — mirror keys with Chinese strings
```

The locale file's existence creates a `zh-CN` resource bundle even though the rest of the app may not have one yet; that's fine — the module is China-targeted and degrades cleanly to `en` everywhere else.

## 16. Testing strategy

- **Models** — `PlatformSettings` singleton enforcement; encryption round-trip on `access_key_secret`; `Page#aliyun_captcha_enabled?` returns false when JSON missing / module off / explicitly false.
- **`Adapters::Aliyun`** — WebMock fixtures under `spec/fixtures/aliyun_captcha/`; **golden signing-string test** (known input → known signature, lifted directly from the SMS adapter test pattern); success / invalid / configuration-error / transport-error paths.
- **`Activities::Verify`** — one branch per outcome (`:success`, `:invalid`, `:unreachable`, `:configuration_error`, `:disabled`); contract failure path; instrumentation emitted.
- **`Activities::UpdatePlatformSettings`** — credential validation, masked-field-preservation pattern (blank `access_key_secret` ⇒ keep existing).
- **Controllers**:
  - `PublicPagesController#submit`: existing spec extended — captcha required & valid → submit succeeds (entry created); invalid → flash + 422 + entry NOT created; Aliyun timeout → submit succeeds + warning logged; module disabled for customer → no captcha required; per-page toggle off → no captcha required; platform credentials missing → submit succeeds + warning logged.
  - `Admin::Maintenance::Platform::AliyunCaptchaController`: only platform owner can access; non-owner gets 403; update preserves secret on blank submission.
  - `Admin::Settings::Modules::AliyunCaptchaController`: tenant scoping; renders module-disabled state correctly.
- **ViewComponents** — `WidgetComponent`: renders nothing when module off / credentials missing / per-page toggle off; renders mount + hidden input + locale-mapped data attributes when on. `PageEditorToggleComponent`: hidden when module off; reflects current page state.
- **Stimulus** — small JS unit test with the SDK mocked: token written into hidden input on success callback; submit button enabled.
- **Integration / system spec** — platform owner configures credentials → customer enables module → customer toggles a page on → member visits the page → fills + verifies captcha → entry created. (System spec uses a stubbed `AliyunCaptcha.init` that auto-resolves with a fake token.)
- **i18n** — request specs assert flash messages render in both `en` and `zh-CN`.

## 17. Security notes

- `PlatformSettings.access_key_secret` uses ActiveRecord `encrypts` at rest.
- The platform admin form uses the **masked-field-preservation pattern** (blank submission ⇒ keep existing) — same rule established for `Payments::MerchantAccount` and `Sms::Credential`.
- `AliyunCaptcha::PlatformSettings` is read-only outside its owning controller. No tenant-scoped controller queries it directly; only `Activities::Verify` and the platform controller touch it.
- `verify_param` is treated as opaque — never logged, never persisted. Only the boolean outcome and (for unreachable/4xx) the response code make it into logs.
- Fail-open is intentional and scoped: it applies to `:unreachable` and `:configuration_error` only. `:invalid` always blocks.

## 18. Out of scope for v1

- Auth-form protection (sign in / sign up / passwords).
- Per-customer credential overrides (hybrid mode). Purely additive later — `PlatformSettings.instance` becomes a resolver method that prefers per-customer credentials when present.
- Other widget modes (slider-only, button trigger). Smart embed only.
- Background health-check cron pinging Aliyun. Health is recorded opportunistically on each verify call; an explicit `/maintenance/platform/aliyun_captcha/health_check` action could be added later if needed.
- Captcha for admin/internal forms.
- Captcha replay protection beyond what Aliyun's own `CaptchaVerifyParam` provides (each token is single-use server-side at the vendor; we don't track tokens locally).

## 19. Risks

- **Signing rule mistakes burn debugging time.** Mitigation: golden signing-string test on the adapter, mirroring the SMS adapter's existing test.
- **Aliyun JS SDK CDN latency in regions outside China.** Mitigation: SDK is loaded `async`; Stimulus controller waits for `window.AliyunCaptcha`; submit button stays enabled if module is off, disabled until token arrives if on. Worst case: member sees a brief "Loading verification..." — acceptable.
- **Fail-open masks misconfiguration.** Mitigation: every fail-open path logs a warning, records `last_health_check_status` on `PlatformSettings`, and surfaces a banner on the platform settings page. Platform owner has a clear feedback loop without breaking customer pages.
- **Per-page toggle silently resurrects after a deprovision/reprovision cycle.** Mitigation: `Provisioner.deprovision` strips `aliyun_captcha.enabled` from every `Page` for the customer at deprovision time.
- **Locale mismatch between Aliyun widget languages and Rails locales.** Mitigation: explicit map (`zh-CN` → `cn`, else `en`); Aliyun docs cover both.
