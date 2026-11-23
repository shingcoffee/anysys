# SMS Module — Professional Redo (Deep Pass)

**Date:** 2026-07-14
**Module:** 3 of 5
**Method:** Consolidated from three parallel adversarial audits (correctness+security, architecture+tests+i18n, feature-gaps). Top findings verified by direct code reading. Changes on `master`, uncommitted; suite green per slice.

## Overall assessment

The strongest of the three so far: a clean single-file-per-vendor adapter registry (Aliyun `:poll` + Twilio `:webhook`), a well-factored send pipeline (normalize → contract → idempotency → opt-out → per-phone rate-limit → daily-cap → race-safe persist → dispatch), monotonic terminal-guarded status transitions, excellent schema indexing, and broad, deep test coverage. Notably SMS is the *source* the Email hardening was copied from — the malformed-cap guard and the blank-vendor-id defense already exist here. No Critical/High issues. The real gaps are in the opt-out lifecycle/visibility and a few webhook edge cases.

## Shipped in this pass (verified, tested, suite green — 377 SMS/config examples)

| # | Sev | Item | Fix |
|---|-----|------|-----|
| **S-SEC-1** | Med | The opt-out list showed **every** global STOP row (`customer_id NULL`) to every tenant admin → one tenant could enumerate numbers only *other* tenants texted (cross-tenant PII) | New `OptOut.visible_to_customer(cid, messaged_phones)` scope: own rows + global rows **only for numbers this tenant actually messaged**. Suppression stays global via `opted_out?`. Spec-pin rewritten; leak-prevention spec added. |
| **S-BUG-2** | Low | `POST /sms/webhooks/aliyun/...` hit a poll-only adapter → `Base#verify_webhook!` raised `NotImplementedError` → unauthenticated **500 + backtrace** | Webhook controller rejects non-`:webhook` adapters as 404. Spec added. |
| **S-BUG-3** | Low | DLR/inbound verified only against the **default-mode** credential → a non-default-mode account's receipts 403'd and never terminalized | Verify against **every** active credential for the provider (both modes), mirroring the Email webhook. Spec added. |
| **S-I18N-1** | High | `common.status.retired` was missing → the SMS templates index rendered a literal **"translation missing"** for retired templates | Added `common.status.retired` (`en` + `zh-CN`). |
| **S-I18N-2** | Med | Bare `f.label :mode/:status/:description` on the credential + template forms fell back to English `humanize` in zh-CN | Explicit `t("common.labels.*")` labels. |
| **S-I18N-3** | Med | Enum `<select>` options (`sandbox/production`, `active/disabled/retired`) rendered raw English in zh-CN | Localized via `t("common.modes.*")` / `t("common.status.*")` with a `humanize` fallback. |
| **S-ARCH-1** | Med | The per-tenant "Daily cap" Settings entry was a **dead link** — no `configuration_schema`, so the generic page rendered nothing and the cap was console/seed-only | Added `configuration_schema` + `configuration_keys` to the registration; made the generic config page's field label i18n-aware (`admin_misc.module_config.fields.<module>.<key>`, `humanize` fallback — improves every module, no regression); added the SMS label key in both locales; corrected the provisioner comment. Specs added (renders + persists + `Send#daily_cap_for` reads it). |

## Considered / deferred

- **S-BUG-1** (opt-out non-functional for Aliyun — no `parse_inbound`; no manual add/resubscribe; `record_for_customer!` has no callers): the STOP-compliance + opt-out-management UI is an enrichment feature (below), not a one-line fix — deferred to the build set.
- **S-BUG-4** (Aliyun transport-errored sends dead-lettered without a `QuerySendDetails`-by-recipient reconcile) and **S-OBS** (cap/rate-limit count non-dispatched rows; cap `0` locks out): low severity, left as-is; noted.
- **S-ARCH-2** extract a shared `FeatureModules::DailySendCap` resolver (dup with Email); **S-ARCH-3** remove dead methods (`Credential#enabled?`/`#write_config`, `PhoneNumber#valid?`); **S-TEST-1** `SaveCredential` unique-race branch — architecture/coverage follow-ups.

## Maximum-enrichment build set (designed, not yet built)

From the feature-gap audit, value-to-effort: (E1) per-tenant **Settings/SMS** surface (the daily-cap wiring above is the first slice; extend with sender label, sandbox toggle, quiet-hours); (E2) **opt-out management + STOP/HELP/START keyword compliance** (manual add/remove/resubscribe, CSV import/export — closes S-BUG-1); (E3) **message event timeline + resend** (`sms_message_events`, stop discarding webhook `raw`, stop collapsing Twilio interim statuses); (E4) **template preview + test-send + GSM-7/UCS-2 segment counter** (parity with Email); (E5) **`phonelib`** for E.164 validation/country/type behind the existing `PhoneNumber` wrapper (directly satisfies AGENTS.md's mature-gem rule); (E6) **scheduled send + quiet-hours**; (E7) **deliverability analytics dashboard** (SQL aggregates, no schema). Deferred: cost/segment metering, multi-vendor failover, A2P 10DLC/brand registration, link shortening, full inbound conversation inbox.
