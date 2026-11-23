---
title: "Authentication"
summary: "How email and password, email links, customer sign-up, and the TOTP gate establish an Authentication::User session."
---

## Summary

`Authentication::User` is the Devise model (`users`). Email is globally unique, so sign-in does not ask for a customer id. The password digest is bcrypt via Devise. A successful first factor rotates the session, then `Authentication::MfaObligation` either lets the request through, sends the user to verify TOTP, or sends an admin or owner to enrol. The `authentication` feature module must be enabled for that user's customer or the attempt is treated as a bad password.

OAuth bearer calls are a separate session and are described in [OAuth](oauth). Who may open `/admin` and `/member` after sign-in is [Tenancy and roles](tenancy-and-roles).

## Flow

```text
POST /auth/sign_in
  email + password          intent=sign_in_link -> IssueSignInLink
        |
        v
Authentication::Throttle     signin:<ip>  20 / 5 minutes
        |
        v
Authentication::SignInFlow
        |  User.find_for_database_authentication  (active, email only)
        |  FeatureModules::Module.enabled?(key: "authentication")
        |  PasswordVerification -> valid_for_authentication? / valid_password?
        v
Authentication::FinishesSignIn
        |  reset_session, sign_in(:user), mark_mfa_verified!(verified: result.mfa_verified)
        v
next_action
        |  :mfa_required        GET/POST /:cid/auth/mfa/session
        |  :mfa_setup_required  GET/POST /:cid/auth/mfa/setup
        |  :authenticated       signed_in_destination (claim first; then stored location, continuation, or LandingPath)
        v
later requests
ApplicationController includes Authentication::EnforcesMfa
        |
        v
Authentication::MfaObligation.for(user:, verified: mfa_session_verified?)
        |  :verify -> /:cid/auth/mfa/session
        |  :enroll -> /:cid/auth/mfa/setup
        |  :none   -> controller
```

Passwordless first factors (`GET /auth/sign_in_link`, `GET /auth/confirmation`, `GET /auth/sign_up/confirm`) call `SignInFlow.complete` and then the same `finish_sign_in`.

## Implementation

### Devise model

`Authentication::User` uses Devise `:database_authenticatable`, `:registerable`, `:recoverable`, `:confirmable`, `:rememberable`, `:trackable`, `:lockable`, and `:timeoutable`. `:validatable` is omitted. Presence, email format, global uniqueness, and password length are declared on the model. `config/initializers/devise.rb` sets `authentication_keys` to `[:email]`, `password_length` to `8..128`, `stretches` to `1` in test and `12` otherwise, `maximum_attempts` to `10`, `unlock_strategy` to `:time`, `unlock_in` to `30.minutes`, `reset_password_within` to `6.hours`, `confirm_within` to `3.days`, `allow_unconfirmed_access_for` to `0.days`, `timeout_in` to `30.minutes`, `paranoid` to `true`, and `sign_out_via` to `:delete`.

`find_for_database_authentication` drops any `customer_id` condition and loads `active.find_by_normalized_email`. The unique index is `LOWER(email)`. `active_for_authentication?` is Devise's check and `active?` (`status` enum). An inactive user is logged out on the next request. `inactive_message` is `:deactivated` in that case.

Routes live in `config/routes.rb`. Devise is mounted at `/auth` with sessions, passwords, and confirmations overridden. Registrations and unlocks are skipped and replaced by the controllers below. MFA routes are tenant-scoped and public: `/:customer_id/auth/mfa/setup`, `mfa/session`, `mfa` (`DELETE`), and `mfa_recovery`.

### Password digest

Account passwords are stored in `users.encrypted_password`. `Authentication::PasswordVerification` is the app wrapper: it calls `user.valid_for_authentication?` and, inside the block, `user.valid_password?`. That is Devise's lockable hook. Calling `valid_password?` alone would check the digest and skip the failed-attempt counter. Devise's encryptor (`Devise::Encryptor` in the installed `devise` gem) hashes with `BCrypt::Password.create` at `klass.stretches` and compares with `BCrypt::Engine.hash_secret`. This initializer does not set `config.pepper`.

