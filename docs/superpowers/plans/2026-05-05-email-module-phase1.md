# Email Module Implementation Plan - Phase 1: Core Infrastructure

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build core email infrastructure - models, services, and delivery pipeline (no UI yet)

**Architecture:** Platform-level SMTP credentials, tenant-scoped templates/messages, Gateway pattern mirroring SMS module

**Tech Stack:** Rails 8.1, Reform contracts, Trailblazer activities, ActiveJob with SolidQueue

---

## File Structure

```
app/models/
├── email_credential.rb
├── email_template.rb
├── email_message.rb

app/services/email/
├── errors.rb
├── credential_resolver.rb
├── template_renderer.rb
├── gateway.rb
├── adapters/
│   └── smtp.rb
├── activities/
│   └── send.rb
└── contracts/
    └── send.rb

app/jobs/email/
└── delivery_job.rb

db/migrate/
├── XXXXXX_create_email_credentials.rb
├── XXXXXX_create_email_templates.rb
└── XXXXXX_create_email_messages.rb

spec/models/
├── email_credential_spec.rb
├── email_template_spec.rb
├── email_message_spec.rb

spec/services/email/
├── credential_resolver_spec.rb
├── template_renderer_spec.rb
├── gateway_spec.rb
├── adapters/smtp_spec.rb
└── activities/send_spec.rb

spec/jobs/email/
└── delivery_job_spec.rb
```

---

### Task 1: Create EmailCredential Model

**Files:**
- Create: `spec/models/email_credential_spec.rb`
- Create: `db/migrate/XXXXXX_create_email_credentials.rb`
- Create: `app/models/email_credential.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# spec/models/email_credential_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe EmailCredential, type: :model do
  describe "validations" do
    subject { build(:email_credential) }

    it { is_expected.to validate_presence_of(:host) }
    it { is_expected.to validate_presence_of(:port) }
    it { is_expected.to validate_presence_of(:username) }
    it { is_expected.to validate_presence_of(:password) }
    it { is_expected.to validate_presence_of(:mode) }
    it { is_expected.to validate_inclusion_of(:mode).in_array(%w[sandbox production]) }
    it { is_expected.to validate_uniqueness_of(:mode) }
    it { is_expected.to validate_inclusion_of(:status).in_array(%w[active disabled]) }
    it { is_expected.to validate_inclusion_of(:authentication).in_array(%w[plain login cram_md5]) }
  end

  describe "scopes" do
    let!(:active_prod) { create(:email_credential, mode: "production", status: "active") }
    let!(:disabled_sandbox) { create(:email_credential, mode: "sandbox", status: "disabled") }

    it ".active returns only active credentials" do
      expect(described_class.active).to contain_exactly(active_prod)
    end
  end

  describe "#enabled?" do
    it "returns true when status is active" do
      credential = build(:email_credential, status: "active")
      expect(credential.enabled?).to be true
    end

    it "returns false when status is disabled" do
      credential = build(:email_credential, status: "disabled")
      expect(credential.enabled?).to be false
    end
  end

  describe "encryption" do
    it "encrypts the password field" do
      credential = create(:email_credential, password: "secret123")
      expect(credential.password).to eq("secret123")
      expect(credential.password_before_type_cast).not_to eq("secret123")
    end
  end
end
```

- [ ] **Step 2: Create factory**

```ruby
# spec/factories/email_credentials.rb
# frozen_string_literal: true

FactoryBot.define do
  factory :email_credential do
    host { "smtp.example.com" }
    port { 587 }
    username { "user@example.com" }
    password { "secret123" }
    mode { "sandbox" }
    status { "active" }
    authentication { "plain" }
    enable_starttls { true }
    ssl { false }

    trait :production do
      mode { "production" }
    end

    trait :disabled do
      status { "disabled" }
    end
  end
end
```

- [ ] **Step 3: Run test to verify it fails**

Run: `bundle exec rspec spec/models/email_credential_spec.rb`
Expected: FAIL - table/model does not exist

- [ ] **Step 4: Create migration**

Run: `bin/rails generate migration CreateEmailCredentials`

```ruby
# db/migrate/XXXXXX_create_email_credentials.rb
class CreateEmailCredentials < ActiveRecord::Migration[8.1]
  def change
    create_table :email_credentials do |t|
      t.string :host, null: false
      t.integer :port, null: false, default: 587
      t.string :username, null: false
      t.text :password, null: false
      t.string :domain
      t.string :authentication, null: false, default: "plain"
      t.boolean :enable_starttls, null: false, default: true
      t.boolean :ssl, null: false, default: false
      t.string :mode, null: false
      t.string :status, null: false, default: "active"
      t.integer :daily_limit
      t.timestamps
    end

    add_index :email_credentials, :mode, unique: true
  end
end
```

- [ ] **Step 5: Run migration**

Run: `bin/rails db:migrate`

- [ ] **Step 6: Create model**

```ruby
# app/models/email_credential.rb
# frozen_string_literal: true

class EmailCredential < ApplicationRecord
  MODES = %w[sandbox production].freeze
  STATUSES = %w[active disabled].freeze
  AUTHENTICATIONS = %w[plain login cram_md5].freeze

  encrypts :password

  validates :host, presence: true
  validates :port, presence: true
  validates :username, presence: true
  validates :password, presence: true
  validates :mode, presence: true, inclusion: { in: MODES }, uniqueness: true
  validates :status, inclusion: { in: STATUSES }
  validates :authentication, inclusion: { in: AUTHENTICATIONS }

  scope :active, -> { where(status: "active") }

  def enabled? = status == "active"
end
```

- [ ] **Step 7: Run tests to verify they pass**

Run: `bundle exec rspec spec/models/email_credential_spec.rb`
Expected: All tests PASS

- [ ] **Step 8: Commit**

```bash
git add spec/models/email_credential_spec.rb spec/factories/email_credentials.rb db/migrate/*_create_email_credentials.rb app/models/email_credential.rb
git commit -m "feat(email): add EmailCredential model with encryption"
```

---

### Task 2: Create EmailTemplate Model

