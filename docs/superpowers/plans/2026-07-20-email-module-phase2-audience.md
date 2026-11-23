# Email Module Phase 2 — Audience Hub: Contacts, Tags, Segments, Lists, Signup Forms

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` or `superpowers:executing-plans`. Depends on Phase 1 plan.

**Goal:** Build a professional audience management area with contacts, tags, reusable segments, refactored lists, and embeddable signup forms.

**Architecture:** Contacts are existing `Authentication::User` records. Tags are a tenant-scoped tag model with polymorphic taggings. Segments are first-class saved queries reused by lists and campaigns. Lists become static (explicit memberships) or dynamic (segment-backed). Signup forms create/update users and apply tags via a public endpoint.

**Tech Stack:** Ruby 3.2.8, Rails 8.1.2, TailwindCSS, StimulusJS, ViewComponent, RSpec.

## Global Constraints

- All user-facing strings I18n in `en` and `zh-CN`.
- TailwindCSS only; StimulusJS only.
- Admin routes require admin/owner; public signup forms are open.
- Cross-tenant scoping enforced.

---

## File Structure

| File | Responsibility |
|---|---|
| `app/models/emails/audience/tag.rb` | Tenant-scoped tag. |
| `app/models/emails/audience/tagging.rb` | Polymorphic join between tag and contact/list/etc. |
| `app/models/emails/audience/segment.rb` | Saved segment with rules JSON and cached match count. |
| `app/models/emails/audience/list_membership.rb` | Static list membership. |
| `app/services/emails/audience/refresh_segment_counts.rb` | Recompute segment match counts. |
| `app/jobs/emails/audience/refresh_segment_counts_job.rb` | Background refresh. |
| `app/services/emails/audience/signup_form_handler.rb` | Process public signup form submissions. |
| `app/controllers/admin/modules/emails/contacts_controller.rb` | Contact index/show. |
| `app/controllers/admin/modules/emails/tags_controller.rb` | Tag CRUD. |
| `app/controllers/admin/modules/emails/segments_controller.rb` | Segment CRUD + builder. |
| `app/controllers/admin/modules/emails/lists_controller.rb` | Refactored list CRUD with type/segment. |
| `app/controllers/admin/modules/emails/signup_forms_controller.rb` | Signup form CRUD. |
| `app/controllers/emails/signup_forms_controller.rb` | Public subscribe endpoint. |
| `app/components/emails/segment_builder_component.rb` | Reuse/extend existing segment builder. |
| `db/migrate/20260721000000_create_email_audience_tables.rb` | Tables for tags, taggings, segments, list_memberships, signup_forms. |
| `db/migrate/20260721000001_add_list_type_and_segment_id_to_email_lists.rb` | Modify email_lists. |
| `config/locales/admin_modules.en.yml` / `.zh-CN.yml` | New audience UI keys. |

---

## Task 1: Create audience tables

**Files:**
- Create: `db/migrate/20260721000000_create_email_audience_tables.rb`

- [ ] **Step 1: Write migration**

```ruby
class CreateEmailAudienceTables < ActiveRecord::Migration[8.1]
  def change
    create_table :email_tags do |t|
      t.references :customer, null: false, foreign_key: true
      t.string :name, null: false
      t.string :color, null: false, default: "#6366f1"
      t.timestamps
    end
    add_index :email_tags, %i[customer_id name], unique: true

    create_table :email_taggings do |t|
      t.references :tag, null: false, foreign_key: { to_table: :email_tags }
      t.references :taggable, polymorphic: true, null: false
      t.timestamps
    end
    add_index :email_taggings, %i[taggable_type taggable_id]

    create_table :email_segments do |t|
      t.references :customer, null: false, foreign_key: true
      t.string :name, null: false
      t.json :rules, null: false, default: {}
      t.integer :match_count, null: false, default: 0
      t.datetime :match_count_refreshed_at
      t.timestamps
    end
    add_index :email_segments, %i[customer_id name], unique: true

    create_table :email_list_memberships do |t|
      t.references :email_list, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.timestamps
    end
    add_index :email_list_memberships, %i[email_list_id user_id], unique: true

    create_table :email_signup_forms do |t|
      t.references :customer, null: false, foreign_key: true
      t.string :name, null: false
      t.string :key, null: false
      t.string :status, null: false, default: "active"
      t.json :settings, null: false, default: {}
      t.timestamps
    end
    add_index :email_signup_forms, %i[customer_id key], unique: true
  end