`bcrypt`, `scrypt`, and `argon2` together appear in `FlowchartRuntime::PasswordHash`, which the flowchart `hash_data` generator calls. That module does not write `Authentication::User#encrypted_password`. Its bcrypt default cost is also `12`.

`Authentication::CredentialLifecycle.around_update` serializes password, existing MFA secret, email and customer-identity changes on the user row. It rejects stale snapshots and transactionally deletes trusted devices, revokes OAuth access/refresh tokens and unredeemed authorization grants, and clears email sign-in tokens. Initial blank-to-secret enrolment does not invalidate grants; secret changes reset `last_otp_at`. `allow_blank_password` permits a passwordless founder. Password confirmation is validated when supplied.

Passwordless validity specs attach an existing persisted customer explicitly. FactoryBot's `build(:user)` also builds its customer association; that unsaved customer's random ID is assigned only on creation, so the user still has a nil `customer_id`. The passwordless flag does not waive tenant identity, and these fixtures must not depend on ambient `Current.customer` to become valid.

`Authentication::Settings#timeout_in(default:)` reads positive integer `session_timeout` minutes; `#maximum_attempts(default:)` reads positive integer `max_login_attempts`. `Authentication::User::TenantSecurityPolicy` applies these on the account instance through `timeout_in`, `maximum_attempts`, and Devise's protected `attempts_exceeded?`/`last_attempt?` hooks. Missing, malformed or inactive settings inherit the current Devise class defaults above. No tenant changes process-global Devise configuration. Settings also reads MFA, registration and reset switches.

Normal cookie sign-in/fetch runs Devise callbacks and maintains the scoped Warden session's `last_request_at`. On an expired GET, the installed Devise FailureApp first clears authentication and redirects to the attempted path; its next unauthenticated request redirects to `/auth/sign_in`. Verify the cleared scope and complete redirect journey, rather than interpreting the first retry as a live session. Callback suppression is limited to stateless bearer principals.

### Password sign-in

`Authentication::SessionsController` skips Devise's `allow_params_authentication!` on `create` so Warden does not also count a failure. `POST /auth/sign_in` with `params[:intent] == "sign_in_link"` delegates to `Authentication::IssuesSignInLink`. Otherwise it reads the trusted-device cookie before session rotation and calls `Authentication::SignInFlow`.

`SignInFlow#call` requires an active user, `password_set?`, `FeatureModules::Module.enabled?(key: "authentication", customer_id:)`, and `PasswordVerification`. A disabled module, a blank password, a lock, or a failed digest all return `:invalid_credentials`. The controller audits `:locked_out` when `access_locked?`, otherwise `:login_failed`, and renders the sign-in form with `devise.failure.invalid` and status `422`. `Authentication::Throttle` on `signin:<ip>` returns `429` after 20 attempts in 5 minutes. The counter increments on every attempt, including successes, via `hit!`.

On success, `post_auth_action` chooses the next step:

- `mfa_required?` (`otp_required_for_login` and a secret) yields `:mfa_required`, unless `Authentication::TrustedDevice.authenticate` accepts the cookie, in which case the result is already `:authenticated`.
- Otherwise, if the user is not a pure member and `Authentication::Settings#mfa_enabled?` is true, the result is `:mfa_setup_required`.
- If `mfa_configured?` (a secret exists but login does not require it yet), the result is also `:mfa_setup_required`.
- Otherwise `:authenticated`.

`FinishesSignIn#finish_sign_in` preserves flash and the stored location across `reset_session`, signs in and sets MFA verification from the result. Devise's Trackable hook updates login history once; the concern no longer duplicates that update. Only `:authenticated` marks the session verified. MFA-required and MFA-setup results redirect to those paths without completing a pending person claim. A fully established session (`:authenticated`, or MFA verify / MFA setup success) redirects through `signed_in_destination(user)` — see **Sign-in destination**.

