# Email Campaigns Module — Aggressive Hardening & Refactor

**Date:** 2026-07-14
**Scope:** Full aggressive refactor of the Email Campaigns (marketing) module to the
payments/email bar.
**Status:** Design — implementation on `master` (no auto-commit; manual review).

## 1. Goal

Email Campaigns is solid on audience segmentation but diverges badly from the refactored Email
module on delivery integrity: campaign sends ignore the new `Emails::Suppression` ledger, the
scheduler has no atomic claim (concurrent double-send + duplicate recurring occurrences), the
campaign state machine has no terminal guards, there is no reaper for stuck `sending` campaigns,
and the `delivered_count` metric is always zero. This refactor closes those gaps and unifies the
Email-module boundary.

## 2. Bugs fixed (from audit)

| # | Bug | Fix |
|---|-----|-----|
| B1 | Campaign send ignores `Emails::Suppression` | `Email::Gateway.queue_for_campaign` now checks it (done during the Email refactor) |
| B2 | Two opt-out ledgers; unsubscribe never suppresses | Unsubscribe writes a per-customer `Emails::Suppression` (reason `unsubscribe`) alongside the user flag |
| B3 | Scheduler has no atomic claim → double-send + duplicate recurrences | `Campaign.claim!` (conditional `update_all` == 1, Payments `charge_due_subscriptions` pattern); only the winner sends + creates the next occurrence |
| B4 | Stats double-count under a send race | Increment `sent_count` only when the recipient message was newly created (`previously_new_record?`) |
| B5 | Campaign transitions are unconditional `update!` | Terminal-guarded `start!/complete!/cancel!/pause!/resume!` (terminal = `sent`, `cancelled`, `failed`) |
| B6 | No reaper for stuck `sending` campaigns | `EmailCampaigns::Cron::ReconcileCampaigns` re-drives `sending` past a claim-TTL (idempotent per-recipient); `config/recurring.yml` |
| B7 | `delivered_count` always 0 | Rolled up on demand from `Emails::Message` via a new `email_campaign_id` FK |
| B8 | Bulk send is uncapped (provider flood) | `SendCampaignJob` processes in bounded batches, re-enqueuing itself until done |
| B10 | `already_sent_user_ids` is an unindexed json_extract scan | Replaced by the indexed `email_campaign_id` column |
| B11 | Editing / destroying a live/sent campaign is unguarded | Controller guards: edit only `draft`/`scheduled`; destroy excludes `sent` |

## 3. Data model

- **`email_campaigns`** → add `claimed_at` (scheduler claim + reaper TTL). `STATUSES` gains
  `failed` (dead-letter).
- **`email_messages`** → add `email_campaign_id` (indexed FK, nullable) so campaign metrics and
  the dedup check are indexed lookups instead of a JSON scan.
- `Emails::Suppression::REASONS` gains `unsubscribe`.

## 4. Delivery integrity

- **Scheduler claim:** `SchedulerJob` claims each due campaign atomically (`claim!`); only the
  winning worker starts it, enqueues `SendCampaignJob`, and creates the next recurring
  occurrence — eliminating the double-send / duplicate-occurrence race.
- **Terminal guards:** `Campaign` transitions no-op on regression from a terminal status;
  `resume!` only from `paused`, `start!` only from `draft`/`scheduled`.
- **Reaper:** `EmailCampaigns::Cron::ReconcileCampaigns` re-enqueues `SendCampaignJob` for
  campaigns stuck `sending` past `CLAIM_TTL` (safe — per-recipient idempotency skips the already
  sent); registered in `recurring.yml`.
- **Throttle:** `SendCampaignJob` sends at most `BATCH_SIZE` per run then re-enqueues itself,
  bounding provider load per tick.
- **Metrics:** `Campaign#delivery_counts` aggregates `Emails::Message` by status via
  `email_campaign_id`; the show view's `delivered_count`/`bounced_count` become real.
- **Observability:** `EmailCampaigns::Instrumentation` subscriber on an
  `email_campaign.lifecycle` notification (started/completed/failed).

## 5. Boundary with the Email module

Unsubscribe now records into the shared `Emails::Suppression` ledger, so the two modules share
one suppression source of truth (bounces + complaints + unsubscribes + manual), all enforced at
send time in `queue_for_campaign`. The user's `email_campaign_blocked` flag stays for the
audience scope (fast pre-filter); suppression is the authoritative send-time gate.

## 6. Out of scope (noted)

- Open/click tracking (no pixel/redirect infra) — only send/delivered/bounced/complained.
- RRULE via a gem (none bundled) — the hand-rolled FREQ/INTERVAL parser stays, documented.
- Per-campaign unsubscribe-token scoping / expiry (tokens ride in long-lived mail).
- CAN-SPAM physical-address field (a template-content concern, not send-path).

## 7. Testing

Scheduler claim (no double-send / single next-occurrence under concurrent perform), terminal
guard matrix, reaper re-drive, suppression-honored + unsubscribe→suppression, stats no-double-
count + real delivered_count via email_campaign_id, batching/re-enqueue, edit/destroy guards,
instrumentation; multi-tenant isolation. i18n en/zh parity.
