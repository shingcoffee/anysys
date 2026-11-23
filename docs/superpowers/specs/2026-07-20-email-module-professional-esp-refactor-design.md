# Email Module — Professional ESP Refactor

**Date:** 2026-07-20  
**Status:** Design — ready for implementation plan  
**Scope:** Massive refactor of the Email module to match the feature set, UX hierarchy, and architecture of industry-standard email platforms (Mailchimp, SendGrid, Postmark, ConvertKit). Reorganizes navigation, enriches capabilities, and keeps the existing multi-tenant Rails foundation intact.

---

## 1. Executive Summary

The current Email module is functionally capable but organized like a collection of admin tables rather than a cohesive Email Service Provider (ESP). This refactor turns it into a professional, productized email platform with:

- A clear **Send / Audience / Content / Analytics / Settings** navigation model.
- **Message streams/categories** that isolate transactional, marketing, and automated mail for reputation and reporting.
- An **Audience hub** with lists, dynamic segments, tags, and signup forms.
- A **Campaign builder** with step-by-step authoring, A/B testing, and deliverability guardrails.
- **Rich analytics** with date-range filtering, cohort trends, and exportable reports.
- **Deliverability tools** including suppression management, bounce/complaint drill-downs, and sender reputation visibility.
- **Template/content management** with categories, a shared asset library, and version history.

The refactor is delivered in phases so each subsystem can be implemented, reviewed, and shipped independently while keeping the suite green.

---

## 2. Baseline — Current State

The existing module (post 2026-07-19 merge) contains:

- **Models:** `Emails::Template`, `Emails::TemplateVersion`, `Emails::Message`, `Emails::MessageEvent`, `Emails::Suppression`, `Emails::Credential`, `EmailCampaigns::Campaign`, `EmailCampaigns::List`.
- **Services:** `Emails::Gateway`, `Emails::Activities::Send`, `Emails::PersistMessage`, `Emails::TemplateRenderer`, `Emails::TemplateLinter`, `Emails::DashboardStats`, `EmailCampaigns::SendCampaignJob`, `EmailCampaigns::AudienceQuery`, provider adapters under `Email::Providers`.
- **Controllers/views:** Dashboard, templates, messages, suppressions, campaigns, lists, block-list, platform credentials, public unsubscribe/tracking/webhooks.
- **Sidebar:** Dashboard → Templates → Messages → Suppressions → Campaigns (accordion with Lists/Block-List).
- **Strengths:** Multi-tenant scoping, idempotent message persistence, provider-agnostic delivery, open/click tracking, webhook-driven bounce/complaint handling, campaign throttling and daily caps.

**Gaps versus an industry ESP:**

1. Flat menu; no separation between "send", "audience", "content", and "analytics".
2. No message streams/categories beyond `message_type` (`transactional`/`campaign`).
3. Audience is limited to a single list + segment rules; no tags, no reusable segments, no signup forms.
4. Campaign creation is a single form, not a guided builder.
5. No A/B testing, winner selection, or send-time optimization.
6. No automation/journey builder (drip sequences, triggered flows).
7. No shared asset/content library for images/files.
8. Reporting is a single 30-day dashboard; no per-campaign deep dives, no cohort comparison, no CSV export.
9. Suppression list is read-only with limited drill-down.
10. No preference center or topic-level unsubscribe.

---

## 3. Industry Reference

### 3.1 Mailchimp (marketing-first ESP)
Top-level navigation: **Dashboard, Create, Campaigns, Automations, Audience, Templates, Content Studio, Reports, Integrations**.
Key concepts:
- **Audience** = contacts + segments + tags + signup forms.
- **Campaigns** = regular, A/B, RSS, automated; guided builder.
- **Automations** = visual customer journeys with triggers and delays.
- **Content Studio** = shared media/assets.
- **Reports** = engagement, revenue, comparative analytics.

