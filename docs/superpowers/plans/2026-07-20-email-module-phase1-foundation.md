# Email Module Phase 1 — Foundation: Streams, Menu Restructure, Namespace Cleanup

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** Restructure the Email module sidebar into an industry-standard ESP navigation, introduce `Emails::Stream` as the central message classifier, and move campaign models/services/controllers into the `Emails` namespace while preserving existing data and URLs.

**Architecture:** Streams replace the flat `message_type` enum. A stream has a `kind` (`transactional`/`marketing`/`automated`), provider/mode overrides, tracking toggle, and throttle settings. The sidebar uses grouped `ModuleContribution` entries. `EmailCampaigns::*` classes are renamed to `Emails::Campaigns::*` and `Emails::Audience::*` with `self.table_name` preserving old tables.

**Tech Stack:** Ruby 3.2.8, Rails 8.1.2, TailwindCSS, StimulusJS, ViewComponent, RSpec, Trailblazer/Reform.

## Global Constraints

- All user-facing strings must be I18n in `en` and `zh-CN`; no hard-coded copy.
- All styling uses TailwindCSS only; no custom CSS.
- All JavaScript uses StimulusJS only; no custom JS frameworks.
- Admin routes require `admin` or `owner`; public endpoints are token/signature-scoped.
- Cross-tenant scoping via `TenantScoped` / `for_current_customer` on every record action.
- Changes made directly on `master`; do not auto-commit.

---

## File Structure

| File | Responsibility |
|---|---|
| `app/models/emails/stream.rb` | Tenant-scoped stream model with kind/provider/status/throttle validations. |
| `app/services/emails/streams/resolve.rb` | Pick the active/default stream for a send. |
| `app/services/emails/streams/default_for_kind.rb` | Ensure one default stream per kind per tenant. |
| `app/services/feature_modules/email/registration.rb` | New grouped sidebar structure. |
| `app/models/emails/campaigns/campaign.rb` | Renamed from `EmailCampaigns::Campaign`; `self.table_name = "email_campaigns"`. |
| `app/models/emails/audience/list.rb` | Renamed from `EmailCampaigns::List`; `self.table_name = "email_lists"`. |
| `app/services/emails/audience/segment_query.rb` | Renamed from `EmailCampaigns::AudienceQuery`. |
| `app/services/emails/campaigns/send_campaign_job.rb` | Renamed from `EmailCampaigns::SendCampaignJob`. |
| `app/services/emails/campaigns/start_campaign.rb` | Renamed from `EmailCampaigns::StartCampaign`. |
| `app/services/emails/campaigns/cron/reconcile_campaigns.rb` | Renamed from `EmailCampaigns::Cron::ReconcileCampaigns`. |
| `app/services/emails/campaigns/recurrence_rule.rb` | Renamed from `EmailCampaigns::RecurrenceRule`. |
| `app/services/emails/campaigns/field_catalog.rb` | Renamed from `EmailCampaigns::FieldCatalog`. |
| `app/services/emails/campaigns/campaign_unsubscribe.rb` | Renamed from `EmailCampaigns::CampaignUnsubscribe`. |
| `app/services/emails/campaigns/instrumentation.rb` | Renamed from `EmailCampaigns::Instrumentation`. |
| `app/jobs/emails/campaigns/send_campaign_job.rb` | Renamed from `EmailCampaigns::SendCampaignJob`. |
| `app/jobs/emails/campaigns/scheduler_job.rb` | Renamed from `EmailCampaigns::SchedulerJob`. |
| `app/jobs/emails/campaigns/reconcile_campaigns_job.rb` | Renamed from `EmailCampaigns::ReconcileCampaignsJob`. |
| `app/controllers/admin/modules/emails/campaigns_controller.rb` | Update references to `Emails::Campaigns`. |
| `app/controllers/admin/modules/emails/lists_controller.rb` | Update references to `Emails::Audience::List`. |
| `app/controllers/admin/modules/emails/block_list_controller.rb` | Update references. |
| `app/controllers/admin/modules/emails/campaign_deliveries_controller.rb` | Update references. |
| `app/controllers/admin/modules/emails/campaign_pauses_controller.rb` | Update references. |
| `app/controllers/admin/modules/emails/campaign_cancellations_controller.rb` | Update references. |
| `config/locales/feature_modules.en.yml` / `.zh-CN.yml` | New grouped email menu keys. |
| `db/migrate/20260720000000_create_email_streams.rb` | Create streams table. |
| `db/migrate/20260720000001_add_stream_id_to_email_messages.rb` | Add nullable stream_id. |
| `db/migrate/20260720000002_seed_default_email_streams.rb` | Create default streams per tenant. |
| `db/migrate/20260720000003_backfill_email_message_streams.rb` | Backfill stream_id from message_type. |
| `spec/models/emails/stream_spec.rb` | Stream model specs. |
| `spec/services/emails/streams/resolve_spec.rb` | Stream resolution specs. |
| `spec/services/feature_modules/email/registration_spec.rb` | Sidebar structure specs. |

