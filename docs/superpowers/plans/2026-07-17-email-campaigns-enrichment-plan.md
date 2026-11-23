# Email & Email Campaign Modules — Refactor + Enrichment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete the architecture clean-up from the 2026-07-14 hardening pass, enrich template-building UX, add open/click tracking + a deliverability dashboard, and wire scheduled/delayed campaign sends with rate throttling.

**Architecture:** Consolidate message persistence into one value object; unify the service namespace to `Emails::`; extend the existing `Emails::TemplateRenderer` for fallbacks/tracking; add an `email_message_events` ledger for engagement; build a read-only dashboard from SQL aggregates; keep all changes on `master` uncommitted.

**Tech Stack:** Rails 7, Ruby 3.3, Action Text / Lexxy, Stimulus, RSpec, ActiveStorage, SQLite, Tailwind CSS.

## Global Constraints

- All changes stay on `master`; do **not** commit.
- Full RSpec suite for email + campaign modules must remain green; add specs for every new behavior.
- i18n parity required for `en` and `zh-CN` on all new UI keys.
- Follow existing patterns: `TenantScoped`, `VendorPlugin`, `PluginRegistry`, `RouteAuthorization`, `ModuleEntriesResolver`.
- No new gems unless required for crypto/UUID/signature logic.
- Do not alter existing webhook auth or suppression behavior except where explicitly required.

---

## Task 1: Architecture — message persistence value object

**Files:**
- Create: `app/services/emails/persist_message.rb`
- Modify: `app/services/email/gateway.rb`, `app/services/email/activities/send.rb`
- Test: `spec/services/emails/persist_message_spec.rb`, update `spec/services/email/gateway_spec.rb` if present, `spec/services/email/activities/send_spec.rb` if present

**Interfaces:**
- Consumes: `Emails::Message` attributes, idempotency key, customer, optional `provider:` override.
- Produces: `Emails::PersistMessage.call(attrs)` returns `[message, created]`; `Emails::Gateway.send_raw` and `Email::Activities::Send` delegate persistence to it.

- [ ] **Step 1: Write failing spec for `Emails::PersistMessage`**

```ruby
require "rails_helper"

RSpec.describe Emails::PersistMessage do
  let(:customer) { create(:customer) }
  let(:template) { create(:email_template, customer: customer) }

  it "creates a queued message" do
    message, created = described_class.call(
      customer: customer,
      to: "test@example.com",
      subject: "Hi",
      body_html: "<p>Hi</p>",
      body_text: "Hi",
      message_type: "transactional",
      status: "queued",
      provider: "smtp"
    )
    expect(created).to be true
    expect(message).to be_persisted
    expect(message.status).to eq("queued")
  end

  it "returns existing row on idempotency race" do
    attrs = {
      customer: customer, to: "test@example.com", subject: "Hi",
      body_html: "<p>Hi</p>", body_text: "Hi",
      message_type: "transactional", status: "queued", provider: "smtp",
      idempotency_key: "abc"
    }
    first, first_created = described_class.call(attrs)
    second, second_created = described_class.call(attrs)
    expect(first_created).to be true
    expect(second_created).to be false
    expect(second.id).to eq(first.id)
  end
end
```

- [ ] **Step 2: Implement `Emails::PersistMessage`**

```ruby
module Emails
  class PersistMessage
    def self.call(attrs, idempotency_key: nil)
      new(attrs, idempotency_key: idempotency_key).call
    end

    def initialize(attrs, idempotency_key: nil)
      @attrs = attrs
      @idempotency_key = idempotency_key
      @customer = attrs[:customer]
    end

    def call
      return existing_message if idempotency_key.present? && existing_message
      [Emails::Message.create!(@attrs), true]
    rescue ActiveRecord::RecordNotUnique
      [Emails::Message.find_by!(customer_id: @customer.id, idempotency_key: @idempotency_key), false]
    end

    private

    def existing_message
      @existing_message ||= Emails::Message.find_by(customer_id: @customer.id, idempotency_key: @idempotency_key)
    end
  end
end
```

- [ ] **Step 3: Refactor `Email::Gateway.send_raw` and `Email::Activities::Send` to use `Emails::PersistMessage`**

- [ ] **Step 4: Run targeted specs**

Run: `bundle exec rspec spec/services/emails/persist_message_spec.rb spec/services/email/activities/send_spec.rb spec/services/email/gateway_spec.rb`
Expected: PASS

---

## Task 2: Architecture — namespace unification (`Email::` → `Emails::`)

