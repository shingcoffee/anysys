# Devise 5.0.x Upgrade Adoption

**Status:** Draft — awaiting user review
**Date:** 2026-05-12
**Scope:** Adopt every change, enhancement, and recommended configuration introduced by Devise between 4.9.4 and 5.0.4 that applies to this app.

---

## 1. Goal

The `Gemfile` was bumped from `~> 4.9` to `~> 5.0` (lockfile pinned to `5.0.4`). The app's custom auth layer already avoided the 5.0 breaking removals (no `devise_error_messages!`, no `sign_in(..., bypass: true)`, no `Devise::TestHelpers`). This spec closes the remaining gap: adopt the 5.0.x enhancements, recommended config, view/copy updates, security-fix verification, and new resource-level override hooks, along with full RSpec coverage of every touched surface.

**Out of scope** (deliberately): enabling Devise modules the app does not currently use (`:confirmable`, `:timeoutable`, `:omniauthable`). Those are product decisions, not upgrade adoption.

## 2. Source of truth

From the Devise 5.0.4 gem's `CHANGELOG.md` (local copy at `~/.rbenv/versions/3.2.8/lib/ruby/gems/3.2.0/gems/devise-5.0.4/CHANGELOG.md`), the deltas from 4.9.4 are:

| # | Change | Applies? | Reason |
|---|--------|----------|--------|
| 1 | `config.responder.error_status = :unprocessable_content` recommended for Rack 3.1+ | Yes | Lockfile pins `rack 3.2.6`. App currently uses `:unprocessable_entity`. |
| 2 | `Devise.secret_key` derives only from `application.secret_key_base` | Verify | App never set a custom `Devise.secret_key`. Pre-production, so no in-flight tokens at risk. |
| 3 | Proc-based `password_length` validator (runtime-overridable) | Yes | Seam for future per-tenant policy. |
| 4 | Resource-scoped `sign_in_after_change_password` override (5.0.2) | Yes | Expose hook on `Authentication::User`. |
| 5 | `sign_in_after_reset_password?` hook in `PasswordsController` (5.0.2) | Yes | Override in custom controller. |
| 6 | View partial: `[data-turbo-cache=false]` → `[data-turbo-temporary]` | Yes | Applies to flash blocks in our Tailwind `_auth_card.html.erb`. |
| 7 | Form layout: `<br>` → `<p>` | N/A | App's custom Tailwind views don't use `<br>`. Verified during audit. |
| 8 | Button label: "Send me reset password instructions" → "Send me password reset instructions" | Yes | Update `passwords/new.html.erb`. |
| 9 | Grammar fix: "Invalid Email or password" → "Invalid email or password"; German `E-Mail` translation fix (5.0.1) | Yes | Install `config/locales/devise.en.yml` (from gem defaults) and correct the hard-coded flash argument in `SessionsController#create`. |
| 10 | CVE-2026-40295 (FailureApp `Referer` open redirect on non-GET session timeout, 5.0.4) | Regression guard | Covered by gem bump. Add a spec to prevent regression. |
| 11 | CVE-2026-32700 (Confirmable race, 5.0.3) | N/A | No `:confirmable` module. |
| 12 | Rails 8 support / lazy-loaded routes in test/dev | Covered | App is on Rails 8.1.2. Suite must stay green. |
| 13 | Ruby 3.4/4.0 support, Mongoid support | N/A | Ruby 3.2.8, ActiveRecord. |

## 3. Architecture

No new units introduced. Changes fall across existing boundaries:

### 3.1 Config
`config/initializers/devise.rb`
- Change `config.responder.error_status = :unprocessable_entity` → `:unprocessable_content`.
- No change to `redirect_status` (already `:see_other`).
- No change to `secret_key` (relies on `application.secret_key_base`, which matches 5.0 behavior).

### 3.2 Model hooks
`app/models/authentication/user.rb` — add two class-level overrides, each deliberately returning the Devise default so they form a documented seam for future per-tenant policy:

```ruby
# Runtime-overridable (Devise 5.0): allows per-tenant policy later.
def self.password_length
  Devise.password_length
end

# Devise 5.0.2 resource-scoped hook.
def self.sign_in_after_change_password?
  Devise.sign_in_after_change_password
end
```

