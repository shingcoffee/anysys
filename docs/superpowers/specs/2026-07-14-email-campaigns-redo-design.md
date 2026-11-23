# Email Campaigns Module — Professional Redo (Deep Pass)

**Date:** 2026-07-14
**Module:** 4 of 5 (authentication → email → sms → email_campaigns → captcha)
**Method:** Consolidated from three parallel adversarial audits (correctness+security, architecture+tests+i18n, feature-gaps vs Mailchimp/Customer.io/Brevo/Klaviyo). Top findings verified by direct code reading. Changes on `master`, uncommitted; suite green per slice.

## Overall assessment

Delivery-infrastructure-mature, marketing-feature-shallow. The send pipeline is genuinely strong — atomic `claim!`/`reclaim_stalled!`/`fail_stalled!` with terminal guards, per-recipient idempotency keys under a unique index, bounded batching with self-re-enqueue, suppression enforced at send time, and a correct RFC 8058 one-click unsubscribe (HMAC tokens, POST-only state change). Admin auth is centralized via `RouteAuthorization`; the audience-query builder is injection-safe (whitelisted fields, Arel-bound values); tests already cover the hard concurrency branches. But one serious tenant-isolation hole survived every prior pass (cross-tenant FKs on campaign create), the opt-out lifecycle has a silent no-op, and the scheduling timezone is display-only. Against industry leaders the entire engagement half (opens/clicks → reporting → A/B) is absent.

## Fix worklist (sequenced low→high blast radius within severity)

| # | Sev | Item | Fix |
|---|-----|------|-----|
| **C-SEC-1** | **High** | Cross-tenant campaign: `campaign_params` permits `email_list_id`/`email_template_id` with no tenant check (`campaigns_controller.rb:52,101-106`); a tenant-A admin can point a campaign at tenant B's list → mail tenant B's entire member base, and read B's list/template names + audience count off the show page | Model-level same-tenant validation on `Campaign` (`email_list.customer_id == customer_id`, same for template). Request + model specs (foreign-FK create/update rejected). |
| **C-BUG-1** | Med | Block-list "unblock" clears only the `email_campaign_blocked` flag; the `Emails::Suppression` "unsubscribe" row written by the same unsubscribe flow stays → sends still short-circuit as `suppressed`. Unblock is a silent no-op | `unblock_campaign_email!` also removes the unsubscribe-reason suppression for that email (bounce/complaint suppressions untouched — those are transport-authoritative). Spec: unblock → next campaign send actually delivers. |
| **C-BUG-2** | Med | `timezone` is display-only: `datetime_local_field` naive string parses in UTC, show page renders `.in_time_zone(campaign.timezone)`, send fires on UTC comparison → admin schedules "09:00 New York", UI echoes "05:00", send happens 09:00 UTC. Recurrence arithmetic is UTC too (DST drift) | Interpret submitted `scheduled_at` in `campaign.timezone` on write (controller layer); advance recurrences in that zone. Specs pin write→display→due round-trip. |
| **C-BUG-3** | Med | Hand-rolled RRULE honors only `FREQ`/`INTERVAL`: no `COUNT`/`UNTIL` (recurs forever, no end), unknown `FREQ`/garbage rule → series silently dies with no feedback; `recurrence_rule` never validated | Support `COUNT`/`UNTIL`; validate the rule at save time so garbage is rejected up front. Specs for WEEKLY/MONTHLY/HOURLY arms, catch-up loop, COUNT/UNTIL termination, invalid-rule rejection (previously only DAILY was tested). |
| **C-BUG-4** | Low | `pause!`/`cancel!`/`complete!` guard on in-memory status then `update!` — unlike the conditional-`update_all` transitions beside them; a race can resurrect a just-completed campaign as "paused" | Make them conditional transitions like `claim!`/`resume!`. Specs pin lost-race behavior. |
| **C-ARCH-1** | Med | Status→badge-variant mapping duplicated and *divergent* (show view inline `case` vs index controller hash: `scheduled` warning-vs-info, `failed` default-vs-danger) | Single `Campaign#status_variant`; both surfaces consume it. |
| **C-I18N-1** | Med | Campaign show badge renders the raw enum (`@campaign.status`) — English in zh-CN; index already translates | `t("common.status.#{...}")` (keys exist in both locales). |
| **C-I18N-2** | Med | Bare `f.label` on `campaigns/_form` (`:name`, `:timezone`) and `lists/_form` (`:name`, `:description`, `:status`) → humanized English in zh-CN | Explicit `t()` labels; en byte-identical to the humanized text; zh-CN idiomatic. |
| **C-ARCH-2** | Low | Dead `Campaign#start!`/`#fail!` (no production callers; specs keep them alive) | Delete methods + their specs (C-BUG-4 replaces the transition surface). |
| **C-TEST-1** | Low | `FeatureModules::EmailCampaigns::Registration` unspecified (`entries_for` unknown-key raise, `sidebar_contributions`, `entry_path`) | Add registration spec. |

## Considered / deferred (noted, not built this pass)

