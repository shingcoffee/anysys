# Authentication Module — Professional Redo (Deep Pass)

**Date:** 2026-07-14
**Module:** 1 of 5 (authentication → email → sms → email_campaigns → captcha)
**Scope:** Fresh, deeper professional-grade pass. Bug fixes + security hardening + architecture consolidation + maximum-tier functionality enrichment. Baseline = the 07-13/07-14 hardening pass (in scope for criticism).
**Method:** Consolidated from five parallel adversarial audits (architecture, correctness, security, feature-gaps, tests/i18n). Top findings verified by direct code reading.
**Execution:** Changes on `master`, uncommitted (user reviews & commits). Fully autonomous.

## Non-negotiable invariants (never weakened)

Three reserved roles + owner-pin (owner grantable only to `lingercoffee@gmail.com` under customer `81721200`); four URL areas with controller-layer guards; record-level `customer_id`/`user_id` checks; I18n en+zh-CN on every user-facing string with key/interpolation parity; ViewComponent/Tailwind/Stimulus only; Trailblazer/Reform for business logic; mature gems over hand-rolls; features degrade gracefully with no live external vendor account; JS at 100% Vitest lines+branches.

---

## Overall assessment

Security *primitives* are strong (tenant-scoped Devise recovery, session-fixation rotation, digest-only trusted devices, decoupled audit ledger, path-driven `RouteAuthorization`). The weakness is **structural entropy from an additive hardening pass**: new services were layered *beside* older inline code instead of replacing it, leaving the module doing several things two or three ways — two MFA enforcers, two MFA implementations with different re-auth rules, two sign-in controllers, three throttlers, two role-assignment paths, an owner-guard smeared across four layers. Duplication is where auth bugs hide, and two already surfaced (admin-vs-member MFA-disable re-auth divergence; the account-vs-role owner-protection gap). The right work is **consolidation onto the single best implementation, then enrichment on the cleaned base.**

---

## Part 1 — Bugs & security fixes (sequenced low→high blast radius)

### Security (do first — highest value)

| # | Sev | Item | Fix |
|---|-----|------|-----|
| **S1** | **High** | Co-tenant admin can take over / lock out the **platform-owner account** — owner-pin protects the *role*, not the *account*. `UsersController#update` sets any tenant user's `:password`; `UserMfaResetsController` disables any user's MFA; `UserActivationsController#destroy` deactivates any user — **none** guard `user.owner?`. A non-owner admin under `81721200` can reset the owner's MFA + password and sign in as owner (`can :manage, :all` cross-tenant), or deactivate the owner. **Verified.** | Add `protect_owner_account!` guard (refuse to mutate a target where `target.owner? && !current_user.owner?`) to `UsersController#update`, `UserMfaResetsController#create`, `UserActivationsController#destroy`. Centralize in one concern. |
| **S2** | **High** | **Role-grants privilege escalation at the CanCan layer.** `RoleGrants::Operation::Update#add_grant!` validates tenant ownership only for `INSTANCE_BASED_TYPES`; a non-owner admin can add a `subject_type:"Platform"`/`"Module"` grant to a custom role → `can :manage, :platform_*`. Currently contained by the path-level platform gate (`enforce_route_role!` requires `platform_owner?`), so not a live route breach, but the grant must not be creatable (defense-in-depth). **Verified.** | Allowlist tenant-grantable `subject_type`s; reject `Platform`/`Module` (and any non-tenant subject) unless `current_user.owner?`. Add op + request specs (TEST-1). |
| **S3** | Med | Deactivating a user does **not** end their live session (`status` enum enforced only at login; no `active_for_authentication?` override; `timeoutable` is idle-only). | Override `Authentication::User#active_for_authentication?` to also require `active?` (+ `inactive_message`), routing status through Devise's per-request `activatable` hook. |
| **S4** | Med | Email-dispatching endpoints unthrottled (MFA-recovery request, confirmation resend) — email-bomb / reputation abuse. Design §4 *claimed* confirmation-resend was covered; shipped code does not. | Apply `Authentication::Throttle` (per-IP + per-`SHA256(email)`) to `MfaRecoveriesController#create` and `ConfirmationsController#create`, mirroring `passwords_controller`. |
| **S5** | Med | Login IP rate-limit uses a **per-process** `MemoryStore` and two independent buckets across the two sign-in controllers (B5). | Migrate login onto the shared-store `Authentication::Throttle` keyed per-IP, shared by both controllers; delete the `MemoryStore` constants. (Folds into ARCH-5.) |
| S6 | Low | Admin resets any peer's password with no notification / no acting-admin re-auth (accountability). | Email the affected user on any admin-initiated credential change; audit via `AuditLog`. (Re-auth deferred — see enrichment #7.) |
| S7 | Low | Self-registration enumerates emails ("Email has already been taken") while `paranoid` covers other flows. | On duplicate email with signup enabled, render the generic "confirmation sent" response (and notify the existing account owner). |
| S8 | Low | MFA-recovery `consume` disables MFA on a **state-changing GET** (link-prefetch risk). | Interstitial page + `POST` to actually disable; keep the signed single-use token. |
| S9 | Low | No CSP; `reconfirmable=false` lets a session-holder repoint email unverified. | Enable CSP (report-only first). `reconfirmable` handled by enrichment #3. |
| S10 | Low | Login timing side-channel (no dummy bcrypt when user not found). | Run a fixed dummy `bcrypt` compare in `SignInFlow` when the user is nil. |

