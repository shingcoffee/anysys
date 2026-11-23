# Email Module Design Specification

**Date:** 2026-05-05  
**Status:** Approved  
**Scope:** Transactional and marketing email system with rich editing features

## Overview

A comprehensive email module following the existing SMS module pattern. Consists of two feature modules:

1. **Email** (core) - Template management, message sending/tracking, SMTP delivery, replaces FlowchartMailer
2. **EmailCampaigns** - Subscriber management, lists/segments, campaign scheduling

## Requirements Summary

- Platform-level SMTP credentials (generic SMTP, provider-agnostic)
- Email templates with three editor modes: code, rich text, drag-and-drop (GrapesJS)
- Subscriber management with tags and attribute-based segmentation
- Campaign scheduling: immediate, scheduled, recurring with timezone support
- Basic delivery tracking (sent, delivered, bounced, failed)
- Daily sending cap per customer
- Flowchart integration (replaces FlowchartMailer)

---

## Data Models

### Email Module (Core)

#### EmailCredential

Platform-level SMTP configuration (no customer_id).

| Field | Type | Constraints |
|-------|------|-------------|
| host | string | required |
| port | integer | required, default: 587 |
| username | string | required |
| password | text | required, encrypted |
| domain | string | optional, for HELO |
| authentication | string | enum: plain/login/cram_md5, default: plain |
| enable_starttls | boolean | default: true |
| ssl | boolean | default: false |
| mode | string | enum: sandbox/production, unique |
| status | string | enum: active/disabled, default: active |
| daily_limit | integer | optional, platform-wide cap |

#### EmailTemplate

Tenant-scoped email templates.

| Field | Type | Constraints |
|-------|------|-------------|
| customer_id | integer | required, indexed |
| key | string | required, unique per customer |
| name | string | required |
| subject | string | required, supports {{variable}} |
| body_html | text | required |
| body_text | text | optional, auto-generated if blank |
| template_type | string | enum: transactional/marketing |
| editor_type | string | enum: code/rich_text/builder |
| builder_data | json | GrapesJS state, default: {} |
| variables | json | array of variable names, default: [] |
| status | string | enum: draft/active/retired, default: draft |

Indexes: `[customer_id, key]` unique, `[customer_id, template_type]`

#### EmailMessage

Every sent email tracked.

| Field | Type | Constraints |
|-------|------|-------------|
| customer_id | integer | required, indexed |
| email_template_id | integer | optional, references EmailTemplate |
| to | string | required |
| cc | string | optional |
| bcc | string | optional |
| from | string | required |
| reply_to | string | optional |
| subject | string | required |
| body_html | text | required |
| body_text | text | optional |
| status | string | enum: pending/queued/sent/delivered/bounced/failed, default: pending |
| message_type | string | enum: transactional/campaign |
| scheduled_at | datetime | optional |
| sent_at | datetime | optional |
| delivered_at | datetime | optional |
| failure_code | string | optional |
| failure_message | string | optional |
| idempotency_key | string | optional, unique per customer |
| metadata | json | campaign_id, subscriber_id, etc., default: {} |

Indexes: `[customer_id, created_at]`, `[customer_id, idempotency_key]` unique where not null, `[customer_id, status]`, `[email_template_id]`

### Email Campaigns Module

#### EmailSubscriber

| Field | Type | Constraints |
|-------|------|-------------|
| customer_id | integer | required, indexed |
| email | string | required, unique per customer |
| first_name | string | optional |
| last_name | string | optional |
| status | string | enum: active/unsubscribed/bounced/complained, default: active |
| tags | json | array of strings, default: [] |
| attributes | json | custom fields, default: {} |
| subscribed_at | datetime | required |
| unsubscribed_at | datetime | optional |
| unsubscribe_token | string | required, unique |

Indexes: `[customer_id, email]` unique, `[customer_id, status]`, `[unsubscribe_token]` unique

#### EmailList