### 3.2 SendGrid (transactional + marketing)
Top-level navigation: **Email API, Marketing, Templates, Suppressions, Stats, Settings**.
Key concepts:
- **Dynamic Templates** with Handlebars and version control.
- **Marketing Campaigns** with lists, segments, senders.
- **Suppressions** grouped by unsubscribes, bounces, spam reports, invalid emails.
- **Subusers / API Keys** for account hierarchy.

### 3.3 Postmark (deliverability-focused)
Top-level navigation: **Dashboard, Message Streams, Templates, Broadcasts, Suppressions, Stats, Servers**.
Key concepts:
- **Message Streams** separate transactional and broadcast traffic.
- **Broadcasts** for one-to-many marketing mail.
- **Suppressions** with bounce categorization.
- **Templates** with version history and live preview.

### 3.4 What we adopt
- Postmark-style **message streams** for traffic separation.
- Mailchimp-style **Audience hub** and **Campaign builder**.
- SendGrid-style **suppression categorization** and **dynamic templates**.
- A unified **Analytics** area with drill-downs and exports.

---

## 4. Target Architecture

### 4.1 Navigation reorganization

All email URLs remain under `/:cid/admin/modules/emails/*`. The sidebar groups them into five product areas:

```
Email
├── Overview
│   └── Dashboard
├── Send
│   ├── Campaigns
│   ├── Messages (was Email Messages)
│   └── Automations (new)
├── Audience
│   ├── All Contacts
│   ├── Lists
│   ├── Segments (new)
│   ├── Tags (new)
│   └── Signup Forms (new)
├── Content
│   ├── Templates
│   └── Asset Library (new)
├── Analytics
│   ├── Reports
│   ├── Deliverability
│   └── Engagement
└── Settings
    ├── Credentials
    ├── Suppressions
    ├── Message Streams (new)
    └── Preference Topics (new)
```

**Settings placement:** `Credentials` stay under platform-owner-only **Maintenance / Platform / Module Settings / Email** per the module categorization rules. All other settings (suppressions, streams, preference topics) are customer-specific and live under **Settings / Email**.

### 4.2 Core domain concepts

| Concept | Purpose |
|---|---|
| **Message Stream** | A tenant-scoped traffic lane (`transactional`, `marketing`, `automated`) with its own provider/mode, tracking toggle, and throttling. Replaces the flat `message_type` enum as the primary classifier. |
| **Audience** | The tenant's contacts (`Authentication::User` today) plus imported contacts (future). |
| **List** | A static or dynamic collection of audience members. Static lists hold explicit memberships; dynamic lists evaluate segment rules at send time. |
| **Segment** | A reusable saved query over audience attributes/behaviors. |
| **Tag** | A manual label applied to audience members. |
| **Campaign** | A marketing broadcast sent to a list/segment with a template, schedule, and optional A/B test. |
| **Automation** | A trigger-based sequence of emails (drip/journey). |
| **Template** | A reusable email layout with variables, categories, and version history. |
| **Asset** | An uploaded image/file available across templates and campaigns. |

### 4.3 Service-layer boundaries

Existing services are refactored into cohesive namespaces:

- `Emails::Streams::*` — stream CRUD, resolution, and routing.
- `Emails::Audience::*` — contacts, lists, segments, tags, signup forms.
- `Emails::Content::*` — templates, assets, categories.
- `Emails::Campaigns::*` — campaign builder, scheduling, A/B tests, delivery orchestration.
- `Emails::Automations::*` — automation definitions, triggers, step execution.
- `Emails::Analytics::*` — stats aggregation, reports, exports.
- `Emails::Deliverability::*` — suppressions, bounce/complaint categorization, reputation.
- `Emails::Delivery::*` — provider adapters, credential resolution, message dispatch.

The existing `EmailCampaigns` namespace is retired; its models and jobs are moved to `Emails::Campaigns`.

---

## 5. Approaches

### Approach A: Big-bang rewrite
Replace the entire module in one large change set: new data model, new controllers, new views, new service layer, menu restructure, and all new features.