### Correctness bugs

| # | Sev | Item | Fix |
|---|-----|------|-----|
| **B1** | **High** | Assigning the **"member" role** via the admin user form strips all roles and never grants `member` → the user can log in but reaches neither member nor admin surface (lockout). `assign_user_role` early-returns on `"member"` after `delete_all`. **Verified.** Stale spec `admin/users_spec.rb:377-394` codifies the bug — rewrite it. | `find_or_create` the tenant's `member` system role and create the `users_roles` row (mirror self-signup `assign_member_role!`). Folds into ARCH-6 (route admin path through `UserRoles::Operation::Assign`). |
| **B2** | Med | Saving the generic module-config page **replaces** the whole `configuration` blob, silently wiping `allow_registration` / `allow_password_reset`. | Merge onto existing config in `Admin::ModuleConfigsController#update`. |
| **B3** | Med | "Remember me" is a dead checkbox — explicit `sign_in(resource, user)` bypasses Warden's Rememberable strategy; no persistent cookie ever set. | After sign-in, honor `sign_in_params[:remember_me]` via Devise `remember_me(resource)`. Extracted into the shared session-establishment path (ARCH-3). |
| **B4** | Med | A member who merely **opens** the MFA setup page persists an `otp_secret` on a bare GET, then is force-locked into enabling MFA on next login (two enforcers disagree). | Don't persist a secret on GET (generate in-memory / on submit); exempt members in the enforcer's configured-but-not-enforced branch. Folds into ARCH-1 + ARCH-2. |
| B5 | Med(consistency) | Unconfirmed sign-in gate lives only in `SessionsController`, not `CustomerResolutionsController`. **Currently backstopped** by Devise's `activatable` per-request hook + 0-day grace, so not a live bypass — but a real divergence. | Move the `confirmed?`/active gate into `SignInFlow` (add `:unconfirmed` next_action) so both controllers share it. |
| B6 | Low | `Throttle#record_failure` first-failure seed is non-atomic (two concurrent first failures both write 1). | Use atomic init (`increment` after a guaranteed-present key, or `write(...unless exist?)` + `increment`); pin with a spec. |
| B7 | Low | Dead per-tenant `session_timeout` / `max_login_attempts` config keys (surfaced as editable, read nowhere). | **Wire them** (enrichment #8) rather than delete — they become live tenant controls. |

---

## Part 2 — Architecture consolidation

Ordered by value; all behind the existing ~390-example auth suite.

1. **Unify the two per-request MFA enforcers** (ARCH-1/SEC-5/B4) into one `Authentication::MfaEnforcement` service — single exempt list, single explicit policy (per-tenant enforcement for admins ∪ per-user opt-in), members honored consistently. Delete `ApplicationController#enforce_mfa!` and the three hand-synced exempt lists. **M**
2. **Collapse the duplicated MFA subsystem** (ARCH-2) into one `Mfa::Operation::{Enable,Disable,Verify}` consumed by both the admin/generic controllers and the member concept; one shared QR + `no-store` concern (reuse `Payments::QrCodeComponent`); pick one disable-reauth policy deliberately (require OTP **and/or** current password uniformly, strongest for the more-privileged actor). **M**
3. **Extract post-auth session establishment + role routing** (ARCH-3/ARCH-4/B3): `SignInFlow#establish_session!(controller)` (reset_session → sign_in → remember_me → tracked fields → mfa_verified → audit → next-action redirect) shared by both sign-in controllers; one `Authentication::User#home_path(customer_id)`; hoist the open-redirect guard into one concern method. **S/M**
4. **Migrate login onto `Authentication::Throttle`** (ARCH-5/SEC-4/S5); delete the per-process `MemoryStore` constants; one limiter across both controllers. **S**
5. **Route the admin Users role path through `UserRoles::Operation::Assign`** (ARCH-6/B1); keep the owner guard in exactly one layer. **M**
6. **`Authentication::DeviseGuarded` concern** (ARCH-9) providing `check_auth_enabled` + settings-gate helpers to the four Devise controllers; **generic `AuthToggleController`** (ARCH-11) parameterized by config key + i18n scope for SignUp/ForgetPassword. **S**
7. **Componentise the auth forms** (ARCH-10): `Authentication::FormErrorsComponent` + `AuthFieldComponent`/`AuthFormComponent`; remove the copy-pasted error-box + `input-member`/`btn-member` markup from five templates. **M**
8. **Retire dead code / finish scaffolding** (ARCH-7/ARCH-8/ARCH-13): wire the four unused Reform contracts through their operations (per convention) or delete them + specs; give the audit ledger a read surface (enrichment #1/#2); fix stale comments (ARCH-14); derive `Ability#member_route_subjects` from routes instead of a hand-maintained array. **S/M**

---

## Part 3 — Maximum-tier enrichment

Value-to-effort order. Member routes stay member-only; four-URL-area placement respected; nothing needs a live external vendor at runtime. The first items light up infrastructure already built and paid for (`authentication_events`, Devise `lockable`/`recoverable`, the dead config keys).

1. **Member recent-activity feed** *(S)* — `/:cid/member/security/activity`, `Authentication::Event.for_user(...).recent` + Pagy, `Member::ActivityListComponent`; teaser card on the security page. No schema, no gem. Closes the write-only-ledger gap (member side).
2. **Admin per-user auth-events view** *(S)* — `events` route on `admin/modules/authentication/users`, ledger scoped `where(customer_id:, user_id:)`. Closes it (admin side).
3. **Member in-app password change + email change w/ re-confirmation** *(M)* — `Member::CredentialsController#password/#email` requiring `current_password`, Devise `update_with_password` / reconfirmation; flip `config.reconfirmable = true` (the `unconfirmed_email` column already exists). Reform contracts. Resolves S9's reconfirmable half.
4. **Password strength + breach/common-password screening** *(M)* — add `zxcvbn`; `Authentication::PasswordPolicy` service (zxcvbn score + bundled offline `config/common_passwords.txt` denylist, no network HIBP); hook `Authentication::User` validation; per-tenant on/off + min-score knob; `password_strength_controller.js` (Stimulus, 100% Vitest, English `default:` + server-passed translations).
5. **Active session / device management** *(M/L)* — new `authentication_sessions` table (`customer_id`, `user_id`, `token_digest`, `ip`, `user_agent`, `last_seen_at`), written on sign-in (mirror `TrustedDevice.issue!`), touched per request; member `/:cid/member/security/sessions` list + revoke-one/revoke-others; admin read-only on user show. Prerequisite for accurate #6.
6. **Sign-in alert emails** *(M)* — extend `Authentication::Instrumentation`: a `login_succeeded` from a device/IP absent from `authentication_sessions`/`trusted_devices` enqueues alert mail via the **existing Email module**; per-tenant toggle; **degrades to no-op** if Email is disabled.
7. **Admin force-password-reset + manual unlock** *(S each)* — `password_resets#create` (send Devise reset / set a `force_password_change` flag) and `unlocks#create` (`user.unlock_access!`) under the admin users resource; audit both. Pairs with S6 notification.
8. **Per-tenant password policy + wire the dead keys** *(S/M)* — extend the `Registration` schema with `min_password_length` / `require_complexity` (read in the #4 policy service); simultaneously **wire the already-present `session_timeout`** (into `timeoutable`) **and `max_login_attempts`** (into the login `Throttle` / Devise `maximum_attempts`) — B7. Three dead keys become live.
9. **Passkeys / WebAuthn** *(L, isolated slice)* — add `webauthn` gem; `authentication_credentials` table (`customer_id`, `user_id`, `webauthn_id`, `public_key`, `sign_count`, `nickname`); `Authentication::WebauthnRelyingParty` wrapper (thin app-level interface); member management `/:cid/member/security/passkeys`; register + assert endpoints on public `/:cid/auth`; `webauthn_register`/`webauthn_login` Stimulus controllers. Password login stays as fallback. Self-hosted relying party — offline.

**Deferred (honest):** impersonation (platform-owner-only + mandatory audit; its own reviewed change), SSO/OIDC/SAML (own module — per-tenant IdP config is not an enrichment), MFA backup codes (module deliberately chose email-link recovery).

---

## Part 4 — Tests & i18n (carried through every slice)

**Highest-value spec additions** (each slice ships with its specs; multi-tenant + authz negatives mandatory):
- **TEST-1** role-grants Platform/Module escalation (op + request) — pairs with S2.
- **TEST-2** `UserRoles::Operation::Assign` refuses owner→ineligible at the op layer (not only via model validation).
- **TEST-3** `Roles::Operation::Create` rejects reserved keys at the op layer (not incidentally via uniqueness).
- **TEST-4** record-level cross-tenant 404 on roles / role_grants / user_role_assignments create / activate / deactivate / reset_mfa.
- **TEST-5** open-redirect rejection branches (`safe_local_path?`, `safe_stored_location`).
- **TEST-6** `SignInFlow` failure-branch contract (locked → `:invalid_credentials` **with** `result.user`; unknown email → `user: nil`, no raise).
- **TEST-7…21** throttle atomicity/window/prod-cache branch; `Ability` owner via real pinned owner; `Settings` defaults; `Registration#sidebar_contributions` four-area conformance; `mandatory!`; deprovisioner re-enable claim; single-use recovery double-consume; etc.
- Refresh the stale checked-in `coverage/javascript/lcov.info`; confirm the 3 flagged JS false-branches with a real `npx vitest run --coverage`.

**I18n fixes** (all currently hard-coded literals; en byte-identical, zh-CN idiomatic; keys in the matching area file):
- **I18N-1** reserved role name/description (`seed_reserved.rb`) — stable keys in the constant, translate in the accessor (rendered on roles index/show, role-grants show, user-roles badge).
- **I18N-2** member MFA op error strings (`member/mfa/operation/{disable,enable}.rb`).
- **I18N-3** auto-created member role name (`registrations_controller.rb`).
- **I18N-4** feature-module description (`Registration.module_description`).
- **I18N-5** `configuration_schema` descriptions (rendered by the generic config page).
- **I18N-6** `you@example.com` placeholder across four auth forms.

---

## Shipped in this pass (verified, tested, suite green)

Slice A (security) + core correctness bugs, each with new/updated specs; auth suite green (419 examples, 0 failures):

- **S1** owner-account protection — `Authentication::OwnerAccountProtectable` concern wired into `UsersController#update`, `UserMfaResetsController#create`, `UserActivationsController#{create,destroy}`. Specs: owner-account-protection block on MFA-reset / deactivate / password-set; owner allowed.
- **S2** role-grants platform-escalation — `RoleGrants::Operation::Update` rejects `Platform`-scoped grants unless the actor is an owner (`OWNER_ONLY_SUBJECT_TYPES`, fail-closed when no actor); controller threads `actor: current_user`. Op specs added (TEST-1).
- **S3** deactivation revokes live sessions — `Authentication::User#active_for_authentication?`/`#inactive_message` route the `status` enum through Devise's per-request activatable hook. Model + request specs.
- **S4** email-flood throttle — `Authentication::EmailFloodThrottled` concern (dual per-IP + per-email buckets) on `MfaRecoveriesController#create` and `ConfirmationsController#create`. Request specs.
- **B1** member-role lockout — `assign_user_role` now creates the per-customer `member` role row instead of early-returning. Stale spec rewritten; lockout + first-demotion specs added.
- **B2** config-blob wipe — `Admin::ModuleConfigsController#update` merges onto existing config. Merge-preservation spec.
- **B3** dead "Remember me" — both sign-in controllers set `resource.remember_me` before `sign_in` so Devise issues the persistent cookie. Cookie specs.

i18n: new keys added to both `en` and `zh-CN` (`admin_modules.flash.users.owner_account_protected`, `auth.errors.platform_grant_forbidden`, `devise.failure.deactivated`, `auth.flash.{confirmation,mfa_recovery}.throttled`).

**Deferred to follow-up slices (captured above, not yet built):** remaining lower-severity security (S6–S10), correctness B4–B7, all of Part 2 (architecture consolidation), all of Part 3 (enrichment #1–#9), and the full Part 4 i18n/coverage sweep. These are designed and sequenced but not implemented in this pass.

## Build sequence

Slices land in this order so a stop is always clean and the suite gates each boundary:
**A. Security fixes** (S1, S2, S3, S4, S6, S7, S8, S9-CSP, S10) → **B. Correctness bugs** (B1/ARCH-6, B2, B4, B5, B6) → **C. Architecture consolidation** (ARCH-1→8, folds in S5/B3/ARCH-14) → **D. Enrichment** (#1→#9 in order, each its own slice) → **E. i18n sweep + coverage refresh**. Targeted specs per slice; full parallel suite green + `vitest --coverage` 100% at module end; browser smoke of the new member security surfaces.