---

## Task 1: Create the `email_streams` table and model

**Files:**
- Create: `db/migrate/20260720000000_create_email_streams.rb`
- Create: `app/models/emails/stream.rb`
- Test: `spec/models/emails/stream_spec.rb`

**Interfaces:**
- Produces: `Emails::Stream` AR model with scopes `.active`, `.for_current_customer`, `.default_for(kind)`, and instance methods `#default?`, `#tracking_enabled?`.

- [ ] **Step 1: Write the migration**

```ruby
# db/migrate/20260720000000_create_email_streams.rb
class CreateEmailStreams < ActiveRecord::Migration[8.1]
  def change
    create_table :email_streams do |t|
      t.references :customer, null: false, foreign_key: true
      t.string :key, null: false
      t.string :name, null: false
      t.string :kind, null: false, default: "transactional"
      t.string :provider
      t.string :mode, null: false, default: "sandbox"
      t.string :status, null: false, default: "active"
      t.boolean :tracking_enabled, null: false, default: true
      t.integer :throttle_per_minute, null: false, default: 1000
      t.string :from_email
      t.string :reply_to
      t.boolean :default_for_kind, null: false, default: false
      t.timestamps
    end

    add_index :email_streams, %i[customer_id key], unique: true
    add_index :email_streams, %i[customer_id kind default_for_kind status], name: "idx_email_streams_default_lookup"
  end
end
```

- [ ] **Step 2: Run the migration**

Run: `bin/rails db:migrate`
Expected: migration succeeds, `email_streams` table exists.

- [ ] **Step 3: Write the model spec (failing)**

```ruby
# spec/models/emails/stream_spec.rb
require "rails_helper"

RSpec.describe Emails::Stream, type: :model do
  let(:customer) { create(:customer) }

  describe "validations" do
    it "requires kind in transactional/marketing/automated" do
      stream = build(:email_stream, customer: customer, kind: "invalid")
      expect(stream).not_to be_valid
      expect(stream.errors[:kind]).to be_present
    end

    it "requires unique key per customer" do
      create(:email_stream, customer: customer, key: "newsletter")
      dup = build(:email_stream, customer: customer, key: "newsletter")
      expect(dup).not_to be_valid
    end
  end

  describe ".default_for" do
    it "returns the default stream for the kind" do
      default = create(:email_stream, customer: customer, kind: "transactional", default_for_kind: true)
      create(:email_stream, customer: customer, kind: "transactional", default_for_kind: false)
      expect(Emails::Stream.default_for(customer, "transactional")).to eq(default)
    end
  end
end
```

- [ ] **Step 4: Run the spec and confirm it fails**

Run: `bundle exec rspec spec/models/emails/stream_spec.rb`
Expected: FAIL — factory/email_stream missing or model not defined.

- [ ] **Step 5: Create the factory**