end
```

- [ ] **Step 2: Run migration**

Run: `bin/rails db:migrate`
Expected: Tables created.

- [ ] **Step 3: Commit**

```bash
git commit -m "feat(email): create audience tables (tags, segments, list memberships, signup forms)"
```

---

## Task 2: Implement tags and taggings

**Files:**
- Create: `app/models/emails/audience/tag.rb`
- Create: `app/models/emails/audience/tagging.rb`
- Modify: `app/models/authentication/user.rb` (add `has_many :taggings`)
- Test: `spec/models/emails/audience/tag_spec.rb`

- [ ] **Step 1: Implement models**

```ruby
# app/models/emails/audience/tag.rb
module Emails
  module Audience
    class Tag < ApplicationRecord
      self.table_name = "email_tags"
      include TenantScoped
      has_many :taggings, class_name: "Emails::Audience::Tagging", dependent: :destroy
      validates :customer_id, :name, presence: true
      validates :name, uniqueness: { scope: :customer_id }
    end
  end
end
```

```ruby
# app/models/emails/audience/tagging.rb
module Emails
  module Audience
    class Tagging < ApplicationRecord
      self.table_name = "email_taggings"
      belongs_to :tag, class_name: "Emails::Audience::Tag"
      belongs_to :taggable, polymorphic: true
      validates :tag_id, uniqueness: { scope: %i[taggable_type taggable_id] }
    end
  end
end
```

- [ ] **Step 2: Add user association**

```ruby
# app/models/authentication/user.rb
has_many :email_taggings, as: :taggable, class_name: "Emails::Audience::Tagging", dependent: :destroy
has_many :email_tags, through: :email_taggings, source: :tag
```

- [ ] **Step 3: Write specs**

```ruby
require "rails_helper"
RSpec.describe Emails::Audience::Tag, type: :model do
  let(:customer) { create(:customer) }
  it "requires unique name per customer" do
    create(:email_tag, customer: customer, name: "VIP")
    expect(build(:email_tag, customer: customer, name: "VIP")).not_to be_valid
  end
end
```

- [ ] **Step 4: Run specs**

Run: `bundle exec rspec spec/models/emails/audience/tag_spec.rb`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git commit -m "feat(email): add audience tags and taggings"
```

---

## Task 3: Implement reusable segments

**Files:**
- Create: `app/models/emails/audience/segment.rb`
- Create: `app/services/emails/audience/refresh_segment_counts.rb`
- Create: `app/jobs/emails/audience/refresh_segment_counts_job.rb`
- Test: `spec/models/emails/audience/segment_spec.rb`
- Test: `spec/services/emails/audience/refresh_segment_counts_spec.rb`

- [ ] **Step 1: Rename/copy `EmailCampaigns::AudienceQuery` to `Emails::Audience::SegmentQuery`**

Already covered in Phase 1 namespace move. Ensure it lives at `app/services/emails/audience/segment_query.rb`.

- [ ] **Step 2: Implement segment model**

```ruby
# app/models/emails/audience/segment.rb
module Emails
  module Audience
    class Segment < ApplicationRecord
      self.table_name = "email_segments"
      include TenantScoped
      belongs_to :customer
      has_many :email_lists, class_name: "Emails::Audience::List", foreign_key: :email_segment_id, dependent: :nullify
      validates :customer_id, :name, :rules, presence: true
      validates :name, uniqueness: { scope: :customer_id }

      def audience
        SegmentQuery.call(customer: customer, rules: rules)
      end

      def refresh_match_count!
        update!(match_count: audience.count, match_count_refreshed_at: Time.current)
      end
    end
  end
end
```

- [ ] **Step 3: Implement refresh service and job**

```ruby
# app/services/emails/audience/refresh_segment_counts.rb
module Emails
  module Audience
    class RefreshSegmentCounts
      def self.call(segment_id)
        segment = Emails::Audience::Segment.find(segment_id)
        segment.refresh_match_count!
      end
    end
  end
end
```

```ruby
# app/jobs/emails/audience/refresh_segment_counts_job.rb
module Emails
  module Audience
    class RefreshSegmentCountsJob < ApplicationJob
      queue_as :default
      def perform(segment_id)
        RefreshSegmentCounts.call(segment_id)
      end
    end
  end
end
```

- [ ] **Step 4: Run specs**

Run: `bundle exec rspec spec/models/emails/audience/segment_spec.rb spec/services/emails/audience/refresh_segment_counts_spec.rb`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git commit -m "feat(email): add reusable audience segments"
```

---

## Task 4: Refactor lists to support static/dynamic types

**Files:**
- Modify: `app/models/emails/audience/list.rb`
- Create: `db/migrate/20260721000001_add_list_type_and_segment_id_to_email_lists.rb`
- Test: `spec/models/emails/audience/list_spec.rb`

- [ ] **Step 1: Write migration**

```ruby
class AddListTypeAndSegmentIdToEmailLists < ActiveRecord::Migration[8.1]
  def change
    add_column :email_lists, :list_type, :string, null: false, default: "dynamic"
    add_reference :email_lists, :email_segment, foreign_key: true, index: true
  end
