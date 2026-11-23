# Five-Module Professional Redo — Umbrella Design

**Date:** 2026-07-14
**Scope:** Fresh, deeper professional-grade pass over the five non-payment modules: authentication, email, sms, email_campaigns, captcha.
**Status:** Approved. Execution: fully autonomous, strictly one module at a time, changes on `master` uncommitted (user reviews and commits).

## 1. Goal

Re-do the review and refactor/enhancement work across all modules on
`/:cid/admin/maintenance/platform/module_settings` (payment excluded — already refactored),
to industry standard: code quality, architecture, functionality enrichment (maximum tier),
and underlying bug hunting + fixes. The 07-13/07-14 hardening pass is the baseline — it
informs but does not constrain; its changes are also in scope for review.

## 2. Order and cycle

Order: **authentication → email → sms → email_campaigns → captcha**. Each module runs the
full cycle to completion before the next module's audit begins:

1. **Deep adversarial audit** — parallel read-only sub-agents on five dimensions:
   (a) architecture & code quality (Rails 8 / Trailblazer / ViewComponent conventions),
   (b) correctness bug hunt, (c) security & tenant isolation,
   (d) functionality-gap benchmark vs industry leaders
   (Auth0/Clerk · Postmark/SendGrid · Twilio · Mailchimp · Turnstile/hCaptcha),
   (e) test-coverage gaps + i18n parity. Findings require file:line evidence and a concrete
   failure scenario; plausible-but-unverified findings are dropped.
2. **Module design doc** — `docs/superpowers/specs/2026-07-14-<module>-redo-design.md`,
   sequenced worklist: bugs (low→high blast radius) → refactors → enrichment features.
   Self-reviewed (approval delegated).
3. **Plan + build** — writing-plans, then anysys-backend / frontend / security-engineer
   builds with anysys-qa-engineer specs (multi-tenant + authorization focus).
4. **Verification gate** — targeted specs during the cycle; full parallel suite green at
   module end; JS touched → vitest 100% lines+branches; UI touched → real-browser check;
   i18n en/zh-CN key parity.
5. **Review** — anysys-tech-lead + anysys-code-reviewer on the module diff; findings fixed
   before the next module starts.

## 3. Maximum-enrichment candidates (finalized by each module's audit)

- **authentication**: passkeys/WebAuthn (`webauthn` gem), active-session management UI
  (list/revoke), sign-in alert emails, remember-me, breached-password screening
- **email**: bounce/complaint webhook ingestion → automatic suppression, deliverability
  dashboard, template preview with variable substitution
- **sms**: delivery receipts (DLR webhooks), inbound two-way messaging with STOP/HELP
  keyword compliance, quiet-hours windows, E.164 normalization
- **email_campaigns**: A/B testing, drip/scheduled sequences, open/click engagement
  analytics, send throttling
- **captcha**: Turnstile + hCaptcha providers (single-file rule), risk-based adaptive
  triggering, verification analytics

## 4. Hard invariants (never weakened)

Reserved three roles + owner pin (canonical user under customer 81721200); four URL areas
with controller-layer guards; `customer_id`/`user_id` record checks; I18n en+zh-CN on every
user-facing string; ViewComponent/Tailwind/Stimulus only; Trailblazer/Reform for business
logic; mature gems over hand-rolls; vendor-facing features degrade gracefully without live
external accounts (webhook endpoints + test modes). No backward-compatibility constraints.

## 5. Risk control

Each fix/feature lands as its own coherent slice so a cycle can stop cleanly; the
full-suite gate at each module boundary prevents cross-module regressions. Nothing is
committed — the accumulated working-tree diff is the user's review surface.