```ruby
# spec/factories/email_streams.rb
FactoryBot.define do
  factory :email_stream, class: "Emails::Stream" do
    customer
    sequence(:key) { |n| "stream-#{n}" }
    name { "Test Stream" }
    kind { "transactional" }
    status { "active" }
    mode { "sandbox" }
    throttle_per_minute { 1000 }
    tracking_enabled { true }
    default_for_kind { false }
  end
end
```

- [ ] **Step 6: Implement the model**

```ruby
# app/models/emails/stream.rb
module Emails
  class Stream < ApplicationRecord
    self.table_name = "email_streams"

    include TenantScoped

    KINDS = %w[transactional marketing automated].freeze
    STATUSES = %w[active disabled].freeze
    MODES = %w[sandbox production].freeze

    belongs_to :customer

    validates :customer_id, presence: true
    validates :key, presence: true,
                    uniqueness: { scope: :customer_id },
                    format: { with: /\A[a-z0-9_]+\z/ }
    validates :name, presence: true
    validates :kind, inclusion: { in: KINDS }
    validates :status, inclusion: { in: STATUSES }
    validates :mode, inclusion: { in: MODES }

    scope :active, -> { where(status: "active") }
    scope :default_for, ->(customer, kind) {
      active.where(customer: customer, kind: kind, default_for_kind: true).order(:id).first
    }

    def active? = status == "active"
    def default? = default_for_kind?
    def tracking_enabled? = tracking_enabled
  end
end
```

- [ ] **Step 7: Run the spec and confirm it passes**

Run: `bundle exec rspec spec/models/emails/stream_spec.rb`
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add db/migrate app/models/emails/stream.rb spec/factories/email_streams.rb spec/models/emails/stream_spec.rb
git commit -m "feat(email): add Emails::Stream model and table"
```

---

## Task 2: Add `stream_id` to `email_messages`

**Files:**
- Create: `db/migrate/20260720000001_add_stream_id_to_email_messages.rb`
- Modify: `app/models/emails/message.rb`
- Test: `spec/models/emails/message_spec.rb` (add examples)

**Interfaces:**
- Consumes: `Emails::Stream`
- Produces: `Emails::Message#stream` association and `stream_id` validation.

- [ ] **Step 1: Write the migration**

```ruby
# db/migrate/20260720000001_add_stream_id_to_email_messages.rb
class AddStreamIdToEmailMessages < ActiveRecord::Migration[8.1]
  def change
    add_reference :email_messages, :email_stream, foreign_key: true, index: true
  end
end
```

- [ ] **Step 2: Run the migration**

Run: `bin/rails db:migrate`
Expected: `email_stream_id` column added.

- [ ] **Step 3: Update the model**

```ruby
# app/models/emails/message.rb
module Emails
  class Message < ApplicationRecord
    # ... existing code ...
    belongs_to :email_stream, optional: true, class_name: "Emails::Stream"
    # ...
  end
end
```

- [ ] **Step 4: Add spec examples**

```ruby
# spec/models/emails/message_spec.rb
it "belongs to an optional stream" do
  message = build(:email_message, email_stream: nil)
  expect(message).to be_valid
end
```

- [ ] **Step 5: Run message specs**

Run: `bundle exec rspec spec/models/emails/message_spec.rb`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git commit -m "feat(email): add stream_id to email_messages"
```

---

## Task 3: Implement stream resolution services

**Files:**
- Create: `app/services/emails/streams/resolve.rb`
- Create: `app/services/emails/streams/default_for_kind.rb`
- Test: `spec/services/emails/streams/resolve_spec.rb`
- Test: `spec/services/emails/streams/default_for_kind_spec.rb`

**Interfaces:**
- Produces: `Emails::Streams::Resolve.call(customer:, kind:, stream_key: nil)` → `Emails::Stream`
- Produces: `Emails::Streams::DefaultForKind.call(customer:, kind:)` → `Emails::Stream`

- [ ] **Step 1: Write failing specs**

```ruby
# spec/services/emails/streams/resolve_spec.rb
require "rails_helper"

