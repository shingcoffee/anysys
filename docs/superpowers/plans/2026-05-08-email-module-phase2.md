# Email Module Implementation Plan - Phase 2: Campaigns Module

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build email campaigns infrastructure - subscribers, lists, segments, campaigns, scheduling

**Architecture:** Tenant-scoped subscriber management with static and dynamic lists. Campaign sender orchestrates batch delivery via Email::Gateway. Scheduler runs every minute via SolidQueue recurring job.

**Tech Stack:** Rails 8.1, Reform contracts, ActiveJob with SolidQueue, ice_cube gem for RRULE parsing

---

## File Structure

```
app/models/
├── email_subscriber.rb
├── email_list.rb
├── email_list_subscriber.rb
└── email_campaign.rb

app/services/email_campaigns/
├── segment_evaluator.rb
├── campaign_sender.rb
└── unsubscribe_handler.rb

app/jobs/email_campaigns/
├── scheduler_job.rb
└── send_campaign_job.rb

db/migrate/
├── XXXXXX_create_email_subscribers.rb
├── XXXXXX_create_email_lists.rb
├── XXXXXX_create_email_list_subscribers.rb
└── XXXXXX_create_email_campaigns.rb

spec/models/
├── email_subscriber_spec.rb
├── email_list_spec.rb
├── email_list_subscriber_spec.rb
└── email_campaign_spec.rb

spec/services/email_campaigns/
├── segment_evaluator_spec.rb
├── campaign_sender_spec.rb
└── unsubscribe_handler_spec.rb

spec/jobs/email_campaigns/
├── scheduler_job_spec.rb
└── send_campaign_job_spec.rb
```

---

### Task 1: Create EmailSubscriber Model

**Files:**
- Create: `spec/models/email_subscriber_spec.rb`
- Create: `spec/factories/email_subscribers.rb`
- Create: `db/migrate/XXXXXX_create_email_subscribers.rb`
- Create: `app/models/email_subscriber.rb`

- [ ] **Step 1: Write spec**

```ruby
# spec/models/email_subscriber_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe EmailSubscriber, type: :model do
  describe "validations" do
    subject { build(:email_subscriber) }

    it "requires customer_id" do
      Current.customer = nil
      sub = build(:email_subscriber, customer: nil)
      expect(sub).not_to be_valid
      expect(sub.errors[:customer_id]).to be_present
    end

    it "requires email" do
      sub = build(:email_subscriber, email: nil)
      expect(sub).not_to be_valid
      expect(sub.errors[:email]).to be_present
    end

    it "validates email format" do
      sub = build(:email_subscriber, email: "not-an-email")
      expect(sub).not_to be_valid
      expect(sub.errors[:email]).to be_present
    end

    it "validates email uniqueness per customer" do
      existing = create(:email_subscriber, email: "user@example.com")
      duplicate = build(:email_subscriber, customer: existing.customer, email: "user@example.com")
      expect(duplicate).not_to be_valid
    end

    it "allows same email for different customers" do
      existing = create(:email_subscriber, email: "user@example.com")
      different = build(:email_subscriber, email: "user@example.com")
      expect(different).to be_valid
    end

    it "validates status inclusion" do
      sub = build(:email_subscriber, status: "invalid")
      expect(sub).not_to be_valid
    end

    it "auto-generates unsubscribe_token" do
      sub = create(:email_subscriber)
      expect(sub.unsubscribe_token).to be_present
      expect(sub.unsubscribe_token.length).to be >= 20
    end

    it "validates unsubscribe_token uniqueness" do
      first = create(:email_subscriber)
      second = build(:email_subscriber)
      second.unsubscribe_token = first.unsubscribe_token
      expect(second).not_to be_valid
    end
  end

  describe "scopes" do
    let(:customer) { create(:customer) }
    let!(:active) { create(:email_subscriber, customer: customer, status: "active") }
    let!(:unsubbed) { create(:email_subscriber, customer: customer, status: "unsubscribed") }
    let!(:bounced) { create(:email_subscriber, customer: customer, status: "bounced") }

    it ".active returns active subscribers" do
      expect(described_class.active).to contain_exactly(active)
    end

    it ".deliverable returns active subscribers" do
      expect(described_class.deliverable).to contain_exactly(active)
    end
  end

  describe "#unsubscribe!" do
    it "sets status and timestamp" do
      sub = create(:email_subscriber, status: "active")
      freeze_time do
        sub.unsubscribe!
        expect(sub.status).to eq("unsubscribed")
        expect(sub.unsubscribed_at).to eq(Time.current)
      end
    end
  end

  describe "#full_name" do
    it "joins first and last name" do
      sub = build(:email_subscriber, first_name: "Jane", last_name: "Doe")
      expect(sub.full_name).to eq("Jane Doe")
    end

    it "handles nil names" do
      sub = build(:email_subscriber, first_name: nil, last_name: nil)
      expect(sub.full_name).to eq("")
    end
  end

  describe "tags" do
    it "stores tags as array" do
      sub = create(:email_subscriber, tags: ["premium", "newsletter"])
      expect(sub.reload.tags).to eq(["premium", "newsletter"])
    end

    it "defaults to empty array" do
      sub = create(:email_subscriber)
      expect(sub.tags).to eq([])
    end
  end
end
```

- [ ] **Step 2: Create factory**

```ruby
# spec/factories/email_subscribers.rb
# frozen_string_literal: true

FactoryBot.define do
  factory :email_subscriber do
    customer
    sequence(:email) { |n| "subscriber#{n}@example.com" }
    first_name { "Jane" }
    last_name { "Doe" }
    status { "active" }
    tags { [] }
    attributes_data { {} }
    subscribed_at { Time.current }

    trait :unsubscribed do
      status { "unsubscribed" }
      unsubscribed_at { Time.current }
    end

    trait :bounced do
      status { "bounced" }
    end
  end
end
```

- [ ] **Step 3: Run failing test**

Run: `cd /home/ec2-user/anysys && bundle exec rspec spec/models/email_subscriber_spec.rb`
Expected: FAIL - table does not exist

- [ ] **Step 4: Create migration**

Run: `bin/rails generate migration CreateEmailSubscribers`