**Files:**
- Create: `spec/models/email_template_spec.rb`
- Create: `spec/factories/email_templates.rb`
- Create: `db/migrate/XXXXXX_create_email_templates.rb`
- Create: `app/models/email_template.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# spec/models/email_template_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe EmailTemplate, type: :model do
  describe "validations" do
    subject { build(:email_template) }

    it { is_expected.to validate_presence_of(:customer_id) }
    it { is_expected.to validate_presence_of(:key) }
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:subject) }
    it { is_expected.to validate_presence_of(:body_html) }
    it { is_expected.to validate_inclusion_of(:template_type).in_array(%w[transactional marketing]) }
    it { is_expected.to validate_inclusion_of(:editor_type).in_array(%w[code rich_text builder]) }
    it { is_expected.to validate_inclusion_of(:status).in_array(%w[draft active retired]) }

    it "validates key uniqueness scoped to customer_id" do
      existing = create(:email_template)
      duplicate = build(:email_template, customer_id: existing.customer_id, key: existing.key)
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:key]).to include("has already been taken")
    end

    it "validates key format" do
      template = build(:email_template, key: "Invalid Key!")
      expect(template).not_to be_valid
      expect(template.errors[:key]).to be_present
    end
  end

  describe "scopes" do
    let(:customer) { create(:customer) }
    let!(:active_template) { create(:email_template, customer: customer, status: "active") }
    let!(:draft_template) { create(:email_template, customer: customer, status: "draft") }
    let!(:retired_template) { create(:email_template, customer: customer, status: "retired") }

    it ".active returns only active templates" do
      expect(described_class.active).to contain_exactly(active_template)
    end

    it ".transactional returns transactional templates" do
      marketing = create(:email_template, customer: customer, template_type: "marketing")
      expect(described_class.transactional).not_to include(marketing)
    end
  end

  describe "#active?" do
    it "returns true when status is active" do
      expect(build(:email_template, status: "active").active?).to be true
    end

    it "returns false when status is not active" do
      expect(build(:email_template, status: "draft").active?).to be false
    end
  end

  describe "#required_vars" do
    it "returns variables as array" do
      template = build(:email_template, variables: ["first_name", "order_id"])
      expect(template.required_vars).to eq(["first_name", "order_id"])
    end

    it "returns empty array when variables is nil" do
      template = build(:email_template, variables: nil)
      expect(template.required_vars).to eq([])
    end
  end

  describe "associations" do
    it { is_expected.to belong_to(:customer) }
    it { is_expected.to have_many(:email_messages).dependent(:restrict_with_exception) }
  end
end
```

- [ ] **Step 2: Create factory**

```ruby
# spec/factories/email_templates.rb
# frozen_string_literal: true

FactoryBot.define do
  factory :email_template do
    customer
    sequence(:key) { |n| "template_#{n}" }
    name { "Welcome Email" }
    subject { "Welcome {{first_name}}!" }
    body_html { "<p>Hello {{first_name}}, welcome to our service.</p>" }
    template_type { "transactional" }
    editor_type { "code" }
    status { "active" }
    variables { ["first_name"] }

    trait :marketing do
      template_type { "marketing" }
    end

    trait :draft do
      status { "draft" }
    end

    trait :with_builder do
      editor_type { "builder" }
      builder_data { { components: [], styles: [] } }
    end
  end
end
```

- [ ] **Step 3: Run test to verify it fails**

Run: `bundle exec rspec spec/models/email_template_spec.rb`
Expected: FAIL - table/model does not exist

- [ ] **Step 4: Create migration**

Run: `bin/rails generate migration CreateEmailTemplates`

```ruby
# db/migrate/XXXXXX_create_email_templates.rb
class CreateEmailTemplates < ActiveRecord::Migration[8.1]
  def change
    create_table :email_templates do |t|
      t.integer :customer_id, null: false
      t.string :key, null: false
      t.string :name, null: false
      t.string :subject, null: false
      t.text :body_html, null: false
      t.text :body_text
      t.string :template_type, null: false, default: "transactional"
      t.string :editor_type, null: false, default: "code"
      t.json :builder_data, null: false, default: {}
      t.json :variables, null: false, default: []
      t.string :status, null: false, default: "draft"
      t.timestamps
    end

    add_index :email_templates, [:customer_id, :key], unique: true
    add_index :email_templates, [:customer_id, :template_type]
    add_index :email_templates, :customer_id
  end
end
```

- [ ] **Step 5: Run migration**

Run: `bin/rails db:migrate`

- [ ] **Step 6: Create model**

```ruby
# app/models/email_template.rb
# frozen_string_literal: true

class EmailTemplate < ApplicationRecord
  include TenantScoped

  TEMPLATE_TYPES = %w[transactional marketing].freeze
  EDITOR_TYPES = %w[code rich_text builder].freeze
  STATUSES = %w[draft active retired].freeze

  belongs_to :customer
  has_many :email_messages, dependent: :restrict_with_exception

  validates :customer_id, presence: true
  validates :key, presence: true,
                  uniqueness: { scope: :customer_id },
                  format: { with: /\A[a-z0-9_]+\z/, message: "only lowercase letters, numbers, and underscores" }
  validates :name, presence: true
  validates :subject, presence: true
  validates :body_html, presence: true
  validates :template_type, inclusion: { in: TEMPLATE_TYPES }
  validates :editor_type, inclusion: { in: EDITOR_TYPES }
  validates :status, inclusion: { in: STATUSES }

  scope :active, -> { where(status: "active") }
  scope :transactional, -> { where(template_type: "transactional") }
  scope :marketing, -> { where(template_type: "marketing") }

  def active? = status == "active"
  def required_vars = Array(variables)
end
```

- [ ] **Step 7: Run tests to verify they pass**

Run: `bundle exec rspec spec/models/email_template_spec.rb`
Expected: All tests PASS

- [ ] **Step 8: Commit**

```bash
git add spec/models/email_template_spec.rb spec/factories/email_templates.rb db/migrate/*_create_email_templates.rb app/models/email_template.rb
git commit -m "feat(email): add EmailTemplate model with tenant scoping"
```

---

### Task 3: Create EmailMessage Model

