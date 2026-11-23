# Authentication Module Enrichment (#1–#9) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the nine maximum-tier enrichment slices from `docs/superpowers/specs/2026-07-14-authentication-redo-design.md` Part 3 — activity feeds, in-app credential management, password policy + strength meter, active-session management, sign-in alerts, admin force-reset/unlock, live tenant auth knobs, and passkeys.

**Architecture:** Each slice is an independent vertical (route → controller guard → service/model → ViewComponent → specs) landing in the correct URL area (member surfaces under `/:cid/member/security/*`, admin surfaces under `/:cid/admin/modules/authentication/users/*`, public auth surfaces under `/:cid/auth/*`). New per-tenant knobs extend the existing `FeatureModules::Authentication::Registration.configuration_schema` + `Authentication::Settings` reader. New tables: `authentication_sessions` (slice 5) and `authentication_credentials` (slice 9) — both tenant-scoped with `customer_id`.

**Tech Stack:** Rails 8.1 / Devise 5 / Pagy 9 / ViewComponent / Stimulus / Reform / RSpec / Vitest. New gems: `zxcvbn` (slice 4), `device_detector` (slice 5), `webauthn` (slice 9).

**Ground rules (from AGENTS.md + umbrella design — apply to every task):**
- NOTHING is committed. Changes stay on `master` uncommitted; the user reviews and commits. Every "verify" step is a real targeted spec run.
- Every user-facing string: `t()` key in the matching area locale file, **both** `config/locales/*.en.yml` and `*.zh-CN.yml`, en byte-identical to what would have been hard-coded, zh-CN idiomatic. Key-set + interpolation parity.
- Stimulus text via Values with English `default:` + server-passed translations (`data-<controller>-<name>-value`). No literals in JS.
- Any JS added → matching Vitest suite in `spec/javascript/**` mirroring the path; `npx vitest run --coverage` must show the touched files at 100% lines+branches (real run, single-fork if the parallel tmp-file race bites).
- Member routes: member-role-only via `Member::BaseController` (RouteAuthorization gates the prefix). Record-level checks via `authorize_owned!`. Admin routes: existing `ApplicationController` + RouteAuthorization admin gate; tenant-scope every find (`where(customer_id: current_customer_id)`).
- `Authentication::Event` is NOT TenantScoped — every ledger query MUST filter both `customer_id` AND (where applicable) `user_id` explicitly.
- Multi-tenant + authorization negative specs are mandatory for every new endpoint (cross-tenant 404, wrong-role rejection, anonymous redirect).

**Verification cadence:** each slice ends with its targeted spec run green; after slice 9, full `bin/rails parallel:spec` + `npx vitest run --coverage` + real-browser smoke of the member security surfaces.

---

## Slice 1 — Member recent-activity feed *(S)*

**Files:**
- Modify: `config/routes.rb` (member security block)
- Create: `app/controllers/member/security_activities_controller.rb`
- Create: `app/components/member/activity_list_component.rb` + `.html.erb`
- Create: `app/views/member/security_activities/show.html.erb`
- Modify: `app/controllers/member/securities_controller.rb` (teaser events)
- Modify: `app/views/member/securities/show.html.erb` (teaser card in aside)
- Modify: `config/locales/member.en.yml`, `config/locales/member.zh-CN.yml`
- Test: `spec/requests/member/security_activities_spec.rb`, `spec/components/member/activity_list_component_spec.rb`

### Task 1.1: Route + controller

- [ ] **Step 1: Add the route** inside the existing `resource :security ... do` block in `config/routes.rb`:

```ruby
      resource  :security,  only: :show, controller: "securities" do
        resource :mfa, only: :destroy, controller: "mfa" do
          get  :setup, on: :collection
          post :setup, on: :collection
        end
        resource :activity, only: :show, controller: "security_activities"
      end
```

- [ ] **Step 2: Write the failing request spec** `spec/requests/member/security_activities_spec.rb`. Follow the existing member request-spec setup conventions (see `spec/requests/member/` neighbors for the sign-in helpers/factories in use):

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Member::SecurityActivities", type: :request do
  # reuse the factories + sign_in helper pattern from spec/requests/member/securities_spec.rb
  # covering:
  it "lists only the current member's own events (scoped customer_id AND user_id)"
  it "paginates with Pagy (page 2 returns the older page)"
  it "redirects anonymous users to sign-in"
  it "rejects admins (member-only surface)"
  it "does not show another member's events from the same tenant"
  it "does not show a same-id user's events from another tenant"
end
```
Each `it` must be implemented with real assertions (create `Authentication::Event` rows directly — e.g. two for the member, one for a co-tenant other member, one for a foreign tenant — then assert body includes/excludes the distinguishing metadata and response status).

- [ ] **Step 3: Run it, verify it fails** — `bundle exec rspec spec/requests/member/security_activities_spec.rb` → routing error.

- [ ] **Step 4: Implement the controller** `app/controllers/member/security_activities_controller.rb`:

```ruby
# frozen_string_literal: true

module Member
  # Member-facing slice of the append-only auth audit ledger.
  # Authentication::Event is NOT TenantScoped — scope BOTH customer_id and
  # user_id explicitly so a member can only ever read their own rows.
  class SecurityActivitiesController < BaseController
    include Pagy::Backend

    PER_PAGE = 20

    def show
      @pagy, @events = pagy(
        ::Authentication::Event
          .for_customer(current_user.customer_id)
          .for_user(current_user.id)
          .order(created_at: :desc),
        limit: PER_PAGE
      )
    end
  end
end
```

- [ ] **Step 5: Run the request spec again** — expect only view-template failures now.

### Task 1.2: List component + view + teaser

- [ ] **Step 1: Component spec** `spec/components/member/activity_list_component_spec.rb` — render with a mixed set of events; assert: translated event label (`member.security_activity.events.login_succeeded` etc.), formatted time, IP fallback (`unknown_ip` key) when blank, empty-state rendering via `Member::EmptyStateComponent` when no events.

- [ ] **Step 2: Component** `app/components/member/activity_list_component.rb`:

```ruby
# frozen_string_literal: true

module Member
  # Renders a list of Authentication::Event rows for the member activity feed.
  # Compact variant (compact: true) renders the teaser (no user-agent line).
  class ActivityListComponent < ViewComponent::Base
    SUCCESS_EVENTS = %w[login_succeeded mfa_verified mfa_enabled password_reset_completed].freeze
    WARN_EVENTS    = ::Authentication::Instrumentation::WARN_EVENTS

    def initialize(events:, compact: false)
      @events  = events
      @compact = compact
    end

    private

    attr_reader :events, :compact

    def label_for(event)
      t("member.security_activity.events.#{event.event}",
        default: event.event.humanize)
    end

    def tone_for(event)
      return :warn    if WARN_EVENTS.include?(event.event)
      return :success if SUCCESS_EVENTS.include?(event.event)
      :neutral
    end
  end