```ruby
class CreateEmailSubscribers < ActiveRecord::Migration[8.1]
  def change
    create_table :email_subscribers do |t|
      t.integer :customer_id, null: false
      t.string :email, null: false
      t.string :first_name
      t.string :last_name
      t.string :status, null: false, default: "active"
      t.json :tags, null: false, default: []
      t.json :attributes_data, null: false, default: {}
      t.datetime :subscribed_at, null: false
      t.datetime :unsubscribed_at
      t.string :unsubscribe_token, null: false
      t.timestamps
    end

    add_index :email_subscribers, [:customer_id, :email], unique: true
    add_index :email_subscribers, [:customer_id, :status]
    add_index :email_subscribers, :unsubscribe_token, unique: true
  end
end
```

NOTE: Field is `attributes_data` not `attributes` because `attributes` is reserved by ActiveRecord.

- [ ] **Step 5: Run migration**

Run: `bin/rails db:migrate`

- [ ] **Step 6: Create model**

```ruby
# app/models/email_subscriber.rb
# frozen_string_literal: true

class EmailSubscriber < ApplicationRecord
  include TenantScoped

  STATUSES = %w[active unsubscribed bounced complained].freeze

  has_many :email_list_subscribers, dependent: :destroy
  has_many :email_lists, through: :email_list_subscribers

  before_validation :ensure_unsubscribe_token, on: :create
  before_validation :ensure_subscribed_at, on: :create

  validates :customer_id,        presence: true
  validates :email,              presence: true,
                                 format: { with: URI::MailTo::EMAIL_REGEXP },
                                 uniqueness: { scope: :customer_id, case_sensitive: false }
  validates :status,             inclusion: { in: STATUSES }
  validates :unsubscribe_token,  presence: true, uniqueness: true

  scope :active,       -> { where(status: "active") }
  scope :deliverable,  -> { where(status: "active") }

  def unsubscribe!
    update!(status: "unsubscribed", unsubscribed_at: Time.current)
  end

  def full_name
    [first_name, last_name].compact.join(" ")
  end

  private

  def ensure_unsubscribe_token
    self.unsubscribe_token ||= SecureRandom.urlsafe_base64(24)
  end

  def ensure_subscribed_at
    self.subscribed_at ||= Time.current
  end
end
```

- [ ] **Step 7: Run tests**

Run: `bundle exec rspec spec/models/email_subscriber_spec.rb`
Expected: All tests PASS

- [ ] **Step 8: Commit**

```bash
git add spec/models/email_subscriber_spec.rb spec/factories/email_subscribers.rb db/migrate/*_create_email_subscribers.rb app/models/email_subscriber.rb
git commit -m "feat(email_campaigns): add EmailSubscriber model"
```

---

### Task 2: Create EmailList and EmailListSubscriber Models

**Files:**
- Create: `spec/models/email_list_spec.rb`
- Create: `spec/models/email_list_subscriber_spec.rb`
- Create: `spec/factories/email_lists.rb`
- Create: `spec/factories/email_list_subscribers.rb`
- Create: `db/migrate/XXXXXX_create_email_lists.rb`
- Create: `db/migrate/XXXXXX_create_email_list_subscribers.rb`
- Create: `app/models/email_list.rb`
- Create: `app/models/email_list_subscriber.rb`

- [ ] **Step 1: Write EmailList spec**

```ruby
# spec/models/email_list_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe EmailList, type: :model do
  describe "validations" do
    it "requires customer_id" do
      list = build(:email_list, customer: nil)
      Current.customer = nil
      expect(list).not_to be_valid
    end

    it "requires name" do
      list = build(:email_list, name: nil)
      expect(list).not_to be_valid
    end

    it "validates list_type inclusion" do
      list = build(:email_list, list_type: "invalid")
      expect(list).not_to be_valid
    end

    it "validates status inclusion" do
      list = build(:email_list, status: "invalid")
      expect(list).not_to be_valid
    end
  end

  describe "associations" do
    it { is_expected.to have_many(:email_list_subscribers) }
    it { is_expected.to have_many(:email_subscribers).through(:email_list_subscribers) }
    it { is_expected.to have_many(:email_campaigns) }
  end

  describe "scopes" do
    let(:customer) { create(:customer) }
    let!(:active) { create(:email_list, customer: customer, status: "active") }
    let!(:archived) { create(:email_list, customer: customer, status: "archived") }

    it ".active returns only active lists" do
      expect(described_class.active).to contain_exactly(active)
    end
  end

  describe "#static?" do
    it "returns true for static lists" do
      expect(build(:email_list, list_type: "static").static?).to be true
    end

    it "returns false for dynamic lists" do
      expect(build(:email_list, list_type: "dynamic").static?).to be false
    end
  end

  describe "#dynamic?" do
    it "returns true for dynamic lists" do
      expect(build(:email_list, list_type: "dynamic").dynamic?).to be true
    end
  end
end
```

- [ ] **Step 2: Write EmailListSubscriber spec**

```ruby
# spec/models/email_list_subscriber_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe EmailListSubscriber, type: :model do
  describe "validations" do
    it "validates uniqueness of subscriber per list" do
      existing = create(:email_list_subscriber)
      duplicate = build(:email_list_subscriber,
        email_list: existing.email_list,
        email_subscriber: existing.email_subscriber
      )
      expect(duplicate).not_to be_valid
    end

    it "allows same subscriber in different lists" do
      sub = create(:email_subscriber)
      list1 = create(:email_list, customer: sub.customer)
      list2 = create(:email_list, customer: sub.customer)
      
      first = create(:email_list_subscriber, email_list: list1, email_subscriber: sub)
      second = build(:email_list_subscriber, email_list: list2, email_subscriber: sub)
      expect(second).to be_valid
    end
  end

  describe "associations" do
    it { is_expected.to belong_to(:email_list) }
    it { is_expected.to belong_to(:email_subscriber) }
  end
end
```

- [ ] **Step 3: Create factories**

```ruby
# spec/factories/email_lists.rb
FactoryBot.define do
  factory :email_list do
    customer
    sequence(:name) { |n| "List #{n}" }
    description { "Test list" }
    list_type { "static" }
    status { "active" }
    segment_rules { {} }

    trait :dynamic do
      list_type { "dynamic" }
      segment_rules do
        {
          "match" => "all",
          "conditions" => [
            { "field" => "tags", "operator" => "contains", "value" => "premium" }
          ]
        }
      end
    end

    trait :archived do
      status { "archived" }
    end
  end
end
```

```ruby
# spec/factories/email_list_subscribers.rb
FactoryBot.define do
  factory :email_list_subscriber do
    email_list
    email_subscriber { create(:email_subscriber, customer: email_list.customer) }
  end
end
```