`DELETE /auth/sign_out` signs out, clears the MFA session keys, audits `:logout`, and redirects to the sign-in form.

`Authentication::SessionsController` also redirects to the sign-in form when a successful result's user is unconfirmed, storing `session[:unconfirmed_email]`. `allow_unconfirmed_access_for` is `0.days`, and `PasswordVerification` rejects a user who fails `active_for_authentication?`, so a password attempt by an unconfirmed user fails inside `SignInFlow` before that branch. Passwordless `SignInFlow.complete` checks `confirmed?` itself.

### MFA gate

`Authentication::MfaObligation` is the only decision. It returns:

- `VERIFY` when `mfa_required?` and this session has not presented a code for the current secret.
- `ENROLL` when the user is not in the required state but `mfa_configured?` is true, or when tenant MFA applies. A previous `verified` flag does not satisfy enrolment.
- `NONE` otherwise.

Tenant MFA (`Settings#mfa_enabled?`) applies to admins and owners. The method returns false when `user.member? && !user.admin_or_owner?`. Members enrol on their own under the member security surface.

`Authentication::MfaSessionVerification` stores `session[:mfa_verified]` and `session[:mfa_secret_digest]`, a SHA-256 of `otp_secret`. `mfa_session_verified?` is true only when both match the current secret. `Authentication::User` encrypts `otp_secret` at rest.

`Authentication::EnforcesMfa` is a `before_action` on `ApplicationController`. `VERIFY` redirects to `mfa_session_path` unless `controller_path` is in `CHALLENGE_EXEMPT_CONTROLLERS` (`authentication/sessions`, `authentication/customer_registrations`, `authentication/mfa_sessions`, `authentication/mfa_recoveries`, `locales`, `oauth/authorizations`). `ENROLL` also allows `authentication/mfa_setups`, `authentication/mfas`, and `member/mfa`. The customer id in the redirect is `current_customer_id` or the user's own id, so a platform owner finishes MFA on the URL tenant.

`Authentication::MfaSessionsController` (`RequiresSignIn`) verifies with `User#verify_otp` (ROTP, issuer `"Anysys"`, drift 15 seconds behind and ahead, `after: last_otp_at`). `claim_otp_timecode` advances `last_otp_at` with a conditional `UPDATE` so one code is spent once. `Authentication::Throttle.mfa` allows 5 failures per user per 15 minutes, shared with enrol and disable. Optional `trust_device` calls `TrustedDevice.issue!` and sets the signed, httponly cookie `trusted_device` for `TrustedDevice::DEFAULT_TTL` (30 days). The row stores the SHA-256 digest, `customer_id`, and `user_id`.

`Authentication::MfaSetupsController` includes `Authentication::MfaEnrollment`. `ensure_otp_secret!` calls `generate_otp_secret!` only when the secret is blank. A prefetch GET (`Purpose`, `Sec-Purpose`, or `X-Sec-Purpose: prefetch`) does not plant a secret and returns `204` while the secret is still blank. The user-menu and member security links set `data-turbo-prefetch="false"`. `create` verifies a code, then `enable_mfa!` sets `otp_required_for_login`. The setup page redirects away when `mfa_required?` is already true, so a finished secret is not rendered again. Responses send `no_store`.

`Authentication::MfasController#destroy` disables MFA only after a fresh OTP or `PasswordVerification` of `current_password`, under the same MFA throttle. It clears the session flag. `Authentication::MfaRecoveriesController` is the lost-authenticator email path. It always renders the same page. `Member::Mfa::Operation::RequestResetLink` and `ConsumeResetLink` do the work. `consume` on `GET` does not spend the token. A successful `POST` resets the session and signs out.

### Email sign-in link