- **Pros:** Clean slate, no intermediate migration state.
- **Cons:** Impossible to review safely; high regression risk; long-running branch conflicts with master; any bug blocks the whole release.
- **Verdict:** Rejected. The codebase already has working email delivery and campaign infrastructure; throwing it away is wasteful and risky.

### Approach B: Phased evolution (recommended)
Keep the working foundation, restructure the menu first, then add/upgrade one subsystem at a time. Each phase ships independently with focused specs and green tests.

- **Pros:** Reviewable chunks, continuous delivery, lower risk, can adapt based on earlier phase feedback.
- **Cons:** Requires careful data migrations and temporary compatibility shims between phases.
- **Verdict:** Recommended.

### Approach C: Surface-only reorganization
Only change the sidebar/menu and rename a few labels; leave backend unchanged.

- **Pros:** Fast, low risk.
- **Cons:** Does not address the user's request to "enrich features and functionalities"; menu labels would mislead because underlying capabilities don't match.
- **Verdict:** Rejected.

---

## 6. Detailed Design

### 6.1 Phase 1 — Foundation: streams, menu restructure, and namespace cleanup

#### 6.1.1 Menu restructure
Update `FeatureModules::Email::Registration#sidebar_contributions` to return the five-area hierarchy above. Add new i18n keys for all labels in `config/locales/feature_modules.en.yml` and `feature_modules.zh-CN.yml`.

The existing entries (`dashboard`, `templates`, `messages`, `suppressions`, `campaigns`, `lists`, `block_list`) are retained as `entry_key`s but grouped under new parent contributions. New entry keys: `automations`, `contacts`, `segments`, `tags`, `signup_forms`, `assets`, `reports`, `deliverability`, `engagement`, `streams`, `preference_topics`.

#### 6.1.2 Message streams
Introduce `Emails::Stream`:

```ruby
# Table: email_streams
# columns: customer_id, key, name, kind, provider, mode, status, tracking_enabled,
#           throttle_per_minute, from_email, reply_to, default_for_kind, created_at, updated_at
```

- `kind`: `transactional`, `marketing`, `automated`.
- `key`: tenant-unique slug (`onboarding`, `newsletter`, `receipts`).
- `status`: `active`, `disabled`.
- `default_for_kind`: exactly one active stream per kind is the default.
- Provider/mode/from_email can be overridden per stream; if blank, fall back to the active credential.

`Emails::Message` gains `stream_id` (nullable initially, backfilled). The `message_type` enum is deprecated and derived from the stream's kind.

Add `Emails::Streams::Resolve` service to pick the right stream for a send. Update `Emails::Activities::Send`, `Emails::Gateway.send_raw`, and `Emails::Gateway.queue_for_campaign` to accept an optional `stream:` argument and record `stream_id` on the message.

Update `EmailCampaigns::SendCampaignJob` (later `Emails::Campaigns::SendCampaignJob`) to resolve the campaign's stream once per batch and use its throttle/cap settings.

#### 6.1.3 Namespace cleanup
Move `EmailCampaigns::*` models/services/jobs/controllers/views to `Emails::Campaigns::*`:

- `EmailCampaigns::Campaign` → `Emails::Campaigns::Campaign`
- `EmailCampaigns::List` → `Emails::Audience::List`
- `EmailCampaigns::AudienceQuery` → `Emails::Audience::SegmentQuery`
- `EmailCampaigns::SendCampaignJob` → `Emails::Campaigns::SendCampaignJob`
- Controllers and views moved from `admin/modules/emails/campaigns` to `admin/modules/emails/campaigns` (already there; class names update).

Add temporary ActiveRecord `self.table_name` declarations and a data migration that does not rename tables. Aliases/redirects keep old URLs working for one phase.

### 6.2 Phase 2 — Audience hub

#### 6.2.1 Contacts
The audience is the tenant's `Authentication::User` records. Add an admin view `/admin/modules/emails/contacts` listing users with email engagement summary (last sent, last open, status).

Add `Emails::Audience::ContactStats` service to compute per-contact aggregates from `Emails::Message` and `Emails::MessageEvent`.