### 3.3 Controller hook
`app/controllers/authentication/passwords_controller.rb` — override the new 5.0.2 hook:

```ruby
protected

def sign_in_after_reset_password?
  Devise.sign_in_after_reset_password
end
```

### 3.4 Views
- `app/views/authentication/shared/_auth_card.html.erb`: add `data-turbo-temporary` on both flash blocks (alert + notice).
- `app/views/authentication/passwords/new.html.erb`: update submit button copy from the 4.x wording to the 5.0 wording.

### 3.5 Locales
New file: `config/locales/devise.en.yml`, a copy of Devise 5.0.4's `config/locales/en.yml`. Kept under `config/locales/` so Rails auto-loads it after the gem's copy, letting us (a) pick up the 5.0 grammar and translation fixes, (b) form a clean home for future copy overrides. A header comment documents the source and load-order intent.

### 3.6 Sessions controller string fix
`app/controllers/authentication/sessions_controller.rb:47` currently does:
```ruby
flash.now[:alert] = I18n.t("devise.failure.invalid", authentication_keys: "Email")
```
Change `"Email"` → `"email"` so the user-facing flash reads `"Invalid email or password."` per the 5.0 grammar correction.

## 4. Data flow / behavioral changes

1. HTTP failure responses from Devise-derived controllers change reason phrase `Unprocessable Entity` → `Unprocessable Content`. Rails 8.1 aliases both symbols, so call sites using `:unprocessable_entity` across the codebase continue to work unchanged.
2. Invalid-credentials flash changes to lowercase email.
3. Password-reset button copy updates.
4. Override hooks from 3.2/3.3 become available. Behavior is identical to before until someone overrides them.

No schema migration. No data backfill.

## 5. Error handling & edge cases

