# Trust This Device — 2FA Sign-In Design

**Date:** 2026-06-13
**Status:** Approved, ready for implementation

## Problem

When a user with 2FA enabled signs in, they are always prompted for a TOTP
code (`/:cid/auth/mfa/session`). Like other major platforms, users should be
able to mark a device as trusted at the verification step so that subsequent
sign-ins from the same device skip the 2FA prompt for a bounded window.

## Decisions

- **Trust window:** 30 days.
- **Management UI:** Deferred. No self-service "trusted devices" list yet.
  Trust auto-expires and is wiped on the revocation events below. Metadata
  columns are included so a UI can be added later with no migration.
- **Auto-revocation:** all of a user's trusted devices are invalidated on
  (a) MFA disable/reset and (b) password change/reset.

## Architecture

The sign-in pipeline already routes both the Devise `SessionsController` and
the public `CustomerResolutionsController` through `Authentication::SignInFlow`
(single source of truth — this was deliberately centralized to prevent an MFA
bypass from the two controllers drifting). All trust-consumption logic lands in
`SignInFlow` to preserve that invariant.

A cookie alone is insufficient: it cannot be expired or revoked server-side.
The source of truth is a server-side `trusted_devices` row; the cookie only
carries an opaque random token whose SHA-256 digest is matched against the row.

### Components

#### 1. Model — `Authentication::TrustedDevice` (table `trusted_devices`)

Follows the `Authentication::User` convention (`self.table_name`, namespaced
class). Columns:

| Column         | Type     | Notes                                            |
|----------------|----------|--------------------------------------------------|
| `customer_id`  | integer  | null:false, indexed — multi-tenant scope         |
| `user_id`      | integer  | null:false, indexed — owner                      |
| `token_digest` | string   | null:false, **unique** — SHA-256 of raw token    |
| `expires_at`   | datetime | null:false, indexed                              |
| `last_used_at` | datetime | nullable — bumped on each successful match       |
| `ip`           | string   | nullable — issuance metadata                     |
| `user_agent`   | string   | nullable — issuance metadata                     |
| timestamps     |          |                                                  |

The raw token is never persisted. `belongs_to :user, class_name "Authentication::User"`.

API:
- `self.digest_for(raw)` — `Digest::SHA256.hexdigest(raw)`.
- `scope :active, -> { where("expires_at > ?", Time.current) }`.
- `self.authenticate(user:, raw_token:)` — returns the active matching record
  for that user (scoped by `user_id` AND `customer_id`), bumping `last_used_at`,
  else `nil`. Returns `nil` for blank tokens.
- `self.issue!(user:, ip:, user_agent:, ttl: 30.days)` — generates a urlsafe
  32-byte token, creates the row with `expires_at: ttl.from_now`, returns
  `[record, raw_token]`.

#### 2. Issuing trust — `MfaSessionsController#create`

- View `mfa_sessions/show.html.erb` gains a **"Trust this device for 30 days"**
  checkbox (Tailwind, inside an extracted ViewComponent for the form if it
  isn't already one).
- On successful `verify_otp`, when the checkbox is set:
  1. `record, raw = TrustedDevice.issue!(user: current_user, ip: request.remote_ip, user_agent: request.user_agent)`
  2. Set signed cookie `:trusted_device` = `"#{record.id}:#{raw}"` with
     `httponly: true`, `secure: Rails.env.production?` (or `request.ssl?`),
     `same_site: :lax`, `expires: 30.days.from_now`.

#### 3. Consuming trust — `Authentication::SignInFlow`

- `Result` gains a `mfa_verified:` boolean (default `false`).
- `.call` accepts optional keyword `trusted_device_token:`.
- `post_auth_action`: when `user.mfa_required?` and
  `TrustedDevice.authenticate(user:, raw_token: trusted_device_token)` returns a
  record → `next_action: :authenticated, mfa_verified: true`. Otherwise the
  existing branching is unchanged (`mfa_verified: false`).
- Both sign-in controllers read the `:trusted_device` signed cookie, split off
  the raw token, pass it as `trusted_device_token:`, and set
  `session[:mfa_verified] = result.mfa_verified`. A trusted device thus lands on
  the dashboard with the session already satisfying `enforce_mfa!`.

#### 4. Auto-revocation — `Authentication::User` callback

```ruby
has_many :trusted_devices, class_name: "Authentication::TrustedDevice",
         dependent: :delete_all
after_update :revoke_trusted_devices!,
  if: -> { saved_change_to_encrypted_password? ||
           (saved_change_to_otp_secret? && otp_secret.nil?) }

def revoke_trusted_devices!
  trusted_devices.delete_all
end
```

- `encrypted_password` change covers password change AND reset.
- `otp_secret → nil` covers `disable_mfa!`, the single path behind both member
  self-disable and admin/owner MFA reset.

A stale cookie left after revocation simply fails the digest lookup — harmless.

## URL / Authorization categorization

No new routes. The trust checkbox lives on the existing
`authentication/mfa_sessions` surface (an MFA-exempt auth controller). All
trust evaluation is server-side and user-scoped; cross-tenant tokens cannot
match because `authenticate` filters on both `user_id` and `customer_id`.

## Testing

- **Model spec:** `digest_for`, `active` scope, `issue!` (token shape, ttl,
  digest stored not raw), `authenticate` (match bumps `last_used_at`; expired →
  nil; blank → nil; wrong user → nil; wrong tenant → nil).
- **SignInFlow spec:** valid trusted token + `mfa_required?` → `:authenticated`
  + `mfa_verified: true`; no/expired/foreign token → `:mfa_required` +
  `mfa_verified: false`; non-MFA user unaffected.
- **MfaSessionsController request spec:** checkbox set → row created + signed
  cookie issued; unchecked → neither; invalid code → no row.
- **Revocation spec:** password change wipes rows; `disable_mfa!` wipes rows;
  rotating `otp_secret` to a new value does NOT wipe (only nil does).
- **Multi-tenant isolation:** a token issued for customer A never satisfies MFA
  for a customer B user.

## Out of scope

- Self-service trusted-device management/list/revoke UI.
- "New device" email notifications.
- Per-device naming.
