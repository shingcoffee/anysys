# Deferred Enrichment Backlog — Five-Module Redo

**Date:** 2026-07-14
**Status:** DEFERRED — designed, not built. Paused by user before implementation started; resume on request.
**Parent:** `2026-07-14-five-module-redo-umbrella-design.md` (fix passes for all five modules shipped and committed in `a5d2750`; these enrichment sets are the remaining designed-but-unbuilt work).

## How to resume

Work strictly **one module at a time**, in umbrella order: **authentication → email → sms → email_campaigns → captcha**. Each module: plan (writing-plans) → subagent build slice-by-slice (backend / frontend / security-engineer + QA) → targeted specs per slice → full parallel suite + vitest 100% + browser smoke at module end → tech-lead + code-reviewer on the module diff. Changes stay on `master` uncommitted (user reviews and commits). Full slice details live in each module's `2026-07-14-<module>-redo-design.md` ("Maximum-enrichment build set" / "Part 3").

- **Authentication already has a full implementation plan:** `docs/superpowers/plans/2026-07-14-authentication-enrichment.md` (9 slices, task-level, with contracts, routes, migrations, spec matrices, and the final verification gate). Start there.
- A slice-1 build was briefly started and then **fully reverted** — the working tree carries no enrichment code; there is no partial state to reconcile.

---

## 1. Authentication (spec: `2026-07-14-authentication-redo-design.md` Part 3; plan: `plans/2026-07-14-authentication-enrichment.md`)

Value-to-effort order; each is its own slice:

1. **Member recent-activity feed** *(S)* — `/:cid/member/security/activity` over the existing `authentication_events` ledger (`Authentication::Event` — NOT TenantScoped, always filter `customer_id` + `user_id`); Pagy; `Member::ActivityListComponent`; teaser card on the security page. Shared `auth.events.*` label tree (en+zh-CN) reused by item 2.
2. **Admin per-user auth-events view** *(S)* — `events` member route on `admin/modules/authentication/users`, ledger scoped `(customer_id, user_id)`; link + recent section on the admin user show.
3. **Member in-app password change + email change w/ re-confirmation** *(M)* — `Member::CredentialsController#password/#email` under `/:cid/member/security/credentials/*`, `current_password` required, Reform contracts, `bypass_sign_in` after password change; flip `config.reconfirmable = true` (`unconfirmed_email` column already exists). New ledger events `password_changed`, `email_change_requested`.
4. **Password strength + breach/common-password screening** *(M)* — add `zxcvbn` gem; `Authentication::PasswordPolicy` service (offline `config/common_passwords.txt` denylist + zxcvbn min-score); `Authentication::User` validation; public throttled `POST /:cid/auth/password_strength` JSON endpoint; `password_strength_controller.js` Stimulus meter (values-based i18n, 100% Vitest) mounted on all four password forms. **Factory passwords must be strengthened repo-wide** (they'd fail the new policy).
5. **Active session / device management** *(M/L)* — new `authentication_sessions` table (`customer_id`, `user_id`, `token_digest` unique, `ip`, `user_agent`, `last_seen_at`, `revoked_at`); `Authentication::UserSession` mirrors `TrustedDevice` (digest-only); `SessionRegistry` concern (issue on sign-in in BOTH sign-in controllers, per-request enforce + throttled touch, revoke on sign-out; pre-feature sessions exempt); member list/revoke-one/revoke-others under `/:cid/member/security/sessions`; admin read-only on user show; `device_detector` gem for UA labels. Prerequisite for item 6.
6. **Sign-in alert emails** *(M)* — `Authentication::SignInAlert` service + job after session issue: alert iff prior sessions exist AND no prior session shares the IP AND no active trusted device (first-ever login never alerts); per-tenant `sign_in_alerts_enabled` toggle (default true); delivery via `Email::Gateway.send_raw`; no-op when Email module inactive; failure-isolated (never breaks login).
7. **Admin force-password-reset + manual unlock** *(S each)* — `users/password_resets#create` (`send_reset_password_instructions`) and `users/unlocks#create` (`unlock_access!`, button only when `access_locked?`) under the admin users resource; both `protect_owner_account!`-guarded and audited (`password_reset_requested` w/ `admin_initiated` metadata; new `account_unlocked` event).
8. **Per-tenant password policy + wire the dead config keys** *(S/M)* — schema + `Authentication::Settings` readers for `min_password_length` (8) / `require_complexity` (false); complexity arm in `PasswordPolicy`; **wire the dead `session_timeout`** (per-record Devise `timeout_in` override) **and `max_login_attempts`** (lockable `attempts_exceeded?`/`maximum_attempts` override — check Devise 5 source for which); generic config page gains i18n description fallback `t("feature_modules.<key>.config.<field>", default: schema description)` (closes I18N-5 for auth).
9. **Passkeys / WebAuthn** *(L, isolated slice)* — `webauthn` gem (~> 3.4); `authentication_credentials` table (`customer_id`, `user_id`, `webauthn_id` unique, `public_key`, `sign_count`, `nickname`, `last_used_at`); `Authentication::WebauthnRelyingParty` thin wrapper (request-derived origin/rp_id); member management `/:cid/member/security/passkeys` (options/create/index/destroy); public login `/:cid/auth/passkey` (options/create — paranoid same-shape response for unknown emails, passkey satisfies MFA, full session-establishment sequence incl. `UserSession` + sign-in alert); `webauthn_codec.js` + `webauthn_register`/`webauthn_login` Stimulus controllers (mock `navigator.credentials` in Vitest, 100%); request specs via `WebAuthn::FakeClient`.

**Explicitly rejected (do not build):** impersonation, SSO/OIDC/SAML, MFA backup codes.

**Also still open for auth beyond enrichment** (design Parts 1–2/4, separate from this backlog's scope but recorded in the design doc): security S6–S10, correctness B4–B7, architecture consolidation ARCH-1→8, i18n sweep I18N-1→6 + TEST-2…21.

---

## 2. Email (spec: `2026-07-14-email-redo-design.md`)

1. **Settings/Emails surface** — closes the four-URL-area violation (area b missing today); natural home for per-tenant email knobs.
2. **Suppression-management UI** — add/remove/import/export suppressions (also unblocks the campaigns block-list completeness note).
3. **Deliverability dashboard** — SQL aggregates + inline SVG, zero new schema.
4. **Open/click tracking** — pixel + signed link rewrite, per-tenant toggle.
5. **Message timeline + provider events + resend** — `email_events` table; stop discarding webhook `raw`.
6. **Template preview-with-vars + token linting + `Versionable` history.**
7. **Scheduled/delayed send + rate throttle** — wire the dead `scheduled_at`.

Also deferred earlier (fix-pass leftover): E-ARCH-1 — remove/wire the dead platform-credential `daily_limit` column (schema change; authoritative cap is module-config `daily_send_cap`).

**Explicitly rejected:** per-tenant sending domains + SPF/DMARC (refactors the platform-global credential), inbound/Action Mailbox, visual block editor.

---

## 3. SMS (spec: `2026-07-14-sms-redo-design.md`)

1. **E1 — per-tenant Settings/SMS surface** — extend the daily-cap slice with sender label, sandbox toggle, quiet hours.
2. **E2 — opt-out management + STOP/HELP/START keyword compliance** — manual add/remove/resubscribe, CSV import/export; closes S-BUG-1 (Aliyun opt-out non-functional: no `parse_inbound`, `record_for_customer!` has no callers).
3. **E3 — message event timeline + resend** — `sms_message_events`; stop discarding webhook `raw`; stop collapsing Twilio interim statuses.
4. **E4 — template preview + test-send + GSM-7/UCS-2 segment counter** (parity with Email).
5. **E5 — `phonelib`** for E.164 validation/country/type behind the existing `PhoneNumber` wrapper (mature-gem rule).
6. **E6 — scheduled send + quiet-hours enforcement.**
7. **E7 — deliverability analytics dashboard** — SQL aggregates, no schema.

**Explicitly rejected:** cost/segment metering, multi-vendor failover, A2P 10DLC/brand registration, link shortening, full inbound conversation inbox.

---

## 4. Email Campaigns (spec: `2026-07-14-email-campaigns-redo-design.md`)

1. **E1 — campaign preview + test-send** *(S)* — reuse `Email::Gateway.send_raw` + `TemplateRenderer` with `VariableContext.for(current_user)`; no schema.
2. **E2 — open/click tracking** *(L)* — signed pixel + redirect endpoints, `email_message_events`, rates into `delivery_counts`. Highest-leverage single investment; unblocks E5/E9 and engagement segments.
3. **E3 — contact CSV import/export** *(M)* — lists currently target only existing auth users.
4. **E4 — per-tenant sending limits + quiet hours** *(M)* — wires the empty Settings/Email-Campaigns area (empty provisioner is its intended home); also the campaign volume-cap deferral lands here.
5. **E5 — A/B testing** *(L, depends on E2).*
6. **E6 — preference center / topic-level unsubscribe** *(M).*
7. **E7 — drip/automation sequences** *(L).*
8. **E8 — merge-tag fallbacks + custom fields** *(S).*
9. **E9 — cross-campaign reporting dashboard** *(M, after E2).*

Smaller deferrals recorded in the fix-pass doc: live-query audience O(n²) rescans + lists-index `audience_count` N+1 (perf), unbounded segment-JSON nesting bound, block-list UI showing bounce/complaint suppressions (folds into Email item 2), segment-builder AND/OR pill i18n (documented exception), public unsubscribe views on raw palette.

**Explicitly rejected:** send-time optimization, inbox-placement/seed testing, visual drag-drop builder, CAN-SPAM address field, static list-membership join tables.

---

## 5. Captcha (spec: `2026-07-14-captcha-redo-design.md`)

1. **G1 — captcha on auth flows** — the single biggest gap: `protect_with_captcha ..., fail: :closed` on sessions / sign-up / password-reset / MFA-recovery + a page-less `WidgetComponent` mode.
2. **G2 — verification analytics** — the write-only `captcha_verifications` ledger is fully indexed (outcome/provider/score/action/customer_id); platform panel under Maintenance/Platform, tenant slice under Settings/Captcha.
3. **G3 — hCaptcha provider** *(S)* — near-clone of Turnstile siteverify; cheapest proof of the single-file rule; brings the third widget controller that justifies the deferred Stimulus base-controller extraction (do the extraction with this item).
4. **G4 — risk-based adaptive triggering** — challenge only after N failures via the existing `Authentication::Throttle` counters.
5. **G5 — reCAPTCHA v3 score provider** — lights up the already-built, currently-dead score-threshold path (nil-score now correctly fails closed).

Naming-only deferral: `Ability` lists `:platform_captcha` instead of the route subject name (CanCan layer is defense-in-depth; real gate verified correct).

**Explicitly rejected:** per-tenant provider selection (deliberately platform-global), automatic provider failover (fail-open already preserves availability), invisible/managed widget modes (until G5 forces the pattern).

---

## Cross-cutting invariants (apply to every item above)

Three reserved roles + owner pin; four URL areas with controller-layer guards; `customer_id`/`user_id` record checks + cross-tenant negative specs on every new endpoint; I18n en+zh-CN parity (en byte-identical, zh-CN idiomatic); ViewComponent/Tailwind/Stimulus only; Trailblazer/Reform for business logic; mature gems over hand-rolls (wrap behind a thin service); vendor-facing features degrade gracefully offline; new JS at 100% Vitest lines+branches; full parallel suite green at each module boundary; nothing committed.