| Field | Type | Constraints |
|-------|------|-------------|
| customer_id | integer | required, indexed |
| name | string | required |
| description | text | optional |
| list_type | string | enum: static/dynamic |
| segment_rules | json | for dynamic lists, default: {} |
| status | string | enum: active/archived, default: active |

#### EmailListSubscriber

Join table for static lists.

| Field | Type | Constraints |
|-------|------|-------------|
| email_list_id | integer | required |
| email_subscriber_id | integer | required |

Indexes: `[email_list_id, email_subscriber_id]` unique

#### EmailCampaign

| Field | Type | Constraints |
|-------|------|-------------|
| customer_id | integer | required, indexed |
| email_template_id | integer | required |
| email_list_id | integer | required |
| name | string | required |
| status | string | enum: draft/scheduled/sending/sent/paused/cancelled, default: draft |
| scheduled_at | datetime | optional |
| started_at | datetime | optional |
| completed_at | datetime | optional |
| recurrence_rule | string | iCal RRULE format, optional |
| timezone | string | IANA timezone, default: UTC |
| stats | json | sent/delivered/bounced/failed counts, default: {} |

Indexes: `[customer_id, status]`, `[status, scheduled_at]` for scheduler queries

---

## Service Architecture

### Email Module Services

```
app/services/email/
├── gateway.rb                 # Public entry point
├── credential_resolver.rb     # Selects credential by mode
├── template_renderer.rb       # Variable interpolation
├── errors.rb                  # Error classes
├── adapters/
│   └── smtp.rb               # SMTP delivery via Mail gem
├── activities/
│   └── send.rb               # Trailblazer activity for sending
└── contracts/
    └── send_contract.rb      # Input validation
```

#### Email::Gateway

```ruby
module Email
  class Gateway
    class << self
      # Send using a template
      def send(customer:, to:, template_key:, vars:, cc: nil, bcc: nil, reply_to: nil, idempotency_key: nil, mode: nil)
      
      # Send raw email (no template)
      def send_raw(customer:, to:, subject:, body_html:, body_text: nil, cc: nil, bcc: nil, from: nil, reply_to: nil, idempotency_key: nil, mode: nil)
      
      # Queue for campaign delivery
      def queue_for_campaign(campaign:, subscriber:)
    end
  end
end
```

#### Email::Activities::Send

Trailblazer activity flow:
1. Validate inputs via contract
2. Check idempotency (return existing if duplicate)
3. Resolve template if template_key provided
4. Check daily cap for customer
5. Render template with variables
6. Create EmailMessage (status: queued)
7. Enqueue Email::DeliveryJob
8. Return success with message_id

#### Email::DeliveryJob

ActiveJob for async delivery:
- Fetches EmailMessage by ID
- Delivers via Email::Adapters::Smtp
- Updates status to sent/failed
- Retries on transient failures (3 attempts, exponential backoff)

#### Email::TemplateRenderer

- Interpolates `{{variable}}` in subject and body
- Supports `ctx.field` references for flowchart compatibility
- Auto-generates body_text from body_html using ActionView::Base.full_sanitizer

### Email Campaigns Services

```
app/services/email_campaigns/
├── campaign_sender.rb         # Orchestrates campaign delivery
├── scheduler_job.rb           # Periodic job for scheduled campaigns
├── segment_evaluator.rb       # Dynamic list rule evaluation
└── unsubscribe_handler.rb     # Process unsubscribe requests
```

#### EmailCampaigns::CampaignSender

1. Load campaign, template, list
2. Resolve subscribers (static: join table, dynamic: SegmentEvaluator)
3. Filter out unsubscribed/bounced
4. For each subscriber:
   - Create EmailMessage with metadata (campaign_id, subscriber_id)
   - Enqueue via Email::Gateway.queue_for_campaign
5. Update campaign stats incrementally
6. Mark campaign as sent when complete

#### EmailCampaigns::SchedulerJob

Runs every minute via SolidQueue recurring job:
1. Find campaigns: status=scheduled AND scheduled_at <= now
2. For each: update status to sending, trigger CampaignSender
3. Handle recurring: parse RRULE, calculate next occurrence, create new scheduled campaign