end
```

- [ ] **Step 2: Update list model**

```ruby
# app/models/emails/audience/list.rb
module Emails
  module Audience
    class List < ApplicationRecord
      self.table_name = "email_lists"
      include TenantScoped

      LIST_TYPES = %w[static dynamic].freeze

      belongs_to :email_segment, optional: true, class_name: "Emails::Audience::Segment"
      has_many :email_campaigns, class_name: "Emails::Campaigns::Campaign", foreign_key: :email_list_id, dependent: :restrict_with_exception
      has_many :list_memberships, class_name: "Emails::Audience::ListMembership", foreign_key: :email_list_id, dependent: :destroy
      has_many :users, through: :list_memberships

      validates :customer_id, :name, presence: true
      validates :list_type, inclusion: { in: LIST_TYPES }
      validates :email_segment_id, presence: true, if: -> { dynamic? }

      scope :active, -> { where(status: "active") }

      def dynamic? = list_type == "dynamic"
      def static? = list_type == "static"

      def audience
        if static?
          users
        else
          email_segment&.audience || Emails::Audience::SegmentQuery.call(customer: customer, rules: segment_rules)
        end
      end

      def audience_count
        audience.count
      end
    end
  end
end
```

- [ ] **Step 3: Add ListMembership model**

```ruby
# app/models/emails/audience/list_membership.rb
module Emails
  module Audience
    class ListMembership < ApplicationRecord
      self.table_name = "email_list_memberships"
      belongs_to :email_list, class_name: "Emails::Audience::List"
      belongs_to :user, class_name: "Authentication::User"
      validates :user_id, uniqueness: { scope: :email_list_id }
    end
  end
end
```

- [ ] **Step 4: Migrate legacy lists**

Write a one-off migration or rake task to create a segment for each existing list's `segment_rules` and link it:

```ruby
Emails::Audience::List.where(email_segment_id: nil).find_each do |list|
  next if list.segment_rules.blank?
  segment = Emails::Audience::Segment.create!(
    customer: list.customer,
    name: "#{list.name} (auto)",
    rules: list.segment_rules
  )
  list.update!(email_segment: segment)
end
```

- [ ] **Step 5: Run specs**

Run: `bundle exec rspec spec/models/emails/audience/list_spec.rb`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git commit -m "feat(email): refactor lists with static/dynamic types and segment linkage"
```

---

## Task 5: Implement signup forms

**Files:**
- Create: `app/models/emails/audience/signup_form.rb`
- Create: `app/services/emails/audience/signup_form_handler.rb`
- Create: `app/controllers/emails/signup_forms_controller.rb`
- Test: `spec/models/emails/audience/signup_form_spec.rb`
- Test: `spec/services/emails/audience/signup_form_handler_spec.rb`
- Test: `spec/requests/emails/signup_forms_spec.rb`

- [ ] **Step 1: Implement model**

```ruby
# app/models/emails/audience/signup_form.rb
module Emails
  module Audience
    class SignupForm < ApplicationRecord
      self.table_name = "email_signup_forms"
      include TenantScoped
      belongs_to :customer
      validates :customer_id, :name, :key, presence: true
      validates :key, uniqueness: { scope: :customer_id }, format: { with: /\A[a-z0-9_-]+\z/ }
      validates :status, inclusion: { in: %w[active disabled] }

      def active? = status == "active"
    end
  end
end
```

- [ ] **Step 2: Implement handler service**

```ruby
# app/services/emails/audience/signup_form_handler.rb
module Emails
  module Audience
    class SignupFormHandler
      def self.call(form:, params:)
        new(form: form, params: params).call
      end

      def initialize(form:, params:)
        @form = form
        @params = params
      end

      def call
        return { success: false, error: I18n.t("emails.signup_forms.disabled") } unless @form.active?

        user = Authentication::User.find_or_initialize_by(customer: @form.customer, email: normalized_email)
        user.first_name = @params[:first_name] if @params[:first_name].present?
        user.last_name = @params[:last_name] if @params[:last_name].present?
        user.status = "active" if user.new_record?

        if user.save
          apply_tags(user)
          { success: true, user: user }
        else
          { success: false, errors: user.errors.full_messages }
        end
      end

      private

      def normalized_email
        @params[:email].to_s.strip.downcase
      end

      def apply_tags(user)
        Array(@form.settings["tag_ids"]).each do |tag_id|
          tag = Emails::Audience::Tag.for_current_customer.find_by(id: tag_id)
          next unless tag
          Emails::Audience::Tagging.find_or_create_by!(tag: tag, taggable: user)
        end
      end
    end
  end
end
```

- [ ] **Step 3: Implement public controller**