`POST /auth/sign_in_link` and the sign-in form's link intent both call `IssuesSignInLink#issue_sign_in_link`. The response is the check-email page for every address. `Authentication::IssueSignInLink` looks up `find_by_normalized_email`. A missing, inactive, or authentication-disabled user is a no-op. A confirmed user gets a Devise token in `sign_in_token` via `update_columns` (no `updated_at`, no credential-revocation callback) and `SignInLinkMailer.sign_in_link(...).deliver_later`. TTL is `15.minutes`. An unconfirmed user gets `User.send_confirmation_instructions`, which still respects the tenant sign-up toggle for members.

`GET /auth/sign_in_link` answers `HEAD` with `200` without consuming the token. Issuance and `Authentication::ConsumeSignInLink` synchronize on the current account snapshot; consumption rechecks eligibility and conditionally clears the token under that lock. Only one request wins. `SignInFlow.complete` remains the subsequent authorization decision.

### Customer and member registration

Public tenant creation is `Authentication::CustomerRegistrationsController`:

1. `GET /auth/sign_up` and `POST /auth/sign_up` collect an email when `Authentication::PlatformSettings.customer_signup_enabled?` (`authentication_platform_settings.allow_customer_signup`, seeded true).
2. `Authentication::IssueCustomerSignup` sends a link. The controller always redirects to the check-email page.
3. `GET /auth/sign_up/confirm` answers `HEAD` without consuming the token. `Authentication::CustomerSignupToken.verify` returns the email. A stateless token is not marked spent, so a confirmed address is sent to the sign-in form instead of being signed in again.
4. A new address runs `Authentication::CustomerSignup`, which creates an active `Customer` (`industry: "technology"`, `role: :admin`, `tier: :basic`), skips the authentication provisioner, and saves an unpassworded confirmed admin. If the random id equals `PLATFORM_CUSTOMER_ID`, the transaction rolls back. `assign_admin!` attaches the system `admin` role.
5. `SignInFlow.complete` then `finish_sign_in`.

Member self-sign-up is `GET /:customer_id/auth/sign_up` and `POST /:customer_id/auth` on `Authentication::RegistrationsController`. `check_auth_enabled` requires the authentication module. `check_registration_allowed` requires `Authentication::Settings#signup_enabled?` (`allow_registration`, default false). `create` calls `Authentication::RegisterMember` (see below). The user is not signed in. They confirm through `Authentication::ConfirmationsController#show`, which also calls `SignInFlow.complete` and, on success, `finish_sign_in` — a passwordless confirmation therefore signs the member in. A signed-in visitor is redirected away from that `show` so one person's confirmation link cannot replace another's session. `GET /auth/confirmation/new` redirects to sign-in. Resend is throttled by `Authentication::EmailFloodThrottled`.

### RegisterMember

`Authentication::RegisterMember.call(customer:, attributes:, request: nil, passwordless: false)` is the shared writer for the public sign-up form and the flowchart `register_member` step. It returns `Result(status:, user:, errors:)` with `status` ∈ `:created`, `:invalid`, `:quota_exceeded`.

It does **not** check `signup_enabled?`. Callers gate that: the controller with `check_registration_allowed`, the step with `Authentication::Settings#signup_enabled?` and the authentication module. Attributes are sliced to `first_name`, `last_name`, `email`, `password`, `password_confirmation`. `passwordless: true` sets `allow_blank_password` so the step can create an unconfirmed member with no password.

Inside `customer.with_lock(requires_new: true)` it runs `Billing::Quota::Guard.check(..., item_key: "member")`, saves the user, and attaches the system `member` role (`assign_member_role!`). Devise `:confirmable` enqueues the confirmation email after the outermost transaction commits. A reserved-role failure becomes `:invalid` with `auth.errors.reserved_role_required`. Quota denial is `:quota_exceeded` and no user is persisted. Losing the unique email index race is `:invalid` with an `email` `:taken` error, never an exception.