RSpec.describe Emails::Streams::Resolve do
  let(:customer) { create(:customer) }

  it "returns the requested stream by key" do
    stream = create(:email_stream, customer: customer, key: "newsletter", kind: "marketing")
    expect(described_class.call(customer: customer, kind: "marketing", stream_key: "newsletter")).to eq(stream)
  end

  it "falls back to default stream for kind" do
    default = create(:email_stream, customer: customer, kind: "transactional", default_for_kind: true)
    expect(described_class.call(customer: customer, kind: "transactional")).to eq(default)
  end

  it "raises when no active stream is found" do
    expect {
      described_class.call(customer: customer, kind: "transactional")
    }.to raise_error(Email::Errors::CredentialsMissing)
  end
end
```

- [ ] **Step 2: Run specs and confirm failure**

Run: `bundle exec rspec spec/services/emails/streams/resolve_spec.rb`
Expected: FAIL.

- [ ] **Step 3: Implement services**

```ruby
# app/services/emails/streams/resolve.rb
module Emails
  module Streams
    class Resolve
      def self.call(customer:, kind:, stream_key: nil)
        stream = nil
        if stream_key.present?
          stream = Emails::Stream.active.find_by(customer: customer, key: stream_key, kind: kind)
        end
        stream ||= DefaultForKind.call(customer: customer, kind: kind)
        stream || raise(Email::Errors::CredentialsMissing, "no active #{kind} stream for customer=#{customer.id}")
      end
    end
  end
end
```

```ruby
# app/services/emails/streams/default_for_kind.rb
module Emails
  module Streams
    class DefaultForKind
      def self.call(customer:, kind:)
        Emails::Stream.active.where(customer: customer, kind: kind, default_for_kind: true).order(:id).first ||
          Emails::Stream.active.where(customer: customer, kind: kind).order(:id).first
      end
    end
  end
end
```

- [ ] **Step 4: Run specs and confirm pass**

Run: `bundle exec rspec spec/services/emails/streams/resolve_spec.rb spec/services/emails/streams/default_for_kind_spec.rb`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git commit -m "feat(email): add stream resolution services"
```

---

## Task 4: Seed default streams per tenant and backfill messages

**Files:**
- Create: `db/migrate/20260720000002_seed_default_email_streams.rb`
- Create: `db/migrate/20260720000003_backfill_email_message_streams.rb`

**Interfaces:**
- Produces: Every existing customer has three default streams; existing messages get `email_stream_id`.

- [ ] **Step 1: Write seed migration**

```ruby
# db/migrate/20260720000002_seed_default_email_streams.rb
class SeedDefaultEmailStreams < ActiveRecord::Migration[8.1]
  def up
    Customer.find_each do |customer|
      next if Emails::Stream.exists?(customer: customer)

      Emails::Stream.create!(
        customer: customer,
        key: "transactional",
        name: I18n.t("feature_modules.email.streams.transactional_default_name"),
        kind: "transactional",
        status: "active",
        mode: Email::CredentialResolver.default_mode,
        default_for_kind: true,
        tracking_enabled: true
      )
      Emails::Stream.create!(
        customer: customer,
        key: "marketing",
        name: I18n.t("feature_modules.email.streams.marketing_default_name"),
        kind: "marketing",
        status: "active",
        mode: Email::CredentialResolver.default_mode,
        default_for_kind: true,
        tracking_enabled: true
      )
      Emails::Stream.create!(
        customer: customer,
        key: "automated",
        name: I18n.t("feature_modules.email.streams.automated_default_name"),
        kind: "automated",
        status: "active",
        mode: Email::CredentialResolver.default_mode,
        default_for_kind: true,
        tracking_enabled: true
      )
    end
  end

  def down
    Emails::Stream.where(key: %w[transactional marketing automated]).destroy_all
  end
end
```

