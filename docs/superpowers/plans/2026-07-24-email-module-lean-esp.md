# Email Module Lean ESP Implementation Plan

> **For agentic workers:** Use subagent-driven-development. Do NOT git commit unless the user explicitly asks (project rule).

**Goal:** Hard-remove incomplete email ESP shells and harden the remaining list→campaign→suppression→send core.

**Architecture:** One migration (data + schema), delete pruned product surfaces, then update Gateway/Send/List/Unsubscribe/sidebar/suppressions admin so the kept path is coherent.

**Tech Stack:** Rails 8.1.2, Trailblazer Activities, Reform, ViewComponent, Stimulus, RSpec, Vitest

## Global Constraints

- I18n en + zh-CN for any remaining user-facing strings; no new hard-coded UI copy
- No backward-compat shims
- Multi-tenant: suppressions may be global (customer_id NULL) or tenant-scoped; tenants cannot delete globals
- Do not auto-commit
- Spec: `docs/superpowers/specs/2026-07-24-email-module-lean-esp-design.md`

---

### Task 1: Migration — opt-out unify + drop pruned schema

**Files:**
- Create: `db/migrate/20260724120000_lean_email_module_prune.rb`
- Modify: `db/schema.rb` (via migrate)

**Steps:**
- [ ] Write migration that:
  1. For each `users` row with `email_campaign_blocked = true`, upsert `email_suppressions` (customer_id, lower(email), reason unsubscribe) if missing
  2. Remove FKs: campaigns→segments/streams, lists→segments, messages→streams, templates→streams, user_preferences→topics
  3. Drop tables: email_automation_enrollments, email_automation_steps, email_automations, email_user_preferences, email_preference_topics, email_signup_forms, email_segments, email_streams
  4. Remove columns: campaigns ab_test_*, email_segment_id, email_stream_id; lists list_type, segment_rules, email_segment_id; messages email_stream_id; templates builder_data, email_stream_id; credentials daily_limit; users email_campaign_blocked, email_campaign_blocked_at (+ index)
- [ ] Run `bin/rails db:migrate`
- [ ] Do not commit

---

### Task 2: Delete pruned app code (models/services/jobs/controllers/views/JS)

Delete all automations, A/B, streams, segments, signup forms, preference topics/center, block list, EmailCampaigns shim, and related Stimulus + component + factory + spec files. Update routes.rb to remove pruned routes. Update tabs/sidebar registration.

**Key deletes (non-exhaustive — grep for leftovers):**
- `app/models/emails/{stream,preference_topic,user_preference}.rb`
- `app/models/emails/automations/**`
- `app/models/emails/audience/{segment,signup_form}.rb`
- `app/services/emails/{streams,automations,preferences,audience/segment*,audience/signup*,campaigns/pick_winner*}/**`
- `app/services/email_campaigns.rb`
- `app/jobs/emails/automations/**`, `pick_winner_job`, `refresh_segment_counts*`
- Controllers/views for automations, streams, segments, signup_forms, preference_topics, block_list, preferences
- Stimulus: `ab_test_builder`, `automation_step_builder`, `segment_builder` (+ vitest twins)
- Factories/specs for deleted models

**Modify:**
- `config/routes.rb` — remove pruned public + admin routes
- `app/services/feature_modules/email/registration.rb` — new tab_paths; remove block_list_entry_config; fix campaigns when disabled → templates
- `app/services/feature_modules/email/provisioner.rb` — stop provisioning streams
- `app/components/emails/tabs_component.rb` (if tab lists hard-coded)
- Locales: remove dead keys only if orphaned specs fail; prefer leave unused keys vs broken references

---

### Task 3: Harden send path (Gateway, Send, PersistMessage, Campaign job, List, Unsubscribe, User)

**Modify:**
- `app/services/emails/gateway.rb` — drop stream_key/stream/variant; no Streams::Resolve; PersistMessage without email_stream
- `app/services/emails/activities/send.rb` — drop stream; add `daily_cap_for` + enforce (raise or return suppressed-style failure per existing error patterns — prefer `Email::Errors` if one exists for cap, else skip enqueue and set status failed with metadata reason)
- `app/services/emails/persist_message.rb` — stop requiring/assigning email_stream
- `app/models/emails/message.rb` / `template.rb` / `campaigns/campaign.rb` — remove stream/segment/ab_test associations and methods
- `app/models/emails/audience/list.rb` — membership-only audience
- `app/jobs/emails/campaigns/send_campaign_job.rb` — THROTTLE_PER_MINUTE=60; no stream/variant; audience without campaign_deliverable flag (list users; gateway suppresses)
- `app/services/emails/campaigns/{build,campaign_unsubscribe,start_campaign}.rb` — no ab_test/segment/stream; unsubscribe suppressions-only
- `app/models/authentication/user.rb` — remove block_campaign_email! / scopes
- `app/controllers/admin/modules/emails/{campaigns,lists,suppressions}_controller.rb` — forms/params without pruned fields; suppressions allow batch delete of tenant unsubscribe/manual
- Credential form: drop daily_limit field

---

### Task 4: Specs + Vitest

- Update/delete specs mirroring Task 2–3
- Run: `bundle exec rspec` on touched email specs (models/services/jobs/requests/components)
- Run: `npx vitest run --coverage` — must stay 100% lines/branches on remaining `app/javascript/**`
- Fix failures until green

---

### Task 5: Review gates

- Dispatch anysys-tech-lead + anysys-code-reviewer on the diff
- Fix any FAIL items that are in scope
