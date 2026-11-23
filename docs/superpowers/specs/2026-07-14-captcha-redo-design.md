# Captcha Module — Professional Redo (Deep Pass)

**Date:** 2026-07-14
**Module:** 5 of 5 (authentication → email → sms → email_campaigns → captcha)
**Method:** Consolidated from three parallel adversarial audits (correctness+security, architecture+tests+i18n, feature-gaps vs Turnstile/hCaptcha/reCAPTCHA). Top findings verified by direct code reading. Changes on `master`, uncommitted; suite green per slice.

## Overall assessment

The strongest module of the five, by a clear margin. The vendor registry genuinely honors the single-file rule (verified: adding hCaptcha would need only `providers/hcaptcha.rb`), the replay defense is layered and correct (10-min consumed-token pre-check + partial-unique DB index reclassifying concurrent double-success as `:replayed` + vendor single-use), secrets are encrypted and never reach the client, all vendor HTTP goes through `OutboundHttp`, the outcome matrix and authorization negatives are thoroughly tested (276 Ruby examples), the three JS files sit at a verified 100% lines+branches, and i18n parity is exact (52/52 keys). **Turnstile — the umbrella's headline enrichment candidate — already exists, complete.** No Critical/High findings anywhere. The real story is reach: captcha protects only page-builder public forms, while the canonical targets (login, signup, password reset, MFA recovery) are unguarded despite the concern being purpose-built for them.

## Fix worklist

| # | Sev | Item | Fix |
|---|-----|------|-----|
| **C5-BUG-1** | Med | **Solved-but-unverified captcha on flowchart-backed pages**: when a page's `form_settings.flowchart_id` resolves, `resolve_form_action` points the form at the DynamicController route — the widget renders and the user solves it, but nothing verifies the token (only `PublicPagesController#submit` is protected). Not a bot hole (DynamicController already 401s anonymous writes — the audience is authenticated), but false assurance | Widget renders **iff the form posts to the captcha-verified endpoint**: suppress on a resolved flowchart action; keep rendering on the unresolvable-flowchart fallback (that path posts to the protected submit and would otherwise hard-block with no widget). Specs pin all three cases. |
| **C5-BUG-2** | Low | Latent score-threshold trap: `Verify#apply_score_threshold` returns `:success` when a threshold is configured but the provider returned a nil score — the first score-based vendor that omits a score silently bypasses the threshold | Nil score under a configured threshold → `:invalid`. Spec added. |
| **C5-ARCH-1** | Low | Dead error classes `Captcha::Errors::{CredentialsMissing,ConfigurationError}` — never raised or rescued | Delete (verify zero references first). |
| **C5-ARCH-2** | Low | Both providers carry an identical `rescue TransportError → {outcome: :unreachable, ...}` block | Hoist a shared helper into `Providers::Base`; both providers use it. |
| **C5-OPS-1** | Low | `captcha_verifications` grows forever: the replay pre-check needs only a 10-minute window but nothing prunes the table (or its partial-unique token index) | Prune cron mirroring `Payments::Cron::PruneWebhookEvents`: `Captcha::Cron::PruneVerifications` (+ job + `config/recurring.yml` daily entry), 90-day retention so the ledger still feeds future analytics. |
| **C5-TEST-1** | Low | `score_threshold > 1` model rejection untested; stale comment in `status_controller_spec.rb:10-11` claims admins are redirected (they are correctly allowed) | Add the validation spec; fix the comment. |

## Considered and deliberately kept