**Files:**
- Create: `spec/models/email_message_spec.rb`
- Create: `spec/factories/email_messages.rb`
- Create: `db/migrate/XXXXXX_create_email_messages.rb`
- Create: `app/models/email_message.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# spec/models/email_message_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe EmailMessage, type: :model do
  describe "validations" do
    subject { build(:email_message) }

    it { is_expected.to validate_presence_of(:customer_id) }
    it { is_expected.to validate_presence_of(:to) }
    it { is_expected.to validate_presence_of(:from) }
    it { is_expected.to validate_presence_of(:subject) }
    it { is_expected.to validate_presence_of(:body_html) }
    it { is_expected.to validate_inclusion_of(:status).in_array(%w[pending queued sent delivered bounced failed]) }
    it { is_expected.to validate_inclusion_of(:message_type).in_array(%w[transactional campaign]) }
  end

  describe "associations" do
    it { is_expected.to belong_to(:customer) }
    it { is_expected.to belong_to(:email_template).optional }
  end

  describe "status transitions" do
    let(:message) { create(:email_message, status: "queued") }

    describe "#mark_sent!" do
      it "updates status and sent_at" do
        freeze_time do
          message.mark_sent!
          expect(message.status).to eq("sent")
          expect(message.sent_at).to eq(Time.current)
        end
      end
    end

    describe "#mark_failed!" do
      it "updates status and failure info" do
        message.mark_failed!(code: "SMTP_ERROR", message: "Connection refused")
        expect(message.status).to eq("failed")
        expect(message.failure_code).to eq("SMTP_ERROR")
        expect(message.failure_message).to eq("Connection refused")
      end
    end

    describe "#mark_delivered!" do
      it "updates status and delivered_at" do
        freeze_time do
          message.mark_delivered!
          expect(message.status).to eq("delivered")
          expect(message.delivered_at).to eq(Time.current)
        end
      end
    end

    describe "#mark_bounced!" do
      it "updates status and failure info" do
        message.mark_bounced!(code: "HARD_BOUNCE", message: "Mailbox not found")
        expect(message.status).to eq("bounced")
        expect(message.failure_code).to eq("HARD_BOUNCE")
        expect(message.failure_message).to eq("Mailbox not found")
      end
    end
  end

  describe "scopes" do
    let(:customer) { create(:customer) }

    it ".for_current_customer scopes by Current.customer" do
      msg1 = create(:email_message, customer: customer)
      msg2 = create(:email_message)
      
      allow(Current).to receive(:customer).and_return(customer)
      expect(described_class.for_current_customer).to contain_exactly(msg1)
    end
  end

  describe "idempotency" do
    it "enforces unique idempotency_key per customer" do
      msg1 = create(:email_message, idempotency_key: "unique-key")
      msg2 = build(:email_message, customer: msg1.customer, idempotency_key: "unique-key")
      expect(msg2).not_to be_valid
    end

    it "allows same idempotency_key for different customers" do
      msg1 = create(:email_message, idempotency_key: "unique-key")
      msg2 = build(:email_message, idempotency_key: "unique-key")
      expect(msg2).to be_valid
    end

    it "allows nil idempotency_key" do
      msg1 = create(:email_message, idempotency_key: nil)
      msg2 = build(:email_message, customer: msg1.customer, idempotency_key: nil)
      expect(msg2).to be_valid
    end
  end
end
```

- [ ] **Step 2: Create factory**

```ruby
# spec/factories/email_messages.rb
# frozen_string_literal: true

FactoryBot.define do
  factory :email_message do
    customer
    to { "recipient@example.com" }
    from { "sender@example.com" }
    subject { "Test Email" }
    body_html { "<p>Test content</p>" }
    status { "pending" }
    message_type { "transactional" }

    trait :queued do
      status { "queued" }
    end

    trait :sent do
      status { "sent" }
      sent_at { Time.current }
    end

    trait :failed do
      status { "failed" }
      failure_code { "SMTP_ERROR" }
      failure_message { "Connection refused" }
    end

    trait :campaign do
      message_type { "campaign" }
      metadata { { campaign_id: 1, subscriber_id: 1 } }
    end
  end
end
```

- [ ] **Step 3: Run test to verify it fails**

Run: `bundle exec rspec spec/models/email_message_spec.rb`
Expected: FAIL - table/model does not exist

- [ ] **Step 4: Create migration**

Run: `bin/rails generate migration CreateEmailMessages`

```ruby
# db/migrate/XXXXXX_create_email_messages.rb
class CreateEmailMessages < ActiveRecord::Migration[8.1]
  def change
    create_table :email_messages do |t|
      t.integer :customer_id, null: false
      t.integer :email_template_id
      t.string :to, null: false
      t.string :cc
      t.string :bcc
      t.string :from, null: false
      t.string :reply_to
      t.string :subject, null: false
      t.text :body_html, null: false
      t.text :body_text
      t.string :status, null: false, default: "pending"
      t.string :message_type, null: false, default: "transactional"
      t.datetime :scheduled_at
      t.datetime :sent_at
      t.datetime :delivered_at
      t.string :failure_code
      t.string :failure_message
      t.string :idempotency_key
      t.json :metadata, null: false, default: {}
      t.timestamps
    end

    add_index :email_messages, [:customer_id, :created_at]
    add_index :email_messages, [:customer_id, :idempotency_key], unique: true, where: "idempotency_key IS NOT NULL", name: "idx_email_messages_customer_idem"
    add_index :email_messages, [:customer_id, :status]
    add_index :email_messages, :email_template_id
  end
end
```

- [ ] **Step 5: Run migration**

Run: `bin/rails db:migrate`

- [ ] **Step 6: Create model**

```ruby
# app/models/email_message.rb
# frozen_string_literal: true

class EmailMessage < ApplicationRecord
  include TenantScoped

  STATUSES = %w[pending queued sent delivered bounced failed].freeze
  MESSAGE_TYPES = %w[transactional campaign].freeze

  belongs_to :customer
  belongs_to :email_template, optional: true

  validates :customer_id, presence: true
  validates :to, presence: true
  validates :from, presence: true
  validates :subject, presence: true
  validates :body_html, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :message_type, inclusion: { in: MESSAGE_TYPES }
  validates :idempotency_key, uniqueness: { scope: :customer_id }, allow_nil: true

  def mark_sent!
    update!(status: "sent", sent_at: Time.current)
  end

  def mark_failed!(code:, message:)
    update!(status: "failed", failure_code: code, failure_message: message)
  end

  def mark_delivered!
    update!(status: "delivered", delivered_at: Time.current)
  end

  def mark_bounced!(code:, message:)
    update!(status: "bounced", failure_code: code, failure_message: message)
  end
end
```