#### 6.2.2 Tags
Introduce `Emails::Audience::Tag` and a polymorphic join `Emails::Audience::Tagging`:

```ruby
# email_tags: customer_id, name, color
# email_taggings: tag_id, taggable_type, taggable_id
```

Contacts can be tagged manually or via import/automation. Tags are shown in the contact index and list builder.

#### 6.2.3 Segments
Promote the existing list segment rules into reusable, first-class `Emails::Audience::Segment`:

```ruby
# email_segments: customer_id, name, rules_json, match_count, updated_at
```

`Emails::Audience::SegmentQuery` (formerly `EmailCampaigns::AudienceQuery`) evaluates `rules_json` against users. Segments are referenced by campaigns and lists. A background job `Emails::Audience::RefreshSegmentCountsJob` recomputes `match_count` asynchronously.

#### 6.2.4 Lists
Refactor `Emails::Audience::List` to support two types:
- `static` — explicit memberships via `Emails::Audience::ListMembership`.
- `dynamic` — references a segment; membership is evaluated at send time.

Add import/bulk-add UI for static lists. Keep existing campaigns compatible by treating legacy lists as dynamic lists whose rules live on the list.

#### 6.2.5 Signup forms
Introduce `Emails::Audience::SignupForm`:

```ruby
# email_signup_forms: customer_id, name, status, settings_json, embed_code
```

Each form gets a public endpoint `POST /:cid/email/signup_forms/:key/subscribe` that creates a user (or updates an existing user) and tags them. The form supports honeypot and reCAPTCHA integration via the existing Captcha module.

### 6.3 Phase 3 — Content hub

#### 6.3.1 Template categories and gallery
Add `category` to `Emails::Template` (free-form tenant-scoped or system defaults: `account`, `marketing`, `notification`, `receipt`). Templates index supports category filter and a gallery/grid view.

#### 6.3.2 Asset library
Introduce `Emails::Asset` backed by Active Storage:

```ruby
# email_assets: customer_id, name, kind, file_blob_id, created_at
```

Assets are images/files reusable in templates. The rich-text editor and template form get an asset picker.

#### 6.3.3 Template enhancements
- **Live preview** already exists; extend it to support stream-specific from/reply-to and tracking pixel injection.
- **Merge-tag helper** UI: click-to-insert variable tags with fallback syntax.
- **Template testing**: send test to multiple addresses, show spam-score hints (basic keyword checks).

### 6.4 Phase 4 — Campaign builder and A/B testing

#### 6.4.1 Wizard-style campaign builder
Replace the single-form campaign UI with a stepper:
1. **Setup** — name, stream, schedule, recurrence.
2. **Audience** — choose list or segment (search/filter).
3. **Content** — choose template or create a one-off; subject/body override.
4. **Review** — audience size, sample preview, send/test.

Use Stimulus for step navigation and async audience-count fetch.

#### 6.4.2 A/B testing
Add `Emails::Campaigns::Experiment` to a campaign:

```ruby
# email_campaigns: add ab_test_enabled, ab_test_config_json, winner_criteria
# ab_test_config_json: { variants: [ { name: 'A', subject: '...' }, { name: 'B', subject: '...' } ], test_percentage: 20, auto_send_winner_after_hours: 4, winner_metric: 'open_rate'|'click_rate' }
```

When enabled:
- A small test percentage of the audience receives variant A or B.
- After the wait period, the winning variant is sent to the remainder.
- `Emails::Campaigns::PickWinnerJob` evaluates opens/clicks and triggers the final send.

### 6.5 Phase 5 — Automations

Introduce `Emails::Automations::Workflow`:

```ruby
# email_automations: customer_id, name, status, trigger_kind, trigger_config_json
# email_automation_steps: automation_id, position, step_type, config_json, email_template_id, delay_minutes
```

- **Triggers:** `user_created`, `tag_added`, `event_received`, `date_field`.
- **Steps:** `delay`, `send_email`, `add_tag`, `remove_tag`, `branch` (future).
- **Execution:** `Emails::Automations::EnqueueJob` polls for triggered enrollments; `Emails::Automations::ProcessStepJob` executes the next step.