Note: Add fallback English literals if I18n unavailable in migration context, e.g. `"Transactional"`.

- [ ] **Step 2: Write backfill migration**

```ruby
# db/migrate/20260720000003_backfill_email_message_streams.rb
class BackfillEmailMessageStreams < ActiveRecord::Migration[8.1]
  def up
    Emails::Stream.find_each do |stream|
      kind_map = {
        "transactional" => "transactional",
        "marketing" => "campaign",
        "automated" => "transactional"
      }
      Emails::Message
        .where(customer_id: stream.customer_id, message_type: kind_map.fetch(stream.kind, "transactional"))
        .where(email_stream_id: nil)
        .update_all(email_stream_id: stream.id)
    end
  end

  def down
    Emails::Message.update_all(email_stream_id: nil)
  end
end
```

- [ ] **Step 3: Run migrations**

Run: `bin/rails db:migrate`
Expected: All migrations pass; verify in console that streams exist and messages have stream_id.

- [ ] **Step 4: Commit**

```bash
git commit -m "feat(email): seed default streams and backfill message streams"
```

---

## Task 5: Update `Emails::Activities::Send` to use streams

**Files:**
- Modify: `app/services/emails/activities/send.rb`
- Test: `spec/services/emails/activities/send_spec.rb`

**Interfaces:**
- Consumes: `Emails::Streams::Resolve`
- Produces: `Emails::Activities::Send.call(..., stream_key: nil)` persists `email_stream_id`.

- [ ] **Step 1: Add a failing spec**

```ruby
# spec/services/emails/activities/send_spec.rb
it "records the default transactional stream" do
  customer = create(:customer)
  stream = create(:email_stream, customer: customer, kind: "transactional", default_for_kind: true)
  template = create(:email_template, customer: customer, status: "active")

  result = described_class.call(customer: customer, to: "user@example.com", template_key: template.key, vars: { "first_name" => "A" })

  expect(result.email_stream_id).to eq(stream.id)
end
```

- [ ] **Step 2: Update the activity**

```ruby
# app/services/emails/activities/send.rb
class Send
  def self.call(customer:, to:, template_key:, vars:, cc: nil, bcc: nil, reply_to: nil,
                idempotency_key: nil, mode: nil, provider: nil, scheduled_at: nil, stream_key: nil)
    # ... existing validation/render code ...
    credential = Email::CredentialResolver.call(mode: mode || Email::CredentialResolver.default_mode, provider: provider)
    stream = Emails::Streams::Resolve.call(customer: customer, kind: "transactional", stream_key: stream_key)

    attrs = {
      customer: customer,
      email_template: template,
      email_stream: stream,
      to: to,
      # ... rest unchanged ...
    }
    # ... rest unchanged ...
  end
end
```

- [ ] **Step 3: Run specs**

Run: `bundle exec rspec spec/services/emails/activities/send_spec.rb`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git commit -m "feat(email): route transactional sends through streams"
```

---

## Task 6: Update campaign send to use streams

**Files:**
- Modify: `app/services/emails/gateway.rb`
- Modify: `app/jobs/email_campaigns/send_campaign_job.rb` (before rename)
- Test: `spec/jobs/email_campaigns/send_campaign_job_spec.rb`

**Interfaces:**
- Consumes: `Emails::Streams::Resolve`
- Produces: Campaign messages record `email_stream_id` based on campaign stream (or default marketing stream).

- [ ] **Step 1: Update `Gateway.queue_for_campaign` to accept stream**

```ruby
# app/services/emails/gateway.rb
def queue_for_campaign(campaign:, user:, attachment_blob_ids: nil, idempotency_key: nil, credential: nil, stream: nil)
  # ...
  stream ||= Emails::Streams::Resolve.call(customer: campaign.customer, kind: "marketing")
  # ...
  message, created = Emails::PersistMessage.call({
    # ...
    email_stream: stream,
    message_type: "campaign",
    # ...
  }, idempotency_key: idempotency_key)
  # ...
