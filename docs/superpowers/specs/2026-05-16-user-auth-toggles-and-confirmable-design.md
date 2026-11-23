# User Authentication — Toggles, Email Confirmation, Full Devise Surface

**Date:** 2026-05-16
**Module:** User Authentication (`feature_modules.key = "authentication"`)
**Status:** Approved (pending spec review)

## Goal

Customer admins control whether self sign-up and password reset are available
to their tenant, via two toggles under
`/:cid/admin/settings/modules/authentication`. New sign-ups must confirm their
email by clicking a link before they can sign in. Forgot-password works the
same way (link delivered to email, clicked to set a new password). Both
surfaces — sign-up and forgot-password — are gated end-to-end (form, submission,
mailer, AND the post-email confirmation/reset endpoint) by their respective
toggle. Public sign-up always assigns the `:member` role and never any other.

## Non-Goals

- Branded mailer templates (stock Devise HTML used).
- A separate toggle for `:lockable` unlock email — left always-on.
- Per-customer sender email / DKIM (platform-wide `Devise.mailer_sender`).
- Configurable token expiry (Devise defaults).
- Adding `:omniauthable` (no third-party identity providers in scope).

## Architecture

```
                ┌──────────────────────────────┐
   admin UI ───►│ Admin::ModuleConfigsController│  (existing, generic)
                │   PATCH /:cid/admin/settings  │
                │   /modules/authentication     │
                └────────────┬──────────────────┘
                             │ writes JSON blob
                             ▼
       ┌─────────────────────────────────────────┐
       │ FeatureModules::CustomerAssignment      │
       │   configuration: {                      │
       │     allow_registration: bool,           │
       │     allow_password_reset: bool, ...     │
       │   }                                     │
       └────────────┬────────────────────────────┘
                    │ read by
                    ▼
       ┌────────────────────────────────────┐
       │ Authentication::Settings.for(cid)  │  ◄── new value object
       │   #signup_enabled?                 │
       │   #password_reset_enabled?         │
       └────────────┬───────────────────────┘
                    │ consulted by
       ┌────────────┴─────────────────────────────────────────────┐
       ▼                ▼              ▼              ▼            ▼
RegistrationsCtrl  PasswordsCtrl  ConfirmationsCtrl  SessionsCtrl  AuthShell views
    new/create      new/create     new/create/show   create        link visibility
                    edit/update    + resend          (handles
                                                      unconfirmed)
                              ▲
                              │ Devise mailer (default templates)
                              │ from = Devise.mailer_sender
                              │
                       ┌──────┴───────────────┐
                       │ Devise :confirmable  │
                       │ added to User model  │
                       │ + columns migration  │
                       │ + backfill confirmed │
                       └──────────────────────┘
```

## Component Boundaries

### `Authentication::Settings` (new)

**File:** `app/services/authentication/settings.rb`

Pure read-side value object. Wraps the JSON blob lookup so controllers and
views never reach into the feature-module schema directly.

Public surface:

- `Authentication::Settings.for(customer_id)` — returns a memoized instance
  per customer_id (memoization is per-request: a `Current.attribute` reset on
  each request clears it).
- `#signup_enabled?` — `true` iff the auth module is enabled for the customer
  AND `config["allow_registration"] == true`.
- `#password_reset_enabled?` — `true` iff the auth module is enabled AND
  `config["allow_password_reset"] == true`.
- `#mfa_enabled?` — passthrough for the existing `mfa_enabled` key (used by
  views that already call this).

Behavior on edge cases:

- Customer not found → both predicates return `false`.
- Module not enabled / not provisioned → both return `false`.
- Config key missing → falls back to the schema default (`allow_registration:
  false`, `allow_password_reset: true`).

### `FeatureModules::Authentication::Registration` (extended)

**File:** `app/services/feature_modules/authentication/registration.rb`

- Add the two new boolean keys to `configuration_schema`:
  - `"allow_registration"` — default `false`, description: "Allow visitors to
    self-register a `member` account. They must confirm their email by clicking
    a link before they can sign in."
  - `"allow_password_reset"` — default `true`, description: "Allow users to
    reset their password via an email link."
- Add a `configuration_keys` class method returning the symbol whitelist
  (`%i[allow_registration allow_password_reset mfa_enabled session_timeout
  max_login_attempts]`). This is required for `Admin::ModuleConfigsController`
  to actually persist any of these keys; today the auth module has no
  whitelist so writes silently drop everything.