Messages sent by automations use the `automated` stream kind and are excluded from campaign daily caps.

### 6.6 Phase 6 — Analytics and deliverability

#### 6.6.1 Reports
`/admin/modules/emails/reports` supports:
- Date range picker (7d, 30d, 90d, custom).
- Stream and campaign filters.
- Aggregate cards: sent, delivered, bounced, complained, opened, clicked, unsubscribed.
- Trend charts (SVG sparklines, already used; extend to bar/line charts).
- Per-campaign report cards.
- CSV export.

`Emails::Analytics::Report` service builds the dataset from `Emails::Message` and `Emails::MessageEvent`.

#### 6.6.2 Deliverability dashboard
`/admin/modules/emails/deliverability` shows:
- Bounce breakdown by category (hard, soft, block, etc.).
- Complaint rate trend.
- Suppression list with reason filter and bulk unblock.
- Stream health summary (send volume vs bounce rate per stream).

#### 6.6.3 Engagement
`/admin/modules/emails/engagement` shows:
- Top links clicked.
- Opens by hour-of-day/day-of-week.
- Device/client breakdown (parsed from `user_agent` in `MessageEvent`).

### 6.7 Phase 7 — Settings and preference center

#### 6.7.1 Message streams UI
CRUD for `Emails::Stream` under Settings / Email.

#### 6.7.2 Suppressions UI enhancements
Move suppressions from a top-level module entry to Settings / Email. Add:
- Reason filter.
- Source filter (manual, webhook, unsubscribe).
- Bulk unblock / import / export.
- Per-email event history.

#### 6.7.3 Preference topics
Introduce `Emails::PreferenceTopic`:

```ruby
# email_preference_topics: customer_id, key, name, description, default_subscribed, required
```

Public preference center at `/email/preferences/:token` lets users opt out of individual topics while staying subscribed to required transactional mail. Update unsubscribe flow to optionally redirect to the preference center.

---

## 7. Data Model Additions

### 7.1 New tables

| Table | Purpose |
|---|---|
| `email_streams` | Tenant-scoped message streams. |
| `email_tags` | Audience tags. |
| `email_taggings` | Polymorphic tag joins. |
| `email_segments` | Reusable saved audience segments. |
| `email_signup_forms` | Embeddable signup forms. |
| `email_assets` | Asset library metadata. |
| `email_automations` | Automation workflows. |
| `email_automation_steps` | Steps inside a workflow. |
| `email_automation_enrollments` | Users currently in a workflow. |
| `email_preference_topics` | Topic-based subscription preferences. |
| `email_user_preferences` | Per-user topic subscriptions. |

### 7.2 Modified tables

| Table | Changes |
|---|---|
| `email_messages` | Add `stream_id` (indexed, nullable then not-null), deprecate `message_type` (kept for migration, derived from stream). |
| `email_templates` | Add `category`, `stream_id` (default stream). |
| `email_campaigns` | Add `stream_id`, `segment_id`, `ab_test_config_json`, `experiment_id` (future). |
| `email_lists` | Add `list_type` (`static`/`dynamic`), `segment_id`, migrate existing rules to segment or keep legacy. |

### 7.3 Retired

- No tables dropped. `EmailCampaigns` namespace is renamed but tables keep their names with `self.table_name`.

---

## 8. Service and Job Additions

### 8.1 New services

| Service | Responsibility |
|---|---|
| `Emails::Streams::Resolve` | Pick the active/default stream for a send. |
| `Emails::Streams::DefaultForKind` | Ensure exactly one default stream per kind per tenant. |
| `Emails::Audience::SegmentQuery` | Compile segment rules to a relation (evolution of `EmailCampaigns::AudienceQuery`). |
| `Emails::Audience::RefreshSegmentCounts` | Recompute segment match counts. |
| `Emails::Campaigns::Build` | Validate and assemble a campaign across wizard steps. |
| `Emails::Campaigns::PickWinner` | A/B test winner selection. |
| `Emails::Automations::Trigger` | Evaluate triggers and create enrollments. |
| `Emails::Automations::ProcessStep` | Execute the next step for an enrollment. |
| `Emails::Analytics::Report` | Aggregate data for reports. |
| `Emails::Analytics::ExportCsv` | Generate CSV exports. |
| `Emails::Deliverability::CategorizeBounce` | Map provider bounce codes to categories. |
| `Emails::Deliverability::ReputationScore` | Compute a simple reputation score per stream. |