end
```

- [ ] **Step 2: Update `SendCampaignJob` to resolve stream once per batch**

```ruby
# app/jobs/email_campaigns/send_campaign_job.rb
# inside perform
credential = Email::CredentialResolver.call(mode: Email::CredentialResolver.default_mode)
stream = Emails::Streams::Resolve.call(customer: campaign.customer, kind: "marketing")
throttle_limit = stream.throttle_per_minute
```

- [ ] **Step 3: Run campaign job specs**

Run: `bundle exec rspec spec/jobs/email_campaigns/send_campaign_job_spec.rb`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git commit -m "feat(email): route campaign sends through streams"
```

---

## Task 7: Rename `EmailCampaigns` namespace to `Emails::Campaigns` and `Emails::Audience`

**Files:**
- Create: `app/models/emails/campaigns/campaign.rb` (copy of `EmailCampaigns::Campaign` with new class name and `self.table_name`)
- Create: `app/models/emails/audience/list.rb` (copy of `EmailCampaigns::List` with new class name and `self.table_name`)
- Create: all renamed service/job/controller files (see File Structure)
- Delete: old `EmailCampaigns::*` files after all references updated
- Modify: all call sites
- Test: all existing specs must pass with new class names

**Interfaces:**
- Produces: `Emails::Campaigns::Campaign`, `Emails::Audience::List`, `Emails::Audience::SegmentQuery`, `Emails::Campaigns::SendCampaignJob`, etc.

- [ ] **Step 1: Copy models with `self.table_name`**

```ruby
# app/models/emails/campaigns/campaign.rb
module Emails
  module Campaigns
    class Campaign < ApplicationRecord
      self.table_name = "email_campaigns"
      # ... existing body from EmailCampaigns::Campaign ...
    end
  end
end
```

```ruby
# app/models/emails/audience/list.rb
module Emails
  module Audience
    class List < ApplicationRecord
      self.table_name = "email_lists"
      # ... existing body from EmailCampaigns::List ...
    end
  end
end
```

- [ ] **Step 2: Rename services and jobs**

For each file in `app/services/email_campaigns/*`:
- Copy to `app/services/emails/campaigns/*` or `app/services/emails/audience/*`.
- Replace module namespace `EmailCampaigns` with `Emails::Campaigns` / `Emails::Audience`.
- Update internal class references (`EmailCampaigns::Campaign` → `Emails::Campaigns::Campaign`).

For jobs:
- Copy `app/jobs/email_campaigns/*` → `app/jobs/emails/campaigns/*`.
- Update class names.

- [ ] **Step 3: Add shims/aliases for backward compatibility**

```ruby
# app/services/email_campaigns.rb (temporary)
module EmailCampaigns
  Campaign = Emails::Campaigns::Campaign
  List = Emails::Audience::List
  # etc.
end
```

- [ ] **Step 4: Update controllers and views**

In `Admin::Modules::Emails::*` controllers, replace `EmailCampaigns::Campaign` with `Emails::Campaigns::Campaign`, `EmailCampaigns::List` with `Emails::Audience::List`.

- [ ] **Step 5: Run the email spec suite**

