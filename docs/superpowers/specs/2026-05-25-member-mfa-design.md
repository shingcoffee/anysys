# Member MFA — Opt-In Self-Service

**Status:** Spec
**Date:** 2026-05-25
**Owner:** xzhang

## Goal

When a member (member) signs up, MFA is **off by default**. Members can enable MFA themselves from inside the member area after signing in, disable it, and recover from a lost authenticator via an emailed reset link.

## Behavior Rules

### R1. Members are always opt-in for MFA

`users.otp_required_for_login` already defaults to `false`, so a freshly registered member starts with MFA off. The change is in the **enforcement** layer:

- `FeatureModules::Authentication::Registration.enforce_mfa!` currently forces every authenticated user (admin and member) into setup when the customer-level `mfa_enabled` setting is on.
- After this change, that helper short-circuits for member users: customer-wide MFA enforcement applies only to admins/owners. Members are never coerced into setup.
- The per-user enforcement path (`SignInFlow#post_auth_action` → `mfa_required?`) is unchanged. Once a member has turned MFA on themselves, they are challenged at sign-in like anyone else.

### R2. Members manage their own MFA inside the member area

All enable/disable surfaces live under `/:cid/member/security/mfa`. Members do not visit the public `/:cid/auth/mfa/setup` flow (which remains for admin enablement and is also the destination of `enforce_mfa!` redirects for admins).

The existing `/:cid/member/security` page replaces its outbound links with real "Enable MFA" / "Disable MFA" actions backed by the new member-namespaced controller.

### R3. Members get an email-based recovery link, exposed only on the MFA challenge page

A member who can't produce a TOTP code clicks "Lost your authenticator?" on `/:cid/auth/mfa/session`, submits their email on the recovery page, and we send a signed, single-use, 15-minute reset link. Clicking the link clears their `otp_secret` and `otp_required_for_login`, signs them out everywhere, and lands them on the sign-in page.

- Admins are excluded — admin MFA reset stays on the existing admin endpoint (`/:cid/admin/authentication/users/:id/mfa_reset`).
- The recovery form returns the **same** response for member-hit, admin-hit, and unknown email (enumeration defense).

## Data

**No schema changes.** All required columns already exist on `users`:

- `otp_secret` (string)
- `otp_required_for_login` (boolean, default false)
- `last_otp_at` (datetime)

**Reset tokens are stateless.** A token is `Rails.application.message_verifier(:member_mfa_reset).generate(payload, purpose: :consume, expires_in: 15.minutes)` where `payload = { user_id:, customer_id:, otp_fingerprint: }`. The fingerprint is `Digest::SHA256.hexdigest(user.otp_secret)` at mint time.

- Short TTL via `expires_in` blocks late replays.
- Fingerprint binding: a successful consume nils `otp_secret`, so every other outstanding token bound to the old fingerprint fails the fingerprint check on the next attempt. Two unconsumed tokens minted within the same TTL window share a fingerprint and both remain usable until one is consumed; that's acceptable because the TTL caps exposure and any consume already disables MFA.

## Business Logic

Trailblazer activities under `app/concepts/member/mfa/`:

### `Activities::Enable`

Input: `user`, `code`.

1. `verify_user_is_member` — guard: `user.member?`.
2. `ensure_otp_secret_exists` — call `user.generate_otp_secret!` if `otp_secret` is blank. (In practice the GET to render the QR seeds the secret; this step is idempotent.)
3. `verify_otp_code` — call `user.verify_otp(code)`.
4. `enable_mfa!` — call `user.enable_mfa!`.

### `Activities::Disable`

Input: `user`, `code`.

1. `verify_user_is_member`.
2. `verify_mfa_currently_enabled` — guard: `user.mfa_required?`.
3. `verify_otp_code`.
4. `disable_mfa!` — `user.disable_mfa!` (already nils `otp_secret`).

### `Activities::RequestResetLink`

Input: `customer_id`, `email`.

1. `find_member` — `Authentication::User.find_by(customer_id:, email: email.downcase.strip)`. If absent OR user is not a member, return success without sending mail (silent miss).
2. `mint_signed_token` — produces the 15-minute token described above.
3. `deliver_email` — `Member::MfaMailer.reset_link(user, token).deliver_later`.

Returns success in all cases. Logs `event: "member_mfa_reset_requested", customer_id:, hit: <bool>`.

### `Activities::ConsumeResetLink`