### 8.2 New/modified jobs

| Job | Responsibility |
|---|---|
| `Emails::Campaigns::SendCampaignJob` | Renamed from `EmailCampaigns::SendCampaignJob`; uses stream settings. |
| `Emails::Campaigns::PickWinnerJob` | Trigger A/B winner and send to remainder. |
| `Emails::Audience::RefreshSegmentCountsJob` | Background segment refresh. |
| `Emails::Automations::EnqueueJob` | Poll triggers and create enrollments. |
| `Emails::Automations::ProcessStepJob` | Execute automation steps. |

---

## 9. UI/UX Changes

- New sidebar structure using grouped `ModuleContribution` children.
- New ViewComponents:
  - `Emails::SidebarNavComponent` (grouped entries).
  - `Emails::StatsCardComponent`.
  - `Emails::SparklineComponent` (extend existing inline SVG).
  - `Emails::CampaignBuilderComponent` (stepper).
  - `Emails::SegmentBuilderComponent` (evolve existing component).
  - `Emails::AssetPickerComponent`.
  - `Emails::StreamFormComponent`.
  - `Emails::PreferenceCenterComponent`.
- All new strings go through I18n with `en` and `zh-CN` parity.
- All pages remain responsive with Tailwind utilities.
- No custom CSS or JS frameworks; Stimulus only.

---

## 10. Authorization

Follow existing rules:
- Admin routes under `/:cid/admin/modules/emails/*` require `admin` or `owner`.
- Member-facing public endpoints (`/email/signup_forms/*`, `/email/preferences/*`, `/email/track/*`, `/email/webhooks/*`) are public or token-scoped.
- Cross-tenant scoping enforced in controllers and services via `TenantScoped` / `for_current_customer`.

---

## 11. Rollout and Migration Strategy

1. **Phase 1 ships first.** Includes data migration to create default streams for each tenant (`transactional`, `marketing`, `automated`), backfill `stream_id` on `email_messages`, and move `EmailCampaigns` classes to `Emails::Campaigns` with table-name aliases.
2. **Phases 2–7 ship sequentially.** Each phase has its own migrations and specs.
3. **No breaking public URLs.** Unsubscribe, tracking, and webhook paths remain stable.
4. **Old `EmailCampaigns` namespace classes are kept as aliases for one phase** then removed in Phase 2 if not needed by callers.

---

## 12. Testing Strategy

- **Model specs:** streams, segments, tags, lists, automations, preference topics.
- **Service specs:** all new services; updated `Emails::Activities::Send`, `Emails::Gateway`, `Emails::Campaigns::SendCampaignJob`.
- **Job specs:** campaign delivery, A/B winner, automation enrollment/step processing, segment refresh.
- **Request specs:** new controllers (streams, segments, tags, assets, automations, reports, preference center), wizard campaign flow.
- **Component specs:** new ViewComponents.
- **i18n parity tests:** every new key present in `en` and `zh-CN`.
- **Feature/module integration:** sidebar contributions, module enablement, campaigns sub-toggle.

Run targeted specs per phase; run the full suite before declaring the entire refactor complete.

---

## 13. Out of Scope

- Inbound email / Action Mailbox.
- Advanced AI send-time optimization.
- Revenue/ROI attribution.
- Dedicated IP / sending-domain DNS management beyond existing DKIM.
- Third-party integrations beyond existing webhooks.

---

## 14. Open Questions

None — this design proceeds directly to implementation planning per user instruction to avoid confirmation gates.