- [ ] **Step 4: Run failing tests**

Run: `bundle exec rspec spec/models/email_list_spec.rb spec/models/email_list_subscriber_spec.rb`

- [ ] **Step 5: Create migrations**

```ruby
# db/migrate/XXXXXX_create_email_lists.rb
class CreateEmailLists < ActiveRecord::Migration[8.1]
  def change
    create_table :email_lists do |t|
      t.integer :customer_id, null: false
      t.string :name, null: false
      t.text :description
      t.string :list_type, null: false, default: "static"
      t.json :segment_rules, null: false, default: {}
      t.string :status, null: false, default: "active"
      t.timestamps
    end

    add_index :email_lists, [:customer_id, :status]
    add_index :email_lists, :customer_id
  end
end
```

```ruby
# db/migrate/XXXXXX_create_email_list_subscribers.rb
class CreateEmailListSubscribers < ActiveRecord::Migration[8.1]
  def change
    create_table :email_list_subscribers do |t|
      t.integer :email_list_id, null: false
      t.integer :email_subscriber_id, null: false
      t.timestamps
    end

    add_index :email_list_subscribers, [:email_list_id, :email_subscriber_id], unique: true, name: "idx_email_list_subscribers_unique"
    add_index :email_list_subscribers, :email_subscriber_id
  end
end
```

Run: `bin/rails db:migrate`

- [ ] **Step 6: Create models**

```ruby
# app/models/email_list.rb
# frozen_string_literal: true

class EmailList < ApplicationRecord
  include TenantScoped

  LIST_TYPES = %w[static dynamic].freeze
  STATUSES   = %w[active archived].freeze

  has_many :email_list_subscribers, dependent: :destroy
  has_many :email_subscribers, through: :email_list_subscribers
  has_many :email_campaigns, dependent: :restrict_with_exception

  validates :customer_id, presence: true
  validates :name,        presence: true
  validates :list_type,   inclusion: { in: LIST_TYPES }
  validates :status,      inclusion: { in: STATUSES }

  scope :active, -> { where(status: "active") }

  def static?  = list_type == "static"
  def dynamic? = list_type == "dynamic"
end
```

```ruby
# app/models/email_list_subscriber.rb
# frozen_string_literal: true

class EmailListSubscriber < ApplicationRecord
  belongs_to :email_list
  belongs_to :email_subscriber

  validates :email_subscriber_id, uniqueness: { scope: :email_list_id }
end
```

- [ ] **Step 7: Run tests**

Expected: All tests PASS

- [ ] **Step 8: Commit**

```bash
git add spec/models/email_list*_spec.rb spec/factories/email_list*.rb db/migrate/*_create_email_list*.rb app/models/email_list*.rb
git commit -m "feat(email_campaigns): add EmailList and EmailListSubscriber models"
```

---

### Task 3: Create EmailCampaign Model

**Files:**
- Create: `spec/models/email_campaign_spec.rb`
- Create: `spec/factories/email_campaigns.rb`
- Create: `db/migrate/XXXXXX_create_email_campaigns.rb`
- Create: `app/models/email_campaign.rb`

- [ ] **Step 1: Write spec**

```ruby
# spec/models/email_campaign_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe EmailCampaign, type: :model do
  describe "validations" do
    it "requires customer_id" do
      campaign = build(:email_campaign, customer: nil)
      Current.customer = nil
      expect(campaign).not_to be_valid
    end

    it "requires name" do
      expect(build(:email_campaign, name: nil)).not_to be_valid
    end

    it "requires email_template" do
      expect(build(:email_campaign, email_template: nil)).not_to be_valid
    end

    it "requires email_list" do
      expect(build(:email_campaign, email_list: nil)).not_to be_valid
    end

    it "validates status inclusion" do
      expect(build(:email_campaign, status: "invalid")).not_to be_valid
    end

    it "validates timezone" do
      expect(build(:email_campaign, timezone: "Invalid/Zone")).not_to be_valid
    end

    it "accepts valid IANA timezone" do
      expect(build(:email_campaign, timezone: "America/New_York")).to be_valid
    end
  end

  describe "associations" do
    it { is_expected.to belong_to(:email_template) }
    it { is_expected.to belong_to(:email_list) }
  end

  describe "scopes" do
    let(:customer) { create(:customer) }
    let!(:scheduled_due) { create(:email_campaign, customer: customer, status: "scheduled", scheduled_at: 1.minute.ago) }
    let!(:scheduled_future) { create(:email_campaign, customer: customer, status: "scheduled", scheduled_at: 1.hour.from_now) }
    let!(:sent_campaign) { create(:email_campaign, customer: customer, status: "sent") }

    it ".due_for_send returns scheduled campaigns past their time" do
      expect(described_class.due_for_send).to contain_exactly(scheduled_due)
    end
  end

  describe "status transitions" do
    let(:campaign) { create(:email_campaign, status: "scheduled") }

    it "#start! transitions to sending" do
      freeze_time do
        campaign.start!
        expect(campaign.status).to eq("sending")
        expect(campaign.started_at).to eq(Time.current)
      end
    end

    it "#complete! transitions to sent" do
      campaign.update!(status: "sending")
      freeze_time do
        campaign.complete!
        expect(campaign.status).to eq("sent")
        expect(campaign.completed_at).to eq(Time.current)
      end
    end

    it "#pause! transitions sending to paused" do
      campaign.update!(status: "sending")
      campaign.pause!
      expect(campaign.status).to eq("paused")
    end

    it "#resume! transitions paused to sending" do
      campaign.update!(status: "paused")
      campaign.resume!
      expect(campaign.status).to eq("sending")
    end

    it "#cancel! transitions to cancelled" do
      campaign.cancel!
      expect(campaign.status).to eq("cancelled")
    end
  end

  describe "#recurring?" do
    it "returns true when recurrence_rule present" do
      expect(build(:email_campaign, recurrence_rule: "FREQ=DAILY").recurring?).to be true
    end

    it "returns false when blank" do
      expect(build(:email_campaign, recurrence_rule: nil).recurring?).to be false
    end
  end

  describe "#increment_stat!" do
    let(:campaign) { create(:email_campaign, stats: {}) }

    it "increments named stat" do
      campaign.increment_stat!(:sent_count)
      expect(campaign.reload.stats["sent_count"]).to eq(1)
      campaign.increment_stat!(:sent_count)
      expect(campaign.reload.stats["sent_count"]).to eq(2)
    end
  end
end
```