- [ ] **Step 7: Run tests to verify they pass**

Run: `bundle exec rspec spec/models/email_message_spec.rb`
Expected: All tests PASS

- [ ] **Step 8: Commit**

```bash
git add spec/models/email_message_spec.rb spec/factories/email_messages.rb db/migrate/*_create_email_messages.rb app/models/email_message.rb
git commit -m "feat(email): add EmailMessage model with status transitions"
```

---

### Task 4: Create Email::Errors Module

**Files:**
- Create: `app/services/email/errors.rb`

- [ ] **Step 1: Create errors module**

```ruby
# app/services/email/errors.rb
# frozen_string_literal: true

module Email
  module Errors
    class Error < StandardError; end
    class CredentialsMissing < Error; end
    class TemplateNotFound < Error; end
    class TemplateVarsInvalid < Error; end
    class DailyCapExceeded < Error; end
    class InvalidRecipient < Error; end

    class DeliveryFailed < Error
      attr_reader :code, :original

      def initialize(msg, code: nil, original: nil)
        @code = code
        @original = original
        super(msg)
      end
    end
  end
end
```

- [ ] **Step 2: Commit**

```bash
mkdir -p app/services/email
git add app/services/email/errors.rb
git commit -m "feat(email): add Email::Errors module"
```

---

### Task 5: Create Email::CredentialResolver

**Files:**
- Create: `spec/services/email/credential_resolver_spec.rb`
- Create: `app/services/email/credential_resolver.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# spec/services/email/credential_resolver_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Email::CredentialResolver do
  describe ".call" do
    context "when active credential exists for mode" do
      let!(:credential) { create(:email_credential, mode: "production", status: "active") }

      it "returns the credential" do
        result = described_class.call(mode: "production")
        expect(result).to eq(credential)
      end
    end

    context "when credential is disabled" do
      let!(:credential) { create(:email_credential, mode: "production", status: "disabled") }

      it "raises CredentialsMissing" do
        expect { described_class.call(mode: "production") }
          .to raise_error(Email::Errors::CredentialsMissing, /no active email credential/)
      end
    end

    context "when no credential exists" do
      it "raises CredentialsMissing" do
        expect { described_class.call(mode: "sandbox") }
          .to raise_error(Email::Errors::CredentialsMissing)
      end
    end
  end

  describe ".default_mode" do
    it "returns production in production environment" do
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("production"))
      expect(described_class.default_mode).to eq("production")
    end

    it "returns sandbox in non-production environments" do
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("development"))
      expect(described_class.default_mode).to eq("sandbox")
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/services/email/credential_resolver_spec.rb`
Expected: FAIL - class does not exist

- [ ] **Step 3: Create the service**

```ruby
# app/services/email/credential_resolver.rb
# frozen_string_literal: true

module Email
  class CredentialResolver
    def self.call(mode:)
      credential = EmailCredential.active.find_by(mode: mode)
      raise Errors::CredentialsMissing, "no active email credential for mode=#{mode}" unless credential
      credential
    end

    def self.default_mode
      Rails.env.production? ? "production" : "sandbox"
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec rspec spec/services/email/credential_resolver_spec.rb`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
mkdir -p spec/services/email
git add spec/services/email/credential_resolver_spec.rb app/services/email/credential_resolver.rb
git commit -m "feat(email): add CredentialResolver service"
```

---

### Task 6: Create Email::TemplateRenderer

**Files:**
- Create: `spec/services/email/template_renderer_spec.rb`
- Create: `app/services/email/template_renderer.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# spec/services/email/template_renderer_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Email::TemplateRenderer do
  describe ".render" do
    let(:template) do
      build(:email_template,
        subject: "Hello {{first_name}}!",
        body_html: "<p>Welcome, {{first_name}} {{last_name}}.</p>",
        body_text: nil
      )
    end
    let(:vars) { { first_name: "John", last_name: "Doe" } }

    it "interpolates variables in subject" do
      result = described_class.render(template: template, vars: vars)
      expect(result[:subject]).to eq("Hello John!")
    end

    it "interpolates variables in body_html" do
      result = described_class.render(template: template, vars: vars)
      expect(result[:body_html]).to eq("<p>Welcome, John Doe.</p>")
    end

    it "auto-generates body_text from body_html when blank" do
      result = described_class.render(template: template, vars: vars)
      expect(result[:body_text]).to eq("Welcome, John Doe.")
    end

    it "uses provided body_text if present" do
      template.body_text = "Plain: {{first_name}}"
      result = described_class.render(template: template, vars: vars)
      expect(result[:body_text]).to eq("Plain: John")
    end

    context "with ctx.field references" do
      let(:template) do
        build(:email_template,
          subject: "Order {{order_id}}",
          body_html: "<p>Hi {{ctx.user.name}}</p>"
        )
      end
      let(:vars) { { order_id: "12345", ctx: { user: { name: "Alice" } } } }

      it "resolves nested ctx references" do
        result = described_class.render(template: template, vars: vars)
        expect(result[:body_html]).to eq("<p>Hi Alice</p>")
      end
    end

    context "with missing variables" do
      let(:vars) { { first_name: "John" } }

      it "leaves missing placeholders empty" do
        result = described_class.render(template: template, vars: vars)
        expect(result[:subject]).to eq("Hello John!")
        expect(result[:body_html]).to eq("<p>Welcome, John .</p>")
      end
    end
  end

  describe ".interpolate" do
    it "handles simple variables" do
      result = described_class.interpolate("Hello {{name}}", { name: "World" })
      expect(result).to eq("Hello World")
    end

    it "handles ctx.field syntax" do
      result = described_class.interpolate("Hi {{ctx.user.email}}", { ctx: { user: { email: "a@b.com" } } })
      expect(result).to eq("Hi a@b.com")
    end

    it "handles string keys" do
      result = described_class.interpolate("Hello {{name}}", { "name" => "World" })
      expect(result).to eq("Hello World")
    end
  end

  describe ".strip_html" do
    it "removes HTML tags" do
      html = "<p><strong>Bold</strong> and <em>italic</em></p>"
      expect(described_class.strip_html(html)).to eq("Bold and italic")
    end

    it "handles nil" do
      expect(described_class.strip_html(nil)).to eq("")
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/services/email/template_renderer_spec.rb`
Expected: FAIL - class does not exist

- [ ] **Step 3: Create the service**

```ruby
# app/services/email/template_renderer.rb
# frozen_string_literal: true