- The provisioner already runs on customer creation; no change needed beyond
  the schema gaining default values.

### `Admin::ModuleConfigsController` (no change)

The existing controller (`app/controllers/admin/module_configs_controller.rb`)
plus its view (`app/views/admin/module_configs/show.html.erb`) already
renders booleans as Yes/No `<select>`s and persists keys via
`configuration_keys`. With the schema additions above, the
`/:cid/admin/settings/modules/authentication` page automatically gains two
new rows: "Allow registration" and "Allow password reset", each with a Yes/No
select. No new controller, no new view file.

Authorization is the existing `RouteAuthorization` concern — the path begins
with `/:cid/admin/`, so admin-or-owner is enforced declaratively. No new
guard needed.

### Devise modules — enable the full set

The User model currently declares:

```ruby
devise :database_authenticatable, :registerable, :recoverable,
       :rememberable, :trackable, :lockable
```

The new declaration:

```ruby
devise :database_authenticatable, :registerable, :recoverable,
       :confirmable, :rememberable, :trackable, :lockable, :timeoutable
```

Rationale per module:

- `:confirmable` (NEW) — required by the goal: email-link activation before
  first sign-in.
- `:timeoutable` (NEW) — idle-session expiry. Devise's
  `Devise.timeout_in = 30.minutes` is set globally; the existing
  `session_timeout` config key already exists in the auth module schema so
  per-customer override is a follow-up if needed.
- `:validatable` — **deliberately NOT enabled.** It adds presence/format/uniqueness
  validations on email, but its uniqueness check is global. This app already
  has tenant-scoped uniqueness in `Authentication::User` (`uniqueness: { scope:
  :customer_id }`). Enabling `:validatable` would either duplicate or override
  that scope and re-introduce cross-tenant collisions. The custom validations
  in `user.rb` (lines 64–76) cover the same ground. Document this decision
  inline in the model.
- `:omniauthable` — out of scope; no third-party identity providers.

Devise's full module set is therefore covered: every module that fits a
multi-tenant Rails 8 app with email/password auth is enabled, with one
documented exception (`:validatable`).

### `Authentication::User` (extended)

`app/models/authentication/user.rb` — additions:

- The new `devise :...` line above.
- A `send_confirmation_instructions(attributes)` class-method override that
  mirrors the existing `send_reset_password_instructions` pattern (lines
  132–172): require `customer_id` from attributes or `Current.customer_id`,
  scope the lookup to that tenant, prevent cross-tenant token leakage. Without
  this override, Devise's stock confirmable would leak tokens across tenants
  with the same email exactly the way reset would have before the existing
  override was added.
- A short comment documenting why `:validatable` is intentionally absent.

### Devise controllers (modified / added)

**`Authentication::RegistrationsController` (existing, modified)**

- Replace the existing `check_registration_allowed` body to read from
  `Authentication::Settings.for(current_customer_id).signup_enabled?` (already
  effectively the same — just routed through the value object instead of
  reaching into the module class directly).
- On block: render `authentication/registrations/disabled.html.erb` with HTTP
  200 (AuthShell page). No `redirect_to`, no 404.
- After successful sign-up: redirect to `new_user_session_path(customer_id:
  current_customer_id)` with flash "We sent a confirmation link to {email}.
  Please click it to activate your account." (Devise's `:confirmable` will
  prevent sign-in until clicked anyway.)
- Strong-params unchanged — still permits only `email`, `password`,
  `password_confirmation`, `first_name`, `last_name`. **Hard invariant: no
  role parameter is permitted from the public form. The `:member` role is
  assigned server-side after save (existing behavior at line 26 of the
  controller).** This is the rule that public sign-up only ever creates
  `:member` users.

**`Authentication::PasswordsController` (existing, modified)**

- Add `before_action :check_password_reset_allowed`, applied to all four
  actions (`new`, `create`, `edit`, `update`).
- Predicate: `Authentication::Settings.for(current_customer_id).password_reset_enabled?`.
- On block: render `authentication/passwords/disabled.html.erb` with HTTP
  200 (AuthShell page). Symmetric with sign-up.
- Existing tenant-scoped recovery behavior preserved (the User model override
  already handles that).