end
```

Template `.html.erb`: `Member::EmptyStateComponent` when `events.blank?`; otherwise a `<ul>` of rows — tone dot (Tailwind `bg-success`/`bg-warning`/`bg-member-muted` circle), label, `event.created_at` via the datetime format used by `Member::DetailGridComponent`, monospace IP (or `t("member.securities.show.unknown_ip")`), and (non-compact) a truncated `event.user_agent` line. Responsive (stack on mobile).

- [ ] **Step 3: Page view** `app/views/member/security_activities/show.html.erb` — mirror `member/securities/show.html.erb` structure: `content_for :title` + `content_for :member_nav, "security"`, `Member::PageLayoutComponent` with `Member::PageHeaderComponent` (title `t("member.security_activity.show.title")`, subtitle key), one `Member::PageSectionComponent` wrapping `render Member::ActivityListComponent.new(events: @events)` + `render Member::PaginationComponent.new(pagy: @pagy)` (check `Member::PaginationComponent`'s actual initializer signature before use), and a back-link to `member_security_path`.

- [ ] **Step 4: Teaser** — in `Member::SecuritiesController#show` add `@recent_events = ::Authentication::Event.for_customer(current_user.customer_id).for_user(current_user.id).order(created_at: :desc).limit(3)`. In the aside of `member/securities/show.html.erb`, add a `Member::PageSectionComponent` (title `t("member.security_activity.teaser_title")`) rendering `Member::ActivityListComponent.new(events: @recent_events, compact: true)` and a "view all" link to `member_security_activity_path(current_user.customer_id)`.

- [ ] **Step 5: i18n** — add to `config/locales/member.en.yml` and `.zh-CN.yml` (same key set):

```yaml
  security_activity:
    teaser_title: "Recent activity"
    view_all: "View all activity"
    show:
      title: "Account activity"
      header_subtitle: "Recent security events on your account"
      back: "Back to security"
      empty_title: "No activity yet"
      empty_body: "Security events like sign-ins and password changes will appear here."
    events:
      login_succeeded: "Signed in"
      login_failed: "Failed sign-in attempt"
      logout: "Signed out"
      locked_out: "Account locked after repeated failures"
      mfa_enabled: "Two-factor authentication enabled"
      mfa_disabled: "Two-factor authentication disabled"
      mfa_verified: "Two-factor code verified"
      mfa_failed: "Two-factor code rejected"
      password_reset_requested: "Password reset requested"
      password_reset_completed: "Password changed"
      role_granted: "Role granted"
      role_revoked: "Role revoked"
      throttled: "Requests rate-limited"
```
(zh-CN: idiomatic terse translations, e.g. `login_succeeded: "登录成功"`, `password_reset_completed: "密码已修改"` …)

- [ ] **Step 6: Verify** — `bundle exec rspec spec/requests/member/security_activities_spec.rb spec/components/member/activity_list_component_spec.rb spec/requests/member/securities_spec.rb` → all green.

---

## Slice 2 — Admin per-user auth-events view *(S)*

**Files:**
- Modify: `config/routes.rb` (admin authentication users resource — add `member { get :events }`)
- Modify: `app/controllers/admin/modules/authentication/users_controller.rb` (add `events` action)
- Create: `app/views/admin/modules/authentication/users/events.html.erb`
- Modify: `app/views/admin/modules/authentication/users/show.html.erb` (link + recent-events section)
- Modify: `config/locales/admin_modules.en.yml`, `.zh-CN.yml`
- Test: extend `spec/requests/admin/modules/authentication/users_spec.rb` (or the existing admin users request spec file — locate with `grep -rl "authentication/users" spec/requests`)

### Task 2.1: Route, action, view

- [ ] **Step 1: Failing request specs** — in the existing admin users request spec add a describe "GET /events" block: admin sees own-tenant user's events; events list excludes other users'/tenants' rows; cross-tenant user id → 404; member role → rejected; anonymous → redirected.

- [ ] **Step 2: Route** — in the admin authentication users resources add:

```ruby
resources :users do
  member { get :events }
  ...
end
```
(Adjust to however the resource is currently declared — find it under `namespace :modules do namespace :authentication` in routes.rb.)

- [ ] **Step 3: Action** in `UsersController` (add `:events` to `before_action :find_user, only:`):

```ruby
      # GET /:customer_id/admin/modules/authentication/users/:id/events
      def events
        @pagy, @events = pagy(
          ::Authentication::Event
            .for_customer(current_customer_id)
            .for_user(@user.id)
            .order(created_at: :desc),
          limit: 25
        )
      end
```
Add `include Pagy::Backend` to the controller.

- [ ] **Step 4: View** `events.html.erb` — consistent admin layout: reuse the admin page-header/table conventions from the sibling `show.html.erb` / other admin module views. Table columns: event label (`t("admin_modules.users.events.names.#{event.event}", default: event.event.humanize)` — reuse the member label keys is NOT allowed across areas; add an `admin_modules.users.events.names` alias tree or point both at a shared `auth.events.*` tree — pick ONE shared tree `auth.events.*` in `auth.en.yml`/`auth.zh-CN.yml` and use it from both member + admin surfaces to avoid duplication), time, IP, user-agent (truncated), metadata (compact JSON). Pagy pagination via the admin pagination partial/component in use on other admin index views. Back-link to the user show.
  - **Correction to Slice 1 step 5**: put the shared `events:` label tree under `auth.en.yml` → `auth.events.*` instead of `member.security_activity.events.*`, and reference it from both the member component and this admin view. Keep the member-page-specific chrome keys (`title`, `teaser_title`, …) in `member.*`.

- [ ] **Step 5: Entry point** — on the admin user `show.html.erb`, add a link/button `t("admin_modules.users.events.view_events")` → `events_admin_modules_authentication_user_path(current_customer_id, @user)`.

- [ ] **Step 6: i18n** — `admin_modules.en.yml`/`.zh-CN.yml`: `users.events.title` ("Authentication events"), `.view_events` ("View authentication events"), `.empty` ("No authentication events recorded for this user."), table headers reuse existing `common.labels.*` where the English matches (check before adding new keys).

- [ ] **Step 7: Verify** — run the admin users request spec file → green.