**Files:**
- Rename/modify: `app/services/email/template_renderer.rb` → `app/services/emails/template_renderer.rb`
- Rename/modify: `app/services/email/variable_context.rb` → `app/services/emails/variable_context.rb`
- Rename/modify: `app/services/email/gateway.rb` → `app/services/emails/gateway.rb`
- Rename/modify: `app/services/email/activities/send.rb` → `app/services/emails/activities/send.rb`
- Update all call sites: controllers, jobs, services, specs, generators.

**Interfaces:**
- `Emails::TemplateRenderer.render(template:, vars:)`
- `Emails::VariableContext.for(user:)`
- `Emails::Gateway.send(...)` and `Emails::Gateway.send_raw(...)`
- `Emails::Activities::Send.call(...)`

- [ ] **Step 1: Rename files and update module names from `Email::` to `Emails::`**
- [ ] **Step 2: Update all callers (grep for `Email::TemplateRenderer`, `Email::VariableContext`, `Email::Gateway`, `Email::Activities::Send`)**
- [ ] **Step 3: Update specs and factories references**
- [ ] **Step 4: Run full email/campaign spec slice**

Run: `bundle exec rspec spec/services/email spec/services/emails spec/services/email_campaigns spec/jobs/email_campaigns spec/models/email_campaigns spec/requests/admin/modules/email_campaigns spec/requests/admin/modules/emails`
Expected: PASS

---

## Task 3: Architecture — drop vestigial columns

**Files:**
- Create: `db/migrate/20260717140000_drop_vestigial_email_message_columns.rb`
- Update: any code still reading `builder_data` or `scheduled_at` on `Emails::Message`

- [ ] **Step 1: Verify `builder_data` and `scheduled_at` on `email_messages` are unused**
- [ ] **Step 2: Write migration to remove them if unused**

```ruby
class DropVestigialEmailMessageColumns < ActiveRecord::Migration[7.1]
  def up
    remove_column :email_messages, :builder_data, if exists
    remove_column :email_messages, :scheduled_at, if exists
  end

  def down
    add_column :email_messages, :builder_data, :jsonb, default: {}
    add_column :email_messages, :scheduled_at, :datetime
  end
end
```

- [ ] **Step 3: Run migration and specs**

---

## Task 4: Template — live preview endpoint and UI

**Files:**
- Create: `app/controllers/admin/modules/emails/template_previews_controller.rb`
- Modify: `app/views/admin/modules/emails/templates/_form.html.erb`
- Modify: `config/routes.rb`
- Test: `spec/requests/admin/modules/emails/template_previews_spec.rb`

**Interfaces:**
- `POST /:customer_id/admin/modules/emails/templates/:id/preview` → JSON `{ subject:, body_html:, body_text: }`
- Consumes `vars` param (JSON or form hash); falls back to `Emails::VariableContext.for(user: current_user)`.

- [ ] **Step 1: Add route and controller**
- [ ] **Step 2: Add preview pane to template form**
- [ ] **Step 3: Write request specs for preview**
- [ ] **Step 4: Run specs**

---

## Task 5: Template — token linting and merge-tag fallbacks

**Files:**
- Create: `app/services/emails/template_linter.rb`
- Modify: `app/services/emails/template_renderer.rb`
- Modify: `app/controllers/admin/modules/emails/templates_controller.rb` (surface warnings)
- Test: `spec/services/emails/template_linter_spec.rb`, `spec/services/emails/template_renderer_spec.rb`

**Interfaces:**
- `Emails::TemplateLinter.lint(template)` → `{ unknown: ["foo"], missing: ["bar"] }`
- `Emails::TemplateRenderer.render` supports `{{first_name|fallback:"Friend"}}`

- [ ] **Step 1: Implement linter with token extraction**
- [ ] **Step 2: Implement fallback syntax in renderer**
- [ ] **Step 3: Surface lint warnings on template form**
- [ ] **Step 4: Specs**

---

## Task 6: Template — version history

**Files:**
- Create: `app/models/emails/template_version.rb`
- Create: `db/migrate/20260717150000_create_email_template_versions.rb`
- Create: `app/controllers/admin/modules/emails/template_versions_controller.rb`
- Create views: `app/views/admin/modules/emails/template_versions/{index,show}.html.erb`
- Modify: `app/models/emails/template.rb` (`after_update :snapshot!`)
- Modify: `config/routes.rb`
- Test: `spec/models/emails/template_version_spec.rb`, `spec/requests/admin/modules/emails/template_versions_spec.rb`