- **Token invalidation risk** (item #2): mitigated by the fact that this is a pre-production app per `AGENTS.md`. Documented here for traceability. No action.
- **Locale precedence**: Rails I18n merges all loaded files; the later-loaded (ours) wins on conflicting keys. Confirmed by a spec (see §6.5).
- **`:unprocessable_content` on Rack < 3.1**: not applicable — lockfile pins 3.2.6.
- **Existing specs asserting `status: :unprocessable_entity`**: continue to pass via Rack/Rails symbol aliasing. Verified by suite run.

## 6. Testing strategy — full coverage for every touched surface

Every file touched gets spec coverage. Existing specs stay; new specs below are added.

### 6.1 Config spec — `spec/config/devise_initializer_spec.rb` (new)
- `Devise.responder.error_status == :unprocessable_content`
- `Devise.responder.redirect_status == :see_other`
- `Devise.password_length == (8..128)`
- `Devise.authentication_keys == [:email]`
- `Devise.case_insensitive_keys == [:email]`
- `Devise.strip_whitespace_keys == [:email]`
- `Devise.stretches == 1` in test env
- `Devise.reconfirmable == false`
- `Devise.expire_all_remember_me_on_sign_out == true`
- `Devise.maximum_attempts == 10`
- `Devise.unlock_in == 30.minutes`
- `Devise.reset_password_within == 6.hours`
- `Devise.sign_out_via == :delete`
- `Devise.skip_session_storage == [:http_auth]`

### 6.2 Model spec — `spec/models/authentication/user_spec.rb` (extend existing)
New test cases added to the existing file, grouped under new `describe` blocks:

- `.password_length` returns `Devise.password_length` and is overridable (stub-and-verify).
- `.sign_in_after_change_password?` returns `Devise.sign_in_after_change_password` and is overridable.
- Existing `find_for_database_authentication` / validation / role / MFA specs remain untouched.

### 6.3 Sessions request spec — `spec/requests/authentication/sessions_spec.rb` (new or extend)
- `GET /:cid/auth/sign_in` renders 200.
- `POST /:cid/auth/sign_in` with valid credentials redirects and sets session.
- `POST /:cid/auth/sign_in` with invalid credentials: response status 422, body contains `"Invalid email or password"` (lowercase — grammar fix assertion).
- `POST /:cid/auth/sign_in` with unknown customer_id: renders sign-in with alert "Invalid customer number", status 422.
- `POST /:cid/auth/sign_in` when auth module disabled: redirects to dashboard.
- `DELETE /:cid/auth/sign_out`: clears session and redirects to sign-in.
- **CVE-2026-40295 regression**: `DELETE /:cid/auth/sign_out` with `Referer: https://evil.example.com/pwn` — response location header must be same-origin (never `evil.example.com`).

### 6.4 Passwords request spec — `spec/requests/authentication/passwords_spec.rb` (new)
- `GET /:cid/auth/password/new` renders 200 and body contains the new button label `"Send me password reset instructions"`.
- `POST /:cid/auth/password` with known email enqueues the reset mailer and redirects to sign-in.
- `POST /:cid/auth/password` with unknown email still redirects to sign-in (paranoid mode not enabled — asserts current behavior).
- `GET /:cid/auth/password/edit?reset_password_token=…` with a valid token renders 200.
- `PATCH /:cid/auth/password` with valid token + matching confirmation updates password and redirects per `after_resetting_password_path_for`.
- `sign_in_after_reset_password?` hook: stub to `false` → assert user is not signed in after reset (expectation: redirected to sign-in, session user key absent).
- When auth module disabled: redirects to dashboard with notice.

### 6.5 Registrations request spec — `spec/requests/authentication/registrations_spec.rb` (new or extend)
- `GET /:cid/auth/sign_up` renders 200 when registration allowed; redirects to sign-in when `allow_registration=false`; redirects to dashboard when auth module disabled.
- `POST /:cid/auth/sign_up` with valid params creates a user, signs them in, redirects to dashboard. Response status on failure is 422 (Unprocessable Content).
- `GET /:cid/auth/edit` (signed in) renders 200; unauthenticated hits the sign-in page.
- `PATCH /:cid/auth` updates profile; failure status 422.

### 6.6 View / component specs
- `spec/views/authentication/shared/_auth_card.html.erb_spec.rb` (new):
  - Renders `<div … data-turbo-temporary …>` around each flash region.
  - Renders title, subtitle, footer locals when provided.
- `spec/views/authentication/passwords/new.html.erb_spec.rb` (new):
  - Submit button text is `"Send me password reset instructions"`.
- `spec/views/authentication/sessions/new.html.erb_spec.rb` (new):
  - Sign-in form posts to the session path, includes email + password inputs.
- `spec/views/authentication/registrations/new.html.erb_spec.rb` (new):
  - Sign-up form renders first/last/email/password/password_confirmation inputs and posts to the registration path.
- `spec/views/authentication/registrations/edit.html.erb_spec.rb` (new):
  - Edit form renders current_password, email, password, password_confirmation inputs and posts via PATCH.

### 6.7 Locale spec — `spec/config/devise_locale_spec.rb` (new)
- `I18n.t("devise.failure.invalid", authentication_keys: "email")` → string contains `"Invalid email or password"` (case-sensitive, asserts the grammar fix took effect).
- `I18n.t("devise.sessions.signed_out")` returns the 5.0 string.
- `I18n.t("devise.passwords.send_instructions")` returns a non-empty string.

### 6.8 Response status regression spec — `spec/requests/devise_response_status_spec.rb` (new)
- A failing sign-in returns HTTP status 422. Assert `response.status == 422` (symbol `:unprocessable_content` and `:unprocessable_entity` both alias to 422 — this guards against accidental redirect changes).
- A failing registration returns HTTP status 422.

### 6.9 Full suite run
`bundle exec rspec` must report zero failures and zero pending tests introduced by this change.

## 6.10 Conventions — file structure, naming, layout/styling

All new files and edits MUST conform to the existing application conventions. This is a hard requirement of the spec, not a suggestion.

### File structure
- Specs live under `spec/` mirroring the `app/` or `config/` path of the file they cover (e.g., `spec/models/authentication/user_spec.rb` for `app/models/authentication/user.rb`).
- Request specs live under `spec/requests/<namespace>/<resource>_spec.rb` — consistent with existing specs such as `spec/requests/authentication/` style.
- View specs live under `spec/views/<controller_path>/<template>_spec.rb` — one spec file per ERB template.
- Config specs live under `spec/config/` (no sub-namespacing required; matches Rails convention where the single `config/` top-level dir is not namespaced).
- Locale overrides live under `config/locales/` with a filename pattern of `<scope>.<locale>.yml` (e.g., `devise.en.yml`), matching the existing `feature_modules.en.yml`.

### Naming
- Ruby files: `snake_case.rb`. Classes: `CamelCase`.
- RSpec files: `<thing>_spec.rb`, describing the exact class/path under test (`RSpec.describe Authentication::User` etc.).
- Namespaced modules follow the project's existing two-level convention (`Authentication::User`, `Authentication::PasswordsController`).
- Locale keys under `devise.*` mirror the gem's key layout — do not introduce a new `anysys.devise.*` parallel tree.
- Override hook method names match Devise's own public API names exactly (`password_length`, `sign_in_after_change_password?`, `sign_in_after_reset_password?`) — no project-specific renaming.

### Layout / styling consistency
- Views use **Tailwind only** (per `AGENTS.md`). No custom CSS, no inline `<style>`, no additional CSS framework. All class lists use the same Tailwind palette already present in `_auth_card.html.erb` (`indigo-600`, `gray-*`, `red-*`, `green-*`, rounded-xl cards with shadow-sm + border-gray-200, etc.).
- Flash blocks retain the existing visual pattern: colored left border (`border-l-4 border-red-400` / `border-green-400`), soft background (`bg-red-50` / `bg-green-50`), padded, rounded. Only the `data-turbo-temporary` attribute is added — no visual regression.
- Form inputs across sessions/registrations/passwords views must share the same input styling already used in the existing templates (same border, focus-ring, padding, font size). If we touch a view, we match the existing classes in that view; we do not reformat.
- Button copy change in `passwords/new.html.erb` preserves the existing button's Tailwind class list verbatim — only the text changes.
- The existing `_auth_card.html.erb` layout is the canonical auth-page shell; all auth views continue to render through it via `render layout: "authentication/shared/auth_card"` or equivalent, and do not introduce a parallel layout.
- ViewComponent: per `AGENTS.md`, the project prefers ViewComponent encapsulation. Devise's custom controllers and views predate this direction and are preserved as-is in this upgrade (migrating auth views to ViewComponents is explicitly out of scope — a separate design decision).

### JavaScript
- Per `AGENTS.md`, only StimulusJS is permitted. This upgrade introduces no JavaScript. The `data-turbo-temporary` attribute is a Turbo-native hook requiring no JS wiring on our side.

### RSpec style
- Use `RSpec.describe` with the constant (not a string) at the top level where possible.
- Use `let(:customer)` / `let(:user)` blocks matching the existing request-spec pattern in this repo.
- Use FactoryBot factories (already loaded via `factory_bot_rails`) — prefer existing `:customer`, `:user` factories. Add factories only if missing.
- Follow existing spec formatting: two-space indentation, trailing blank line, `frozen_string_literal: true` magic comment at the top.

### Documentation headers
- New Ruby files: `# frozen_string_literal: true` as the first line.
- New locale files: a top-of-file comment noting the source (Devise 5.0.4 defaults) and the load-order intent (overrides the gem's bundled `en.yml`).

## 7. Implementation order

1. Config: flip `error_status` to `:unprocessable_content`.
2. Model: add `password_length` and `sign_in_after_change_password?` hooks.
3. Controller: add `sign_in_after_reset_password?` hook.
4. Views: add `data-turbo-temporary`; update button copy.
5. Sessions controller: lowercase `"email"` argument.
6. Locales: add `config/locales/devise.en.yml` (copy of gem defaults with header comment).
7. Specs: add/extend per §6.
8. Run full `bundle exec rspec`; fix any regression.

## 8. Acceptance criteria

- Every change in §2 marked "Yes" or "Verify" is reflected in the codebase.
- Every touched file has corresponding spec coverage per §6.
- Every new/edited file conforms to §6.10 (file structure, naming, layout/styling, RSpec style, headers).
- Full RSpec suite passes with no new failures and no pending tests.
- No feature-level behavior change beyond the items enumerated in §4.