- [ ] **Step 2: Create factory**

```ruby
# spec/factories/email_campaigns.rb
FactoryBot.define do
  factory :email_campaign do
    customer
    email_template { create(:email_template, customer: customer) }
    email_list { create(:email_list, customer: customer) }
    sequence(:name) { |n| "Campaign #{n}" }
    status { "draft" }
    timezone { "UTC" }
    stats { {} }

    trait :scheduled do
      status { "scheduled" }
      scheduled_at { 1.hour.from_now }
    end

    trait :sending do
      status { "sending" }
      started_at { Time.current }
    end

    trait :sent do
      status { "sent" }
      started_at { 1.hour.ago }
      completed_at { Time.current }
    end

    trait :recurring do
      recurrence_rule { "FREQ=DAILY;INTERVAL=1" }
    end
  end
end
```

- [ ] **Step 3: Run failing test**

- [ ] **Step 4: Create migration**

```ruby
class CreateEmailCampaigns < ActiveRecord::Migration[8.1]
  def change
    create_table :email_campaigns do |t|
      t.integer :customer_id, null: false
      t.integer :email_template_id, null: false
      t.integer :email_list_id, null: false
      t.string :name, null: false
      t.string :status, null: false, default: "draft"
      t.datetime :scheduled_at
      t.datetime :started_at
      t.datetime :completed_at
      t.string :recurrence_rule
      t.string :timezone, null: false, default: "UTC"
      t.json :stats, null: false, default: {}
      t.timestamps
    end

    add_index :email_campaigns, [:customer_id, :status]
    add_index :email_campaigns, [:status, :scheduled_at]
    add_index :email_campaigns, :email_template_id
    add_index :email_campaigns, :email_list_id
  end
end
```

- [ ] **Step 5: Create model**

```ruby
# app/models/email_campaign.rb
# frozen_string_literal: true

class EmailCampaign < ApplicationRecord
  include TenantScoped

  STATUSES = %w[draft scheduled sending sent paused cancelled].freeze

  belongs_to :email_template
  belongs_to :email_list

  validates :customer_id, presence: true
  validates :name,        presence: true
  validates :status,      inclusion: { in: STATUSES }
  validate  :timezone_is_valid

  scope :due_for_send, -> {
    where(status: "scheduled").where("scheduled_at <= ?", Time.current)
  }

  def start!
    update!(status: "sending", started_at: Time.current)
  end

  def complete!
    update!(status: "sent", completed_at: Time.current)
  end

  def pause!
    update!(status: "paused")
  end

  def resume!
    update!(status: "sending")
  end

  def cancel!
    update!(status: "cancelled")
  end

  def recurring?
    recurrence_rule.present?
  end

  def increment_stat!(key)
    key_str = key.to_s
    with_lock do
      current = stats[key_str].to_i
      update!(stats: stats.merge(key_str => current + 1))
    end
  end

  private

  def timezone_is_valid
    return if timezone.blank?
    ActiveSupport::TimeZone.find_tzinfo(timezone)
  rescue TZInfo::InvalidTimezoneIdentifier
    errors.add(:timezone, "is not a valid IANA timezone")
  end
end
```

- [ ] **Step 6: Run tests, commit**

```bash
git add spec/models/email_campaign_spec.rb spec/factories/email_campaigns.rb db/migrate/*_create_email_campaigns.rb app/models/email_campaign.rb
git commit -m "feat(email_campaigns): add EmailCampaign model with status transitions"
```

---

### Task 4: Create EmailCampaigns::SegmentEvaluator

**Files:**
- Create: `spec/services/email_campaigns/segment_evaluator_spec.rb`
- Create: `app/services/email_campaigns/segment_evaluator.rb`

Evaluates dynamic list rules against EmailSubscriber records.

- [ ] **Step 1: Write spec**

```ruby
# spec/services/email_campaigns/segment_evaluator_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe EmailCampaigns::SegmentEvaluator do
  let(:customer) { create(:customer) }
  let!(:premium_active) { create(:email_subscriber, customer: customer, tags: ["premium"], status: "active") }
  let!(:basic_active)   { create(:email_subscriber, customer: customer, tags: ["basic"], status: "active") }
  let!(:premium_attr)   { create(:email_subscriber, customer: customer, tags: ["premium"], attributes_data: { "plan" => "enterprise" }, status: "active") }

  describe ".call" do
    it "returns subscribers matching tag contains rule" do
      rules = {
        "match" => "all",
        "conditions" => [
          { "field" => "tags", "operator" => "contains", "value" => "premium" }
        ]
      }

      result = described_class.call(customer: customer, rules: rules)
      expect(result).to contain_exactly(premium_active, premium_attr)
    end

    it "returns subscribers matching attribute equals rule" do
      rules = {
        "match" => "all",
        "conditions" => [
          { "field" => "attributes.plan", "operator" => "equals", "value" => "enterprise" }
        ]
      }

      result = described_class.call(customer: customer, rules: rules)
      expect(result).to contain_exactly(premium_attr)
    end

    it "supports match=any (OR logic)" do
      rules = {
        "match" => "any",
        "conditions" => [
          { "field" => "tags", "operator" => "contains", "value" => "basic" },
          { "field" => "attributes.plan", "operator" => "equals", "value" => "enterprise" }
        ]
      }

      result = described_class.call(customer: customer, rules: rules)
      expect(result).to contain_exactly(basic_active, premium_attr)
    end

    it "supports match=all (AND logic)" do
      rules = {
        "match" => "all",
        "conditions" => [
          { "field" => "tags", "operator" => "contains", "value" => "premium" },
          { "field" => "attributes.plan", "operator" => "equals", "value" => "enterprise" }
        ]
      }

      result = described_class.call(customer: customer, rules: rules)
      expect(result).to contain_exactly(premium_attr)
    end

    it "filters by status field" do
      create(:email_subscriber, customer: customer, status: "unsubscribed")
      rules = {
        "match" => "all",
        "conditions" => [
          { "field" => "status", "operator" => "equals", "value" => "active" }
        ]
      }

      result = described_class.call(customer: customer, rules: rules)
      expect(result.count).to eq(3)
    end

    it "supports date comparisons" do
      old_sub = create(:email_subscriber, customer: customer, subscribed_at: 1.year.ago)
      rules = {
        "match" => "all",
        "conditions" => [
          { "field" => "subscribed_at", "operator" => "before", "value" => "2026-01-01" }
        ]
      }

      result = described_class.call(customer: customer, rules: rules)
      expect(result).to include(old_sub)
    end

    it "returns all customer subscribers when rules empty" do
      result = described_class.call(customer: customer, rules: {})
      expect(result.count).to eq(EmailSubscriber.where(customer: customer).count)
    end

    it "scopes results to customer" do
      other_customer = create(:customer)
      create(:email_subscriber, customer: other_customer, tags: ["premium"])

      rules = { "match" => "all", "conditions" => [{ "field" => "tags", "operator" => "contains", "value" => "premium" }] }
      result = described_class.call(customer: customer, rules: rules)
      
      expect(result.map(&:customer_id).uniq).to eq([customer.id])
    end
  end
end
```