Run: `bundle exec rspec spec/models/email_campaigns spec/jobs/email_campaigns spec/services/email_campaigns spec/requests/admin/modules/emails`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git commit -m "refactor(email): move EmailCampaigns namespace into Emails::Campaigns and Emails::Audience"
```

---

## Task 8: Restructure the Email sidebar

**Files:**
- Modify: `app/services/feature_modules/email/registration.rb`
- Modify: `config/locales/feature_modules.en.yml`
- Modify: `config/locales/feature_modules.zh-CN.yml`
- Test: `spec/services/feature_modules/email/registration_spec.rb`

**Interfaces:**
- Produces: Grouped sidebar contributions with new entry keys and paths.

- [ ] **Step 1: Add i18n keys**

```yaml
# config/locales/feature_modules.en.yml
en:
  feature_modules:
    email:
      groups:
        overview: "Overview"
        send: "Send"
        audience: "Audience"
        content: "Content"
        analytics: "Analytics"
        settings: "Settings"
      entries:
        dashboard: "Dashboard"
        templates: "Templates"
        messages: "Messages"
        suppressions: "Suppressions"
        campaigns: "Campaigns"
        lists: "Lists"
        block_list: "Block-List"
        automations: "Automations"
        contacts: "All Contacts"
        segments: "Segments"
        tags: "Tags"
        signup_forms: "Signup Forms"
        assets: "Asset Library"
        reports: "Reports"
        deliverability: "Deliverability"
        engagement: "Engagement"
        streams: "Message Streams"
        preference_topics: "Preference Topics"
      settings:
        daily_cap: "Campaign daily cap"
```

```yaml
# config/locales/feature_modules.zh-CN.yml (add equivalents)
zh-CN:
  feature_modules:
    email:
      groups:
        overview: "概览"
        send: "发送"
        audience: "受众"
        content: "内容"
        analytics: "分析"
        settings: "设置"
      entries:
        # ... mirror all keys with professional zh-CN translations ...
```

- [ ] **Step 2: Update registration sidebar method**

```ruby
# app/services/feature_modules/email/registration.rb
def self.sidebar_contributions(context)
  customer = context&.current_customer
  entries = [
    group_contribution("overview", [
      entry("dashboard", "/#{customer.id}/admin/modules/emails/dashboard")
    ]),
    group_contribution("send", send_entries(customer)),
    group_contribution("audience", audience_entries(customer)),
    group_contribution("content", [
      entry("templates", "/#{customer.id}/admin/modules/emails/templates"),
      entry("assets", "/#{customer.id}/admin/modules/emails/assets")
    ]),
    group_contribution("analytics", [
      entry("reports", "/#{customer.id}/admin/modules/emails/reports"),
      entry("deliverability", "/#{customer.id}/admin/modules/emails/deliverability"),
      entry("engagement", "/#{customer.id}/admin/modules/emails/engagement")
    ]),
    group_contribution("settings", [
      entry("streams", "/#{customer.id}/admin/modules/emails/streams"),
      entry("suppressions", "/#{customer.id}/admin/modules/emails/suppressions"),
      entry("preference_topics", "/#{customer.id}/admin/modules/emails/preference_topics")
    ])
  ]

  {
    entries: entries,
    settings: [ModuleContribution.new(label: I18n.t("feature_modules.email.settings.daily_cap"), entry_key: "daily_cap")]
  }
end

# helper methods
def self.group_contribution(group_key, children)
  ModuleContribution.new(
    label: I18n.t("feature_modules.email.groups.#{group_key}"),
    entry_key: group_key,
    children: children
  )
end

def self.entry(key, path)
  ModuleContribution.new(label: I18n.t("feature_modules.email.entries.#{key}"), entry_key: key, path: ->(_cid) { path })
end

def self.send_entries(customer)
  base = [
    entry("messages", "/#{customer.id}/admin/modules/emails/messages"),
    entry("automations", "/#{customer.id}/admin/modules/emails/automations")
  ]
  if campaigns_enabled?(customer)
    base.unshift(entry("campaigns", "/#{customer.id}/admin/modules/emails/campaigns"))
  end
  base
end

def self.audience_entries(customer)
  base = [
    entry("contacts", "/#{customer.id}/admin/modules/emails/contacts"),
    entry("segments", "/#{customer.id}/admin/modules/emails/segments"),
    entry("tags", "/#{customer.id}/admin/modules/emails/tags"),
    entry("signup_forms", "/#{customer.id}/admin/modules/emails/signup_forms")
  ]
  if campaigns_enabled?(customer)
    base.concat([
      entry("lists", "/#{customer.id}/admin/modules/emails/lists"),
      entry("block_list", "/#{customer.id}/admin/modules/emails/block_list")
    ])
  end
  base