**`Authentication::ConfirmationsController` (NEW)**

`app/controllers/authentication/confirmations_controller.rb`, subclasses
`Devise::ConfirmationsController`.

- `before_action :check_auth_enabled` (mirrors registrations pattern).
- `before_action :check_signup_allowed` — confirmation is the second half of
  the sign-up flow; if sign-up is disabled, confirmation is too (per the
  approved "Pending links stop working" answer).
- On block: render `authentication/registrations/disabled.html.erb`.
- Strong-params permits `email` (for resend). Sets `customer_id` from
  `current_customer_id` so `User.send_confirmation_instructions` finds the
  right tenant.

Routes change in `config/routes.rb`:

```ruby
devise_for :users, path: ":customer_id/auth",
  class_name: "Authentication::User",
  constraints: { customer_id: /\d{8}/ },
  controllers: {
    sessions:      "authentication/sessions",
    registrations: "authentication/registrations",
    passwords:     "authentication/passwords",
    confirmations: "authentication/confirmations" # NEW
  }
```

This adds the routes Devise's `:confirmable` needs:
- `GET  /:cid/auth/confirmation/new` — request a new confirmation email
- `POST /:cid/auth/confirmation`     — send confirmation instructions
- `GET  /:cid/auth/confirmation`     — confirm via token in email link

**`Authentication::SessionsController` (existing, modified)**

When sign-in fails specifically because the user's email is unconfirmed,
the user must see an AuthShell "Please confirm your email" panel with a
"Resend confirmation" form (`POST /:cid/auth/confirmation`) — not Devise's
default generic flash.

Mechanism: install a custom Warden failure app
(`Authentication::FailureApp`, subclassing `Devise::FailureApp`) and wire it
in `config/initializers/devise.rb` via `config.warden { |w| w.failure_app =
... }`. The custom failure app overrides `respond` so that when `warden_message
== :unconfirmed`, it stores the submitted email in the session
(`session[:unconfirmed_email]`) and redirects to
`new_user_session_path(customer_id: ...)` with no flash. For all other
failure messages, it falls back to `super`.

`Authentication::SessionsController#new` then reads
`session.delete(:unconfirmed_email)`. If present, it renders the inline
"please confirm your email + resend" panel above the sign-in form (in
`sessions/new.html.erb`). The resend form POSTs to
`/:cid/auth/confirmation`, which respects the sign-up toggle as already
specified.

This avoids screen-scraping flash text and keeps the unconfirmed branch
deterministic.

### Mailer

- Stock `Devise::Mailer` templates. No subclass.
- `ApplicationMailer.default from:` updated to read from `Devise.mailer_sender`
  so all mail (Devise + future custom) shares one source of truth instead of
  the placeholder `from@example.com` it currently has.
- Confirmation email is sent automatically by `:confirmable` on User create
  and on `send_confirmation_instructions` (resend).
- Reset-password email is sent automatically by `:recoverable` on
  `send_reset_password_instructions`.

### AuthShell view changes

- `authentication/sessions/new.html.erb`:
  - Hide the "Forgot password?" link when `!auth_settings.password_reset_enabled?`.
  - Hide the "Don't have an account? Sign up" link when `!auth_settings.signup_enabled?`.
- `authentication/sessions/new.html.erb` also gains the inline "please
  confirm your email + resend" panel that renders when the previous sign-in
  attempt failed due to unconfirmed email.
- New disabled-state pages:
  - `app/views/authentication/registrations/disabled.html.erb` — AuthShell-
    styled "Sign-up is currently disabled for this organization. Contact
    your administrator." with link back to sign-in.
  - `app/views/authentication/passwords/disabled.html.erb` — AuthShell-
    styled "Password reset is currently disabled for this organization."
    with link back to sign-in.

### View helper

`ApplicationController` exposes:

```ruby
helper_method :auth_settings

def auth_settings
  Authentication::Settings.for(current_customer_id)
end
```

This is what the AuthShell views consult to hide/show links.

## Data Model

### Migration: `add_devise_confirmable_to_users`

`Authentication::User` is bound to the `users` table (per `self.table_name =
"users"` in the model and `create_table "users"` in `db/schema.rb`), so the
migration targets `users`.