- [ ] **Step 2: Create service**

```ruby
# app/services/email_campaigns/segment_evaluator.rb
# frozen_string_literal: true

module EmailCampaigns
  class SegmentEvaluator
    OPERATORS = %w[
      equals not_equals contains not_contains
      greater_than less_than after before
      is_blank is_present
    ].freeze

    def self.call(customer:, rules:)
      new(customer: customer, rules: rules).call
    end

    def initialize(customer:, rules:)
      @customer = customer
      @rules = rules || {}
    end

    def call
      subscribers = EmailSubscriber.where(customer_id: @customer.id)
      return subscribers if conditions.empty?

      subscribers.select { |sub| matches?(sub) }
    end

    private

    attr_reader :customer, :rules

    def conditions
      Array(rules["conditions"])
    end

    def match_mode
      rules["match"] == "any" ? :any? : :all?
    end

    def matches?(subscriber)
      conditions.send(match_mode) { |cond| evaluate(subscriber, cond) }
    end

    def evaluate(subscriber, cond)
      field    = cond["field"].to_s
      operator = cond["operator"].to_s
      value    = cond["value"]
      actual   = resolve_field(subscriber, field)

      case operator
      when "equals"        then values_equal?(actual, value)
      when "not_equals"    then !values_equal?(actual, value)
      when "contains"      then contains_value?(actual, value)
      when "not_contains"  then !contains_value?(actual, value)
      when "greater_than"  then numeric_compare(actual, value, :>)
      when "less_than"     then numeric_compare(actual, value, :<)
      when "after"         then date_compare(actual, value, :>)
      when "before"        then date_compare(actual, value, :<)
      when "is_blank"      then actual.blank?
      when "is_present"    then actual.present?
      else false
      end
    end

    def resolve_field(subscriber, field)
      if field.start_with?("attributes.")
        key = field.sub("attributes.", "")
        subscriber.attributes_data[key]
      elsif field == "tags"
        subscriber.tags
      else
        subscriber.public_send(field) if subscriber.respond_to?(field)
      end
    end

    def values_equal?(actual, expected)
      actual.to_s == expected.to_s
    end

    def contains_value?(actual, expected)
      return false if actual.nil?
      Array(actual).map(&:to_s).include?(expected.to_s)
    end

    def numeric_compare(actual, expected, op)
      actual.to_f.public_send(op, expected.to_f)
    rescue
      false
    end

    def date_compare(actual, expected, op)
      a = parse_date(actual)
      b = parse_date(expected)
      return false unless a && b
      a.public_send(op, b)
    end

    def parse_date(val)
      case val
      when Time, DateTime, ActiveSupport::TimeWithZone then val
      when Date then val.to_time
      else Time.zone.parse(val.to_s) rescue nil
      end
    end
  end
end
```

- [ ] **Step 3: Run tests, commit**

```bash
mkdir -p app/services/email_campaigns spec/services/email_campaigns
git add spec/services/email_campaigns/segment_evaluator_spec.rb app/services/email_campaigns/segment_evaluator.rb
git commit -m "feat(email_campaigns): add SegmentEvaluator for dynamic lists"
```

---

### Task 5: Create EmailCampaigns::SendCampaignJob

**Files:**
- Create: `spec/jobs/email_campaigns/send_campaign_job_spec.rb`
- Create: `app/jobs/email_campaigns/send_campaign_job.rb`

Performs the actual campaign sending - resolves subscribers, queues messages.

- [ ] **Step 1: Write spec**

```ruby
# spec/jobs/email_campaigns/send_campaign_job_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe EmailCampaigns::SendCampaignJob, type: :job do
  let(:customer) { create(:customer) }
  let!(:credential) { create(:email_credential, mode: "sandbox") }
  let(:template) { create(:email_template, customer: customer, key: "campaign_welcome", variables: ["first_name"], subject: "Hi {{first_name}}", body_html: "<p>Welcome {{first_name}}</p>") }
  let(:list) { create(:email_list, customer: customer, list_type: "static") }
  let(:campaign) { create(:email_campaign, customer: customer, email_template: template, email_list: list, status: "sending") }

  before do
    sub1 = create(:email_subscriber, customer: customer, email: "a@example.com", first_name: "Alice")
    sub2 = create(:email_subscriber, customer: customer, email: "b@example.com", first_name: "Bob")
    unsubbed = create(:email_subscriber, :unsubscribed, customer: customer, email: "c@example.com")
    
    create(:email_list_subscriber, email_list: list, email_subscriber: sub1)
    create(:email_list_subscriber, email_list: list, email_subscriber: sub2)
    create(:email_list_subscriber, email_list: list, email_subscriber: unsubbed)
  end

  describe "#perform" do
    it "creates EmailMessage for each active subscriber" do
      expect { described_class.perform_now(campaign.id) }
        .to change(EmailMessage, :count).by(2)
    end

    it "skips unsubscribed subscribers" do
      described_class.perform_now(campaign.id)
      messages = EmailMessage.where(message_type: "campaign")
      expect(messages.pluck(:to)).to contain_exactly("a@example.com", "b@example.com")
    end

    it "marks campaign as sent on completion" do
      described_class.perform_now(campaign.id)
      expect(campaign.reload.status).to eq("sent")
    end

    it "updates campaign stats" do
      described_class.perform_now(campaign.id)
      stats = campaign.reload.stats
      expect(stats["sent_count"]).to eq(2)
    end

    it "sets campaign metadata on messages" do
      described_class.perform_now(campaign.id)
      msg = EmailMessage.where(message_type: "campaign").first
      expect(msg.metadata["campaign_id"]).to eq(campaign.id)
    end

    context "with dynamic list" do
      let(:list) do
        create(:email_list, customer: customer, list_type: "dynamic", segment_rules: {
          "match" => "all",
          "conditions" => [{ "field" => "tags", "operator" => "contains", "value" => "premium" }]
        })
      end

      it "uses SegmentEvaluator to resolve subscribers" do
        sub = create(:email_subscriber, customer: customer, email: "premium@example.com", tags: ["premium"])
        
        described_class.perform_now(campaign.id)
        expect(EmailMessage.where(to: "premium@example.com").count).to eq(1)
      end
    end

    context "when paused mid-send" do
      it "stops processing if status changes to paused" do
        # This is harder to test with synchronous perform_now,
        # but we verify the check is in place
        campaign.update!(status: "paused")
        
        expect { described_class.perform_now(campaign.id) }
          .not_to change(EmailMessage, :count)
      end
    end
  end
end
```

