# Authentication Module — Aggressive Hardening & Refactor

**Date:** 2026-07-14
**Scope:** Security hardening of the mandatory Authentication module to an OWASP-ASVS bar.
**Status:** Design — implementation on `master` (no auto-commit; manual review).

## 1. Goal

Authentication is already well-built and security-conscious: session fixation is prevented
(`reset_session` before sign-in), TOTP replay is blocked (`after: last_otp_at`), enumeration
is defended (paranoid mode + identical failure renders), the reserved-role **owner-pin**
invariant is enforced, and tenant scoping is thorough. This refactor is therefore *hardening,
not rebuild* — it closes the concrete gaps the audit found while preserving every existing
invariant (owner-pin, path-driven admin/member/platform gates, per-customer scoping).

**Non-negotiable invariants (must not weaken):** the three reserved roles and their access
rules; `owner` grantable only to the canonical user under customer 81721200; admin-or-owner on
admin routes, member on member routes; record-level `customer_id`/`user_id` ownership checks.

## 2. Bugs / gaps fixed (from audit), sequenced low→high blast radius

| # | Item | Fix |
|---|------|-----|
| C  | `otp_secret` plaintext at rest | `encrypts :otp_secret` (Rails AR encryption) + spec asserting ciphertext at rest |
| F  | No auth audit trail | New `authentication_events` ledger (login success/failure, lockout, MFA enable/disable/verify-fail, role grant/revoke, password reset) + `Authentication::Instrumentation` subscriber on `authentication.event` notifications |
| B4 | A non-owner admin can strip the platform owner's role via the multi-assign / `destroy` path | Symmetric owner guard in `UserRoles::Operation::Assign` + `UserRoleAssignmentsController#destroy` (mirror the single-user path guard) + spec |
| B2/B5/B6 | Unthrottled MFA verify + per-process login store + no reset/confirm throttle | One `Authentication::Throttle` service backed by the shared cache store, covering login + MFA-verify + password-reset + confirmation-resend uniformly |
| B7 | Dead per-tenant `session_timeout` / `max_login_attempts` | Wire both: throttle reads `max_login_attempts`; a `timeoutable` override reads `session_timeout` from the customer config |
| B3 | (audit miscalc) — ROTP `drift_*` are SECONDS not steps, so ±15 was ±15s (≈1 live code), not ±7.5 min | No numeric change needed; left at ±15s (sane skew tolerance) with a corrected comment. Brute force is bounded by the new MFA throttle + replay prevention |
| B1 | Two divergent per-request MFA enforcers (AppController + Registration.before_request) | Consolidate into ONE `Authentication::MfaEnforcement` service with a single exempt list — **done last**, behind the full request-spec suite |
| B8 | Member signing in from marketing root lands on `/admin` | Route by role (mirror `after_sign_in_path_for`) |
| B9 | `users/show` `first_name[0]` can `NoMethodError` on blank name | Nil-safe initial helper |
| B11 | Hard-coded English strings in `Roles`/`RoleGrants` concept operations | Route through I18n (en + zh-CN) |

## 3. Data model

- **`authentication_events`** (new ledger): `customer_id`, `user_id` (nullable — failed logins may
  not resolve a user), `event` (string), `ip`, `user_agent`, `metadata` (JSON), `created_at`.
  Indexed on `(customer_id, created_at)` and `(user_id, created_at)`. TenantScoped where a tenant
  is known; failed pre-auth events recorded with best-effort `customer_id`.
- **`authentication_users.otp_secret`** → encrypted (no schema change; `encrypts` is transparent;
  existing plaintext read via `support_unencrypted_data` during transition, then re-encrypted on
  next MFA change).

## 4. New services

- `Authentication::Throttle` — `check!(key:, limit:, period:)` / `record_failure` / `clear`,
  backed by `Rails.cache` (shared store). Used by sessions, mfa_sessions, passwords,
  confirmations. Reads per-tenant `max_login_attempts` where applicable. On breach → a
  localized "too many attempts" response (no enumeration).
- `Authentication::AuditLog.record(event:, user:, customer_id:, request:, **meta)` — thin writer
  that emits an `authentication.event` notification; the ledger row is written by the subscriber
  so controllers stay decoupled.
- `Authentication::Instrumentation` subscriber (+ initializer) — persists events + structured log.
- `Authentication::MfaEnforcement` (last) — single source of truth for per-request MFA, replacing
  the two enforcers; one exempt list; preserves current (union-of-both) strictness exactly.

## 4a. Delivered vs deferred

**Delivered:** `encrypts :otp_secret`; audit-log ledger + `Authentication::AuditLog` +
`Authentication::Instrumentation` subscriber, wired into login (success/failed/locked), logout,
MFA (verified/failed/enabled/disabled), password reset (requested/completed), role
grant/revoke, and throttle events; B4 symmetric owner-demotion guard (Assign + destroy); a
shared-store `Authentication::Throttle` on MFA-verify (B2) and password-reset (B6); TOTP drift
comment corrected (B3 — no numeric change; ±15s was already sane once the seconds-vs-steps
miscalc was fixed); member-root routing on the login AND MFA controllers (B8); nil-safe initials
(B9); I18n the four concept-operation
strings (B11). All 390 existing auth examples stay green.

**Deferred (documented, follow-up):** B1 (consolidating the two MFA enforcers) — high blast
radius on a mandatory module and *not an active bypass* (the union is at least as strict), so it
warrants its own dedicated change behind the full suite rather than riding this pass. B7 (wiring
per-tenant `session_timeout`/`max_login_attempts`) — changes real per-request login/timeout
behavior; deferred to avoid destabilizing the login path in the same pass. B5 (login uses a
per-process store) — the new shared-store Throttle is in place for MFA/reset; migrating the
existing Rails-8 `rate_limit` login blocks onto it is a follow-up. Password breach/complexity
checks and a user-facing session/device UI remain future work.

## 5. Out of scope (noted)

- Backup/recovery codes (recovery is an email-link MFA reset by design) — not added.
- Password breach/complexity checks (HIBP/zxcvbn) — length policy retained; noted as follow-up.
- User-facing active-session/device management UI — server-side trusted devices already exist.

## 6. Testing

Per gap: otp_secret ciphertext-at-rest; MFA-verify throttle + lockout; **B4 owner cannot be
demoted by a non-owner via the assign/destroy path**; reset/confirm throttle; per-tenant
session_timeout/max_login_attempts wiring; audit-ledger rows for each event type; consolidated
MFA enforcer parity vs the old two-enforcer behavior; member-root routing; i18n parity. All
existing ~390 auth examples must stay green at every step (the invariant safety net).