module Email
  class TemplateRenderer
    class << self
      def render(template:, vars:)
        subject = interpolate(template.subject, vars)
        body_html = interpolate(template.body_html, vars)
        body_text = template.body_text.present? ? interpolate(template.body_text, vars) : strip_html(body_html)

        { subject: subject, body_html: body_html, body_text: body_text }
      end

      def interpolate(text, vars)
        return "" if text.blank?

        text.to_s.gsub(/\{\{(\w+(?:\.\w+)*)\}\}/) do
          keys = $1.split(".")
          resolve_value(keys, vars).to_s
        end
      end

      def strip_html(html)
        ActionController::Base.helpers.strip_tags(html.to_s)
      end

      private

      def resolve_value(keys, vars)
        keys.inject(vars) do |current, key|
          break nil unless current.is_a?(Hash)
          current[key.to_sym] || current[key.to_s]
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec rspec spec/services/email/template_renderer_spec.rb`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add spec/services/email/template_renderer_spec.rb app/services/email/template_renderer.rb
git commit -m "feat(email): add TemplateRenderer with variable interpolation"
```

---

### Task 7: Create Email::Contracts::Send

**Files:**
- Create: `spec/services/email/contracts/send_spec.rb`
- Create: `app/services/email/contracts/send.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# spec/services/email/contracts/send_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Email::Contracts::Send do
  let(:customer) { create(:customer) }
  let(:template) { create(:email_template, customer: customer, key: "welcome", variables: ["first_name"]) }

  describe "validations" do
    context "with valid inputs" do
      let(:params) do
        {
          customer_id: customer.id,
          to: "user@example.com",
          template_key: "welcome",
          vars: { first_name: "John" }
        }
      end

      it "is valid" do
        contract = described_class.new(OpenStruct.new)
        expect(contract.validate(params)).to be true
      end

      it "exposes the resolved template" do
        contract = described_class.new(OpenStruct.new)
        contract.validate(params)
        expect(contract.template).to eq(template)
      end
    end

    context "with missing to" do
      it "is invalid" do
        contract = described_class.new(OpenStruct.new)
        result = contract.validate(customer_id: customer.id, to: "", template_key: "welcome", vars: {})
        expect(result).to be false
        expect(contract.errors[:to]).to be_present
      end
    end

    context "with invalid email format" do
      it "is invalid" do
        contract = described_class.new(OpenStruct.new)
        result = contract.validate(customer_id: customer.id, to: "not-an-email", template_key: "welcome", vars: {})
        expect(result).to be false
        expect(contract.errors[:to]).to be_present
      end
    end

    context "with non-existent template" do
      it "is invalid" do
        contract = described_class.new(OpenStruct.new)
        result = contract.validate(customer_id: customer.id, to: "a@b.com", template_key: "nonexistent", vars: {})
        expect(result).to be false
        expect(contract.errors[:template_key]).to include("is not a registered active template")
      end
    end

    context "with missing required vars" do
      it "is invalid" do
        contract = described_class.new(OpenStruct.new)
        result = contract.validate(customer_id: customer.id, to: "a@b.com", template_key: "welcome", vars: {})
        expect(result).to be false
        expect(contract.errors[:vars]).to be_present
      end
    end

    context "with extra vars" do
      it "is invalid" do
        contract = described_class.new(OpenStruct.new)
        result = contract.validate(
          customer_id: customer.id,
          to: "a@b.com",
          template_key: "welcome",
          vars: { first_name: "John", unknown: "value" }
        )
        expect(result).to be false
        expect(contract.errors[:vars]).to be_present
      end
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/services/email/contracts/send_spec.rb`
Expected: FAIL - class does not exist

- [ ] **Step 3: Create the contract**

```ruby
# app/services/email/contracts/send.rb
# frozen_string_literal: true

require "reform/form"

module Email
  module Contracts
    class Send < Reform::Form
      property :customer_id
      property :to
      property :template_key
      property :vars
      property :cc
      property :bcc
      property :reply_to
      property :idempotency_key

      validates :to, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP, message: "is not a valid email" }
      validates :template_key, presence: true
      validates :vars, presence: true
      validate :template_exists_and_active
      validate :vars_shape_matches_template

      def template
        @template ||= EmailTemplate.active.find_by(customer_id: customer_id, key: template_key)
      end

      private

      def template_exists_and_active
        return if template_key.blank?
        return if template.present?
        errors.add(:template_key, "is not a registered active template")
      end

      def vars_shape_matches_template
        return unless template && vars.is_a?(Hash)
        required = template.required_vars.map(&:to_s)
        provided = vars.keys.map(&:to_s)
        missing = required - provided
        extra = provided - required
        errors.add(:vars, "missing required keys: #{missing.join(', ')}") if missing.any?
        errors.add(:vars, "has unknown keys: #{extra.join(', ')}") if extra.any?
      end
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec rspec spec/services/email/contracts/send_spec.rb`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
mkdir -p app/services/email/contracts spec/services/email/contracts
git add spec/services/email/contracts/send_spec.rb app/services/email/contracts/send.rb
git commit -m "feat(email): add Send contract with template validation"
```

---

### Task 8: Create Email::Adapters::Smtp

**Files:**
- Create: `spec/services/email/adapters/smtp_spec.rb`
- Create: `app/services/email/adapters/smtp.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# spec/services/email/adapters/smtp_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Email::Adapters::Smtp do
  let(:credential) do
    build(:email_credential,
      host: "smtp.example.com",
      port: 587,
      username: "user",
      password: "pass",
      authentication: "plain",
      enable_starttls: true
    )
  end

  let(:message) do
    build(:email_message,
      to: "recipient@example.com",
      from: "sender@example.com",
      subject: "Test Subject",
      body_html: "<p>HTML body</p>",
      body_text: "Text body",
      cc: "cc@example.com",
      bcc: "bcc@example.com",
      reply_to: "reply@example.com"
    )
  end

  describe "#deliver" do
    let(:adapter) { described_class.new(credential: credential) }

    it "builds mail with correct attributes" do
      mail_double = instance_double(Mail::Message, deliver: true)
      
      expect(Mail).to receive(:new).and_yield(mail_double).and_return(mail_double)
      expect(mail_double).to receive(:to).with("recipient@example.com")
      expect(mail_double).to receive(:from).with("sender@example.com")
      expect(mail_double).to receive(:subject).with("Test Subject")
      expect(mail_double).to receive(:cc).with("cc@example.com")
      expect(mail_double).to receive(:bcc).with("bcc@example.com")
      expect(mail_double).to receive(:reply_to).with("reply@example.com")
      expect(mail_double).to receive(:text_part=)
      expect(mail_double).to receive(:html_part=)
      expect(mail_double).to receive(:delivery_method).with(:smtp, hash_including(
        address: "smtp.example.com",
        port: 587,
        user_name: "user",
        password: "pass"
      ))

      adapter.deliver(message)
    end

    context "when SMTP raises an error" do
      it "raises DeliveryFailed" do
        allow(Mail).to receive(:new).and_raise(Net::SMTPAuthenticationError.new("auth failed"))
        
        expect { adapter.deliver(message) }
          .to raise_error(Email::Errors::DeliveryFailed, /SMTP delivery failed/)
      end
    end
  end

  describe "#smtp_settings" do
    it "returns correct SMTP configuration" do
      adapter = described_class.new(credential: credential)
      settings = adapter.send(:smtp_settings)

      expect(settings[:address]).to eq("smtp.example.com")
      expect(settings[:port]).to eq(587)
      expect(settings[:user_name]).to eq("user")
      expect(settings[:password]).to eq("pass")
      expect(settings[:authentication]).to eq("plain")
      expect(settings[:enable_starttls_auto]).to be true
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/services/email/adapters/smtp_spec.rb`
Expected: FAIL - class does not exist

- [ ] **Step 3: Create the adapter**

```ruby
# app/services/email/adapters/smtp.rb
# frozen_string_literal: true