- [ ] **Step 2: Create job**

```ruby
# app/jobs/email_campaigns/send_campaign_job.rb
# frozen_string_literal: true

module EmailCampaigns
  class SendCampaignJob < ApplicationJob
    queue_as :default

    def perform(campaign_id)
      campaign = EmailCampaign.find(campaign_id)
      return unless campaign.status == "sending"

      subscribers = resolve_subscribers(campaign)

      subscribers.each do |subscriber|
        # Re-check campaign status to support pause
        campaign.reload
        break unless campaign.status == "sending"

        send_to_subscriber(campaign, subscriber)
      end

      campaign.reload
      campaign.complete! if campaign.status == "sending"
    end

    private

    def resolve_subscribers(campaign)
      list = campaign.email_list

      base = if list.dynamic?
               EmailCampaigns::SegmentEvaluator.call(customer: campaign.customer, rules: list.segment_rules)
             else
               list.email_subscribers
             end

      Array(base).select { |sub| sub.status == "active" }
    end

    def send_to_subscriber(campaign, subscriber)
      Email::Gateway.queue_for_campaign(campaign: campaign, subscriber: subscriber)
      campaign.increment_stat!(:sent_count)
    rescue => e
      campaign.increment_stat!(:failed_count)
      Rails.logger.error("Campaign #{campaign.id} send to #{subscriber.email} failed: #{e.message}")
    end
  end
end
```

- [ ] **Step 3: Run tests, commit**

```bash
mkdir -p app/jobs/email_campaigns spec/jobs/email_campaigns
git add spec/jobs/email_campaigns/send_campaign_job_spec.rb app/jobs/email_campaigns/send_campaign_job.rb
git commit -m "feat(email_campaigns): add SendCampaignJob"
```

---

### Task 6: Create EmailCampaigns::SchedulerJob

**Files:**
- Create: `spec/jobs/email_campaigns/scheduler_job_spec.rb`
- Create: `app/jobs/email_campaigns/scheduler_job.rb`

Runs every minute to dispatch due campaigns.

- [ ] **Step 1: Write spec**

```ruby
# spec/jobs/email_campaigns/scheduler_job_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe EmailCampaigns::SchedulerJob, type: :job do
  describe "#perform" do
    let(:customer) { create(:customer) }
    let!(:due) { create(:email_campaign, :scheduled, customer: customer, scheduled_at: 1.minute.ago) }
    let!(:future) { create(:email_campaign, :scheduled, customer: customer, scheduled_at: 1.hour.from_now) }
    let!(:already_sent) { create(:email_campaign, customer: customer, status: "sent") }

    it "transitions due campaigns to sending" do
      described_class.perform_now
      expect(due.reload.status).to eq("sending")
      expect(future.reload.status).to eq("scheduled")
      expect(already_sent.reload.status).to eq("sent")
    end

    it "enqueues SendCampaignJob for each due campaign" do
      expect {
        described_class.perform_now
      }.to have_enqueued_job(EmailCampaigns::SendCampaignJob).with(due.id)
    end

    context "with recurring campaign" do
      let!(:recurring) {
        create(:email_campaign, :scheduled, :recurring,
          customer: customer,
          scheduled_at: 1.minute.ago,
          recurrence_rule: "FREQ=DAILY;INTERVAL=1"
        )
      }

      it "creates next occurrence" do
        expect { described_class.perform_now }
          .to change(EmailCampaign, :count).by(1)

        next_occurrence = EmailCampaign.where(status: "scheduled").last
        expect(next_occurrence.scheduled_at).to be > Time.current
        expect(next_occurrence.recurrence_rule).to eq(recurring.recurrence_rule)
      end
    end
  end
end
```

- [ ] **Step 2: Create job**

```ruby
# app/jobs/email_campaigns/scheduler_job.rb
# frozen_string_literal: true

module EmailCampaigns
  class SchedulerJob < ApplicationJob
    queue_as :default

    def perform
      EmailCampaign.due_for_send.find_each do |campaign|
        process(campaign)
      end
    end

    private

    def process(campaign)
      schedule_next_occurrence(campaign) if campaign.recurring?
      campaign.start!
      SendCampaignJob.perform_later(campaign.id)
    end

    def schedule_next_occurrence(campaign)
      next_at = compute_next_occurrence(campaign)
      return unless next_at

      EmailCampaign.create!(
        customer:        campaign.customer,
        email_template:  campaign.email_template,
        email_list:      campaign.email_list,
        name:            campaign.name,
        status:          "scheduled",
        scheduled_at:    next_at,
        recurrence_rule: campaign.recurrence_rule,
        timezone:        campaign.timezone
      )
    end

    def compute_next_occurrence(campaign)
      # Simple RRULE parsing - supports FREQ=DAILY|WEEKLY|MONTHLY with INTERVAL
      rule = parse_rrule(campaign.recurrence_rule)
      return nil unless rule

      base = campaign.scheduled_at
      interval = rule["INTERVAL"]&.to_i || 1

      case rule["FREQ"]
      when "DAILY"   then base + (interval.days)
      when "WEEKLY"  then base + (interval.weeks)
      when "MONTHLY" then base + (interval.months)
      when "HOURLY"  then base + (interval.hours)
      end
    end

    def parse_rrule(rrule)
      return nil if rrule.blank?
      rrule.split(";").each_with_object({}) do |part, h|
        k, v = part.split("=", 2)
        h[k] = v
      end
    end
  end
end
```

- [ ] **Step 3: Run tests, commit**