#### EmailCampaigns::SegmentEvaluator

Evaluates rules against EmailSubscriber:
```ruby
# Example rules structure
{
  "match": "all", # or "any"
  "conditions": [
    { "field": "tags", "operator": "contains", "value": "premium" },
    { "field": "attributes.plan", "operator": "equals", "value": "enterprise" },
    { "field": "subscribed_at", "operator": "after", "value": "2026-01-01" }
  ]
}
```

Supported operators: equals, not_equals, contains, not_contains, greater_than, less_than, after, before, is_blank, is_present

---

## Feature Module Registrations

### FeatureModules::Email::Registration

```ruby
module FeatureModules
  module Email
    class Registration < FeatureModules::BaseModule
      def self.module_key         = "email"
      def self.module_name        = "Email"
      def self.module_description = "Transactional and marketing email delivery"

      required! # Auto-enabled for all customers

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
    end
  end
end
```

### FeatureModules::EmailCampaigns::Registration

```ruby
module FeatureModules
  module EmailCampaigns
    class Registration < FeatureModules::BaseModule
      def self.module_key         = "email_campaigns"
      def self.module_name        = "Email Campaigns"
      def self.module_description = "Marketing campaigns with subscribers, lists, and scheduling"

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
    end
  end
end
```

---

## Routes

```ruby
# config/routes.rb additions

# Email module
scope "/:customer_id/email" do
  namespace :admin do
    resources :templates, except: [:show]
    resources :messages, only: [:index, :show]
  end
end

# Email Campaigns module
scope "/:customer_id/email_campaigns" do
  namespace :admin do
    resources :subscribers
    resources :lists
    resources :campaigns do
      member do
        post :send_now
        post :pause
        post :resume
        post :cancel
        post :test_send
      end
    end
  end
end

# Public unsubscribe (no auth required)
get "/unsubscribe/:token", to: "email_campaigns/unsubscribes#show", as: :email_unsubscribe
post "/unsubscribe/:token", to: "email_campaigns/unsubscribes#create"
```

---

## UI Components (ViewComponent)

### Email Module Components

```
app/components/email/
├── templates_table_component.rb
├── template_form_component.rb
├── template_editor_component.rb       # Wraps all editor modes
├── code_editor_component.rb           # Monaco/CodeMirror
├── rich_text_editor_component.rb      # Trix/TipTap
├── builder_editor_component.rb        # GrapesJS wrapper
├── variable_helper_component.rb       # Variable insertion dropdown
├── preview_component.rb               # Email preview pane
├── messages_table_component.rb
├── message_detail_component.rb
└── status_badge_component.rb
```

### Email Campaigns Components

```
app/components/email_campaigns/
├── subscribers_table_component.rb
├── subscriber_form_component.rb
├── subscriber_import_component.rb     # CSV import
├── tags_input_component.rb
├── lists_table_component.rb
├── list_form_component.rb
├── segment_builder_component.rb       # Dynamic list rules UI
├── campaigns_table_component.rb
├── campaign_form_component.rb
├── campaign_wizard_component.rb       # Step-by-step campaign creation
├── schedule_picker_component.rb       # Date/time/timezone/recurrence
├── recurrence_builder_component.rb    # RRULE UI
├── campaign_stats_component.rb
└── unsubscribe_page_component.rb
```

---

## Stimulus Controllers

```
app/javascript/controllers/
├── email_code_editor_controller.js     # Monaco/CodeMirror integration
├── email_rich_text_controller.js       # Rich text editor
├── email_builder_controller.js         # GrapesJS integration
├── email_preview_controller.js         # Live preview
├── email_variable_insert_controller.js # Insert variable at cursor
├── email_test_send_controller.js       # Test send modal
├── segment_builder_controller.js       # Add/remove conditions
├── tags_input_controller.js            # Tag autocomplete/management
├── schedule_picker_controller.js       # Datetime + timezone
├── recurrence_builder_controller.js    # RRULE building
├── csv_import_controller.js            # File upload + mapping
└── campaign_actions_controller.js      # Send/pause/resume/cancel
```