The sign-up form calls it with a password (`passwordless: false`). The `register_member` step calls it with `passwordless: true` and identity attributes only. See [Audience flows](audience-flows) and [Flowchart runtime](flowchart-runtime).

### No account enumeration on sign-up

Both sign-up paths answer a taken address exactly like a new one:

- **Form.** When the only error is `email` `:taken`, `RegistrationsController#create` drops that error and responds with the same redirect and `auth.flash.confirmation_sent` flash as a created account. With other errors it re-renders them but never the "already taken" one. The quota check runs before validation, so a full quota answers every address the same way.
- **Notice.** `Authentication::NotifyExistingMember.call(user:, customer_id:)` decides what a taken address receives: a confirmed active member of the tenant gets a sign-in link through `IssueSignInLink`, counted against the sign-in link page's per-address flood bucket (`EmailFloodThrottled.email_throttle("sign_in_link", email, tenant_key: "global")`); anyone else gets nothing. The `register_member` step uses the same service.
- **Mail.** `Authentication::User#send_devise_notification` uses `deliver_later`, so no Devise mail (confirmation, reset, unlock) waits on SMTP inside the request.
- **Timing.** `Authentication::UniformTiming` pads the response to `FLOOR` (0.4 seconds), measured from before the email lookup. It pads only after the transaction commits and never while one is open, so no lock is held while waiting (and transactional specs never sleep). Keep the floor above the slowest branch, which is creating the account.

### Sign-in destination

`Authentication::FinishesSignIn#signed_in_destination(user)` is the only post-auth landing helper. Password sign-in, the email sign-in link, confirmation, MFA verify, and MFA setup all use it once the session is fully established — never while MFA is still pending (`finish_sign_in` sends those users to `/auth/mfa/session` or `/auth/mfa/setup` first; those controllers call `signed_in_destination` after the second factor passes).

It always completes a pending person claim first (`People::Claim.complete!(user)`), then picks a path:

1. a safe stored location (`safe_return_path_for(user, stored_location_for(:user))`) — an OAuth authorize return, for example;
2. the claim's continuation (`/:cid/actions/:key` in the user's own tenant, with the recorded prefill);
3. `Authentication::LandingPath.for(user)`.

The stored location wins because anyone can trigger the existing-email branch of `register_member` with someone else's address; that must not override where that person already intended to return. Completing the claim first still links the Student entry (when there is one) and consumes the row. Claims live in the database, so a confirmation or sign-in link opened on another device completes them too. See [Person linking](person-linking).

Account edit is `GET /auth/edit` and `PATCH/PUT /auth`. Existing passwords are reverified through `Authentication::PasswordVerification.authenticate` before assigning submitted credentials, preserving Lockable counters and form errors without saving rejected credentials. A passwordless founder may set a password without `current_password`; `email` is stripped until a password exists (`reconfirmable` is false).

Member quota counts actual member assignments, excluding provisioned/admin accounts. Paid entitlement limits come from the accepted subscription `plan_snapshot`, so subsequent catalog changes do not alter an existing accepted allowance. Auth quota regressions construct that snapshot up front and use member fixtures when consuming capacity.

### Password reset

`Authentication::PasswordsController` throttles `create` with the shared email-flood limiter. `User.send_reset_password_instructions` uses `recover_by_email`: unknown emails return a stub with `:not_found` (paranoid mode hides that), and a known user is mailed only when `password_reset_available?` (`authentication` module on, and `Settings#password_reset_enabled?`, default true). `edit` and `update` resolve the user from the reset token and render `:disabled` with `403` when that predicate is now false. `sign_in_after_reset_password?` returns false, so the mailbox proof does not skip MFA. The success redirect is the sign-in form. A password change still revokes trusted devices and OAuth tokens through the user callback.

## Where to pay attention

### Route audit: credential and proof invariants