require "mail"

module Email
  module Adapters
    class Smtp
      def initialize(credential:)
        @credential = credential
      end

      def deliver(message)
        mail = build_mail(message)
        mail.delivery_method(:smtp, smtp_settings)
        mail.deliver
      rescue Net::SMTPAuthenticationError, Net::SMTPServerBusy, Net::SMTPSyntaxError,
             Net::SMTPFatalError, Net::SMTPUnknownError, Net::OpenTimeout,
             Net::ReadTimeout, Errno::ECONNREFUSED => e
        raise Errors::DeliveryFailed.new("SMTP delivery failed: #{e.message}", code: e.class.name, original: e)
      end

      private

      attr_reader :credential

      def build_mail(message)
        Mail.new do |m|
          m.to message.to
          m.from message.from
          m.subject message.subject
          m.cc message.cc if message.cc.present?
          m.bcc message.bcc if message.bcc.present?
          m.reply_to message.reply_to if message.reply_to.present?

          m.text_part = Mail::Part.new do
            content_type "text/plain; charset=UTF-8"
            body message.body_text || ""
          end

          m.html_part = Mail::Part.new do
            content_type "text/html; charset=UTF-8"
            body message.body_html
          end
        end
      end

      def smtp_settings
        {
          address: credential.host,
          port: credential.port,
          user_name: credential.username,
          password: credential.password,
          authentication: credential.authentication.to_sym,
          enable_starttls_auto: credential.enable_starttls,
          ssl: credential.ssl,
          domain: credential.domain
        }.compact
      end
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec rspec spec/services/email/adapters/smtp_spec.rb`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
mkdir -p app/services/email/adapters spec/services/email/adapters
git add spec/services/email/adapters/smtp_spec.rb app/services/email/adapters/smtp.rb
git commit -m "feat(email): add SMTP adapter for email delivery"
```

---

### Task 9: Create Email::DeliveryJob

**Files:**
- Create: `spec/jobs/email/delivery_job_spec.rb`
- Create: `app/jobs/email/delivery_job.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# spec/jobs/email/delivery_job_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Email::DeliveryJob, type: :job do
  let!(:credential) { create(:email_credential, mode: "sandbox") }
  let(:message) { create(:email_message, :queued) }

  describe "#perform" do
    let(:adapter_double) { instance_double(Email::Adapters::Smtp) }

    before do
      allow(Email::CredentialResolver).to receive(:call).and_return(credential)
      allow(Email::Adapters::Smtp).to receive(:new).and_return(adapter_double)
    end

    context "when delivery succeeds" do
      it "marks message as sent" do
        allow(adapter_double).to receive(:deliver)
        
        freeze_time do
          described_class.perform_now(message.id)
          message.reload
          
          expect(message.status).to eq("sent")
          expect(message.sent_at).to eq(Time.current)
        end
      end
    end

    context "when delivery fails" do
      it "marks message as failed and re-raises" do
        error = Email::Errors::DeliveryFailed.new("SMTP error", code: "NET_ERROR")
        allow(adapter_double).to receive(:deliver).and_raise(error)

        expect { described_class.perform_now(message.id) }.to raise_error(Email::Errors::DeliveryFailed)
        
        message.reload
        expect(message.status).to eq("failed")
        expect(message.failure_code).to eq("NET_ERROR")
      end
    end

    context "when message not found" do
      it "raises ActiveRecord::RecordNotFound" do
        expect { described_class.perform_now(-1) }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end
  end

  describe "retry configuration" do
    it "retries on DeliveryFailed" do
      expect(described_class.rescue_handlers).to include(
        have_attributes(key: "Email::Errors::DeliveryFailed")
      )
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/jobs/email/delivery_job_spec.rb`
Expected: FAIL - class does not exist

- [ ] **Step 3: Create the job**