---

## GrapesJS Integration

### Setup

Add GrapesJS via importmap or npm:
```javascript
// app/javascript/controllers/email_builder_controller.js
import { Controller } from "@hotwired/stimulus"
import grapesjs from "grapesjs"
import gjsPresetNewsletter from "grapesjs-preset-newsletter"

export default class extends Controller {
  static targets = ["canvas", "builderData"]
  static values = { data: Object }

  connect() {
    this.editor = grapesjs.init({
      container: this.canvasTarget,
      plugins: [gjsPresetNewsletter],
      pluginsOpts: {
        [gjsPresetNewsletter]: { /* options */ }
      },
      storageManager: false,
      // Load existing data
      components: this.dataValue.components || '',
      style: this.dataValue.styles || ''
    })

    // Save on change
    this.editor.on('change:changesCount', () => this.save())
  }

  save() {
    const data = {
      html: this.editor.getHtml(),
      css: this.editor.getCss(),
      components: this.editor.getComponents(),
      styles: this.editor.getStyle()
    }
    this.builderDataTarget.value = JSON.stringify(data)
  }
}
```

### Email Blocks

Pre-configured blocks for email:
- Header (logo + navigation)
- Text block (paragraph with formatting)
- Image (with alt text, link)
- Button (CTA with link)
- Divider (horizontal line)
- Columns (2/3 column layouts)
- Footer (unsubscribe link, address)
- Social icons

---

## Flowchart Integration

### Migration from FlowchartMailer

1. FlowchartMailer.configured_email becomes Email::Gateway.send
2. Same context interpolation patterns supported
3. Flowchart email steps reference EmailTemplate by key

### Flowchart Step Configuration

```ruby
# In flowchart step configuration
{
  type: "email",
  template_key: "welcome_email",
  to: "ctx.user_email",
  vars: {
    first_name: "ctx.first_name",
    order_number: "ctx.order_number"
  }
}
```

### Activity Step Integration

```ruby
# app/services/flowchart_runtime/steps/email_step.rb
module FlowchartRuntime
  module Steps
    class EmailStep
      def self.call(config, ctx, customer:)
        result = Email::Gateway.send(
          customer: customer,
          to: resolve_field(config[:to], ctx),
          template_key: config[:template_key],
          vars: resolve_vars(config[:vars], ctx),
          cc: resolve_field(config[:cc], ctx),
          bcc: resolve_field(config[:bcc], ctx),
          reply_to: resolve_field(config[:reply_to], ctx),
          idempotency_key: config[:idempotency_key]
        )
        
        { message_id: result[:message_id], status: result[:status] }
      end
    end
  end
end
```

---

## Jobs Configuration

### SolidQueue Recurring Jobs

```yaml
# config/recurring.yml
email_campaign_scheduler:
  class: EmailCampaigns::SchedulerJob
  schedule: every minute
  queue: default
```

### Job Classes

```ruby
# app/jobs/email/delivery_job.rb
module Email
  class DeliveryJob < ApplicationJob
    queue_as :default
    retry_on Net::SMTPError, wait: :polynomially_longer, attempts: 3

    def perform(email_message_id)
      message = EmailMessage.find(email_message_id)
      Email::Adapters::Smtp.deliver(message)
      message.update!(status: "sent", sent_at: Time.current)
    rescue => e
      message.update!(status: "failed", failure_code: e.class.name, failure_message: e.message)
      raise
    end
  end
end

# app/jobs/email_campaigns/scheduler_job.rb
module EmailCampaigns
  class SchedulerJob < ApplicationJob
    queue_as :default

    def perform
      EmailCampaign
        .where(status: "scheduled")
        .where("scheduled_at <= ?", Time.current)
        .find_each do |campaign|
          campaign.update!(status: "sending", started_at: Time.current)
          CampaignSender.call(campaign)
        end
    end
  end
end
```

---

## Error Handling

### Email::Errors