---

## Slice 3 — Member in-app password change + email change with re-confirmation *(M)*

**Files:**
- Modify: `config/initializers/devise.rb` (`config.reconfirmable = true`)
- Modify: `config/routes.rb` (member security block)
- Create: `app/controllers/member/credentials_controller.rb`
- Create: `app/concepts/member/credentials/contract/password.rb`, `app/concepts/member/credentials/contract/email.rb` (Reform)
- Create: `app/concepts/member/credentials/operation/update_password.rb`, `operation/update_email.rb` (follow the module's existing PORO `self.call` activity convention — mirror `app/concepts/member/mfa/operation/*.rb` shape)
- Modify: `app/views/member/securities/show.html.erb` (in-app forms replace the reset link-out)
- Modify: `app/models/authentication/event.rb` (EVENTS += `password_changed email_change_requested`)
- Modify: `config/locales/member.en.yml`, `.zh-CN.yml`, `auth.en.yml`, `auth.zh-CN.yml` (event labels)
- Test: `spec/requests/member/credentials_spec.rb`, contract specs under `spec/concepts/member/credentials/`

### Task 3.1: Reconfirmable + operations (TDD)

- [ ] **Step 1: Flip reconfirmable** — `config.reconfirmable = true` in `config/initializers/devise.rb`. Immediately run the auth request specs (`bundle exec rspec spec/requests/authentication spec/models/authentication`) to catch any spec that asserted direct email overwrite; fix genuinely stale expectations (per the stale-test policy) — email changes now park in `unconfirmed_email` until the confirmation link is followed.

- [ ] **Step 2: Contract specs first.** `Password` contract: requires `current_password`, `password` (+ confirmation match); `Email` contract: requires `current_password`, `email` (format). Validation errors carry i18n messages.

- [ ] **Step 3: Contracts** (Reform, mirroring existing contracts under `app/concepts/**/contract/`):

```ruby
# app/concepts/member/credentials/contract/password.rb
# frozen_string_literal: true

module Member
  module Credentials
    module Contract
      class Password < Reform::Form
        property :current_password, virtual: true
        property :password,              virtual: true
        property :password_confirmation, virtual: true

        validates :current_password, presence: true
        validates :password, presence: true, confirmation: true
        validates :password_confirmation, presence: true
      end
    end
  end
end
```

`Email` analogous: `property :current_password, virtual: true; property :email; validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }`.

- [ ] **Step 4: Operation specs** — `UpdatePassword.call(user:, params:)`: wrong `current_password` → failure with `:current_password` error; weak params → contract errors; success → `user.reload.valid_password?(new)` true, instruments `password_changed`. `UpdateEmail`: success parks new address in `unconfirmed_email`, sends confirmation mail (assert `ActionMailer` deliveries/enqueue), original `email` unchanged, instruments `email_change_requested`; wrong current password → failure.

- [ ] **Step 5: Operations** — PORO `self.call` returning a Result (mirror the shape used by `app/concepts/member/mfa/operation/*.rb` — read one first and copy its Result idiom). Core:

```ruby
# UpdatePassword core
return failure(...) unless user.valid_password?(params[:current_password])
if user.update(password: ..., password_confirmation: ...)
  ActiveSupport::Notifications.instrument("authentication.event",
    event: "password_changed", user_id: user.id, customer_id: user.customer_id,
    ip: ip, user_agent: user_agent)
  success(user)
end
```

`UpdateEmail` uses plain `user.update(email: new_email)` — with `reconfirmable` on, Devise parks it in `unconfirmed_email` and mails the confirmation link itself.

### Task 3.2: Controller + routes + UI

- [ ] **Step 1: Failing request specs** `spec/requests/member/credentials_spec.rb` — member-only (admin rejected, anonymous redirected); wrong current password → 422 re-render with error flash; successful password change keeps the session signed in (subsequent authenticated GET still 200 — pins the `bypass_sign_in` behavior); successful email change → `unconfirmed_email` set, `email` unchanged, confirmation mail enqueued, redirect with notice.

- [ ] **Step 2: Routes** — inside the member `resource :security` block:

```ruby
        resource :credentials, only: [], controller: "credentials" do
          patch :password
          patch :email
        end
```
Paths: `PATCH /:cid/member/security/credentials/password`, `.../email`.

- [ ] **Step 3: Controller** `app/controllers/member/credentials_controller.rb` — `Member::BaseController` subclass; each action builds the contract, validates, calls the operation, and on success `bypass_sign_in(current_user)` (password change invalidates the session otherwise), `redirect_to member_security_path(current_user.customer_id), notice: t("member.credentials.flash.password_changed")` / `...email_change_requested`. On failure re-render the security show (set the ivars `SecuritiesController#show` sets — extract a shared private method or redirect with `flash[:alert]` + anchored fragment; prefer redirect-with-alert for simplicity, carrying `flash[:credential_errors]` is NOT needed — the flash alert message from the first contract error suffices).

- [ ] **Step 4: UI** — in `member/securities/show.html.erb` password section: replace the link-out with an inline `<details>` (same pattern as the disable-MFA block) containing a `form_tag password_member_security_credentials_path(...), method: :patch` with `current_password`, `password`, `password_confirmation` fields (`input-member` class, labels via `t("member.credentials.labels.*")`). Add a new "Email address" `Member::PageSectionComponent` showing the current email, a pending-`unconfirmed_email` notice when present (`t("member.credentials.pending_email", email: ...)`), and a `<details>` form (`current_password`, `email`) posting to `email_member_security_credentials_path`. Keep the Devise "forgot password" reset link as a secondary line (`t("member.credentials.forgot_link")` → existing `new_user_password_path`).

- [ ] **Step 5: Events** — add `password_changed` + `email_change_requested` to `Authentication::Event::EVENTS` and to the shared `auth.events.*` label tree (en+zh-CN).

- [ ] **Step 6: i18n** — `member.credentials.*` tree (labels, flash, section titles, pending notice, forgot link) en+zh-CN.

- [ ] **Step 7: Verify** — `bundle exec rspec spec/requests/member/credentials_spec.rb spec/concepts/member/credentials spec/requests/member/securities_spec.rb spec/requests/authentication` → green.

---

## Slice 4 — Password strength + common-password screening *(M)*

**Files:**
- Modify: `Gemfile` (+ `gem "zxcvbn", "~> 0.1"` — the pure-Ruby zxcvbn port; run `bundle install`)
- Create: `config/common_passwords.txt` (top ~1000 list, one per line, lowercase)
- Create: `app/services/authentication/password_policy.rb`
- Modify: `app/models/authentication/user.rb` (policy validation)
- Modify: `app/services/authentication/settings.rb` (+ `password_policy_enabled?`, `password_min_score`)
- Modify: `app/services/feature_modules/authentication/registration.rb` (schema + keys)
- Create: `app/controllers/authentication/password_strengths_controller.rb` (+ route)
- Create: `app/javascript/controllers/password_strength_controller.js`
- Modify: the four password-bearing forms (member security password form from slice 3, public registration form, Devise `passwords/edit` view, admin user form — locate under `app/views/authentication/` + `app/views/admin/modules/authentication/users/_form*`)
- Test: `spec/services/authentication/password_policy_spec.rb`, `spec/models/authentication/user_spec.rb` (extend), `spec/requests/authentication/password_strengths_spec.rb`, `spec/javascript/controllers/password_strength_controller.test.js`

### Task 4.1: Policy service (TDD)

- [ ] **Step 1: Failing service spec** — cases: blank → invalid; `"password123"` (in denylist) → invalid `:common`; short (< min length from settings) → invalid `:too_short`; low zxcvbn score < tenant min score → invalid `:weak`; strong passphrase → valid with score. Tenant knobs respected: policy disabled → always valid; min score honored per customer.

- [ ] **Step 2: Service:**

```ruby
# frozen_string_literal: true

module Authentication
  # Central password acceptance policy: offline common-password denylist +
  # zxcvbn strength scoring, tuned per tenant via Authentication::Settings.
  # Wrapped here (single public interface) so the zxcvbn gem can be swapped
  # without touching callers.
  class PasswordPolicy
    Result = Struct.new(:valid?, :score, :error, keyword_init: true)

    COMMON_PASSWORDS_PATH = Rails.root.join("config/common_passwords.txt")

    def self.evaluate(password, customer_id:)
      new(customer_id).evaluate(password)
    end

    def self.score(password)
      Zxcvbn.test(password.to_s).score
    end

    def self.common_passwords
      @common_passwords ||= Set.new(COMMON_PASSWORDS_PATH.readlines(chomp: true).map(&:downcase))
    end

    def initialize(customer_id)
      @settings = Authentication::Settings.for(customer_id)
    end

    def evaluate(password)
      return Result.new(valid?: true, score: nil) unless @settings.password_policy_enabled?
      return Result.new(valid?: false, score: 0, error: :too_short) if password.to_s.length < @settings.min_password_length
      return Result.new(valid?: false, score: 0, error: :common) if self.class.common_passwords.include?(password.to_s.downcase)

      score = self.class.score(password)
      return Result.new(valid?: false, score: score, error: :weak) if score < @settings.password_min_score

      Result.new(valid?: true, score: score)
    end
  end
end
```
(`min_password_length` reader arrives in slice 8's Settings extension — for this slice add `password_policy_enabled?` (default true), `password_min_score` (default 2), and `min_password_length` (default 8) readers to `Authentication::Settings` + schema now; slice 8 adds the remaining knobs.)

- [ ] **Step 3: Denylist file** — generate `config/common_passwords.txt` with the classic top-1000 leaked-password list (write from knowledge: `123456`, `password`, `qwerty`, … one per line, lowercase, deduped). Keep it plain ASCII.

- [ ] **Step 4: User validation** — in `Authentication::User`:

```ruby
validate :password_meets_policy, if: -> { password.present? }

def password_meets_policy
  result = Authentication::PasswordPolicy.evaluate(password, customer_id: customer_id)
  return if result.valid?

  errors.add(:password, I18n.t("auth.password_policy.errors.#{result.error}"))
end
```
i18n: `auth.password_policy.errors.{too_short,common,weak}` en+zh-CN (en for `too_short` must interpolate the tenant minimum: "is too short (minimum %{count} characters)" — pass `count:`).
**Watch out:** factories/seeds use passwords like `password123` — set factory passwords to a strong constant (e.g. `Sup3r-Str0ng-Passw0rd!42`) in one shared place rather than weakening the policy. Run the full auth + member spec subset after.

### Task 4.2: Strength endpoint + Stimulus meter

- [ ] **Step 1: Failing request spec** — `POST /:cid/auth/password_strength` with `{password: "..."}` returns JSON `{score: 0..4, label: <translated>}`; throttled per-IP via `Authentication::Throttle` (assert 429 after limit, reuse the throttle-reset spec helper `rate_limit_reset.rb`); anonymous allowed (public auth surface); no record persisted.

- [ ] **Step 2: Route** (public auth scope, next to the MFA routes):

```ruby
      resource :password_strength, only: :create, controller: "authentication/password_strengths"
```

- [ ] **Step 3: Controller** — skip CSRF is NOT needed (same-origin form fetch sends the token; pass it in JS). Evaluate via `Authentication::PasswordPolicy.score`, look up label `t("auth.password_strength.levels.l#{score}")`, respond JSON. Throttle exactly like `EmailFloodThrottled`'s per-IP arm (reuse `Authentication::Throttle`).

- [ ] **Step 4: Vitest first** `spec/javascript/controllers/password_strength_controller.test.js` — cover: debounce (fake timers), empty input clears meter, fetch success renders width/label/color for each score 0–4 (branch per level), fetch failure hides the meter (no crash), abort of in-flight request on re-input, CSRF token header read from meta tag, missing meta tag branch.

- [ ] **Step 5: Controller JS** `app/javascript/controllers/password_strength_controller.js` — targets: `input`, `bar`, `label`; values: `url: String`, `labels: Object` (score→translated label map, English defaults inline), `errorLabel: String`. Debounced (300 ms) POST `{password}`; render bar width `(score+1)*20%` + tone classes; all user-visible text from values. 100% lines+branches.

- [ ] **Step 6: Wire into forms** — mount on the password fields in: member security password form (slice 3), public registration form, Devise password-reset edit form, admin user form. Server passes `data-password-strength-url-value` + `-labels-value` (`t("auth.password_strength.levels").to_json`).

- [ ] **Step 7: Verify** — targeted rspec files + `npx vitest run --coverage` (touched file 100%/100%).

---

## Slice 5 — Active session / device management *(M/L)*

**Files:**
- Create: migration `create_authentication_sessions`
- Create: `app/models/authentication/user_session.rb`
- Create: `app/controllers/concerns/authentication/session_registry.rb` (issue on sign-in, enforce + touch per request, revoke on sign-out)
- Modify: `app/controllers/authentication/sessions_controller.rb`, `app/controllers/authentication/customer_resolutions_controller.rb` (issue after `sign_in`), `ApplicationController` (include enforcement), Devise sign-out path (revoke)
- Modify: `Gemfile` (+ `gem "device_detector", "~> 1.1"`)
- Create: `app/controllers/member/security_sessions_controller.rb` + view + routes
- Create: `app/components/member/session_list_component.rb` + `.html.erb`
- Modify: admin user `show.html.erb` + `UsersController#show` (read-only active sessions)
- Modify: `app/models/authentication/event.rb` (EVENTS += `session_revoked`), locales
- Test: model spec, `spec/requests/member/security_sessions_spec.rb`, enforcement request spec, sign-in-creates-record extension to existing session specs

### Task 5.1: Table + model (TDD)

- [ ] **Step 1: Migration:**

```ruby
class CreateAuthenticationSessions < ActiveRecord::Migration[8.1]
  def change
    create_table :authentication_sessions do |t|
      t.integer  :customer_id, null: false
      t.integer  :user_id,     null: false
      t.string   :token_digest, null: false
      t.string   :ip
      t.string   :user_agent
      t.datetime :last_seen_at, null: false
      t.datetime :revoked_at
      t.timestamps
    end
    add_index :authentication_sessions, :token_digest, unique: true
    add_index :authentication_sessions, %i[customer_id user_id]
  end
end
```

- [ ] **Step 2: Model spec** — `issue!` returns `[record, raw]`, persists digest not raw, sets tenant from user; `authenticate(user:, raw_token:)` nil on blank/foreign-tenant/revoked, bumps `last_seen_at` at most once per minute; `revoke!` idempotent; `revoke_all_for(user, except:)` spares the given record and foreign tenants untouched; `active` scope excludes revoked.

- [ ] **Step 3: Model** `Authentication::UserSession` — mirror `TrustedDevice` exactly (digest_for/issue!/authenticate) plus:

```ruby
scope :active, -> { where(revoked_at: nil) }

TOUCH_INTERVAL = 1.minute

def revoke!
  update_column(:revoked_at, Time.current) if revoked_at.nil?
end

def self.revoke_all_for(user, except: nil)
  active.where(customer_id: user.customer_id, user_id: user.id)
        .where.not(id: except&.id)
        .update_all(revoked_at: Time.current)
end

def display_name
  client = DeviceDetector.new(user_agent.to_s)
  [client.name, client.os_name].compact_blank.join(" · ")
end
```
`authenticate` returns nil when `revoked_at` present (query `active`), touches `last_seen_at` only when staler than `TOUCH_INTERVAL` (avoid a write per request).

### Task 5.2: Registry concern — issue / enforce / revoke

- [ ] **Step 1: Failing request specs** — after password sign-in a `UserSession` row exists and `session[:auth_session_token]` set; a request with a revoked record signs the user out (redirect to sign-in with `t("auth.flash.session_revoked")` alert); pre-feature sessions (no token in session) are left alone; Devise sign-out revokes the record.

- [ ] **Step 2: Concern** `app/controllers/concerns/authentication/session_registry.rb`:

```ruby
# frozen_string_literal: true

module Authentication
  # Central session-record lifecycle: issue on sign-in, enforce + touch per
  # request, revoke on sign-out. Sessions signed in before this feature have
  # no token in the Rails session and are exempt from enforcement (they die
  # via Devise timeoutable instead).
  module SessionRegistry
    extend ActiveSupport::Concern

    SESSION_KEY = :auth_session_token

    included do
      before_action :enforce_session_registry!, if: :user_signed_in?
    end

    def register_user_session!(user)
      record, raw = Authentication::UserSession.issue!(
        user: user, ip: request.remote_ip, user_agent: request.user_agent
      )
      session[SESSION_KEY] = raw
      record
    end

    def revoke_user_session!
      raw = session.delete(SESSION_KEY)
      return if raw.blank? || current_user.nil?

      Authentication::UserSession.active.find_by(
        customer_id: current_user.customer_id, user_id: current_user.id,
        token_digest: Authentication::UserSession.digest_for(raw)
      )&.revoke!
    end

    def current_user_session
      raw = session[SESSION_KEY]
      return nil if raw.blank? || current_user.nil?

      Authentication::UserSession.authenticate(user: current_user, raw_token: raw)
    end

    private

    def enforce_session_registry!
      raw = session[SESSION_KEY]
      return if raw.blank?                    # pre-feature session
      return if current_user_session.present? # live record — touched inside authenticate

      cid = current_user.customer_id
      sign_out(current_user)
      redirect_to new_user_session_path(customer_id: cid),
                  alert: t("auth.flash.session_revoked")
    end
  end
end
```

- [ ] **Step 3: Wire** — `include Authentication::SessionRegistry` in `ApplicationController`; call `register_user_session!(user)` right after each `sign_in` in `Authentication::SessionsController` + `CustomerResolutionsController` (and MFA-session controller if it is the point that completes login — read the flow first: the record must be issued exactly once per login, AFTER the final `sign_in` that establishes the session). Hook `revoke_user_session!` into sign-out: override `destroy` in `Authentication::SessionsController` (call before `super`) — check how sign-out is routed first (`devise_for` sessions controller `destroy`).

- [ ] **Step 4: Run enforcement/sign-in specs** → green. Also re-run the whole `spec/requests/authentication` set (login-path change → wide blast radius).

### Task 5.3: Member sessions UI + admin read-only

- [ ] **Step 1: Failing request specs** `spec/requests/member/security_sessions_spec.rb` — index lists only own active sessions (cross-user/cross-tenant rows excluded); current session badged; `DELETE .../sessions/:id` revokes own row (and instruments `session_revoked`), foreign row → 404; `DELETE .../sessions/others` revokes all but current; revoking the CURRENT session signs out.

- [ ] **Step 2: Routes** (member security block):

```ruby
        resources :sessions, only: %i[index destroy], controller: "security_sessions", path: "security/sessions" do
          collection { delete :others }
        end
```
(Place inside the member namespace at the same level as `resource :security`; nesting under a singular `resource` breaks `resources` path helpers — use the explicit `path:` form above.)

- [ ] **Step 3: Controller** `Member::SecuritySessionsController` — index: `@sessions = Authentication::UserSession.active.where(customer_id: current_user.customer_id, user_id: current_user.id).order(last_seen_at: :desc)`; `@current_session = current_user_session`. destroy: find within that same scope (`find` → 404 on miss, satisfying `authorize_owned!` semantics), `revoke!`, instrument `session_revoked`; if it was the current session, `sign_out` + redirect to sign-in, else redirect back with notice. `others`: `revoke_all_for(current_user, except: current_user_session)`, notice.

- [ ] **Step 4: Component + view** — `Member::SessionListComponent.new(sessions:, current_session:)`: rows with `display_name`, IP (mono), `last_seen_at` relative time, "This device" success-badge for the current row, per-row revoke button (`button_to`, method: :delete, danger ghost). View mirrors slice 1's page (PageLayout/PageHeader/PageSection + "Sign out other devices" `button_to` on the header). Link from the securities show page + slice 1's aside.

- [ ] **Step 5: Admin read-only** — `UsersController#show`: `@active_sessions = Authentication::UserSession.active.where(customer_id: current_customer_id, user_id: @user.id).order(last_seen_at: :desc).limit(10)`; render a plain table section on the show view (admin styling; no revoke buttons). i18n keys under `admin_modules.users.sessions.*`.

- [ ] **Step 6: i18n** — `member.security_sessions.*` (title, subtitle, this_device, revoke, revoke_others, revoked_flash, revoked_current_flash, empty) + `auth.flash.session_revoked` + `auth.events.session_revoked` en+zh-CN.

- [ ] **Step 7: Verify** — targeted member + authentication request specs, model spec → green.

---

## Slice 6 — Sign-in alert emails *(M)*

**Files:**
- Modify: `app/services/feature_modules/authentication/registration.rb` (schema + keys: `sign_in_alerts_enabled`, boolean, default true)
- Modify: `app/services/authentication/settings.rb` (+ `sign_in_alerts_enabled?`)
- Create: `app/services/authentication/sign_in_alert.rb`
- Create: `app/jobs/authentication/sign_in_alert_job.rb`
- Modify: the two sign-in controllers (invoke after `register_user_session!`)
- Modify: locales (`auth.*` mail subject/body keys, en+zh-CN)
- Test: `spec/services/authentication/sign_in_alert_spec.rb`, `spec/jobs/authentication/sign_in_alert_job_spec.rb`, request-level assertion in the sessions specs

### Task 6.1: Detection + delivery (TDD)

- [ ] **Step 1: Failing service specs** — known device (an earlier `UserSession` row with the same IP for this user, or an active `TrustedDevice`) → no-op; first-ever session for the user → no-op (account's very first login should not alert — guard: any prior session rows exist); new IP + prior history → enqueues job; toggle off → no-op; Email module inactive for the tenant → no-op (check how the Email module exposes "active for tenant" — grep `FeatureModules::CustomerAssignment` usage in `Email::Gateway` / `Emails::` and reuse that predicate); gateway raise inside the JOB is rescued + logged (never bubbles).

- [ ] **Step 2: Service:**

```ruby
# frozen_string_literal: true

module Authentication
  # Decides whether a just-established session is "new device" and enqueues
  # the alert mail. Failure-isolated: any error here must never break login.
  class SignInAlert
    def self.call(user:, session_record:)
      new(user, session_record).call
    rescue StandardError => e
      Rails.logger.warn("[auth.alert] sign-in alert skipped: #{e.class}: #{e.message}")
      nil
    end

    def initialize(user, session_record)
      @user = user
      @record = session_record
    end

    def call
      return unless Authentication::Settings.for(@user.customer_id).sign_in_alerts_enabled?
      return unless email_module_active?
      return if known_device?

      Authentication::SignInAlertJob.perform_later(@record.id)
    end
    ...
  end
end
```
`known_device?`: prior (`where.not(id: @record.id)`) sessions exist AND (`sessions with same ip exist` OR active trusted device rows exist for the user matching... trusted devices are not IP-bound — treat ANY active trusted device as known only if the design intent is "don't alert users who opted into trust"; implement: alert iff prior sessions exist AND no prior session shares the IP AND no active trusted device). First login (no prior sessions) → known (no alert).

- [ ] **Step 3: Job** — loads the session record (+user), builds subject/body from i18n (`I18n.with_locale` of the user's stored locale preference if the user model has one — grep `locale` on the user/customer; else default), sends via `Email::Gateway.send_raw(...)` — read `app/services/email/gateway.rb` first for the exact signature (`send_raw(customer:/customer_id:, to:, subject:, body_html:, ...)`) and the suppression/cap semantics; rescue-log any error. Body: plain informative HTML — time, IP, device (`UserSession#display_name`), "wasn't you? change your password" link to the member security page.

- [ ] **Step 4: Trigger** — in both sign-in controllers, right after `register_user_session!(user)`: `Authentication::SignInAlert.call(user: user, session_record: record)`.

- [ ] **Step 5: i18n** — `auth.sign_in_alert.{subject,heading,body_html,ip,device,time,not_you_html}` en+zh-CN.

- [ ] **Step 6: Verify** — service + job + sessions request specs green.

---

## Slice 7 — Admin force-password-reset + manual unlock *(S each)*

**Files:**
- Modify: `config/routes.rb` (admin users sub-resources)
- Create: `app/controllers/admin/modules/authentication/users/password_resets_controller.rb`, `users/unlocks_controller.rb`
- Modify: admin user `show.html.erb` (action buttons)
- Modify: `app/models/authentication/event.rb` (EVENTS += `account_unlocked`), locales
- Test: `spec/requests/admin/modules/authentication/user_password_resets_spec.rb`, `user_unlocks_spec.rb`

### Task 7.1: Both endpoints (TDD)

- [ ] **Step 1: Failing request specs** — for each endpoint: admin on own-tenant user → 302 + flash + effect (reset mail enqueued / `locked_at` cleared) + `Authentication::Event` row (`password_reset_requested` with `metadata: {admin_initiated: true, actor_id: ...}` / `account_unlocked`); target is the pinned owner + actor is non-owner admin → blocked by `protect_owner_account!` (assert the existing flash key `admin_modules.flash.users.owner_account_protected`); cross-tenant user id → 404; member → rejected; anonymous → redirect.

- [ ] **Step 2: Routes:**

```ruby
resources :users do
  member { get :events }
  scope module: :users do
    resource :password_reset, only: :create
    resource :unlock,         only: :create
  end
end
```

- [ ] **Step 3: Controllers** — thin; both `include ::Authentication::OwnerAccountProtectable`, `before_action :find_user` (tenant-scoped, copy the finder), `before_action :protect_owner_account!`. PasswordResets#create: `@user.send_reset_password_instructions`, instrument `password_reset_requested` (metadata `admin_initiated: true, actor_id: current_user.id`), redirect to user show with `t("admin_modules.flash.users.reset_sent", name: ...)`. Unlocks#create: `@user.unlock_access!`, instrument `account_unlocked` (same metadata shape), redirect with `t("admin_modules.flash.users.unlocked", name: ...)`.
  (`protect_owner_account!` reads `@user` — verify the concern's target-ivar contract in `app/controllers/concerns/authentication/owner_account_protectable.rb` first and conform.)

- [ ] **Step 4: Buttons** on admin user show — "Send password reset" always; "Unlock account" only when `@user.access_locked?`; `button_to` POST, admin button styles, confirm dialog via the app's existing confirm pattern (grep `data: { turbo_confirm` usage). Labels via i18n.

- [ ] **Step 5: i18n** — `admin_modules.users.actions.{send_reset,unlock}`, `admin_modules.flash.users.{reset_sent,unlocked}` + `auth.events.account_unlocked` en+zh-CN.

- [ ] **Step 6: Verify** — both request spec files green.

---

## Slice 8 — Per-tenant password policy knobs + wire the dead config keys *(S/M)*

**Files:**
- Modify: `app/services/feature_modules/authentication/registration.rb` (schema: `min_password_length` number default 8, `require_complexity` boolean default false; keys list; plus the slice-4/6 keys if not yet merged)
- Modify: `app/services/authentication/settings.rb` (readers: `session_timeout_minutes`, `max_login_attempts`, `min_password_length`, `require_complexity?`)
- Modify: `app/services/authentication/password_policy.rb` (complexity arm)
- Modify: `app/models/authentication/user.rb` (`timeout_in`, lockable threshold override)
- Modify: `app/views/admin/module_configs/show.html.erb` render path — description i18n fallback (implements design item I18N-5 generically)
- Test: extend settings/policy/user specs; lockable + timeout request-level specs

### Task 8.1: Settings readers + policy complexity (TDD)

- [ ] **Step 1: Failing specs** — `Settings` returns configured values, falls back to schema defaults when unset/blank, clamps nonsense (`0`/negative/non-numeric → default); `PasswordPolicy` with `require_complexity` on rejects a long all-lowercase password (`:complexity`), accepts mixed-case+digit.

- [ ] **Step 2: Settings readers:**

```ruby
    def session_timeout_minutes = positive_number(config["session_timeout"], default: 30)
    def max_login_attempts      = positive_number(config["max_login_attempts"], default: 10)
    def min_password_length     = positive_number(config["min_password_length"], default: 8)
    def require_complexity?     = module_active? && bool(config["require_complexity"], default: false)

    private

    def positive_number(value, default:)
      n = value.to_i
      n.positive? ? n : default
    end
```

- [ ] **Step 3: Policy complexity arm** — after the length check: `return Result.new(valid?: false, score: 0, error: :complexity) if @settings.require_complexity? && !password.match?(/\A(?=.*[a-z])(?=.*[A-Z])(?=.*\d).*\z/m)`; i18n `auth.password_policy.errors.complexity` en+zh-CN.

### Task 8.2: Wire `session_timeout` + `max_login_attempts` (TDD)

- [ ] **Step 1: Failing specs** — model: `user.timeout_in` reflects the tenant config; lockable: with tenant `max_login_attempts: 3`, the 3rd failed login locks (`access_locked?` true) while the Devise class default is 10. Request-level: idle session past the tenant timeout is signed out (use `travel_to`).

- [ ] **Step 2: Overrides** in `Authentication::User`:

```ruby
    # Devise timeoutable consults this per record — tenant-tunable.
    def timeout_in
      Authentication::Settings.for(customer_id).session_timeout_minutes.minutes
    end

    # Devise lockable's attempts_exceeded? uses this — tenant-tunable.
    def maximum_attempts
      Authentication::Settings.for(customer_id).max_login_attempts
    end

    private :maximum_attempts  # only if Devise's attempts_exceeded? calls it on the instance —
                               # READ Devise 5's lockable source first; if it uses
                               # self.class.maximum_attempts, override attempts_exceeded? instead:
    # def attempts_exceeded?
    #   failed_attempts >= Authentication::Settings.for(customer_id).max_login_attempts
    # end
```
Check `Devise::Models::Lockable#attempts_exceeded?` in the installed gem (`bundle show devise`) and pick the correct override; pin with the spec either way.

- [ ] **Step 3: Config-page description i18n fallback** — where the generic module-config page renders `schema["description"]`, wrap: `t("feature_modules.#{@module_key}.config.#{key}", default: schema["description"])`; add `feature_modules.authentication.config.*` translations for ALL five authentication schema keys (en = byte-identical to the schema strings; zh-CN idiomatic). This closes I18N-5 for authentication without breaking other modules (they fall back to their English descriptions).

- [ ] **Step 4: Verify** — settings/policy/user/lockable/timeout specs + `spec/requests/admin/module_configs_spec.rb` green.

---

## Slice 9 — Passkeys / WebAuthn *(L, isolated)*

**Files:**
- Modify: `Gemfile` (+ `gem "webauthn", "~> 3.4"`)
- Create: migration `create_authentication_credentials`
- Create: `app/models/authentication/credential.rb`
- Create: `app/services/authentication/webauthn_relying_party.rb`
- Create: `app/controllers/member/security_passkeys_controller.rb` (+ member routes: index/options/create/destroy)
- Create: `app/controllers/authentication/passkey_sessions_controller.rb` (+ public routes: options/create)
- Create: `app/javascript/lib/webauthn_codec.js`, `app/javascript/controllers/webauthn_register_controller.js`, `app/javascript/controllers/webauthn_login_controller.js`
- Modify: sign-in view (passkey button), member security show (passkeys section link), member passkeys view
- Modify: `app/models/authentication/event.rb` (EVENTS += `passkey_registered passkey_removed`), locales
- Test: model/wrapper specs, `spec/requests/member/security_passkeys_spec.rb`, `spec/requests/authentication/passkey_sessions_spec.rb` (use `WebAuthn::FakeClient`), vitest suites for all three JS files

### Task 9.1: Table, model, relying-party wrapper (TDD)

- [ ] **Step 1: Migration:**

```ruby
class CreateAuthenticationCredentials < ActiveRecord::Migration[8.1]
  def change
    create_table :authentication_credentials do |t|
      t.integer :customer_id, null: false
      t.integer :user_id,     null: false
      t.string  :webauthn_id, null: false
      t.text    :public_key,  null: false
      t.bigint  :sign_count,  null: false, default: 0
      t.string  :nickname,    null: false
      t.datetime :last_used_at
      t.timestamps
    end
    add_index :authentication_credentials, :webauthn_id, unique: true
    add_index :authentication_credentials, %i[customer_id user_id]
  end
end
```

- [ ] **Step 2: Model** — `belongs_to :user, class_name: "Authentication::User"`; validates presence + nickname uniqueness per user; `scope :for_user`.

- [ ] **Step 3: Wrapper spec then wrapper** `Authentication::WebauthnRelyingParty` — single public interface over the `webauthn` gem (AGENTS.md library-wrapper rule):

```ruby
# frozen_string_literal: true

module Authentication
  # Thin app-level wrapper around the webauthn gem (single public interface so
  # the gem can be swapped without touching callers). Relying party identity is
  # derived from the request (self-hosted, offline).
  class WebauthnRelyingParty
    def self.for(request)
      new(WebAuthn::RelyingParty.new(
        origin: request.base_url,
        id:     request.host,
        name:   "Anysys"
      ))
    end

    def initialize(rp) = @rp = rp

    def registration_options(user:, exclude: [])
      @rp.options_for_registration(
        user: { id: WebAuthn.generate_user_id, name: user.email, display_name: user.display_name },
        exclude: exclude,
        authenticator_selection: { user_verification: "preferred", resident_key: "preferred" }
      )
    end

    def verify_registration(response:, challenge:)
      @rp.verify_registration(response, challenge, user_presence: true)
    end

    def authentication_options(allow: [])
      @rp.options_for_authentication(allow: allow, user_verification: "preferred")
    end

    def verify_authentication(response:, challenge:, credential:)
      @rp.verify_authentication(response, challenge, public_key: credential.public_key,
                                                     sign_count: credential.sign_count)
    end
  end
end
```
(Adapt exact method names to the installed webauthn 3.x API — read the gem README via `bundle show webauthn` first; specs with `WebAuthn::FakeClient` pin the real behavior. "Anysys" name: route through i18n default? RP name is shown by the BROWSER, not our UI — a constant is acceptable; use the app name constant if one exists.)

### Task 9.2: Member passkey management (TDD)

- [ ] **Step 1: Failing request specs** (`WebAuthn::FakeClient.new(origin)`): options → 200 JSON with challenge (stored in session) excluding existing credentials; create with fake-client attestation → credential row (tenant-scoped, nickname required, instruments `passkey_registered`); duplicate webauthn_id → 422; destroy own → gone + `passkey_removed`; destroy other user's/tenant's → 404; admin/anonymous rejected on all.

- [ ] **Step 2: Routes** (member namespace, beside the sessions routes):

```ruby
        resources :passkeys, only: %i[index create destroy], controller: "security_passkeys", path: "security/passkeys" do
          collection { post :options }
        end
```

- [ ] **Step 3: Controller** — options: build `registration_options` (exclude existing ids), `session[:webauthn_registration_challenge] = options.challenge`, render `options` JSON (gem objects respond to `as_json` in browser-consumable shape). create: verify, persist (`webauthn_id: verified.id, public_key: verified.public_key, sign_count: verified.sign_count`, nickname from params, tenant from current_user), instrument; rescue `WebAuthn::Error` → 422 JSON with translated message. destroy: scoped find → `authorize_owned!` semantics → destroy + instrument.

- [ ] **Step 4: View + component** — passkeys index page (PageLayout, list rows: nickname, created, last used, delete button; "Add a passkey" form: nickname input + button mounting `webauthn-register` Stimulus controller with values: options-url, create-url, error messages map, success redirect). Link from securities show (new PageSection "Passkeys").

### Task 9.3: Passkey login (TDD)

- [ ] **Step 1: Failing request specs** — options (POST email+customer_id): known user → allow-list of that user's credentials + challenge in session; unknown email → SAME-SHAPE response with empty allow list (paranoid — no enumeration), never 404. create: fake-client assertion → signed in (session established, `UserSession` row via `register_user_session!`, `session[:mfa_verified]` true, `sign_count` bumped, `last_used_at` touched, `login_succeeded` event with `metadata: {method: "passkey"}`); wrong-tenant credential → rejected; sign-count regression → rejected (gem raises) → 422 + `login_failed` event; deactivated user → rejected via the standard `active_for_authentication?` path.

- [ ] **Step 2: Routes** (public auth scope):

```ruby
      resource :passkey_session, only: :create, controller: "authentication/passkey_sessions", path: "passkey" do
        post :options, on: :collection
      end
```

- [ ] **Step 3: Controller** — mirrors the password `SessionsController`'s post-auth sequence exactly (session-fixation `reset_session`, `sign_in`, `register_user_session!`, `SignInAlert`, audit, redirect to the role home path); passkey satisfies MFA (`session[:mfa_verified] = true`). Find credential by `webauthn_id` **scoped to the resolved customer_id**; user via the credential. Throttle per-IP like the other auth endpoints.

- [ ] **Step 4: JS** — `lib/webauthn_codec.js` (base64url ⇄ ArrayBuffer, pure functions — trivially 100%); `webauthn_register_controller.js` (fetch options → decode → `navigator.credentials.create` → encode → POST create → redirect/error target); `webauthn_login_controller.js` (same for `get`; hide mount when `!window.PublicKeyCredential`). All text via values with English defaults. Vitest: mock `fetch` + `navigator.credentials`; cover every branch (missing support, options failure, user-abort DOMException, create failure, server 422, success).

- [ ] **Step 5: Sign-in view** — "Sign in with a passkey" secondary button under the password form, mounting the login controller (server passes URLs + translated strings).

- [ ] **Step 6: Verify** — all slice-9 rspec + `npx vitest run --coverage` (three files 100%/100%).

---

## Final gate (after slice 9)

- [ ] `bin/rails parallel:spec` — full suite green (known flaky: JS drawer spec, auth passwords_spec under parallel — re-run in isolation before judging).
- [ ] `npx vitest run --coverage` — 100% lines+branches on all touched JS.
- [ ] i18n parity check: every new key present in both en and zh-CN with matching interpolations (grep the new trees in both files).
- [ ] Real-browser smoke (SKIP_AUTH off — auth flows need real sessions): sign in, member security page (activity teaser, sessions list, passkey add UI renders), admin user show (events link, reset/unlock buttons), strength meter renders on registration form. `rm -f public/assets/.manifest.json && SKIP_AUTH=1 bin/rails server -b 0.0.0.0 -p 3000` for the admin surfaces; screenshot per verify-ui memory.
- [ ] anysys-tech-lead + anysys-code-reviewer on the accumulated diff; fix findings.
- [ ] NOTHING committed — leave the working tree for user review.