Input: `token`.

1. `verify_signature_and_ttl` — `message_verifier.verified(token, purpose: :consume)`. Failure → result `:invalid_or_expired`.
2. `load_user_and_check_member` — load by `(user_id, customer_id)`; require `user.member?`. Failure → `:invalid_or_expired` (same response, no signal to attacker).
3. `verify_fingerprint_matches` — current `otp_secret` fingerprint must equal payload's fingerprint. Failure → `:invalid_or_expired`.
4. `disable_mfa!` — `user.disable_mfa!`.
5. The activity returns success with the loaded user. The controller (`#consume`) handles session teardown via `reset_session` and a Devise sign-out so any pre-existing session held by the attacker or the legitimate user is invalidated.

Logs `event: "member_mfa_reset_consumed", user_id:`.

## Reform Contracts

Under `app/concepts/member/mfa/contracts/`:

- `Enable` — `code` (presence, exactly 6 digits, only digits).
- `Disable` — `code` (same as above).
- `ResetRequest` — `email` (presence, email format).

## Routes

### Member area (member-only, protected)

```ruby
namespace :member do
  resource :security, only: :show do
    resource :mfa, only: [:destroy], controller: "mfa" do
      get  :setup, on: :collection
      post :setup, on: :collection
    end
  end
end
```

Resolved:

- `GET    /:cid/member/security/mfa/setup`
- `POST   /:cid/member/security/mfa/setup`
- `DELETE /:cid/member/security/mfa`

### Public area (recovery flow)

```ruby
namespace :auth do
  resource :mfa_recovery, only: [:new, :create] do
    get :consume, on: :collection
  end
end
```

Resolved:

- `GET  /:cid/auth/mfa_recovery/new`
- `POST /:cid/auth/mfa_recovery`
- `GET  /:cid/auth/mfa_recovery/consume?token=...`

## Controllers

### `Member::MfaController < Member::BaseController`

Inherits `require_member!` from the base. Three actions:

- `setup` (GET) — generate the OTP secret if blank, render the setup view (QR + secret + code field).
- `setup` (POST) — run `Activities::Enable` with `current_user` and the submitted code.
- `destroy` — run `Activities::Disable` with `current_user` and the submitted code.

The controller never accepts a target `user_id`; it always operates on `current_user`. This makes the record-level ownership check trivial and removes a class of cross-user vulnerabilities.

### `Authentication::MfaRecoveriesController < ApplicationController`

Public, no auth. Three actions:

- `new` — render the request form.
- `create` — run `Activities::RequestResetLink`. Always render the same generic confirmation ("If that email belongs to a member account, we sent a reset link").
- `consume` — run `Activities::ConsumeResetLink` with the `token` param. On success: `reset_session`, redirect to sign-in with flash "Two-factor authentication has been disabled. Please sign in." On failure: redirect to sign-in with flash "This reset link is invalid or has expired."

Member-only enforcement lives **inside the activities** so the controller can return identical responses regardless of the email's role / existence.

### `Authentication::MfaSessionsController#show` (existing)

The view (`app/views/authentication/mfa_sessions/show.html.erb` or its component) gains one link below the code input: "Lost your authenticator?" → `auth_mfa_recovery_new_path`. No controller logic change.

### `FeatureModules::Authentication::Registration.enforce_mfa!` (existing)

One-line change: early-return when `controller.current_user.member?`. This is the single point that flips R1.

## Authorization Recap

| Path | Category | Guard |
|---|---|---|
| `/:cid/member/security/mfa/*` | member | `Member::BaseController#require_member!` + customer scoping via `RouteAuthorization`. Controller operates on `current_user` only — no `user_id` params. |
| `/:cid/auth/mfa_recovery/*` | public | None at the controller layer. Activities reject non-member targets. Tokens are signature-verified, 15-minute TTL, fingerprint-bound. |

## UI Surfaces

ViewComponents under `app/components/member/security/` and `app/components/authentication/mfa_recovery/`. Tailwind only, Stimulus only.