```bash
git add spec/jobs/email_campaigns/scheduler_job_spec.rb app/jobs/email_campaigns/scheduler_job.rb
git commit -m "feat(email_campaigns): add SchedulerJob with RRULE support"
```

---

### Task 7: Create EmailCampaigns::UnsubscribeHandler

**Files:**
- Create: `spec/services/email_campaigns/unsubscribe_handler_spec.rb`
- Create: `app/services/email_campaigns/unsubscribe_handler.rb`

- [ ] **Step 1: Write spec**

```ruby
# spec/services/email_campaigns/unsubscribe_handler_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe EmailCampaigns::UnsubscribeHandler do
  describe ".unsubscribe_by_token" do
    let!(:subscriber) { create(:email_subscriber, status: "active") }

    it "marks subscriber as unsubscribed" do
      result = described_class.unsubscribe_by_token(subscriber.unsubscribe_token)
      expect(result.status).to eq("unsubscribed")
      expect(result.unsubscribed_at).to be_present
    end

    it "returns nil for invalid token" do
      expect(described_class.unsubscribe_by_token("invalid")).to be_nil
    end

    it "is idempotent" do
      described_class.unsubscribe_by_token(subscriber.unsubscribe_token)
      result = described_class.unsubscribe_by_token(subscriber.unsubscribe_token)
      expect(result.status).to eq("unsubscribed")
    end
  end

  describe ".find_by_token" do
    let!(:subscriber) { create(:email_subscriber) }

    it "finds subscriber by token" do
      expect(described_class.find_by_token(subscriber.unsubscribe_token)).to eq(subscriber)
    end

    it "returns nil for invalid token" do
      expect(described_class.find_by_token("invalid")).to be_nil
    end
  end
end
```

- [ ] **Step 2: Create service**

```ruby
# app/services/email_campaigns/unsubscribe_handler.rb
# frozen_string_literal: true

module EmailCampaigns
  class UnsubscribeHandler
    def self.find_by_token(token)
      EmailSubscriber.find_by(unsubscribe_token: token)
    end

    def self.unsubscribe_by_token(token)
      subscriber = find_by_token(token)
      return nil unless subscriber

      subscriber.unsubscribe! unless subscriber.status == "unsubscribed"
      subscriber
    end
  end
end
```

- [ ] **Step 3: Run tests, commit**

```bash
git add spec/services/email_campaigns/unsubscribe_handler_spec.rb app/services/email_campaigns/unsubscribe_handler.rb
git commit -m "feat(email_campaigns): add UnsubscribeHandler service"
```

---

### Task 8: Update Email::Gateway.queue_for_campaign

The existing `queue_for_campaign` references `subscriber.attributes_data`. Verify it works with the now-existing EmailSubscriber model.

**Files:**
- Modify: `spec/services/email/gateway_spec.rb` (uncomment/add campaign tests)

- [ ] **Step 1: Add tests for queue_for_campaign**

Add to spec/services/email/gateway_spec.rb after the .send_raw describe block:

```ruby
describe ".queue_for_campaign" do
  let(:campaign) { create(:email_campaign, customer: customer, email_template: template) }
  let(:subscriber) {
    create(:email_subscriber,
      customer: customer,
      email: "sub@example.com",
      first_name: "Jane",
      attributes_data: { "name" => "Jane Override" }
    )
  }

  it "creates message with campaign metadata" do
    result = described_class.queue_for_campaign(campaign: campaign, subscriber: subscriber)

    expect(result.message_type).to eq("campaign")
    expect(result.metadata["campaign_id"]).to eq(campaign.id)
    expect(result.metadata["subscriber_id"]).to eq(subscriber.id)
    expect(result.to).to eq("sub@example.com")
  end

  it "renders template with subscriber data" do
    result = described_class.queue_for_campaign(campaign: campaign, subscriber: subscriber)
    # template subject is "Hi {{name}}" and attributes_data has "name" => "Jane Override"
    expect(result.subject).to eq("Hi Jane Override")
  end

  it "enqueues delivery job" do
    expect {
      described_class.queue_for_campaign(campaign: campaign, subscriber: subscriber)
    }.to have_enqueued_job(Email::DeliveryJob)
  end
end
```

- [ ] **Step 2: Run tests, commit**

```bash
git add spec/services/email/gateway_spec.rb
git commit -m "test(email): add queue_for_campaign tests"
```

---

### Task 9: Configure SolidQueue Recurring Job

**Files:**
- Modify: `config/recurring.yml` (create if not exists)

- [ ] **Step 1: Check existing recurring.yml**

Run: `cat config/recurring.yml 2>/dev/null || echo "doesnt exist"`

- [ ] **Step 2: Add recurring job entry**

If file doesn't exist:
```yaml
# config/recurring.yml
production:
  email_campaign_scheduler:
    class: EmailCampaigns::SchedulerJob
    schedule: every minute
    queue: default
```

If file exists, add the email_campaign_scheduler entry under appropriate environment.

- [ ] **Step 3: Commit**

```bash
git add config/recurring.yml
git commit -m "feat(email_campaigns): schedule SchedulerJob to run every minute"
```

---

### Task 10: Create FeatureModule Registration for Email Campaigns

**Files:**
- Create: `app/services/feature_modules/email_campaigns/registration.rb`
- Create: `app/services/feature_modules/email_campaigns/provisioner.rb`

- [ ] **Step 1: Create provisioner**

```ruby
# app/services/feature_modules/email_campaigns/provisioner.rb
# frozen_string_literal: true

module FeatureModules
  module EmailCampaigns
    class Provisioner
      def self.call(customer)
        # No customer-specific provisioning needed
      end

      def self.revoke(customer)
        # No specific cleanup needed - campaigns are tenant-scoped via FK
      end
    end
  end
end
```

- [ ] **Step 2: Create registration**