```ruby
# app/controllers/emails/signup_forms_controller.rb
module Emails
  class SignupFormsController < ActionController::Base
    skip_forgery_protection if respond_to?(:skip_forgery_protection)

    def subscribe
      form = Emails::Audience::SignupForm.for_current_customer.find_by!(key: params[:key])
      result = Emails::Audience::SignupFormHandler.call(form: form, params: signup_params)

      if result[:success]
        redirect_to email_signup_form_subscribed_path(key: form.key), notice: I18n.t("emails.signup_forms.subscribed")
      else
        render json: { error: result[:error] || result[:errors] }, status: :unprocessable_entity
      end
    end

    private

    def signup_params
      params.permit(:email, :first_name, :last_name)
    end
  end
end
```

- [ ] **Step 4: Add routes**

```ruby
# config/routes.rb public section
get "/email/signup_forms/:key/subscribed", to: "emails/signup_forms#subscribed", as: :email_signup_form_subscribed
post "/email/signup_forms/:key/subscribe", to: "emails/signup_forms#subscribe"
```

- [ ] **Step 5: Run specs**

Run: `bundle exec rspec spec/models/emails/audience/signup_form_spec.rb spec/services/emails/audience/signup_form_handler_spec.rb spec/requests/emails/signup_forms_spec.rb`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git commit -m "feat(email): add signup forms and public subscription endpoint"
```

---

## Task 6: Build admin controllers and views for Audience hub

**Files:**
- Create: `app/controllers/admin/modules/emails/contacts_controller.rb`
- Create: `app/controllers/admin/modules/emails/tags_controller.rb`
- Create: `app/controllers/admin/modules/emails/segments_controller.rb`
- Create: `app/controllers/admin/modules/emails/signup_forms_controller.rb`
- Modify: `app/controllers/admin/modules/emails/lists_controller.rb`
- Create corresponding views under `app/views/admin/modules/emails/<resource>/`

- [ ] **Step 1: Implement contacts controller**

```ruby
# app/controllers/admin/modules/emails/contacts_controller.rb
module Admin
  module Modules
    module Emails
      class ContactsController < ApplicationController
        dashboard_menu_item :modules

        def index
          @columns = [
            { key: :email, label: I18n.t("common.labels.email"), searchable: true },
            { key: :name, label: I18n.t("common.labels.name"), searchable: true },
            { key: :tags, label: I18n.t("feature_modules.email.entries.tags") },
            { key: :last_sent_at, label: I18n.t("admin_modules.emails.contacts.last_sent_at"), type: :datetime }
          ]
          scope = Authentication::User.for_current_customer.left_joins(:email_messages)
                                       .select("authentication_users.*, MAX(email_messages.sent_at) AS last_sent_at")
                                       .group("authentication_users.id")
                                       .order("last_sent_at DESC NULLS LAST")
          result = ModuleEntriesResolver.call(scope: scope, columns: @columns, params: permitted_params)
          @rows = result[:rows]
          @pagination = result[:pagination]
        end

        private

        def permitted_params
          params.permit(:page, :per_page, :sort, :dir, :q).to_h.symbolize_keys
        end
      end
    end
  end
end
```

- [ ] **Step 2: Implement tags controller (CRUD)**

Standard CRUD with `Emails::Audience::Tag`.

- [ ] **Step 3: Implement segments controller**

Reuse existing segment builder component. On create/update, enqueue `RefreshSegmentCountsJob`.

- [ ] **Step 4: Implement signup forms controller (CRUD)**

CRUD for `Emails::Audience::SignupForm` with settings for tag_ids.

- [ ] **Step 5: Update lists controller**

Support `list_type` and `email_segment_id` params; for static lists, allow bulk import via emails textarea.

- [ ] **Step 6: Add i18n keys**

Add all new audience UI keys to `admin_modules.emails.contacts/tags/segments/lists/signup_forms` in both locales.

- [ ] **Step 7: Run request specs**

Run: `bundle exec rspec spec/requests/admin/modules/emails/contacts_spec.rb spec/requests/admin/modules/emails/tags_spec.rb spec/requests/admin/modules/emails/segments_spec.rb spec/requests/admin/modules/emails/signup_forms_spec.rb`
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git commit -m "feat(email): add admin audience hub controllers and views"
```

---

## Task 7: Phase 2 integration

- [ ] **Step 1: Run full email + audience spec suite**

Run: `bundle exec rspec spec/models/emails/audience spec/services/emails/audience spec/jobs/emails/audience spec/requests/admin/modules/emails spec/requests/emails/signup_forms_spec.rb`
Expected: PASS.

- [ ] **Step 2: Stage**

```bash
git add -A
```

Phase 2 complete. Commit when ready:

```bash
git commit -m "feat(email): Phase 2 — audience hub with tags, segments, lists, signup forms"
```