```ruby
# app/jobs/email/delivery_job.rb
# frozen_string_literal: true

module Email
  class DeliveryJob < ApplicationJob
    queue_as :default
    retry_on Errors::DeliveryFailed, wait: :polynomially_longer, attempts: 3

    def perform(email_message_id, mode: nil)
      message = EmailMessage.find(email_message_id)
      credential = CredentialResolver.call(mode: mode || CredentialResolver.default_mode)
      adapter = Adapters::Smtp.new(credential: credential)

      adapter.deliver(message)
      message.mark_sent!
    rescue Errors::DeliveryFailed => e
      message.mark_failed!(code: e.code.to_s, message: e.message)
      raise
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec rspec spec/jobs/email/delivery_job_spec.rb`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
mkdir -p app/jobs/email spec/jobs/email
git add spec/jobs/email/delivery_job_spec.rb app/jobs/email/delivery_job.rb
git commit -m "feat(email): add DeliveryJob with retry logic"
```

---

### Task 10: Create Email::Activities::Send

**Files:**
- Create: `spec/services/email/activities/send_spec.rb`
- Create: `app/services/email/activities/send.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# spec/services/email/activities/send_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Email::Activities::Send do
  let(:customer) { create(:customer) }
  let!(:template) { create(:email_template, customer: customer, key: "welcome", variables: ["name"]) }
  let!(:credential) { create(:email_credential, mode: "sandbox") }

  describe ".call" do
    let(:valid_params) do
      {
        customer: customer,
        to: "user@example.com",
        template_key: "welcome",
        vars: { name: "John" }
      }
    end

    context "with valid inputs" do
      it "creates an EmailMessage" do
        expect { described_class.call(**valid_params) }
          .to change(EmailMessage, :count).by(1)
      end

      it "returns the created message" do
        result = described_class.call(**valid_params)
        expect(result).to be_a(EmailMessage)
        expect(result.to).to eq("user@example.com")
        expect(result.status).to eq("queued")
      end

      it "renders template variables" do
        result = described_class.call(**valid_params)
        expect(result.body_html).to include("John")
      end

      it "enqueues delivery job" do
        expect {
          described_class.call(**valid_params)
        }.to have_enqueued_job(Email::DeliveryJob)
      end

      it "sets message_type to transactional" do
        result = described_class.call(**valid_params)
        expect(result.message_type).to eq("transactional")
      end
    end

    context "with idempotency_key" do
      it "returns existing message on duplicate key" do
        first = described_class.call(**valid_params, idempotency_key: "unique-123")
        second = described_class.call(**valid_params, idempotency_key: "unique-123")
        
        expect(second.id).to eq(first.id)
        expect(EmailMessage.count).to eq(1)
      end

      it "creates new message for different key" do
        first = described_class.call(**valid_params, idempotency_key: "key-1")
        second = described_class.call(**valid_params, idempotency_key: "key-2")
        
        expect(second.id).not_to eq(first.id)
      end
    end

    context "with invalid inputs" do
      it "raises TemplateVarsInvalid on contract failure" do
        expect {
          described_class.call(customer: customer, to: "", template_key: "welcome", vars: {})
        }.to raise_error(Email::Errors::TemplateVarsInvalid)
      end
    end

    context "with daily cap exceeded" do
      before do
        cfm = create(:customer_feature_module,
          customer: customer,
          feature_module: create(:feature_module, key: "email"),
          configuration: { "daily_send_cap" => 2 }.to_json
        )
        2.times { create(:email_message, customer: customer) }
      end

      it "raises DailyCapExceeded" do
        expect {
          described_class.call(**valid_params)
        }.to raise_error(Email::Errors::DailyCapExceeded)
      end
    end

    context "with optional fields" do
      it "sets cc, bcc, reply_to when provided" do
        result = described_class.call(
          **valid_params,
          cc: "cc@example.com",
          bcc: "bcc@example.com",
          reply_to: "reply@example.com"
        )
        expect(result.cc).to eq("cc@example.com")
        expect(result.bcc).to eq("bcc@example.com")
        expect(result.reply_to).to eq("reply@example.com")
      end
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/services/email/activities/send_spec.rb`
Expected: FAIL - class does not exist

- [ ] **Step 3: Create the activity**

```ruby
# app/services/email/activities/send.rb
# frozen_string_literal: true

require "ostruct"

module Email
  module Activities
    class Send
      DEFAULT_DAILY_CAP = 1_000

      class << self
        def call(customer:, to:, template_key:, vars:, cc: nil, bcc: nil, reply_to: nil, idempotency_key: nil, mode: nil)
          # 1. Validate contract
          contract = Contracts::Send.new(OpenStruct.new)
          unless contract.validate(customer_id: customer.id, to: to, template_key: template_key, vars: vars)
            raise Errors::TemplateVarsInvalid, contract.errors.full_messages.to_sentence
          end

          # 2. Check idempotency
          if idempotency_key.present?
            existing = EmailMessage.find_by(customer_id: customer.id, idempotency_key: idempotency_key)
            return existing if existing
          end

          # 3. Check daily cap
          check_daily_cap!(customer)

          # 4. Render template
          template = contract.template
          rendered = TemplateRenderer.render(template: template, vars: vars)

          # 5. Resolve from address
          credential = CredentialResolver.call(mode: mode || CredentialResolver.default_mode)
          from_address = credential.username

          # 6. Create message
          message = EmailMessage.create!(
            customer: customer,
            email_template: template,
            to: to,
            from: from_address,
            cc: cc,
            bcc: bcc,
            reply_to: reply_to,
            subject: rendered[:subject],
            body_html: rendered[:body_html],
            body_text: rendered[:body_text],
            status: "queued",
            message_type: "transactional",
            idempotency_key: idempotency_key
          )

          # 7. Enqueue delivery
          DeliveryJob.perform_later(message.id, mode: mode)

          message
        end

        private

        def check_daily_cap!(customer)
          cap = daily_cap_for(customer)
          count = EmailMessage.where(customer_id: customer.id)
                              .where(created_at: Time.zone.now.beginning_of_day..)
                              .count
          raise Errors::DailyCapExceeded, "customer #{customer.id} exceeded daily cap of #{cap}" if count >= cap
        end

        def daily_cap_for(customer)
          cfm = CustomerFeatureModule.joins(:feature_module)
                                     .where(customer_id: customer.id, feature_modules: { key: "email" })
                                     .first
          return DEFAULT_DAILY_CAP unless cfm

          config = cfm.configuration
          parsed = config.is_a?(String) ? (JSON.parse(config) rescue {}) : (config || {})
          cap = parsed["daily_send_cap"]
          cap.present? ? cap.to_i : DEFAULT_DAILY_CAP
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec rspec spec/services/email/activities/send_spec.rb`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
mkdir -p app/services/email/activities spec/services/email/activities
git add spec/services/email/activities/send_spec.rb app/services/email/activities/send.rb
git commit -m "feat(email): add Send activity with daily cap and idempotency"
```

---

### Task 11: Create Email::Gateway