Password reset edit checks the query token; update checks the permitted `user[reset_password_token]` consumed by Devise, ignoring a conflicting top-level token. `Authentication::MfaMutation` checks the current credential snapshot. Recovery tokens bind member, tenant and current-secret fingerprint and revalidate under the reset lock. `Authentication::OwnerIdentity` pins the existing owner's email/customer. Bare `code` parameters, including nested keys, are filtered case-insensitively without filtering `postal_code`.

`Authentication::HandlesCredentialConflicts` handles only User stale-object errors: HTTP `409`, no-store/no-referrer, localized plain text or JSON `{ error: "stale_credentials", message: ... }`. Reload before retrying. Related boundaries: [OAuth](oauth), [Access grants](access-grants), [Member and public](member-and-public).

MFA recovery consume GET/HEAD/POST and missing/invalid/expired-token branches carry private/no-store and no-referrer. `Authentication::MutationAudit.mfa(user:, request: nil, actor: nil, source:)` records actual required/configured before/after states under the credential lock; `roles(user:, before_role_ids:, request: nil, actor: nil)` records role-ID deltas under the caller's mutation lock. Role editor/assignment/removal, auth/member MFA, admin reset and recovery share this writer. Outcome rows participate in the mutation transaction; logging waits for all enclosing transactions to commit. Rejected/no-op/rolled-back writes emit no success event, and metadata excludes credentials, codes, tokens and request parameter hashes.

Mounted member/admin/customer signup and provisioner paths save account plus exactly one reserved assignment atomically. Raw model creation remains a low-level API without an automatic role callback; standalone callers use provisioning/assignment APIs. Bearer requests establish a callback-free principal after Devise account-eligibility checks, leaving browser login history unchanged; see [OAuth](oauth).

:::note
These APIs and route integrations are source-documented. On 2026-10-12 the parallel RSpec suite passed **25,266 examples, 0 failures**. Browser and concurrency acceptance beyond that suite remain separate.
:::

:::attention
`Authentication::SignInFlow` returns `:invalid_credentials` when `FeatureModules::Module.enabled?` is false for `"authentication"`. The sign-in form shows the same Devise invalid-email message as a wrong password. Do not add a distinct "module disabled" response on `Authentication::SessionsController#create`.
:::

:::attention
`Authentication::MfaObligation` and `SignInFlow#tenant_mfa_enforced?` skip tenant MFA when `user.member? && !user.admin_or_owner?`. `FeatureModules::Authentication::Registration`'s schema text says MFA is for all users. The predicates above are the rule that runs.
:::

:::attention
`Authentication::PasswordVerification` must stay on `valid_for_authentication?`. `Authentication::MfasController` uses it for the password re-check so a disable attempt increments Devise's lockable counter. `valid_password?` by itself does not.
:::

:::attention
Devise's initializer supplies fallback timeout (30 minutes) and failed-attempt limit (10). Active tenant overrides are effective for browser idle expiry, Lockable warnings/counters and PasswordVerification, and are resolved per account without changing other tenants.
:::

:::note
`Authentication::User` passwords are bcrypt through Devise. `FlowchartRuntime::PasswordHash` is the bcrypt, scrypt, and argon2 wrapper for flowchart steps. A flowchart hash does not authenticate a user.
:::

:::attention
`signed_in_destination` completes `People::Claim.complete!(user)` before it looks at the stored location. A stored OAuth return still wins the redirect, but the Student entry is linked and the claim is consumed. Do not complete a claim from `finish_sign_in` while `next_action` is `:mfa_required` or `:mfa_setup_required`.
:::

:::attention
`Authentication::RegisterMember` does not read `signup_enabled?`. A caller that skips the controller or the `register_member` step must gate sign-up itself. Devise sends the confirmation email after the outermost commit, not from inside the lock.
:::

## Key code