```ruby
class AddDeviseConfirmableToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :confirmation_token,   :string
    add_column :users, :confirmed_at,         :datetime
    add_column :users, :confirmation_sent_at, :datetime
    add_column :users, :unconfirmed_email,    :string

    add_index  :users, :confirmation_token, unique: true

    # Backfill: every existing user is treated as already confirmed so the
    # migration is a no-op for them. Only NEW sign-ups go through the
    # activation flow.
    reversible do |dir|
      dir.up do
        execute <<~SQL
          UPDATE users
             SET confirmed_at = CURRENT_TIMESTAMP
           WHERE confirmed_at IS NULL
        SQL
      end
    end
  end
end
```

### `FeatureModules::Authentication::Registration` schema additions

Two new keys on the configuration_schema (already covered above), plus the
`configuration_keys` whitelist method. No schema migration — the config blob
is JSON in `customer_feature_modules.configuration`.

### Devise initializer (`config/initializers/devise.rb`)

- `config.confirm_within = 3.days` (Devise default) — leave implicit / explicit.
- `config.allow_unconfirmed_access_for = 0.days` — strict: confirmation
  required before any sign-in. Matches the goal exactly.
- `config.reconfirmable = false` — already set; kept.
- `config.timeout_in = 30.minutes` — paired with `:timeoutable`.
- `config.reset_password_within = 6.hours` — already set; unchanged.

## Flows

### Sign-up (allow_registration = true)

1. Visitor requests `/:cid/auth/sign_up` →
   `Authentication::RegistrationsController#new` checks
   `auth_settings.signup_enabled?` (true) → renders form.
2. Submission → builds `Authentication::User` with `customer_id`, `email`,
   `password`, `password_confirmation`, `first_name`, `last_name`. The
   `:member` role is assigned server-side after save (existing line 26).
3. `:confirmable` generates a `confirmation_token`, sets
   `confirmation_sent_at`, sends the confirmation email via stock
   `Devise::Mailer#confirmation_instructions`.
4. Controller redirects to sign-in with flash: "We sent a confirmation link
   to {email}. Please click it to activate your account."
5. Until `confirmed_at` is set, sign-in returns the AuthShell "please
   confirm" page (with resend form) instead of completing.
6. User clicks email link → `GET /:cid/auth/confirmation?confirmation_token=...`
   → `Authentication::ConfirmationsController#show` checks
   `auth_settings.signup_enabled?`, then Devise confirms the user (sets
   `confirmed_at`), redirects to sign-in with flash "Email confirmed.
   Please sign in."
7. User signs in → routed to `/:cid/member` (existing behavior).

### Sign-up (allow_registration = false)

- Every action on `RegistrationsController` and `ConfirmationsController`
  renders `authentication/registrations/disabled.html.erb` with HTTP 200.
- Pending confirmation links from before the toggle was flipped → see the
  same disabled page when clicked. (Per the "pending links stop working"
  decision.)
- AuthShell hides the "Sign up" link on the sign-in page.

### Forgot password (allow_password_reset = true)

Standard Devise flow:

1. `GET /:cid/auth/password/new` → form.
2. POST → `Authentication::User.send_reset_password_instructions`
   (existing tenant-scoped override) sends email.
3. Email link → `GET /:cid/auth/password/edit?reset_password_token=...` →
   form to set new password.
4. PATCH → password updated, redirect to sign-in.

### Forgot password (allow_password_reset = false)

- All four `PasswordsController` actions render
  `authentication/passwords/disabled.html.erb`. In-flight reset links from
  before the toggle was flipped stop working. AuthShell hides the "Forgot
  password?" link on the sign-in page.

### Settings page

- Path: `/:cid/admin/settings/modules/authentication`
- Renders the existing `admin/module_configs/show.html.erb`. With the new
  schema keys, it shows two extra Yes/No selects: "Allow registration" and
  "Allow password reset", plus the existing "MFA enabled", "Session
  timeout", "Max login attempts" rows.
- PATCH submits to `admin_module_config_path` which writes the JSON blob.

## Authorization Invariants

- Settings page (`/:cid/admin/settings/modules/authentication`): admin or
  owner only — enforced declaratively by `RouteAuthorization` concern (path
  starts with `/:cid/admin/`).