**Files:**
- Create: `spec/services/email/gateway_spec.rb`
- Create: `app/services/email/gateway.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# spec/services/email/gateway_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Email::Gateway do
  let(:customer) { create(:customer) }
  let!(:template) { create(:email_template, customer: customer, key: "welcome", variables: ["name"]) }
  let!(:credential) { create(:email_credential, mode: "sandbox") }

  describe ".send" do
    it "delegates to Activities::Send" do
      expect(Email::Activities::Send).to receive(:call).with(
        customer: customer,
        to: "user@example.com",
        template_key: "welcome",
        vars: { name: "John" },
        cc: nil,
        bcc: nil,
        reply_to: nil,
        idempotency_key: nil,
        mode: nil
      ).and_call_original

      described_class.send(
        customer: customer,
        to: "user@example.com",
        template_key: "welcome",
        vars: { name: "John" }
      )
    end
  end

  describe ".send_raw" do
    it "creates message without template" do
      result = described_class.send_raw(
        customer: customer,
        to: "user@example.com",
        subject: "Direct Subject",
        body_html: "<p>Direct body</p>"
      )

      expect(result).to be_a(EmailMessage)
      expect(result.subject).to eq("Direct Subject")
      expect(result.email_template_id).to be_nil
      expect(result.status).to eq("queued")
    end

    it "enqueues delivery job" do
      expect {
        described_class.send_raw(
          customer: customer,
          to: "user@example.com",
          subject: "Test",
          body_html: "<p>Test</p>"
        )
      }.to have_enqueued_job(Email::DeliveryJob)
    end
  end

  describe ".queue_for_campaign" do
    let(:campaign) { create(:email_campaign, customer: customer, email_template: template) }
    let(:subscriber) { create(:email_subscriber, customer: customer, email: "sub@example.com", first_name: "Jane") }

    it "creates message with campaign metadata" do
      result = described_class.queue_for_campaign(campaign: campaign, subscriber: subscriber)

      expect(result.message_type).to eq("campaign")
      expect(result.metadata["campaign_id"]).to eq(campaign.id)
      expect(result.metadata["subscriber_id"]).to eq(subscriber.id)
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/services/email/gateway_spec.rb`
Expected: FAIL - class does not exist (some tests will fail due to missing EmailCampaign/EmailSubscriber - skip those for now)

- [ ] **Step 3: Create the gateway**

```ruby
# app/services/email/gateway.rb
# frozen_string_literal: true

module Email
  class Gateway
    class << self
      def send(customer:, to:, template_key:, vars:, cc: nil, bcc: nil, reply_to: nil, idempotency_key: nil, mode: nil)
        Activities::Send.call(
          customer: customer,
          to: to,
          template_key: template_key,
          vars: vars,
          cc: cc,
          bcc: bcc,
          reply_to: reply_to,
          idempotency_key: idempotency_key,
          mode: mode
        )
      end

      def send_raw(customer:, to:, subject:, body_html:, body_text: nil, cc: nil, bcc: nil, from: nil, reply_to: nil, idempotency_key: nil, mode: nil)
        check_idempotency(customer, idempotency_key) do |existing|
          return existing if existing
        end

        credential = CredentialResolver.call(mode: mode || CredentialResolver.default_mode)
        from_address = from || credential.username

        message = EmailMessage.create!(
          customer: customer,
          to: to,
          from: from_address,
          cc: cc,
          bcc: bcc,
          reply_to: reply_to,
          subject: subject,
          body_html: body_html,
          body_text: body_text || TemplateRenderer.strip_html(body_html),
          status: "queued",
          message_type: "transactional",
          idempotency_key: idempotency_key
        )

        DeliveryJob.perform_later(message.id, mode: mode)
        message
      end

      def queue_for_campaign(campaign:, subscriber:)
        template = campaign.email_template
        vars = build_subscriber_vars(subscriber)
        rendered = TemplateRenderer.render(template: template, vars: vars)

        credential = CredentialResolver.call(mode: CredentialResolver.default_mode)

        message = EmailMessage.create!(
          customer: campaign.customer,
          email_template: template,
          to: subscriber.email,
          from: credential.username,
          subject: rendered[:subject],
          body_html: rendered[:body_html],
          body_text: rendered[:body_text],
          status: "queued",
          message_type: "campaign",
          metadata: { campaign_id: campaign.id, subscriber_id: subscriber.id }
        )

        DeliveryJob.perform_later(message.id)
        message
      end

      private

      def check_idempotency(customer, key)
        return unless key.present?
        existing = EmailMessage.find_by(customer_id: customer.id, idempotency_key: key)
        yield existing if block_given?
      end

      def build_subscriber_vars(subscriber)
        {
          email: subscriber.email,
          first_name: subscriber.first_name,
          last_name: subscriber.last_name
        }.merge(subscriber.attributes.symbolize_keys)
      end
    end
  end
end
```

- [ ] **Step 4: Run applicable tests**

Run: `bundle exec rspec spec/services/email/gateway_spec.rb -e "send" -e "send_raw"`
Expected: Tests for .send and .send_raw PASS (queue_for_campaign will fail until Phase 2)

- [ ] **Step 5: Commit**

```bash
git add spec/services/email/gateway_spec.rb app/services/email/gateway.rb
git commit -m "feat(email): add Gateway as public entry point"
```

---

### Task 12: Run Full Test Suite and Final Commit

- [ ] **Step 1: Run all email specs**

Run: `bundle exec rspec spec/models/email_*.rb spec/services/email/ spec/jobs/email/`
Expected: All tests PASS (except gateway campaign tests)

- [ ] **Step 2: Final commit for Phase 1**

```bash
git add -A
git commit -m "feat(email): complete Phase 1 - core infrastructure

- EmailCredential, EmailTemplate, EmailMessage models
- Email::Gateway, CredentialResolver, TemplateRenderer services
- Email::Adapters::Smtp for SMTP delivery
- Email::Activities::Send with daily cap and idempotency
- Email::DeliveryJob with retry logic
- Full test coverage for all components"
```

---

## Phase 1 Complete

Phase 1 delivers the core email infrastructure. Next phases:
- **Phase 2:** Email Campaigns module (subscribers, lists, campaigns)
- **Phase 3:** Admin UI and controllers
- **Phase 4:** Rich editors (GrapesJS, Trix)
- **Phase 5:** Flowchart integration