**Interfaces:**
- `Emails::TemplateVersion.create_for(template, user:)` snapshots current attributes.
- `template.restore_to_version!(version)` reverts attributes.

- [ ] **Step 1: Migration and model**
- [ ] **Step 2: Controller, routes, views**
- [ ] **Step 3: Snapshot hook and restore method**
- [ ] **Step 4: Specs**

---

## Task 7: Tracking — `email_message_events` table and endpoints

**Files:**
- Create: `db/migrate/20260717160000_create_email_message_events.rb`
- Create: `app/models/emails/message_event.rb`
- Create: `app/controllers/emails/tracking_controller.rb`
- Modify: `config/routes.rb`
- Modify: `app/services/emails/template_renderer.rb` (inject tracking pixel + rewrite links when enabled)
- Modify: `app/services/emails/gateway.rb` or `Emails::DeliverMessageJob` (persist `tracking_enabled` context)
- Test: `spec/models/emails/message_event_spec.rb`, `spec/requests/emails/tracking_spec.rb`, `spec/services/emails/template_renderer_spec.rb`

**Interfaces:**
- `Emails::MessageEvent.create_open(message, request:)`
- `Emails::MessageEvent.create_click(message, url:, request:)`
- `GET /email/track/:message_id/open.gif?sig=...`
- `GET /email/track/:message_id/click?url=...&sig=...`
- Signature via `Rails.application.message_verifier(:email_tracking)`.

- [ ] **Step 1: Migration and model with dedupe indexes**
- [ ] **Step 2: Signed URL helpers and verifier**
- [ ] **Step 3: Open pixel endpoint (1x1 GIF)**
- [ ] **Step 4: Click redirect endpoint**
- [ ] **Step 5: Inject pixel + rewrite links in renderer when `tracking_enabled`**
- [ ] **Step 6: Specs**

---

## Task 8: Reporting — deliverability dashboard

**Files:**
- Create: `app/controllers/admin/modules/emails/dashboard_controller.rb`
- Create: `app/views/admin/modules/emails/dashboard/show.html.erb`
- Create: `app/services/emails/dashboard_stats.rb`
- Modify: `config/routes.rb`, feature-module registration sidebar if needed
- Test: `spec/services/emails/dashboard_stats_spec.rb`, `spec/requests/admin/modules/emails/dashboard_spec.rb`

**Interfaces:**
- `Emails::DashboardStats.for(customer, since: 30.days.ago)` returns aggregates + daily series.

- [ ] **Step 1: Service that aggregates message statuses + events by day**
- [ ] **Step 2: Controller + view with inline SVG sparklines**
- [ ] **Step 3: Route and sidebar entry**
- [ ] **Step 4: Specs**

---

## Task 9: Scheduling + throttling

**Files:**
- Modify: `app/jobs/email_campaigns/send_campaign_job.rb` (rate throttle)
- Modify: `app/services/email_campaigns/start_campaign.rb` (timezone preview)
- Modify: `app/services/emails/activities/send.rb` and `Emails::DeliverMessageJob` (delayed transactional sends)
- Modify: `app/models/emails/credential.rb` or module config for throttle value
- Test: `spec/jobs/email_campaigns/send_campaign_job_spec.rb`, `spec/services/emails/deliver_message_job_spec.rb`

**Interfaces:**
- `SendCampaignJob` defers when `campaignThrottlePerMinute` exceeded.
- `Emails::DeliverMessageJob` reschedules itself when `message.scheduled_at` is future.

- [ ] **Step 1: Add per-minute throttle to campaign job**
- [ ] **Step 2: Support delayed transactional sends**
- [ ] **Step 3: Specs**

---

## Task 10: Verification

- [ ] **Step 1: Run full email + campaign specs**

Run: `bundle exec rspec spec/services/email spec/services/emails spec/services/email_campaigns spec/jobs/email_campaigns spec/jobs/emails spec/models/email_campaigns spec/models/emails spec/requests/admin/modules/email_campaigns spec/requests/admin/modules/emails spec/requests/emails`
Expected: PASS

- [ ] **Step 2: Check i18n parity**

Run: `bundle exec rake i18n:check` or diff `config/locales/email.en.yml` vs `config/locales/email.zh-CN.yml`
Expected: no missing keys on new strings

- [ ] **Step 3: RuboCop / syntax check**

Run: `bundle exec rubocop app/services/emails app/services/email_campaigns app/controllers/admin/modules/emails app/controllers/emails app/models/emails app/models/email_campaigns --format simple`
Expected: no new offenses