```ruby
module Email
  module Errors
    class Error              < StandardError; end
    class CredentialsMissing < Error; end
    class TemplateNotFound   < Error; end
    class TemplateVarsInvalid < Error; end
    class DailyCapExceeded   < Error; end
    class InvalidRecipient   < Error; end
    class DeliveryFailed     < Error
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

---

## Testing Strategy

### Model Specs
- Validations, scopes, associations
- Status transitions
- Encryption for credentials

### Service Specs
- Email::Gateway.send with various inputs
- Email::TemplateRenderer interpolation
- EmailCampaigns::SegmentEvaluator rule matching
- EmailCampaigns::CampaignSender full flow

### Request Specs
- All controller actions
- Authorization (tenant isolation)
- Unsubscribe flow

### Component Specs
- All ViewComponents render correctly
- Editor components handle different modes

### System Specs
- Template creation with each editor type
- Campaign creation wizard flow
- Subscriber import

### Job Specs
- DeliveryJob success/failure paths
- SchedulerJob finds and processes due campaigns

---

## File Structure Summary

```
app/
├── components/
│   ├── email/
│   └── email_campaigns/
├── controllers/
│   ├── email/
│   │   └── admin/
│   │       ├── templates_controller.rb
│   │       └── messages_controller.rb
│   └── email_campaigns/
│       ├── admin/
│       │   ├── subscribers_controller.rb
│       │   ├── lists_controller.rb
│       │   └── campaigns_controller.rb
│       └── unsubscribes_controller.rb
├── jobs/
│   ├── email/
│   │   └── delivery_job.rb
│   └── email_campaigns/
│       └── scheduler_job.rb
├── models/
│   ├── email_credential.rb
│   ├── email_template.rb
│   ├── email_message.rb
│   ├── email_subscriber.rb
│   ├── email_list.rb
│   ├── email_list_subscriber.rb
│   └── email_campaign.rb
├── services/
│   ├── email/
│   │   ├── gateway.rb
│   │   ├── credential_resolver.rb
│   │   ├── template_renderer.rb
│   │   ├── errors.rb
│   │   ├── adapters/
│   │   │   └── smtp.rb
│   │   ├── activities/
│   │   │   └── send.rb
│   │   └── contracts/
│   │       └── send_contract.rb
│   ├── email_campaigns/
│   │   ├── campaign_sender.rb
│   │   ├── scheduler_job.rb
│   │   ├── segment_evaluator.rb
│   │   └── unsubscribe_handler.rb
│   └── feature_modules/
│       ├── email/
│       │   ├── registration.rb
│       │   └── provisioner.rb
│       └── email_campaigns/
│           ├── registration.rb
│           └── provisioner.rb
├── views/
│   ├── email/
│   │   └── admin/
│   │       ├── templates/
│   │       └── messages/
│   └── email_campaigns/
│       ├── admin/
│       │   ├── subscribers/
│       │   ├── lists/
│       │   └── campaigns/
│       └── unsubscribes/
└── javascript/
    └── controllers/
        ├── email_*.js
        └── *_controller.js
```

---

## Migration Plan

### Phase 1: Core Email Module
1. Database migrations for EmailCredential, EmailTemplate, EmailMessage
2. Email services (Gateway, Adapters, Activities)
3. Feature module registration
4. Admin UI for templates and messages
5. Basic Stimulus controllers

### Phase 2: Email Campaigns Module
1. Database migrations for subscribers, lists, campaigns
2. Campaign services (CampaignSender, SegmentEvaluator, SchedulerJob)
3. Feature module registration
4. Admin UI for subscribers, lists, campaigns

### Phase 3: Rich Editors
1. GrapesJS integration for drag-and-drop builder
2. Rich text editor (Trix/TipTap)
3. Code editor with syntax highlighting

### Phase 4: Flowchart Integration
1. Update flowchart email step to use Email::Gateway
2. Deprecate FlowchartMailer
3. Migration guide for existing flowcharts

### Phase 5: Polish
1. CSV import for subscribers
2. Campaign wizard refinement
3. Comprehensive test coverage