- Sign-up form: public (gated by `signup_enabled?`).
- Confirmation link: public (gated by `signup_enabled?`).
- Forgot-password form: public (gated by `password_reset_enabled?`).
- Reset-password edit/update: public (gated by `password_reset_enabled?`).
- **Public sign-up role assignment: `:member` only.** Strong-params
  whitelist excludes any role field; controller hard-codes the role
  assignment after save. There is no code path through the public sign-up
  form that produces a non-`:member` user.
- All Devise routes already include `customer_id` as a path segment, so
  tenant scoping is enforced before any controller body runs.

## Testing

Test framework: RSpec (per AGENTS.md).

### Service / model specs

- `Authentication::Settings` spec (new) — covers: module disabled, module
  enabled with both keys true, both false, key missing (uses default),
  customer not found.
- `Authentication::User` spec — extends existing spec to cover the new
  `send_confirmation_instructions` tenant-scoped override (mirrors the
  existing reset-password override spec).

### Migration / data spec

- A spec that runs the migration in a fresh schema and asserts: existing
  user rows have `confirmed_at` populated; new columns and unique index
  exist; new sign-ups created after migrate are unconfirmed by default.

### Request specs

- `RegistrationsController`:
  - `signup_enabled? = false` → `GET /:cid/auth/sign_up` returns 200 with
    disabled page; `POST` returns 200 disabled page.
  - `signup_enabled? = true` → `GET` renders form; `POST` creates an
    unconfirmed user; mailer sends one confirmation email; user cannot sign
    in until confirmed.
  - Sign-up params include `role=admin` → user is created with `:member`
    role only (verifies the strong-params guard + server-side assignment).
- `ConfirmationsController`:
  - `signup_enabled? = false` → `GET /:cid/auth/confirmation?token=...`
    returns 200 with disabled page even when the token is valid.
  - `signup_enabled? = true` → valid token confirms user; invalid token
    shows the standard Devise error.
  - Resend (`POST /:cid/auth/confirmation`) sends an email when enabled,
    blocks when disabled.
- `PasswordsController`:
  - All four actions render disabled page when `password_reset_enabled? =
    false`.
  - Standard reset flow works when enabled.
- `SessionsController`:
  - Unconfirmed user sign-in attempt → AuthShell "please confirm your
    email" page with resend form.

### System spec

- Customer admin signs in, navigates to `/:cid/admin/settings/modules/authentication`,
  toggles both flags, saves. Reloads page and the new values persist. Sign
  out, confirm public surfaces respect the new toggles end-to-end.

### Stale-test fallout

The AuthShell reskin (recent commits 99e31b8, 1b6defb, 02d4ac9, 31e8f11)
already touched sign-up and password specs. Adding `:confirmable` will fail
any sign-up spec that asserts the user can sign in immediately after sign-up.
Per the user's stale-test policy, those specs get rewritten to follow the
confirm flow (extract token from the mailer queue, GET the confirmation URL,
then sign in) — not deleted, not reverted.

## Implementation Order

The implementation plan (next step) will sequence this. Rough order:

1. Migration: add confirmable columns + backfill + unique index.
2. `Authentication::User`: add `:confirmable` and `:timeoutable` to the
   `devise :...` line; add `send_confirmation_instructions` override; add
   the comment on `:validatable`.
3. `config/initializers/devise.rb`: set `confirm_within`,
   `allow_unconfirmed_access_for = 0`, `timeout_in`.
4. `FeatureModules::Authentication::Registration`: add the two new schema
   keys + `configuration_keys` whitelist.
5. `Authentication::Settings` value object + `auth_settings` helper on
   `ApplicationController`.
6. `Authentication::ConfirmationsController` + route entry +
   `registrations/disabled.html.erb`.
7. `Authentication::PasswordsController` gate + `passwords/disabled.html.erb`.
8. `Authentication::FailureApp` (Warden failure handler) wired in
   `config/initializers/devise.rb`; `Authentication::SessionsController#new`
   reads `session[:unconfirmed_email]`; AuthShell "please confirm + resend"
   partial.
9. `ApplicationMailer.default from:` switches to `Devise.mailer_sender`.
10. AuthShell sign-in view: gate the "Sign up" / "Forgot password" links.
11. Tests: service spec, request specs, system spec, update stale specs.

## Out of Scope

- Branded mailer templates.
- `:lockable` toggle.
- Per-customer sender / DKIM.
- Configurable token expiry.
- `:omniauthable` (third-party identity).
- Any change to `:lockable` behavior or its existing email.