- Campaign volume caps (campaign mail deliberately bypasses the transactional daily cap; no per-tenant ceiling) — belongs with the Settings/Email-Campaigns surface (enrichment E4), not a point fix.
- Live-query audience (not snapshotted; batch rescans make very large lists O(n²)) and lists-index `audience_count` N+1 — performance work, correct behavior today at current scale.
- Unbounded segment-JSON nesting (admin-only `SystemStackError` risk) — low impact; bound it when the segment builder is next touched.
- Block-list UI showing bounce/complaint suppressions (today it shows only unsubscribes — misleadingly incomplete) — folds into the Email module's deferred suppression-management UI enrichment.
- Segment-builder AND/OR pills not i18n'd — documented exception (Stimulus overwrites `textContent`; needs the coordinated JS change, out of scope per the 06-26 design).
- Public unsubscribe views use raw palette instead of design tokens — styling nit.
- Empty provisioner / `settings: []` — intended MVP scope; becomes the natural home for enrichment E4.
- Review notes accepted as-is (code-reviewer PASS, low/non-blocking): an unparseable `scheduled_at` casts to nil instead of surfacing a form error (admin-only field; the browser datetime control already constrains input); the atomic `update_all` transitions don't bump `updated_at` (deliberately mirrors the pre-existing `claim!`/`reclaim_stalled!` convention in the same file). The suggested unsubscribe→resubscribe→unsubscribe cycle spec was added.

## Maximum-enrichment build set (designed, not yet built)

Value-to-effort order from the gap audit: (E1) **campaign preview + test-send** (S — reuse `Email::Gateway.send_raw` + `TemplateRenderer` with `VariableContext.for(current_user)`; no schema); (E2) **open/click tracking** (L — signed pixel + redirect endpoints, `email_message_events`, rates into `delivery_counts`; unblocks reporting, A/B, engagement segments — the highest-leverage single investment); (E3) **contact CSV import/export** (M — today lists can only target existing auth users); (E4) **per-tenant sending limits + quiet hours** (M — wire the empty Settings area; enforce `daily_limit`); (E5) **A/B testing** (L, depends on E2); (E6) **preference center / topic-level unsubscribe** (M); (E7) **drip/automation sequences** (L); (E8) **merge-tag fallbacks + custom fields** (S); (E9) **cross-campaign reporting dashboard** (M, after E2). Deferred outright: send-time optimization, inbox-placement/seed testing, visual drag-drop builder, CAN-SPAM address field (template concern), static list-membership join tables.

## Shipped in this pass (verified, tested — module set 340 examples, 0 failures)

All ten worklist items above (C-SEC-1, C-BUG-1..4, C-ARCH-1/2, C-I18N-1/2, C-TEST-1) landed:

- **C-SEC-1** — `Campaign` same-tenant validation on `email_list`/`email_template` (new `admin_modules.errors.validations.cross_tenant_association` key, en+zh-CN); request-level negatives on create/update with foreign FKs.
- **C-BUG-1** — `CampaignUnsubscribe.resubscribe(user)` unblocks AND deletes only the tenant-scoped `unsubscribe` suppression row (global/bounce/complaint rows untouched); `BlockListController#unblock/#batch_unblock` use it. End-to-end specs incl. cross-tenant 404s.
- **C-BUG-2** — `scheduled_at` now interpreted in the campaign timezone on write (controller parse), rendered as campaign-zone wall-clock on the edit form, and recurrence arithmetic runs in that zone (DST-safe — verified across the Mar-2026 US spring-forward). Round-trip spec: NY 09:00 → 13:00 UTC.
- **C-BUG-3** — new `EmailCampaigns::RecurrenceRule` value object (single parser used by both the new `Campaign` format validation and `StartCampaign`); `COUNT` decrements onto the cloned occurrence and terminates at ≤1; `UNTIL` (date and datetime forms) ends the series; unsupported parts (e.g. BYDAY) now rejected up front instead of silently ignored. WEEKLY/MONTHLY/HOURLY arms + catch-up loop now spec-covered.
- **C-BUG-4** — `pause!`/`cancel!`/`complete!` are atomic conditional transitions (boolean, mirror `resume!`); lost-race matrix specced. `complete!` tightened to fire only from `sending`.
- **C-ARCH-1 / C-I18N-1** — single `Campaign::STATUS_BADGE_VARIANTS` + `#status_variant` consumed by both index and show (divergent inline mappings deleted); show badge label translated via `common.status.*`.
- **C-I18N-2** — explicit `t("common.labels.*")` labels on both forms (new `common.labels.timezone` key, en+zh-CN).
- **C-ARCH-2** — dead `Campaign#start!`/`#fail!` deleted with their specs.
- **C-TEST-1** — new `FeatureModules::EmailCampaigns::Registration` spec (entries scoping, sidebar shape, unknown-key raise).

Also fixed (found by the module-boundary suite gate, pre-existing and unrelated to this module): `spec/components/page_builder/settings_modal_component_spec.rb` was state-dependent — the boot-time module registration sweep seeds a persistent *inactive* `captcha` row, which the spec's create-only `find_or_create_by!` block silently kept inactive. Now forces the status deterministically.

## Verification gate

Targeted specs per slice (module set: 340 examples, 0 failures); full parallel suite green at module end; i18n en/zh-CN parity on all new keys; no JS touched (segment-builder exception stands) so no vitest delta expected; real-browser smoke of the campaign show/form surfaces.
