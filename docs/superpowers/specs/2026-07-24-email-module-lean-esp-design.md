# Email Module — Lean ESP Core Design

**Date:** 2026-07-24  
**Status:** Approved (Approach 1; decisions locked)

## Goal

Make the Email module professional and intuitive by hard-removing incomplete / non-standard shells and hardening the remaining industry-shaped core: credentials → templates → transactional send → lists → campaigns → suppressions → analytics.

## Product decisions (locked)

| Decision | Choice |
|----------|--------|
| Strategy | Hybrid: prune incomplete shells, harden remaining path |
| Streams | Remove entirely |
| Opt-out | Single suppression ledger; absorb block list |
| Signup forms | Remove |
| Prune aggressiveness | Hard remove (code + schema) |
| Audience | Lists only (membership); no segments |
| Approach | Surgical prune + send-path harden (not Contact model rebuild) |

## Target IA

| Area | Surfaces |
|------|----------|
| Overview | Dashboard, reports, deliverability, engagement |
| Campaigns | Campaigns, templates (+ versions). Messages remain reachable |
| Audience | Contacts, lists (+ membership), tags, suppressions |
| Settings | Module config only (`campaigns_enabled`, `daily_send_cap`) |

**Public kept:** webhooks, open/click tracking, RFC 8058 unsubscribe.  
**Public removed:** preference center, signup forms.  
**Platform kept:** SMTP/Postmark credentials + DKIM (owner-only).

## Hard prune

Remove end-to-end (routes, controllers, views, components, Stimulus, jobs, services, models, factories, specs, locales) and drop schema:

- A/B testing (`ab_test_*`, PickWinner*, `ab_test_builder`)
- Automations (tables, Trigger/ProcessStep, jobs, CRUD, Stimulus)
- Preference topics + public preference center + `user_preferences`
- Streams (`email_streams`, FKs on messages/campaigns/templates, provisioner seeding, Resolve)
- Signup forms
- Segments (+ dynamic list `email_segment_id` / `segment_rules` / `list_type`)
- Block list UI + `users.email_campaign_blocked*` (after data migration)
- `EmailCampaigns` shim, `email_templates.builder_data`, credential `daily_limit`

**Keep:** tags (organization only, not a send target).

## Harden remaining path

1. **Suppressions as sole opt-out**
   - Migrate `email_campaign_blocked=true` users → `email_suppressions` (`reason: unsubscribe`, tenant-scoped).
   - `CampaignUnsubscribe` writes/clears suppressions only (no user flag).
   - Campaign audience = list members; Gateway short-circuits suppressed addresses.
   - Suppressions admin: list + batch remove tenant unsubscribe/manual rows (global rows never deletable by tenant).

2. **No streams**
   - Drop `email_stream_id` from messages/campaigns/templates.
   - Gateway / Activities::Send / PersistMessage no longer take/resolve stream.
   - Campaign throttle: `Emails::Campaigns::SendCampaignJob::THROTTLE_PER_MINUTE` (default `60`).

3. **Lists = membership only**
   - `List#audience` → `users` through memberships.
   - Drop `list_type`, `segment_rules`, `email_segment_id`.
   - Campaign form: list picker only (no segment/stream/A/B).

4. **Transactional daily cap**
   - Implement `Emails::Activities::Send.daily_cap_for(customer)`; enforce before queueing non-suppressed transactional sends. Cap from module `daily_send_cap` (default `1000`).

5. **Sidebar / tabs**
   - Overview: dashboard | reports | deliverability | engagement
   - Campaigns: campaigns | templates (when enabled); templates only when disabled
   - Audience: contacts | lists | tags | suppressions
   - Settings: module Settings page only

6. **Naming**
   - Delete `app/services/email_campaigns.rb` shim.
   - Keep `Email::` transport vs `Emails::` product (Payments-style).

## Data migration order

1. Blocked users → suppressions (`reason: unsubscribe`).
2. Drop FKs/columns/tables for pruned features.
3. Drop `users.email_campaign_blocked*` and related scopes/methods.

## Non-goals

- Separate Contact model, new providers, double opt-in, inbound email, soft-bounce retry
- Rebuilding pruned features
- Full Figma redesign of kept surfaces (tab pruning only)

## Success criteria

- No routes/nav to pruned features; schema gone.
- Unsubscribe → suppression → send skips address.
- Campaigns send only to list membership.
- Vitest 100% on remaining JS; email-module RSpec green; no references to removed constants.

## Amendment (2026-07-24)

**Lists keep conditional filters.** Static membership lists and dynamic `segment_rules` (SegmentQuery + SegmentBuilder UI) are restored on `email_lists`. The separate Segments admin/table remains removed; rules live on the list.