```ruby
# app/services/feature_modules/email_campaigns/registration.rb
# frozen_string_literal: true

module FeatureModules
  module EmailCampaigns
    class Registration < FeatureModules::BaseModule
      def self.module_key         = "email_campaigns"
      def self.module_name        = "Email Campaigns"
      def self.module_description = "Marketing campaigns with subscribers, lists, and scheduling"

      def self.provision!(customer)   = Provisioner.call(customer)
      def self.deprovision!(customer) = Provisioner.revoke(customer)

      entry_path { |customer| "/#{customer.id}/email_campaigns/admin/campaigns" }
      default_exit kind: "route", name: "customer_home"

      def self.sidebar_contributions(_controller)
        {
          entries: [
            ModuleContribution.new(label: "Subscribers", entry_key: "subscribers", path: ->(cid) { "/#{cid}/email_campaigns/admin/subscribers" }),
            ModuleContribution.new(label: "Lists", entry_key: "lists", path: ->(cid) { "/#{cid}/email_campaigns/admin/lists" }),
            ModuleContribution.new(label: "Campaigns", entry_key: "campaigns", path: ->(cid) { "/#{cid}/email_campaigns/admin/campaigns" })
          ],
          settings: [],
          metadata: { order: 51 }
        }
      end

      def self.entries_for(entry_key:, params:)
        case entry_key
        when "subscribers" then subscribers_entry_config
        when "lists"       then lists_entry_config
        when "campaigns"   then campaigns_entry_config
        else raise ArgumentError, "unknown entry_key: #{entry_key}"
        end
      end

      class << self
        private

        def subscribers_entry_config
          {
            title: "Subscribers",
            columns: [
              { key: :email, label: "Email", searchable: true },
              { key: :status, label: "Status", sortable: true },
              { key: :subscribed_at, label: "Subscribed", sortable: true }
            ],
            scope: ::EmailSubscriber.for_current_customer.order(created_at: :desc)
          }
        end

        def lists_entry_config
          {
            title: "Lists",
            columns: [
              { key: :name, label: "Name", searchable: true },
              { key: :list_type, label: "Type" },
              { key: :status, label: "Status" }
            ],
            scope: ::EmailList.for_current_customer.order(created_at: :desc)
          }
        end

        def campaigns_entry_config
          {
            title: "Campaigns",
            columns: [
              { key: :name, label: "Name", searchable: true },
              { key: :status, label: "Status", sortable: true },
              { key: :scheduled_at, label: "Scheduled", sortable: true }
            ],
            scope: ::EmailCampaign.for_current_customer.order(created_at: :desc)
          }
        end
      end
    end
  end
end
```

- [ ] **Step 3: Commit**

```bash
mkdir -p app/services/feature_modules/email_campaigns
git add app/services/feature_modules/email_campaigns/
git commit -m "feat(email_campaigns): add FeatureModule registration"
```

---

### Task 11: Create FeatureModule Registration for Email Core

**Files:**
- Create: `app/services/feature_modules/email/registration.rb`
- Create: `app/services/feature_modules/email/provisioner.rb`

- [ ] **Step 1: Create provisioner**

```ruby
# app/services/feature_modules/email/provisioner.rb
# frozen_string_literal: true

module FeatureModules
  module Email
    class Provisioner
      def self.call(customer)
        # No customer-specific provisioning - templates created via UI
      end

      def self.revoke(customer)
        # Templates and messages are tenant-scoped, deleted via FK cascade
      end
    end
  end
end
```

- [ ] **Step 2: Create registration**

```ruby
# app/services/feature_modules/email/registration.rb
# frozen_string_literal: true

module FeatureModules
  module Email
    class Registration < FeatureModules::BaseModule
      def self.module_key         = "email"
      def self.module_name        = "Email"
      def self.module_description = "Transactional and marketing email delivery"

      required! # Auto-enabled for all customers

      def self.provision!(customer)   = Provisioner.call(customer)
      def self.deprovision!(customer) = Provisioner.revoke(customer)

      entry_path { |customer| "/#{customer.id}/email/admin/templates" }
      default_exit kind: "route", name: "customer_home"

      input_contract do
        property :to,           validates: { presence: true, format: { with: URI::MailTo::EMAIL_REGEXP } }
        property :template_key, validates: { presence: true }
        property :vars,         validates: { presence: true }
        property :cc
        property :bcc
        property :reply_to
        property :idempotency_key
      end

      output_contract do
        property :message_id, validates: { presence: true }
        property :status,     validates: { inclusion: { in: %w[queued sent failed] } }
      end

      def self.sidebar_contributions(_controller)
        {
          entries: [
            ModuleContribution.new(label: "Templates", entry_key: "templates", path: ->(cid) { "/#{cid}/email/admin/templates" }),
            ModuleContribution.new(label: "Messages", entry_key: "messages", path: ->(cid) { "/#{cid}/email/admin/messages" })
          ],
          settings: [
            ModuleContribution.new(label: "Daily cap", entry_key: "daily_cap")
          ],
          metadata: { order: 50 }
        }
      end

      def self.entries_for(entry_key:, params:)
        case entry_key
        when "templates" then templates_entry_config
        when "messages"  then messages_entry_config
        else raise ArgumentError, "unknown entry_key: #{entry_key}"
        end
      end

      class << self
        private

        def templates_entry_config
          {
            title: "Email Templates",
            columns: [
              { key: :name, label: "Name", searchable: true },
              { key: :key, label: "Key" },
              { key: :template_type, label: "Type" },
              { key: :status, label: "Status", sortable: true }
            ],
            scope: ::EmailTemplate.for_current_customer.order(created_at: :desc)
          }
        end

        def messages_entry_config
          {
            title: "Email Messages",
            columns: [
              { key: :created_at, label: "At", sortable: true },
              { key: :to, label: "To", searchable: true },
              { key: :subject, label: "Subject" },
              { key: :status, label: "Status", sortable: true }
            ],
            scope: ::EmailMessage.for_current_customer.includes(:email_template).order(created_at: :desc)
          }
        end
      end
    end
  end
end
```

- [ ] **Step 3: Commit**

```bash
mkdir -p app/services/feature_modules/email
git add app/services/feature_modules/email/
git commit -m "feat(email): add FeatureModule registration"
```

---

### Task 12: Run Full Phase 2 Test Suite

- [ ] **Step 1: Run all email_campaigns specs**

Run: `cd /home/ec2-user/anysys && bundle exec rspec spec/models/email_*.rb spec/services/email/ spec/services/email_campaigns/ spec/jobs/email/ spec/jobs/email_campaigns/`
Expected: All tests PASS

- [ ] **Step 2: Final commit**

```bash
# No additional changes — just verify
git log --oneline -15
```

---

## Phase 2 Complete

Models created: EmailSubscriber, EmailList, EmailListSubscriber, EmailCampaign
Services: SegmentEvaluator, UnsubscribeHandler
Jobs: SendCampaignJob, SchedulerJob (recurring)
FeatureModule registrations: Email and EmailCampaigns

Next: Phase 3 - Admin UI and controllers
