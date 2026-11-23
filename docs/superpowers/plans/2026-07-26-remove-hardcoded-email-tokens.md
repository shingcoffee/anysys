# Remove Hard-Coded Email Template Tokens Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove static hard-coded model email tokens (`email`, `first_name`, `last_name`, `full_name`, `customer.name`, `customer.id`) so that email tokens derive dynamically from Platform Module Settings and Customer Entity Attributes, while retaining `unsubscribe_url` as a built-in system token.

**Architecture:** Update `Emails::PlatformTokenSeeds` to only seed `unsubscribe_url` and purge legacy hard-coded seeds. Update `Emails::VariableContext` to expose attribute structures (`authentication_user`, `customer`) so dynamic model tokens enabled in Platform Module Settings resolve seamlessly when rendering email templates.

**Tech Stack:** Ruby 3.2.8, Rails 8.1.2, RSpec, ActiveRecord

## Global Constraints

- Ruby v3.2.8 and Rails v8.1.2 conventions
- All user-facing strings must be localized with I18n
- No auto-commits; stage changes with `git add`
- Ensure all updated specs pass cleanly

---

### Task 1: Update Platform Token Seeds Service

**Files:**
- Modify: `app/services/emails/platform_token_seeds.rb:8-33`
- Test: `spec/services/emails/variable_context_spec.rb`

**Interfaces:**
- Consumes: `Emails::TemplateToken` model
- Produces: `Emails::PlatformTokenSeeds.ensure!` seeding only `unsubscribe_url` and removing legacy platform seeds.

- [ ] **Step 1: Write the failing test**

Edit `spec/services/emails/variable_context_spec.rb`:
```ruby
# frozen_string_literal: true

require "rails_helper"
require "cgi"

RSpec.describe Emails::VariableContext do
  it "builds a symbol-keyed hash with authentication_user, customer, and unsubscribe_url" do
    customer = create(:customer)
    user = create(:user, customer: customer, first_name: "Ada", last_name: "L", email: "ada@x.com")
    vars = described_class.for(user: user)

    expect(vars[:authentication_user][:email]).to eq("ada@x.com")
    expect(vars[:authentication_user][:first_name]).to eq("Ada")
    expect(vars[:customer][:name]).to eq(customer.name)

    expect(vars[:unsubscribe_url]).to match(%r{/unsubscribe/.+\z})
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/services/emails/variable_context_spec.rb`
Expected: FAIL with `undefined method '[]' for nil:NilClass` (since `vars[:authentication_user]` is nil)

- [ ] **Step 3: Update `Emails::PlatformTokenSeeds` and `Emails::VariableContext`**

In `app/services/emails/platform_token_seeds.rb`:
```ruby
# frozen_string_literal: true

module Emails
  class PlatformTokenSeeds
    ROWS = [
      { source_key: "unsubscribe_url", label: "unsubscribe_url" }
    ].freeze

    LEGACY_KEYS = %w[email first_name last_name full_name customer.name customer.id].freeze

    def self.ensure!
      ROWS.each do |row|
        TemplateToken.find_or_create_by!(
          source_type: TemplateToken::SOURCE_PLATFORM,
          source_key: row[:source_key]
        ) do |token|
          token.customer_id = nil
          token.label = row[:label]
          token.entity_id = nil
          token.attribute_slug = nil
        end
      end

      # Purge legacy hard-coded seeds so tokens come dynamically from module/entity settings
      TemplateToken.platform.where(source_key: LEGACY_KEYS).destroy_all
    end
  end
end
```

In `app/services/emails/variable_context.rb`:
```ruby
# frozen_string_literal: true

module Emails
  class VariableContext
    def self.for(user:)
      new(user).to_h
    end

    def initialize(user)
      @user = user
    end

    def to_h
      {
        authentication_user: @user.attributes.symbolize_keys,
        customer:            @user.customer&.attributes&.symbolize_keys || {},
        unsubscribe_url:     unsubscribe_url
      }
    end

    private

    def unsubscribe_url
      Emails::SendActivities::SendActivityUnsubscribe.url_for(@user)
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec rspec spec/services/emails/variable_context_spec.rb`
Expected: PASS

- [ ] **Step 5: Stage changes**

```bash
git add app/services/emails/platform_token_seeds.rb app/services/emails/variable_context.rb spec/services/emails/variable_context_spec.rb
```

---

### Task 2: Verify Template Renderer with Dynamic Model Attribute Tokens

**Files:**
- Modify/Test: `spec/services/emails/template_renderer_spec.rb`

**Interfaces:**
- Consumes: `Emails::TemplateRenderer.render`
- Produces: Correct interpolation of dynamic tokens (e.g. `authentication_user.email`) toggled in Platform Module Settings.

- [ ] **Step 1: Write/Update the test in `spec/services/emails/template_renderer_spec.rb`**

Add an example verifying that a `platform_field` token with `source_key: "authentication_user.email"` interpolates user email correctly:
```ruby
    it "interpolates dynamic module model attribute tokens" do
      token = Emails::TemplateToken.find_or_create_by!(
        source_type: Emails::TemplateToken::SOURCE_PLATFORM,
        source_key: "authentication_user.email"
      ) { |t| t.label = "User.email" }

      template = create(:email_template, subject: "Hello {{#{token.uuid}}}", body_html: "<p>Email: {{#{token.uuid}}}</p>")
      user = create(:user, email: "user@example.com")
      vars = Emails::VariableContext.for(user: user)

      res = described_class.render(template: template, vars: vars)
      expect(res[:subject]).to eq("Hello user@example.com")
      expect(res[:body_html]).to include("user@example.com")
    end
```

- [ ] **Step 2: Run test suite**

Run: `bundle exec rspec spec/services/emails/template_renderer_spec.rb spec/services/emails/token_catalog_spec.rb`
Expected: PASS

- [ ] **Step 3: Run seed task and full email spec suite to verify no regressions**

Run: `bin/rails db:seed && bundle exec rspec spec/services/emails/`
Expected: PASS

- [ ] **Step 4: Stage changes**

```bash
git add spec/services/emails/template_renderer_spec.rb
```