1. **`Member::Security::MfaStatusCardComponent`** — replaces the static block on the security page. Pill (green "MFA on" / amber "MFA off"), one line of explanation, single CTA: "Enable MFA" link or "Disable MFA" disclosure.
2. **`Member::Security::MfaSetupComponent`** — full page at `/setup`. Server-rendered QR (reuse the helper used by the admin flow — `rqrcode`), monospace secret with copy button, 6-digit code input + verify, back link.
3. **`Member::Security::MfaDisableConfirmComponent`** — inline panel on the security page. 6-digit code input + confirm/cancel.
4. **`Authentication::MfaRecovery::RequestFormComponent`** — public page. Single email field + submit. Post-submit notice copy is identical for hit and miss.
5. **MFA challenge page** — one-line markup addition: "Lost your authenticator?" link.

**Stimulus:** reuse the existing `clipboard_controller.js` if present from the admin MFA setup; otherwise add a small one. No other JS.

**Mailer:** `Member::MfaMailer#reset_link(user, token)` with `.html.erb` and `.text.erb` templates. Subject "Reset two-factor authentication for your account". Body: short paragraph, link button, "expires in 15 minutes", "if you didn't request this, ignore". Uses the existing transactional mail layout.

**i18n:** all user-visible strings in `config/locales/en.yml` under `member.security.mfa.*` and `authentication.mfa_recovery.*`.

**Sidebar:** no new entry. MFA hangs off the existing member "Security" page.

## Testing

### Activity specs (`spec/concepts/member/mfa/activities/*`)

- `Enable` — happy path; wrong code leaves `otp_required_for_login=false`; non-member input fails the role check; blank `otp_secret` is generated on first call.
- `Disable` — happy path nils the secret; wrong code leaves MFA on; non-member fails.
- `RequestResetLink` — member email → mail enqueued and token signed; non-member email → no mail, success result; unknown email → no mail, success result.
- `ConsumeResetLink` — valid token → MFA cleared; expired token (>15 min) fails; tampered signature fails; reused token after secret changed fails (fingerprint mismatch — proves single-use); admin-targeted token fails.

### Contract specs

`Enable`, `Disable`, `ResetRequest` — presence, format, length.

### Request specs (`spec/requests/member/mfa_spec.rb`, `spec/requests/authentication/mfa_recoveries_spec.rb`)

- Multi-tenant isolation: member of customer A cannot hit `/:B_cid/member/security/mfa/setup`.
- Authorization: signed-out → redirect to sign-in. Admin user → blocked from member MFA endpoints.
- `MfaRecoveriesController#create` returns identical status + body for member-hit, admin-hit, and unknown email.
- `#consume` with an admin-targeted token → generic redirect; admin's MFA is unchanged.

### Component specs (`spec/components/member/security/*`)

- `MfaStatusCardComponent` renders correct CTA for both `mfa_required?` states.
- `MfaSetupComponent` renders QR + secret + form when given a user with a fresh `otp_secret`.
- `MfaDisableConfirmComponent` renders the code input form posting to DELETE.

### System spec (`spec/system/member/mfa_lifecycle_spec.rb`)

One end-to-end happy-path browser walk-through:

1. Member signs up → lands on dashboard with MFA off.
2. Visits `/:cid/member/security` → sees "MFA off" and Enable button.
3. Clicks Enable → scans QR (test reads `otp_secret` directly and computes the code via `ROTP::TOTP`).
4. Submits code → MFA on.
5. Signs out, signs back in → forced through `/:cid/auth/mfa/session` challenge.
6. Clicks "Lost your authenticator?" → enters email → reads delivered mail from `ActionMailer::Base.deliveries` → clicks link → redirected to sign-in with MFA disabled.
7. Signs in normally → no challenge.

### Stale-test policy

Existing `enforce_mfa!`-related specs that assume customer-wide MFA forces member users will fail after R1. Per the user's stale-test policy, those specs are **rewritten** to assert "members are not forced; admins still are," not patched-around by reverting the production change.

## Observability

Plain Rails logs are sufficient. Two structured log events:

- `event: "member_mfa_reset_requested", customer_id:, hit: true|false`
- `event: "member_mfa_reset_consumed", user_id:`

Useful for spotting abuse patterns (spike in `hit: false` from one IP, repeated consume failures) without a new dashboard.

## Out of Scope

- Backup codes / printable recovery codes — recovery is via email link.
- WebAuthn / hardware keys — TOTP only.
- SMS / phone-based factors — TOTP only.
- Admin email-based recovery — admins continue to use the peer-admin reset endpoint.
- Cross-tenant member identity (a single email belonging to multiple customers) — out of scope; existing `find_for_database_authentication(email:, customer_id:)` semantics are unchanged.