```ruby
# config/initializers/devise.rb
  config.stretches = Rails.env.test? ? 1 : 12

  config.reconfirmable = false

  config.expire_all_remember_me_on_sign_out = true

  config.password_length = 8..128

  config.email_regexp = /\A[^@\s]+@[^@\s]+\z/

  config.lock_strategy = :failed_attempts
  config.unlock_keys = [:email]
  config.unlock_strategy = :time
  config.maximum_attempts = 10
  config.unlock_in = 30.minutes
```

```ruby
# config/initializers/devise.rb
  config.confirm_within = 3.days
  config.allow_unconfirmed_access_for = 0.days

  # ==========================================================================
  # :timeoutable
  # ==========================================================================
   # Default idle-session expiry; User::TenantSecurityPolicy resolves
   # active account overrides without changing process-global configuration.
  config.timeout_in = 30.minutes

  # Paranoid mode: do not reveal whether an email exists (password reset,
  # unlock instructions). Mitigates user enumeration during account recovery.
  config.paranoid = true

  config.sign_out_via = :delete

  config.responder.error_status = :unprocessable_content
  config.responder.redirect_status = :see_other

  # Email is globally unique. find_for_database_authentication looks up by
  # email alone; tenant comes from the matched user row.
  config.authentication_keys = [:email]
```

```ruby
# app/services/authentication/password_verification.rb
    def self.call(user:, password:, on_comparison: nil)
      user.valid_for_authentication? do
        matches = user.valid_password?(password)
        on_comparison&.call(matches)
        matches
      end
    end
```

```ruby
# app/services/authentication/sign_in_flow.rb
    def post_auth_action(user)
      if user.mfa_required?
        return :authenticated if trusted_device?(user)
        return :mfa_required
      end
      # Tenant-wide MFA for admins/owners: send them to setup *before*
      # marking the session verified. Otherwise visiting GET mfa/setup
      # plants otp_secret (mfa_configured? becomes true) while
      # session[:mfa_verified] is already true from password login, and
      # both enforce_mfa! gates treat enrollment as done.
      return :mfa_setup_required if tenant_mfa_enforced?(user)
      return :mfa_setup_required if user.mfa_configured?

      :authenticated
    end

    def tenant_mfa_enforced?(user)
      return false if user.member? && !user.admin_or_owner?

      Authentication::Settings.for(user.customer_id).mfa_enabled?
    end
```

```ruby
# app/services/authentication/mfa_obligation.rb
    def call
      return NONE unless user.respond_to?(:mfa_required?)

      return verified ? NONE : VERIFY if user.mfa_required?

      # An enrolment obligation is NOT satisfiable by a session flag — only by
      # actually enrolling. Honouring `verified` here was a real bypass: a
      # session established before the tenant switched MFA on (or before an
      # admin reset the user's secret) carried `verified = true` for its whole
      # life, and the gate short-circuited on it, so the mandate never applied
      # to anyone already signed in.
      return ENROLL if user.mfa_configured?
      return ENROLL if tenant_enforced?

      NONE
    end
```

```ruby
# app/controllers/concerns/authentication/enforces_mfa.rb
    CHALLENGE_EXEMPT_CONTROLLERS = %w[
      authentication/sessions
      authentication/customer_registrations
      authentication/mfa_sessions
      authentication/mfa_recoveries
      locales
      oauth/authorizations
    ].freeze
```

```ruby
# app/services/flowchart_runtime/password_hash.rb
    PASSWORD_ALGORITHMS = %w[bcrypt scrypt argon2].freeze
    DEFAULT_BCRYPT_COST = 12
```

```ruby
# app/services/authentication/register_member.rb
    def self.call(customer:, attributes:, request: nil, passwordless: false)
      # :created / :invalid / :quota_exceeded
    end
```

```ruby
# app/controllers/concerns/authentication/finishes_sign_in.rb
    def signed_in_destination(user)
      continuation = People::Claim.complete!(user)
      stored = stored_location_for(:user)
      safe_return_path_for(user, stored) || continuation || default_signed_in_path_for(user)
    end
```