end
```

Note: `ModuleContribution` may not support a `children:` key directly; use the existing API (check `app/services/feature_modules/module_contribution.rb`).

- [ ] **Step 3: Add sidebar spec**

```ruby
# spec/services/feature_modules/email/registration_spec.rb
it "groups entries into Overview/Send/Audience/Content/Analytics/Settings" do
  customer = create(:customer)
  contributions = described_class.sidebar_contributions(double(current_customer: customer))
  group_keys = contributions[:entries].map(&:entry_key)
  expect(group_keys).to eq(%w[overview send audience content analytics settings])
end
```

- [ ] **Step 4: Run registration spec**

Run: `bundle exec rspec spec/services/feature_modules/email/registration_spec.rb`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git commit -m "feat(email): restructure sidebar into industry-standard ESP groups"
```

---

## Task 9: Add placeholder routes and controllers for new entries

**Files:**
- Modify: `config/routes.rb`
- Create: placeholder controllers for new entries (empty `index` actions)

**Interfaces:**
- Produces: Routes resolve for all new sidebar paths so the sidebar links do not 404.

- [ ] **Step 1: Add routes**

```ruby
# config/routes.rb inside namespace :emails
namespace :emails do
  get "dashboard", to: "dashboard#show"
  resources :automations, only: %i[index]
  resources :contacts, only: %i[index]
  resources :segments, only: %i[index]
  resources :tags, only: %i[index]
  resources :signup_forms, only: %i[index]
  resources :assets, only: %i[index]
  resources :reports, only: %i[index]
  resources :deliverability, only: %i[index]
  resources :engagement, only: %i[index]
  resources :streams, only: %i[index]
  resources :preference_topics, only: %i[index]
  # ... existing routes ...
end
```

- [ ] **Step 2: Create placeholder controllers**

For each new resource, create `app/controllers/admin/modules/emails/<resource>_controller.rb` with an empty `index` action and a minimal view rendering "Coming in Phase N".

Example:

```ruby
# app/controllers/admin/modules/emails/automations_controller.rb
module Admin
  module Modules
    module Emails
      class AutomationsController < ApplicationController
        dashboard_menu_item :modules
        def index; end
      end
    end
  end
end
```

- [ ] **Step 3: Run routing specs**

Run: `bundle exec rspec spec/routing/admin/modules/emails` or a quick smoke test.
Expected: New routes resolve.

- [ ] **Step 4: Commit**

```bash
git commit -m "feat(email): add placeholder routes and controllers for new menu entries"
```

---

## Task 10: Phase 1 integration and full email spec run

**Files:**
- All files touched above.

- [ ] **Step 1: Run full email spec suite**

Run: `bundle exec rspec spec/models/emails spec/services/emails spec/jobs/emails spec/requests/admin/modules/emails spec/services/feature_modules/email`
Expected: PASS.

- [ ] **Step 2: Run rubocop/static analysis if configured**

Run: `bundle exec rubocop app/models/emails app/services/emails app/jobs/emails app/controllers/admin/modules/emails --format simple`
Expected: No new offenses.

- [ ] **Step 3: Stage changes**

```bash
git add -A
```

Phase 1 is complete. Do not commit yet if the human reviewer wants to review first; otherwise commit with:

```bash
git commit -m "feat(email): Phase 1 foundation — streams, menu restructure, namespace cleanup"
```

---

## Self-Review

- Spec coverage: streams table/model, stream resolution, message stream_id, send activity, campaign job, namespace rename, sidebar restructure, placeholder routes — all covered.
- Placeholder scan: no TBD/TODO; placeholder controllers are explicit "Coming in Phase N" views (acceptable as temporary UI).
- Type consistency: `Emails::Stream` used consistently; `Emails::Streams::Resolve` signature stable across consumers.
