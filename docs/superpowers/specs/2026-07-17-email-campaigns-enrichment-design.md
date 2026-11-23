# Email & Email Campaign Modules — Refactor + Enrichment

**Date:** 2026-07-17  
**Status:** Design → implementation on `master` (no auto-commit; manual review).  
**Scope:** Architecture follow-ups, template-building UX, open/click tracking + reporting, scheduled sends. A/B testing and preference-center topics are documented as follow-up phases.

## 1. Goals

- Finish the architecture clean-up left from the 2026-07-14 hardening pass.
- Enrich the template-building experience (preview, linting, fallbacks, version history).
- Add engagement tracking (opens/clicks) and a deliverability dashboard.
- Wire scheduled/delayed campaign sends and rate throttling.
- Keep the implementation reviewable, fully specced, and green.

## 2. Architecture follow-ups

| # | Item | Change |
|---|------|--------|
| A1 | Dedupe message creation | Introduce `Emails::PersistMessage` value object used by `Email::Gateway.send_raw`, `Email::Activities::Send`, and `Email::Gateway.queue_for_campaign`. Single source of truth for idempotency, suppression, daily-cap, and provider metadata. |
| A2 | Namespace unification | Move service layer from `Email::` to `Emails::` (`Email::Gateway` → `Emails::Gateway`, `Email::TemplateRenderer` → `Emails::TemplateRenderer`, `Email::VariableContext` → `Emails::VariableContext`, providers stay in `Email::Providers`). Update all call sites and specs. |
| A3 | Drop vestigial columns | Remove `builder_data` and `scheduled_at` from `email_messages` if they are unused, after confirming `email_campaigns.scheduled_at` owns campaign scheduling. |
| A4 | Forward `provider:` arg | `Emails::Gateway.send` already passes `provider:` to `Activities::Send`; verify the provider flows through to `CredentialResolver` and the persisted message. |
| A5 | Provider result convention | Unify `Emails::DeliverMessageJob` to always record `provider_message_id` and `raw_response` from the provider result. |

## 3. Template-building enrichment

| # | Item | Change |
|---|------|--------|
| T1 | Live preview endpoint | `POST /:cid/admin/modules/emails/templates/:id/preview` accepts sample variable JSON and returns rendered subject + HTML + text. |
| T2 | UI preview pane | Add a preview card to the template form with a tabbed subject/HTML/text view and a "reload" button. |
| T3 | Token linting | `Emails::TemplateLinter` scans `subject`, `body_html`, `body_text` for `{{...}}` tokens and reports unknown variables against the template's `variables` array. Surfaces warnings in the form and dashboard. |
| T4 | Merge-tag fallbacks | Extend `Emails::TemplateRenderer` to support `{{first_name|fallback:"Friend"}}` syntax. If the variable resolves to blank, the fallback literal is used. |
| T5 | Version history | Add `Emails::TemplateVersion` snapshots (`template_id`, `snapshot` JSON, `created_by`) on every update. Admin can compare or restore a previous snapshot. |

## 4. Open/click tracking + reporting

| # | Item | Change |
|---|------|--------|
| E1 | `email_message_events` table | `message_id`, `event_type` (`open`/`click`), `url` (click only), `ip`, `user_agent`, `occurred_at`. Unique index on `(message_id, event_type, url, occurred_at)` for clicks, `(message_id, event_type, DATE(occurred_at))` for opens to avoid duplicate-pixel spam. |
| E2 | Signed pixel endpoint | `GET /email/track/:message_id/open.gif` — verifies a signed token, records an `open` event once per day per message, returns a 1x1 transparent GIF. |
| E3 | Signed redirect endpoint | `GET /email/track/:message_id/click?url=...&sig=...` — verifies signature, records a `click` event, 302 redirects to the original URL. |
| E4 | Tracking toggle | Per-tenant `tracking_enabled` setting on `Emails::Credential` or module config; when off, no tracking pixels/rewrites are injected. |
| E5 | Link rewrite in renderer | `Emails::TemplateRenderer` optionally appends tracking pixel and rewrites `href` links through the signed redirect endpoint. |
| E6 | Deliverability dashboard | Admin page under `/admin/modules/emails/dashboard` showing aggregate counts + inline SVG sparklines for sent, delivered, bounced, complained, opened, clicked, suppressed, unsubscribed. |

## 5. Scheduling + throttling

| # | Item | Change |
|---|------|--------|
| S1 | Campaign scheduled sends | The scheduler already honors `scheduled_at`; ensure timezone-aware interpretation and add a per-campaign "send time" preview. |
| S2 | Rate throttle | Add `emails.campaign_throttle_per_minute` module config; `SendCampaignJob` sleeps or defers when the rolling per-minute window is exceeded. |
| S3 | Delayed transactional | Add `scheduled_at` to `Emails::Message` (reuse column if present); `Emails::DeliverMessageJob` reschedules itself if `scheduled_at` is in the future. |

## 6. Out of scope (follow-up phases)

- Full A/B testing framework (variants, winner selection, auto-send).
- Preference center / topic-level unsubscribe.
- Inbound email / Action Mailbox.
- Per-tenant sending domains.

## 7. Testing

- Full email + campaign spec suite must remain green.
- New specs for: `Emails::PersistMessage`, namespace renames, template preview, linter, fallbacks, version restore, tracking endpoints (signature validation, dedupe), dashboard aggregates, scheduled send behavior.
- i18n parity for `en` and `zh-CN` on all new keys.