- **Fail-open on `:configuration_error`/`:unreachable` for `page_submit`** — the documented 07-13 policy choice (never let a platform misconfiguration DoS every tenant's public forms); `TestConnection` surfaces bad credentials off the request path, auth-grade flows can opt into `fail: :closed` per action. Kept.
- **Ledger row dropped on `RecordInvalid`** (verify.rb rescue) — vanishingly rare, degrades one token to vendor-side single-use only. Noted.
- **Aliyun `endpoint` config interpolated into the outbound URL** — platform-owner-only input, scheme pinned to https, goes through `OutboundHttp`. Noted for an optional allowlist.
- **`Ability` lists `:platform_captcha` instead of the route subject name** — the CanCan layer is defense-in-depth; the real gate (`enforce_route_role!` on the `maintenance/platform` prefix) is verified correct. Naming-only, deferred.
- **`VerificationContext#user_agent` unread by providers** — kept: it is persisted to the ledger and feeds the future analytics surface (G2).
- **Stimulus base-controller extraction** (aliyun/turnstile duplicate form-wiring) — DRY win vs. regression risk on two stable files pinned at 100% coverage; deferred until a third widget controller (hCaptcha/reCAPTCHA) makes the abstraction pay.
- **Systemic, umbrella-level notes** (apply to all five modules, not captcha-specific): PORO `self.call` activities rather than `trailblazer-activity` operations is the de-facto codebase convention; `Registration.module_name/module_description` persist English into `feature_modules.name/description` at sync (display path already falls back through i18n); repo-wide `npx vitest run --coverage` has a parallel-worker tmp-file race (single-fork runs are accurate).

## Maximum-enrichment build set (designed, not yet built)

Value-to-effort order from the gap audit: (G1) **captcha on auth flows** — the single biggest gap; `protect_with_captcha ... fail: :closed` on sessions/sign-up/password-reset/MFA-recovery plus a page-less `WidgetComponent` mode (the concern's own doc comment already shows the intended usage); (G2) **verification analytics** — the ledger has outcome/provider/score/action/customer_id fully indexed and write-only; platform panel under Maintenance/Platform, tenant slice under Settings/Captcha; (G3) **hCaptcha provider** (S — near-clone of Turnstile's siteverify; the cheapest proof of the single-file rule, brings the third widget controller that justifies the Stimulus base extraction); (G4) **risk-based adaptive triggering** — challenge only after N failures via the existing `Authentication::Throttle` counters; (G5) **reCAPTCHA v3 score provider** — lights up the already-built, currently-dead score-threshold path. Deferred outright: per-tenant provider selection (deliberately platform-global), automatic provider failover (fail-open already preserves availability), invisible/managed widget modes (until G5 forces the pattern).

## Shipped in this pass (verified, tested)

All six worklist items landed, and C5-BUG-1 turned out **bigger than audited**:

- **C5-BUG-1 (upgraded: High-impact pre-existing bug)** — building the fix revealed the widget **never rendered anywhere**: the form/wizard component templates guarded it with `defined?(@page)`, but the components never accepted or set a `page:` ivar (ViewComponents don't inherit view ivars), verified empirically with a real GET against a captcha-enabled page. So captcha-enabled pages enforced verification server-side while showing users no widget. Fixed by threading `page:` through `FormComponent`/`WizardComponent` (glue added at both `PageContentGenerator` call sites) into `Captcha::WidgetComponent`, which now also receives `form_action:` and renders **iff the form posts to the page's verified public-submit endpoint** — suppressed on a resolved flowchart action (the original false-assurance finding), rendered on the unresolvable-flowchart fallback. All three cases pinned at component + request level (44 examples); page-render/preview surfaces regression-checked (205 examples green). Note: admin page-preview passes a placeholder `#` action, so the widget intentionally stays out of the preview modal.
- **C5-BUG-2** — nil score under a configured threshold now fails closed (`:invalid`); spec extended.
- **C5-ARCH-1** — dead `Captcha::Errors::{CredentialsMissing,ConfigurationError}` deleted (grep-verified zero references).
- **C5-ARCH-2** — `Providers::Base#with_transport_rescue` hoisted; both providers use it, byte-identical behavior.
- **C5-OPS-1** — `Captcha::Cron::PruneVerifications` (90-day retention, batch delete) + `Captcha::PruneVerificationsJob` + daily `recurring.yml` entry, mirroring `Payments::Cron::PruneWebhookEvents`.
- **C5-TEST-1** — score-threshold bounds spec + stale spec-comment fix (QA pass).

## Verification gate

Targeted specs per slice (backend set: 201 examples green; widget set: 44 + 205 collateral green); full parallel suite green at module end; no JS touched in the fix set (G3/G5 would be the JS-touching slices) so no vitest delta; i18n — no new user-facing strings (prune job and internals only); real-browser check of a captcha-enabled public page.
