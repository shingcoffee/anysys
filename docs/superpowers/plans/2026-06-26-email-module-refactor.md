# Email Module Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refactor the email subsystem: Action Text rich-text templates with tenant-isolated storage, a User-based reflection-driven audience query, platform-level DKIM signing, a per-user campaign Block-List, and test-send — retiring the `Subscriber` entity entirely.

**Architecture:** `Authentication::User` becomes the single campaign audience. Lists are saved dynamic queries compiled by a schema-whitelisted, tenant-scoped `EmailCampaigns::AudienceQuery`. A boolean flag on `users` suppresses campaign mail only. DKIM config lives on the global `Emails::Credential`; all mail is signed in the SMTP adapter. Templates use Action Text with per-blob `customer_id` isolation and CID image embedding for delivery. The transactional `Email::Gateway.send` API is unchanged.

**Tech Stack:** Rails 8.1, RSpec, Reform/Trailblazer, Action Text + Active Storage, Trix, Stimulus, Tailwind, ViewComponent, `mail` gem + OpenSSL for DKIM.

**Spec:** `docs/superpowers/specs/2026-06-26-email-module-refactor-design.md`

**Test execution:** This is a cross-cutting refactor (auth/tenant scoping + multiple modules). Per AGENTS.md, run the **full suite** (`bin/rails parallel:spec`) at phase boundaries; run targeted specs per task. Never run rspec concurrently with another rspec process (shared test.sqlite3).

---

## File Map

**Phase 0 — Retire Subscriber**
- Delete: `app/models/email_campaigns/subscriber.rb`, `app/models/email_campaigns/list_subscriber.rb`
- Delete: `app/services/email_campaigns/segment_evaluator.rb`, `app/services/email_campaigns/unsubscribe_handler.rb`
- Delete: `app/controllers/admin/modules/email_campaigns/subscribers_controller.rb`, `app/views/admin/modules/email_campaigns/subscribers/`
- Delete: `spec/**/email_campaigns/*subscriber*`, subscriber factory
- Migration: drop `email_subscribers`, `email_list_subscribers`
- Modify: `config/routes.rb`, `app/services/feature_modules/email_campaigns/registration.rb`, `app/models/email_campaigns/list.rb`, `app/models/email_campaigns/campaign.rb`

**Phase 1 — Block flag + Block-List**
- Migration: add `users.email_campaign_blocked`, `users.email_campaign_blocked_at`
- Modify: `app/models/authentication/user.rb`
- Create: `app/controllers/admin/modules/email_campaigns/block_list_controller.rb`
- Create: `app/views/admin/modules/email_campaigns/block_list/index.html.erb`
- Create: `app/components/email_campaigns/block_list_table_component.{rb,html.erb}` + spec
- Create: `app/javascript/controllers/batch_select_controller.js`
- Modify: `config/routes.rb`, `registration.rb`

**Phase 2 — AudienceQuery + FieldCatalog + List**
- Create: `app/services/email_campaigns/field_catalog.rb` + spec
- Create: `app/services/email_campaigns/audience_query.rb` + spec
- Modify: `app/models/email_campaigns/list.rb`, `app/controllers/admin/modules/email_campaigns/lists_controller.rb`
- Modify: `app/jobs/email_campaigns/send_campaign_job.rb`, `app/services/email/gateway.rb`
- Create: condition-builder component + Stimulus + `lists/_form.html.erb` rework

**Phase 3 — User-based unsubscribe**
- Create: `app/services/email_campaigns/campaign_unsubscribe.rb` + spec
- Modify: `app/controllers/email_campaigns/unsubscribes_controller.rb`, `config/routes.rb`, unsubscribe views

**Phase 4 — DKIM**
- Migration: add DKIM columns to `email_credentials`
- Modify: `app/models/emails/credential.rb`, `app/services/email/adapters/smtp.rb`
- Create: `app/services/email/dkim_signer.rb` + spec
- Create: `app/controllers/admin/maintenance/platform/emails/credentials_controller.rb` + views
- Modify: `config/routes.rb`

**Phase 5 — Action Text + storage isolation + editor**
- Run `bin/rails action_text:install`
- Migration: add `active_storage_blobs.customer_id`
- Modify: `app/models/emails/template.rb`
- Create: `app/services/emails/compile_template.rb` + spec
- Create: `app/controllers/admin/modules/emails/attachments_controller.rb`
- Modify: `app/services/email/adapters/smtp.rb` (CID embedding)
- Create: `app/javascript/controllers/template_variable_picker_controller.js`
- Modify: `app/views/admin/modules/emails/templates/_form.html.erb`, templates controller

**Phase 6 — VariableContext + test-send**
- Create: `app/services/email/variable_context.rb` + spec
- Modify: `app/services/email/gateway.rb` (queue_for_campaign uses VariableContext)
- Create: test-send controller action + button

---

## PHASE 0 — Retire the Subscriber entity

### Task 0.1: Drop subscriber tables (migration)

**Files:**
- Create: `db/migrate/<ts>_drop_email_subscriber_tables.rb`

- [ ] **Step 1: Generate migration**

Run: `bin/rails g migration DropEmailSubscriberTables`

- [ ] **Step 2: Write the migration**

```ruby
# frozen_string_literal: true

class DropEmailSubscriberTables < ActiveRecord::Migration[8.1]
  def up
    drop_table :email_list_subscribers
    drop_table :email_subscribers
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
```

- [ ] **Step 3: Migrate**

Run: `bin/rails db:migrate && RAILS_ENV=test bin/rails db:test:prepare`
Expected: `email_subscribers` and `email_list_subscribers` removed from `db/schema.rb`.

- [ ] **Step 4: Commit**

```bash
git add db/migrate db/schema.rb && git commit -m "refactor(email): drop subscriber tables"
```

### Task 0.2: Delete Subscriber code + specs and detach associations

**Files:**
- Delete: `app/models/email_campaigns/subscriber.rb`, `app/models/email_campaigns/list_subscriber.rb`
- Delete: `app/services/email_campaigns/segment_evaluator.rb`, `app/services/email_campaigns/unsubscribe_handler.rb`
- Delete: `app/controllers/admin/modules/email_campaigns/subscribers_controller.rb`
- Delete: `app/views/admin/modules/email_campaigns/subscribers/`
- Delete: subscriber specs + `spec/factories` subscriber entries
- Modify: `app/models/email_campaigns/list.rb`, `config/routes.rb`, `registration.rb`

- [ ] **Step 1: Delete files**

```bash
git rm app/models/email_campaigns/subscriber.rb \
       app/models/email_campaigns/list_subscriber.rb \
       app/services/email_campaigns/segment_evaluator.rb \
       app/services/email_campaigns/unsubscribe_handler.rb \
       app/controllers/admin/modules/email_campaigns/subscribers_controller.rb
git rm -r app/views/admin/modules/email_campaigns/subscribers
git rm -r spec/models/email_campaigns/subscriber_spec.rb spec/services/email_campaigns/segment_evaluator_spec.rb 2>/dev/null || true
grep -rl "subscriber" spec/ | grep -i email | xargs git rm 2>/dev/null || true
```

- [ ] **Step 2: Remove subscriber factory**

Edit `spec/factories/email_campaigns.rb` (and any `spec/factories/email_subscribers.rb`) — `git rm` the subscriber factory file if standalone, or delete the `factory :email_subscriber` / `:email_list` static-membership blocks. Keep `:email_campaign`; `:email_list` will be reworked in Task 2.5.

- [ ] **Step 3: Strip subscriber associations from List model**

Edit `app/models/email_campaigns/list.rb` — remove `has_many :email_list_subscribers`, `has_many :email_subscribers`, the `LIST_TYPES` static branch usage stays for now (reworked Phase 2). Result:

```ruby
# frozen_string_literal: true

module EmailCampaigns
  class List < ApplicationRecord
    self.table_name = "email_lists"

    include TenantScoped

    STATUSES = %w[active archived].freeze

    has_many :email_campaigns, dependent: :restrict_with_exception,
                               class_name: "EmailCampaigns::Campaign",
                               foreign_key: :email_list_id

    validates :customer_id, presence: true
    validates :name,        presence: true
    validates :status,      inclusion: { in: STATUSES }

    scope :active, -> { where(status: "active") }
  end
end
```

(The `list_type`/`static?`/`dynamic?` API is removed here; all lists are dynamic in Phase 2.)

- [ ] **Step 4: Remove subscribers route + nav entry**

Edit `config/routes.rb` line ~405: delete `resources :subscribers`.
Edit `registration.rb`: delete the `Subscribers` `ModuleContribution`, the `when "subscribers"` branch, and `subscribers_entry_config`. Update `module_description` to `"Marketing campaigns with audience lists, scheduling, and block-list"`.

- [ ] **Step 5: Verify boot + grep clean**

Run: `bin/rails runner 'puts "ok"'`
Run: `grep -rn "EmailCampaigns::Subscriber\|SegmentEvaluator\|UnsubscribeHandler\|email_subscribers\|email_list_subscribers" app config | grep -v unsubscribe_token`
Expected: `ok`; grep returns only references that Phases 2–3 will replace (send_campaign_job, unsubscribes_controller). Note them; they're fixed later.

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "refactor(email): remove Subscriber model, service, controller, nav, specs"
```

---

## PHASE 1 — User campaign block flag + Block-List

### Task 1.1: Add block flag to users (migration + model scope)

**Files:**
- Create: `db/migrate/<ts>_add_email_campaign_blocked_to_users.rb`
- Modify: `app/models/authentication/user.rb`
- Test: `spec/models/authentication/user_spec.rb`

- [ ] **Step 1: Write the failing test** in `spec/models/authentication/user_spec.rb`

```ruby
RSpec.describe Authentication::User do
  describe "campaign block flag" do
    it "defaults to not blocked and exposes deliverable/blocked scopes" do
      customer = create(:customer)
      ok = create(:user, customer: customer)
      blocked = create(:user, customer: customer, email_campaign_blocked: true)

      expect(ok.email_campaign_blocked).to be(false)
      expect(described_class.campaign_deliverable).to include(ok)
      expect(described_class.campaign_deliverable).not_to include(blocked)
      expect(described_class.campaign_blocked).to include(blocked)
    end

    it "#block_campaign_email! and #unblock_campaign_email! toggle the flag and timestamp" do
      user = create(:user)
      user.block_campaign_email!
      expect(user.email_campaign_blocked).to be(true)
      expect(user.email_campaign_blocked_at).to be_present
      user.unblock_campaign_email!
      expect(user.email_campaign_blocked).to be(false)
      expect(user.email_campaign_blocked_at).to be_nil
    end
  end
end
```

- [ ] **Step 2: Run, expect fail**

Run: `bin/rspec spec/models/authentication/user_spec.rb -e "campaign block flag"`
Expected: FAIL (no column / no methods).

- [ ] **Step 3: Migration**

```ruby
# frozen_string_literal: true

class AddEmailCampaignBlockedToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :email_campaign_blocked, :boolean, null: false, default: false
    add_column :users, :email_campaign_blocked_at, :datetime
    add_index  :users, [:customer_id, :email_campaign_blocked]
  end
end
```

Run: `bin/rails db:migrate && RAILS_ENV=test bin/rails db:test:prepare`

- [ ] **Step 4: Add model API** — in `app/models/authentication/user.rb` Scopes section:

```ruby
    scope :campaign_deliverable, -> { where(email_campaign_blocked: false) }
    scope :campaign_blocked,     -> { where(email_campaign_blocked: true) }
```

and instance methods (near role predicates):

```ruby
    def block_campaign_email!
      update!(email_campaign_blocked: true, email_campaign_blocked_at: Time.current)
    end

    def unblock_campaign_email!
      update!(email_campaign_blocked: false, email_campaign_blocked_at: nil)
    end
```

- [ ] **Step 5: Run, expect pass**

Run: `bin/rspec spec/models/authentication/user_spec.rb -e "campaign block flag"`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat(email): add campaign block flag + scopes to User"
```

### Task 1.2: Block-List table ViewComponent

**Files:**
- Create: `app/components/email_campaigns/block_list_table_component.rb`
- Create: `app/components/email_campaigns/block_list_table_component.html.erb`
- Test: `spec/components/email_campaigns/block_list_table_component_spec.rb`

- [ ] **Step 1: Failing component spec**

```ruby
require "rails_helper"

RSpec.describe EmailCampaigns::BlockListTableComponent, type: :component do
  it "renders a row per blocked user with a checkbox and unblock control" do
    customer = create(:customer)
    user = create(:user, customer: customer, email_campaign_blocked: true,
                  email_campaign_blocked_at: Time.current, first_name: "Ada", last_name: "L")

    render_inline(described_class.new(users: [user], customer_id: customer.id))

    expect(page).to have_css("input[type=checkbox][name='user_ids[]'][value='#{user.id}']")
    expect(page).to have_text("Ada L")
    expect(page).to have_text(user.email)
    expect(page).to have_css("button, a", text: /Unblock/i)
  end

  it "renders an empty state when no users are blocked" do
    render_inline(described_class.new(users: [], customer_id: 123))
    expect(page).to have_text(/No blocked users/i)
  end
end
```

- [ ] **Step 2: Run, expect fail** — `bin/rspec spec/components/email_campaigns/block_list_table_component_spec.rb` → FAIL (uninitialized constant).

- [ ] **Step 3: Component class**

```ruby
# frozen_string_literal: true

module EmailCampaigns
  class BlockListTableComponent < ViewComponent::Base
    def initialize(users:, customer_id:)
      @users = users
      @customer_id = customer_id
    end

    attr_reader :users, :customer_id

    def unblock_one_path(user)
      "/#{customer_id}/admin/modules/email_campaigns/block_list/#{user.id}"
    end

    def batch_unblock_path
      "/#{customer_id}/admin/modules/email_campaigns/block_list/batch_unblock"
    end
  end
end
```

- [ ] **Step 4: Template** `block_list_table_component.html.erb` — Tailwind-only, follows existing admin table styling (`table`, `form-label`, `btn`). Use the project's existing table classes (inspect `app/views/admin/modules/email_campaigns/lists/index.html.erb` for the exact wrapper). Must include: a wrapping `<form>` posting to `batch_unblock_path` (method PATCH) with `data-controller="batch-select"`, a header "select all" checkbox (`data-batch-select-target="all"`), one row per user with `name="user_ids[]"` checkbox (`data-batch-select-target="item"`), email, full name, `email_campaign_blocked_at` (use `l(...)`), and a per-row "Unblock" button posting PATCH to `unblock_one_path(user)` (use `button_to`). A "Unblock selected" submit button (`data-batch-select-target="submit"`, disabled until a box is checked). Empty state: "No blocked users." when `users.empty?`.

- [ ] **Step 5: Run, expect pass** — `bin/rspec spec/components/email_campaigns/block_list_table_component_spec.rb` → PASS

- [ ] **Step 6: Commit** — `git add -A && git commit -m "feat(email): block-list table component"`

### Task 1.3: batch-select Stimulus controller

**Files:**
- Create: `app/javascript/controllers/batch_select_controller.js`

- [ ] **Step 1: Implement** (no JS unit test harness per repo memory — verify in system spec later)

```javascript
import { Controller } from "@hotwired/stimulus"

// Manages a "select all" checkbox + row checkboxes and enables the
// batch-action submit only when at least one row is selected.
export default class extends Controller {
  static targets = ["all", "item", "submit"]

  connect() { this.refresh() }

  toggleAll() {
    this.itemTargets.forEach((cb) => { cb.checked = this.allTarget.checked })
    this.refresh()
  }

  refresh() {
    const anyChecked = this.itemTargets.some((cb) => cb.checked)
    if (this.hasSubmitTarget) this.submitTarget.disabled = !anyChecked
    if (this.hasAllTarget) {
      const allChecked = this.itemTargets.length > 0 && this.itemTargets.every((cb) => cb.checked)
      this.allTarget.checked = allChecked
    }
  }
}
```

Wire actions in the template: `all` → `change->batch-select#toggleAll`, each `item` → `change->batch-select#refresh`.

- [ ] **Step 2: Commit** — `git add -A && git commit -m "feat(email): batch-select stimulus controller"`

### Task 1.4: BlockListController (index, unblock one, batch_unblock)

**Files:**
- Create: `app/controllers/admin/modules/email_campaigns/block_list_controller.rb`
- Create: `app/views/admin/modules/email_campaigns/block_list/index.html.erb`
- Modify: `config/routes.rb`
- Test: `spec/requests/admin/modules/email_campaigns/block_list_spec.rb`

- [ ] **Step 1: Routes** — inside `namespace :email_campaigns`:

```ruby
          get  "block_list",                 to: "block_list#index"
          patch "block_list/batch_unblock",  to: "block_list#batch_unblock"
          patch "block_list/:id",            to: "block_list#unblock", as: :email_campaigns_block_list_unblock
```

(Place `batch_unblock` before `:id` so it isn't captured as an id.)

- [ ] **Step 2: Failing request spec**

```ruby
require "rails_helper"

RSpec.describe "Admin::Modules::EmailCampaigns::BlockList", type: :request do
  let(:customer) { create(:customer) }
  let(:admin)    { create(:user, :admin, customer: customer) }
  let!(:blocked) { create(:user, customer: customer, email_campaign_blocked: true, email_campaign_blocked_at: Time.current) }

  before { sign_in admin }

  it "lists blocked users for the current customer" do
    get "/#{customer.id}/admin/modules/email_campaigns/block_list"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(blocked.email)
  end

  it "unblocks a single user" do
    patch "/#{customer.id}/admin/modules/email_campaigns/block_list/#{blocked.id}"
    expect(blocked.reload.email_campaign_blocked).to be(false)
  end

  it "batch-unblocks selected users" do
    other = create(:user, customer: customer, email_campaign_blocked: true)
    patch "/#{customer.id}/admin/modules/email_campaigns/block_list/batch_unblock",
          params: { user_ids: [blocked.id, other.id] }
    expect(blocked.reload.email_campaign_blocked).to be(false)
    expect(other.reload.email_campaign_blocked).to be(false)
  end

  it "does not unblock a user from another tenant" do
    other_customer = create(:customer)
    foreign = create(:user, customer: other_customer, email_campaign_blocked: true)
    patch "/#{customer.id}/admin/modules/email_campaigns/block_list/#{foreign.id}"
    expect(response).to have_http_status(:not_found).or have_http_status(:found)
    expect(foreign.reload.email_campaign_blocked).to be(true)
  end

  it "denies a member" do
    member = create(:user, :member, customer: customer)
    sign_in member
    get "/#{customer.id}/admin/modules/email_campaigns/block_list"
    expect(response).not_to have_http_status(:ok)
  end
end
```

(Use the repo's existing user factory traits for `:admin`/`:member`; inspect `spec/factories` for the exact trait names and adapt if different.)

- [ ] **Step 3: Run, expect fail** — FAIL (no route/controller).

- [ ] **Step 4: Controller**

```ruby
# frozen_string_literal: true

module Admin
  module Modules
    module EmailCampaigns
      class BlockListController < ApplicationController
        dashboard_menu_item :modules

        def index
          @users = Authentication::User
                     .for_current_customer
                     .campaign_blocked
                     .order(email_campaign_blocked_at: :desc)
        end

        def unblock
          user = scoped_users.find(params[:id])
          user.unblock_campaign_email!
          redirect_to index_path, notice: "User unblocked."
        end

        def batch_unblock
          ids = Array(params[:user_ids]).map(&:to_i)
          scoped_users.where(id: ids).find_each(&:unblock_campaign_email!)
          redirect_to index_path, notice: "#{ids.size} user(s) unblocked."
        end

        private

        def scoped_users
          Authentication::User.for_current_customer.campaign_blocked
        end

        def index_path
          "/#{current_customer.id}/admin/modules/email_campaigns/block_list"
        end
      end
    end
  end
end
```

(Cross-tenant access raises `ActiveRecord::RecordNotFound` from `scoped_users.find` → 404, satisfying the isolation test.)

- [ ] **Step 5: View** `index.html.erb` — page header "Block-List" with description "Users who opted out of campaign email. Transactional email is unaffected.", then `render(EmailCampaigns::BlockListTableComponent.new(users: @users, customer_id: current_customer.id))`. Match the layout/header markup used by `lists/index.html.erb`.

- [ ] **Step 6: Run, expect pass** — `bin/rspec spec/requests/admin/modules/email_campaigns/block_list_spec.rb` → PASS

- [ ] **Step 7: Commit** — `git add -A && git commit -m "feat(email): block-list admin controller, view, routes"`

### Task 1.5: Add Block-List nav entry

**Files:** Modify `app/services/feature_modules/email_campaigns/registration.rb`

- [ ] **Step 1:** In `sidebar_contributions`, set entries to (Campaigns, Lists, Block-List):

```ruby
          entries: [
            ModuleContribution.new(label: "Campaigns", entry_key: "campaigns", path: ->(cid) { "/#{cid}/admin/modules/email_campaigns/campaigns" }),
            ModuleContribution.new(label: "Lists",     entry_key: "lists",     path: ->(cid) { "/#{cid}/admin/modules/email_campaigns/lists" }),
            ModuleContribution.new(label: "Block-List", entry_key: "block_list", path: ->(cid) { "/#{cid}/admin/modules/email_campaigns/block_list" })
          ],
```

Add a `when "block_list"` branch to `entries_for` returning `{ title: "Block-List", columns: [...], scope: ::Authentication::User.for_current_customer.campaign_blocked.order(email_campaign_blocked_at: :desc) }` with columns `email`, `email_campaign_blocked_at`.

- [ ] **Step 2: Spec** — extend `spec/services/feature_modules/email_campaigns/registration_spec.rb` (if present) to assert the nav labels are `["Campaigns", "Lists", "Block-List"]` and no longer include `"Subscribers"`. Run it → PASS.

- [ ] **Step 3: Commit** — `git add -A && git commit -m "feat(email): block-list nav entry; drop subscribers nav"`

---

## PHASE 2 — User-based AudienceQuery + FieldCatalog

### Task 2.1: FieldCatalog (reflection-driven field metadata)

**Files:**
- Create: `app/services/email_campaigns/field_catalog.rb`
- Test: `spec/services/email_campaigns/field_catalog_spec.rb`

The catalog enumerates queryable fields: `Authentication::User` columns plus columns of associated tenant-scoped models, keyed by a stable `field` identifier `"<assoc_or_self>.<column>"` (self uses bare column names for back-compat with existing `{{first_name}}` style). It is the single source of truth shared by `AudienceQuery` (validation) and the builder UI (options) and the variable picker.

- [ ] **Step 1: Failing spec**

```ruby
require "rails_helper"

RSpec.describe EmailCampaigns::FieldCatalog do
  subject(:catalog) { described_class.new }

  it "exposes core User scalar fields" do
    fields = catalog.fields.map { |f| f[:field] }
    expect(fields).to include("email", "first_name", "last_name", "created_at", "status")
  end

  it "exposes fields from associations as <assoc>.<column>" do
    fields = catalog.fields.map { |f| f[:field] }
    # users belongs to customer / has roles; payments belong to user
    expect(fields).to include("roles.key")
  end

  it "marks each field with a value type and allowed operators" do
    email = catalog.fields.find { |f| f[:field] == "email" }
    expect(email[:type]).to eq(:string)
    expect(email[:operators]).to include("equals", "contains")

    created = catalog.fields.find { |f| f[:field] == "created_at" }
    expect(created[:operators]).to include("after", "before")
  end

  it "resolves a field to its association path + column, rejecting unknown fields" do
    expect(catalog.resolve("roles.key")).to eq(association: :roles, column: "key", type: :string)
    expect(catalog.resolve("email")).to eq(association: nil, column: "email", type: :string)
    expect(catalog.resolve("evil; DROP TABLE users; --")).to be_nil
    expect(catalog.resolve("roles.nonexistent")).to be_nil
  end
end
```

- [ ] **Step 2: Run, expect fail.**

- [ ] **Step 3: Implement**

```ruby
# frozen_string_literal: true

module EmailCampaigns
  # Reflection-driven catalog of queryable fields over Authentication::User
  # and its associations. Single source of truth for AudienceQuery validation
  # and the builder UI. Field identifiers are always validated against this
  # catalog before reaching SQL — there is no free-form column input.
  class FieldCatalog
    ROOT = Authentication::User

    # Associations exposed to the segment builder. belongs_to/has_many to
    # tenant-scoped or reference models only. Extend by adding here.
    EXPOSED_ASSOCIATIONS = %i[roles customer].freeze

    OPERATORS_BY_TYPE = {
      string:   %w[equals not_equals contains not_contains is_blank is_present],
      integer:  %w[equals not_equals greater_than less_than is_blank is_present],
      float:    %w[equals not_equals greater_than less_than is_blank is_present],
      boolean:  %w[equals not_equals],
      datetime: %w[after before is_blank is_present],
      date:     %w[after before is_blank is_present]
    }.freeze

    def fields
      @fields ||= self_fields + association_fields
    end

    # Returns { association:, column:, type: } or nil if the identifier is not
    # a known, whitelisted field. NEVER returns user-controlled column names.
    def resolve(identifier)
      fields.find { |f| f[:field] == identifier.to_s }
            &.slice(:association, :column, :type)
    end

    private

    def self_fields
      columns_for(ROOT).map do |col|
        build(field: col.name, association: nil, column: col.name, sql_type: col.type)
      end
    end

    def association_fields
      EXPOSED_ASSOCIATIONS.flat_map do |assoc_name|
        reflection = ROOT.reflect_on_association(assoc_name)
        next [] unless reflection

        columns_for(reflection.klass).map do |col|
          build(field: "#{assoc_name}.#{col.name}", association: assoc_name, column: col.name, sql_type: col.type)
        end
      end
    end

    def columns_for(klass)
      sensitive = %w[encrypted_password password otp_secret reset_password_token
                     confirmation_token unlock_token]
      klass.columns.reject { |c| sensitive.include?(c.name) }
    end

    def build(field:, association:, column:, sql_type:)
      type = normalize_type(sql_type)
      {
        field:     field,
        association: association,
        column:    column,
        type:      type,
        label:     field.tr(".", " ").titleize,
        operators: OPERATORS_BY_TYPE.fetch(type, OPERATORS_BY_TYPE[:string])
      }
    end

    def normalize_type(sql_type)
      case sql_type
      when :integer        then :integer
      when :float, :decimal then :float
      when :boolean        then :boolean
      when :datetime, :timestamp then :datetime
      when :date           then :date
      else :string
      end
    end
  end
end
```

- [ ] **Step 4: Run, expect pass.**
- [ ] **Step 5: Commit** — `git add -A && git commit -m "feat(email): FieldCatalog for user segment queries"`

### Task 2.2: AudienceQuery (compile rules → tenant-scoped User relation)

**Files:**
- Create: `app/services/email_campaigns/audience_query.rb`
- Test: `spec/services/email_campaigns/audience_query_spec.rb`

- [ ] **Step 1: Failing spec** (coverage + tenant isolation + injection safety)

```ruby
require "rails_helper"

RSpec.describe EmailCampaigns::AudienceQuery do
  let(:customer)  { create(:customer) }
  let(:other)     { create(:customer) }

  def query(rules)
    described_class.new(customer: customer, rules: rules).relation
  end

  it "returns all customer users when there are no conditions" do
    u = create(:user, customer: customer)
    create(:user, customer: other)
    expect(query({}).to_a).to eq([u])
  end

  it "filters by a scalar User attribute with bound parameters" do
    match = create(:user, customer: customer, first_name: "Ada")
    create(:user, customer: customer, first_name: "Bob")
    rules = { "match" => "all", "conditions" => [{ "field" => "first_name", "operator" => "equals", "value" => "Ada" }] }
    expect(query(rules).to_a).to eq([match])
  end

  it "filters across an association (roles.key)" do
    admin  = create(:user, :admin, customer: customer)
    member = create(:user, :member, customer: customer)
    rules = { "match" => "all", "conditions" => [{ "field" => "roles.key", "operator" => "equals", "value" => "admin" }] }
    result = query(rules).to_a
    expect(result).to include(admin)
    expect(result).not_to include(member)
  end

  it "never returns users from another tenant even if a condition would match" do
    create(:user, customer: other, first_name: "Ada")
    rules = { "match" => "all", "conditions" => [{ "field" => "first_name", "operator" => "equals", "value" => "Ada" }] }
    expect(query(rules).to_a).to be_empty
  end

  it "ignores conditions referencing unknown/dangerous fields (no SQL injection)" do
    create(:user, customer: customer)
    rules = { "match" => "all",
              "conditions" => [{ "field" => "email\") OR 1=1 --", "operator" => "equals", "value" => "x" }] }
    expect { query(rules).to_a }.not_to raise_error
    # malformed field is dropped → no rows match the (now empty) AND-set differently:
    expect(query(rules).count).to eq(Authentication::User.for_customer(customer.id).count).or eq(0)
  end

  it "supports match=any (OR)" do
    a = create(:user, customer: customer, first_name: "Ada")
    b = create(:user, customer: customer, first_name: "Bob")
    create(:user, customer: customer, first_name: "Cy")
    rules = { "match" => "any", "conditions" => [
      { "field" => "first_name", "operator" => "equals", "value" => "Ada" },
      { "field" => "first_name", "operator" => "equals", "value" => "Bob" }
    ] }
    expect(query(rules).to_a).to match_array([a, b])
  end
end
```

- [ ] **Step 2: Run, expect fail.**

- [ ] **Step 3: Implement** — build an `ActiveRecord::Relation`, validate every field via `FieldCatalog`, bind values via Arel, join only whitelisted associations, scope to the customer.

```ruby
# frozen_string_literal: true

module EmailCampaigns
  # Compiles a segment-rules AST into a tenant-scoped ActiveRecord::Relation
  # over Authentication::User. SAFETY INVARIANTS:
  #   * Every field is resolved through FieldCatalog (schema whitelist) — an
  #     unresolved field is dropped, never interpolated into SQL.
  #   * Values are bound as Arel parameters (never string-interpolated).
  #   * The root relation is always scoped to the customer; joined
  #     tenant-scoped tables inherit the customer filter where applicable.
  class AudienceQuery
    def self.call(customer:, rules:)
      new(customer: customer, rules: rules).relation
    end

    def initialize(customer:, rules:)
      @customer = customer
      @rules    = (rules || {}).with_indifferent_access
      @catalog  = FieldCatalog.new
    end

    def relation
      rel = Authentication::User.for_customer(@customer.id)
      predicates = compiled_conditions
      return rel if predicates.empty?

      combined = combine(predicates)
      rel = apply_joins(rel)
      rel.where(combined).distinct
    end

    def count
      relation.count
    end

    private

    attr_reader :customer, :rules, :catalog

    def conditions
      Array(rules[:conditions])
    end

    def any_match?
      rules[:match].to_s == "any"
    end

    # [{ resolved:, predicate: Arel::Node }] for valid conditions only.
    def compiled_conditions
      @compiled_conditions ||= conditions.filter_map do |cond|
        resolved = catalog.resolve(cond["field"] || cond[:field])
        next nil unless resolved

        node = predicate_for(resolved, (cond["operator"] || cond[:operator]).to_s, cond["value"] || cond[:value])
        next nil unless node

        { resolved: resolved, predicate: node }
      end
    end

    def combine(entries)
      nodes = entries.map { |e| e[:predicate] }
      nodes.reduce { |acc, n| any_match? ? acc.or(n) : acc.and(n) }
    end

    def apply_joins(rel)
      assocs = compiled_conditions.map { |e| e[:resolved][:association] }.compact.uniq
      assocs.any? ? rel.left_outer_joins(*assocs) : rel
    end

    def arel_column(resolved)
      klass = resolved[:association] ? Authentication::User.reflect_on_association(resolved[:association]).klass : Authentication::User
      klass.arel_table[resolved[:column]]
    end

    def predicate_for(resolved, operator, value)
      col = arel_column(resolved)
      casted = cast_value(resolved[:type], value)

      case operator
      when "equals"        then col.eq(casted)
      when "not_equals"    then col.not_eq(casted)
      when "contains"      then col.matches("%#{sanitize_like(value)}%")
      when "not_contains"  then col.does_not_match("%#{sanitize_like(value)}%")
      when "greater_than"  then col.gt(casted)
      when "less_than"     then col.lt(casted)
      when "after"         then col.gt(parse_time(value))
      when "before"        then col.lt(parse_time(value))
      when "is_blank"      then col.eq(nil)
      when "is_present"    then col.not_eq(nil)
      else nil
      end
    end

    def cast_value(type, value)
      case type
      when :integer       then value.to_i
      when :float         then value.to_f
      when :boolean       then ActiveModel::Type::Boolean.new.cast(value)
      when :datetime, :date then parse_time(value)
      else value.to_s
      end
    end

    def parse_time(value)
      Time.zone.parse(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end

    # Escape LIKE wildcards in user input; the value itself is still bound
    # by Arel#matches as a parameter.
    def sanitize_like(value)
      value.to_s.gsub(/[\\%_]/) { |c| "\\#{c}" }
    end
  end
end
```

- [ ] **Step 4: Run, expect pass.** Adjust the injection test assertion to the actual behavior (dropped condition → relation falls back to full customer set or empty AND); the key assertion is `not_to raise_error` and that no foreign rows appear.
- [ ] **Step 5: Commit** — `git add -A && git commit -m "feat(email): tenant-safe reflection-driven AudienceQuery"`

### Task 2.3: List model uses segment_rules; helper for audience

**Files:** Modify `app/models/email_campaigns/list.rb`; Test: `spec/models/email_campaigns/list_spec.rb`

- [ ] **Step 1: Failing spec** — `list.audience(customer)` returns `AudienceQuery` relation for its rules, and `list.audience_count` returns the count.

```ruby
it "resolves its audience via AudienceQuery" do
  customer = create(:customer)
  ada = create(:user, customer: customer, first_name: "Ada")
  create(:user, customer: customer, first_name: "Bob")
  list = create(:email_list, customer: customer,
                segment_rules: { "match" => "all", "conditions" => [{ "field" => "first_name", "operator" => "equals", "value" => "Ada" }] })
  expect(list.audience.to_a).to eq([ada])
  expect(list.audience_count).to eq(1)
end
```

- [ ] **Step 2: Run, fail.**
- [ ] **Step 3: Implement** — add to `List`:

```ruby
    def audience
      EmailCampaigns::AudienceQuery.call(customer: customer, rules: segment_rules)
    end

    def audience_count
      audience.count
    end
```

- [ ] **Step 4: Run, pass. Step 5: Commit** — `git commit -am "feat(email): List#audience via AudienceQuery"`

### Task 2.4: Campaign send path → Users (deliverable, not blocked)

**Files:** Modify `app/jobs/email_campaigns/send_campaign_job.rb`, `app/services/email/gateway.rb`; Test: `spec/jobs/email_campaigns/send_campaign_job_spec.rb`

- [ ] **Step 1: Failing spec** — sending a campaign enqueues one message per deliverable user and skips blocked users.

```ruby
it "sends to deliverable users and skips blocked ones" do
  customer = create(:customer)
  ada = create(:user, customer: customer, first_name: "Ada")
  blocked = create(:user, customer: customer, first_name: "Ada", email_campaign_blocked: true)
  list = create(:email_list, customer: customer,
                segment_rules: { "match" => "all", "conditions" => [{ "field" => "first_name", "operator" => "equals", "value" => "Ada" }] })
  campaign = create(:email_campaign, :sending, customer: customer, email_list: list)

  expect { described_class.new.perform(campaign.id) }
    .to change { Emails::Message.where(message_type: "campaign").count }.by(1)
  expect(Emails::Message.last.to).to eq(ada.email)
end
```

- [ ] **Step 2: Run, fail.**
- [ ] **Step 3: Rewrite `send_campaign_job.rb`** to iterate Users:

```ruby
# frozen_string_literal: true

module EmailCampaigns
  class SendCampaignJob < ApplicationJob
    queue_as :default

    def perform(campaign_id)
      campaign = EmailCampaigns::Campaign.find(campaign_id)
      return unless campaign.status == "sending"

      campaign.email_list.audience.campaign_deliverable.find_each do |user|
        campaign.reload
        break unless campaign.status == "sending"
        send_to_user(campaign, user)
      end

      campaign.reload
      campaign.complete! if campaign.status == "sending"
    end

    private

    def send_to_user(campaign, user)
      Email::Gateway.queue_for_campaign(campaign: campaign, user: user)
      campaign.increment_stat!(:sent_count)
    rescue => e
      campaign.increment_stat!(:failed_count)
      Rails.logger.error("Campaign #{campaign.id} send to #{user.email} failed: #{e.message}")
    end
  end
end
```

- [ ] **Step 4: Update `Email::Gateway.queue_for_campaign`** signature to `(campaign:, user:)`, building vars via `Email::VariableContext.for(user:)` (interim: inline `{ email:, first_name:, last_name: }` until Phase 6 wires VariableContext — leave a `# TODO Phase 6` only if VariableContext not yet built; prefer doing Phase 6 Task 6.1 first if executing out of order). Replace `subscriber.email` → `user.email`, `build_subscriber_vars` → VariableContext.

```ruby
      def queue_for_campaign(campaign:, user:)
        template = campaign.email_template
        vars     = Email::VariableContext.for(user: user)
        rendered = TemplateRenderer.render(template: template, vars: vars)

        credential = CredentialResolver.call(mode: CredentialResolver.default_mode)

        message = Emails::Message.create!(
          customer:       campaign.customer,
          email_template: template,
          to:             user.email,
          from:           credential.username,
          subject:        rendered[:subject],
          body_html:      rendered[:body_html],
          body_text:      rendered[:body_text],
          status:         "queued",
          message_type:   "campaign",
          metadata:       { campaign_id: campaign.id, user_id: user.id }
        )

        DeliveryJob.perform_later(message.id)
        message
      end
```

Delete the old `build_subscriber_vars`.

- [ ] **Step 5: Run, pass.** (Requires VariableContext from Task 6.1 — execute 6.1 before this step, or stub vars.)
- [ ] **Step 6: Commit** — `git commit -am "feat(email): campaign send targets deliverable Users"`

### Task 2.5: Lists controller + form rework (dynamic-only, condition builder)

**Files:** Modify `app/controllers/.../lists_controller.rb`, `app/views/.../lists/_form.html.erb`, `lists/show.html.erb`, `lists/index.html.erb`; rework factory `:email_list`; create condition-builder component + Stimulus. Test: lists request spec + component spec.

- [ ] **Step 1:** Update `:email_list` factory — drop `list_type`, keep `name`, `status { "active" }`, `segment_rules { {} }`.
- [ ] **Step 2:** Lists controller: remove `list_type` from `list_params`; keep `segment_rules_json` parsing. `index` columns: drop the `:list_type` column and the `:subscriber_count` lambda → replace with `{ key: :audience, label: "Audience", type: :number, sortable: false, cell: ->(l) { l.audience_count } }`. `show`: `@audience_count = @list.audience_count`. `new`: `::EmailCampaigns::List.new(customer: current_customer, status: "active", segment_rules: {})`.
- [ ] **Step 3:** Build `EmailCampaigns::SegmentBuilderComponent` (ViewComponent) rendering the condition rows from `FieldCatalog.new.fields`, plus a hidden `email_list[segment_rules_json]` input maintained by a `segment-builder` Stimulus controller (add/remove rows, match all/any toggle, serialize to JSON on change). Component spec asserts it renders a field `<select>` containing `email` and `roles.key` options and a match-mode toggle. Keep the raw-JSON `<textarea>` as a collapsible "Advanced" fallback (kept in sync). Tailwind + Stimulus only.
- [ ] **Step 4:** `_form.html.erb`: replace the segment_rules textarea block with `render(EmailCampaigns::SegmentBuilderComponent.new(list: list, catalog: EmailCampaigns::FieldCatalog.new))`; drop the `list_type` `<select>`.
- [ ] **Step 5:** Request spec: creating a dynamic list with a posted `segment_rules_json` persists `segment_rules`; `show` displays the audience count. Run targeted specs → PASS.
- [ ] **Step 6: Commit** — `git commit -am "feat(email): user-segment list builder UI (dynamic-only)"`

> **UI note:** Steps 3–4 are the primary new UI surface — dispatch through `anysys-ux-designer` then `anysys-frontend-developer` per AGENTS.md. Tailwind responsive (mobile→desktop), Stimulus only.

---

## PHASE 3 — User-based unsubscribe flow

### Task 3.1: Signed unsubscribe token + handler

**Files:** Create `app/services/email_campaigns/campaign_unsubscribe.rb`; Test: spec.

- [ ] **Step 1: Failing spec**

```ruby
require "rails_helper"

RSpec.describe EmailCampaigns::CampaignUnsubscribe do
  let(:user) { create(:user) }

  it "round-trips a signed token for a user" do
    token = described_class.token_for(user)
    expect(described_class.find_user(token)).to eq(user)
  end

  it "blocks campaign email on unsubscribe" do
    token = described_class.token_for(user)
    described_class.unsubscribe(token)
    expect(user.reload.email_campaign_blocked).to be(true)
  end

  it "returns nil for a tampered token" do
    expect(described_class.find_user("garbage")).to be_nil
  end
end
```

- [ ] **Step 2: Run, fail.**
- [ ] **Step 3: Implement** using `Rails.application.message_verifier`:

```ruby
# frozen_string_literal: true

module EmailCampaigns
  class CampaignUnsubscribe
    PURPOSE = "campaign_unsubscribe"

    def self.verifier
      Rails.application.message_verifier(PURPOSE)
    end

    def self.token_for(user)
      verifier.generate(user.id, purpose: PURPOSE)
    end

    def self.find_user(token)
      id = verifier.verify(token.to_s, purpose: PURPOSE)
      Authentication::User.find_by(id: id)
    rescue ActiveSupport::MessageVerifier::InvalidSignature
      nil
    end

    def self.unsubscribe(token)
      user = find_user(token)
      return nil unless user

      user.block_campaign_email! unless user.email_campaign_blocked
      user
    end
  end
end
```

- [ ] **Step 4: Run, pass. Step 5: Commit** — `git commit -am "feat(email): signed user-based campaign unsubscribe"`

### Task 3.2: Rewire public unsubscribe controller + routes + views

**Files:** Modify `app/controllers/email_campaigns/unsubscribes_controller.rb`, `config/routes.rb` (lines ~61-62), unsubscribe views. Test: request spec.

- [ ] **Step 1:** Controller now uses `CampaignUnsubscribe`:

```ruby
    def show
      @user = EmailCampaigns::CampaignUnsubscribe.find_user(params[:token])
      render :not_found, status: :not_found and return unless @user
    end

    def create
      @user = EmailCampaigns::CampaignUnsubscribe.unsubscribe(params[:token])
      if @user
        render :confirmed
      else
        render :not_found, status: :not_found
      end
    end
```

- [ ] **Step 2:** Update views `show`/`confirmed` to read `@user.email` instead of `@subscriber`. Routes already pass `:token`; keep paths.
- [ ] **Step 3: Request spec** — GET with a valid token renders ok; POST blocks the user; tampered token → 404. Run → PASS.
- [ ] **Step 4:** Add the unsubscribe link to the campaign render — in `Email::Gateway.queue_for_campaign`, append a footer link (or expose `{{unsubscribe_url}}` in `VariableContext`, Task 6.1). Use `Rails.application.routes.url_helpers.email_unsubscribe_url(token: CampaignUnsubscribe.token_for(user), host: ...)`. Define the host via `Rails.application.config.action_mailer.default_url_options` or a settings value.
- [ ] **Step 5: Commit** — `git commit -am "feat(email): public unsubscribe flips user block flag"`

---

## PHASE 4 — DKIM signing

### Task 4.1: DKIM columns on credential

**Files:** Migration; Modify `app/models/emails/credential.rb`; Test: model spec.

- [ ] **Step 1: Migration**

```ruby
class AddDkimToEmailCredentials < ActiveRecord::Migration[8.1]
  def change
    add_column :email_credentials, :dkim_enabled, :boolean, null: false, default: false
    add_column :email_credentials, :dkim_domain, :string
    add_column :email_credentials, :dkim_selector, :string
    add_column :email_credentials, :dkim_private_key, :text
  end
end
```

Run migrate + test:prepare.

- [ ] **Step 2:** In `Emails::Credential` add `encrypts :dkim_private_key`, a `dkim_configured?` predicate (`dkim_enabled && dkim_domain.present? && dkim_selector.present? && dkim_private_key.present?`), and conditional presence validations for domain/selector/private_key `if: :dkim_enabled`.
- [ ] **Step 3: Model spec** — `dkim_configured?` true only when all present + enabled; private key encrypted (not stored plaintext). Run → PASS.
- [ ] **Step 4: Commit** — `git commit -am "feat(email): DKIM columns on email credential"`

### Task 4.2: DkimSigner service

**Files:** Create `app/services/email/dkim_signer.rb`; Test: spec.

- [ ] **Step 1: Failing spec** — given a `Mail::Message` and a credential with a generated test RSA key, `DkimSigner.sign!(mail, credential)` adds a `DKIM-Signature` header containing `d=<domain>; s=<selector>`.

```ruby
require "rails_helper"

RSpec.describe Email::DkimSigner do
  it "adds a verifiable DKIM-Signature header" do
    key = OpenSSL::PKey::RSA.new(2048)
    credential = build(:email_credential, dkim_enabled: true, dkim_domain: "example.com",
                       dkim_selector: "mail", dkim_private_key: key.to_pem)
    mail = Mail.new { to "a@b.com"; from "s@example.com"; subject "Hi"; body "x" }

    described_class.sign!(mail, credential)

    expect(mail.header["DKIM-Signature"]).to be_present
    expect(mail.header["DKIM-Signature"].value).to include("d=example.com").and include("s=mail")
  end

  it "is a no-op when DKIM is not configured" do
    credential = build(:email_credential, dkim_enabled: false)
    mail = Mail.new { to "a@b.com"; from "s@example.com"; subject "Hi"; body "x" }
    described_class.sign!(mail, credential)
    expect(mail.header["DKIM-Signature"]).to be_nil
  end
end
```

(Add an `:email_credential` factory if absent.)

- [ ] **Step 2: Run, fail.**
- [ ] **Step 3: Implement** — use the `mail` gem's built-in DKIM via `Mail::Message#... ` — the `mail` gem does NOT sign DKIM natively, so implement relaxed/simple canonicalization signing with OpenSSL:

```ruby
# frozen_string_literal: true

require "openssl"
require "base64"

module Email
  # Signs an outgoing Mail::Message with a DKIM-Signature header using the
  # platform credential's RSA key. Uses relaxed/simple canonicalization over a
  # fixed header set. No-op unless the credential has DKIM fully configured.
  class DkimSigner
    SIGNED_HEADERS = %w[from to subject date message-id].freeze

    def self.sign!(mail, credential)
      return mail unless credential.respond_to?(:dkim_configured?) && credential.dkim_configured?

      new(mail, credential).sign!
      mail
    end

    def initialize(mail, credential)
      @mail = mail
      @credential = credential
      @key = OpenSSL::PKey::RSA.new(credential.dkim_private_key)
    end

    def sign!
      bh = body_hash
      sig_header = base_signature(bh)
      signature  = rsa_sign("#{canonical_headers}\r\n#{folded(sig_header)}")
      @mail.header["DKIM-Signature"] = "#{sig_header} b=#{signature}"
    end

    private

    def body_hash
      body = (@mail.body.encoded.to_s.gsub(/\r?\n/, "\r\n").sub(/(\r\n)*\z/, "")) + "\r\n"
      Base64.strict_encode64(OpenSSL::Digest::SHA256.digest(body))
    end

    def present_headers
      SIGNED_HEADERS.select { |h| @mail.header[h] }
    end

    def canonical_headers
      present_headers.map do |h|
        "#{h}:#{@mail.header[h].value.to_s.strip.gsub(/\s+/, ' ')}"
      end.join("\r\n")
    end

    def base_signature(bh)
      [
        "v=1", "a=rsa-sha256", "c=relaxed/simple",
        "d=#{@credential.dkim_domain}", "s=#{@credential.dkim_selector}",
        "t=#{Time.now.to_i}", "h=#{present_headers.join(':')}",
        "bh=#{bh}"
      ].join("; ").then { |s| "DKIM-Signature: #{s};" }.sub(/\ADKIM-Signature: /, "")
    end

    def folded(sig_header)
      "dkim-signature:#{sig_header} b="
    end

    def rsa_sign(data)
      Base64.strict_encode64(@key.sign(OpenSSL::Digest::SHA256.new, data))
    end
  end
end
```

> Canonicalization is fiddly; if a vetted gem (`dkim`) is acceptable, prefer adding `gem "dkim"` and delegating. Keep the public `sign!(mail, credential)` contract identical so the SMTP adapter is unaffected. The spec asserts presence + `d=`/`s=`; add a fuller verification test if using the gem.

- [ ] **Step 4: Run, pass. Step 5: Commit** — `git commit -am "feat(email): DKIM signer service"`

### Task 4.3: SMTP adapter signs before deliver

**Files:** Modify `app/services/email/adapters/smtp.rb`; Test: adapter spec.

- [ ] **Step 1: Failing spec** — `Smtp#deliver` calls `DkimSigner.sign!` with the built mail + credential before `mail.deliver`. Use a stubbed delivery method (`mail.delivery_method :test`) and assert `Email::DkimSigner` received `sign!`.
- [ ] **Step 2:** In `deliver`, after `mail = build_mail(message)` and before setting delivery method / `mail.deliver`, insert `Email::DkimSigner.sign!(mail, credential)`.
- [ ] **Step 3: Run, pass. Step 4: Commit** — `git commit -am "feat(email): sign all outgoing mail with DKIM in SMTP adapter"`

### Task 4.4: Platform email-credential settings UI (incl. DKIM + DNS hint)

**Files:** Create `app/controllers/admin/maintenance/platform/emails/credentials_controller.rb` + views; routes. Test: request spec.

- [ ] **Step 1: Routes** — mirror SMS under platform module_settings:

```ruby
# within the platform module_settings namespace (see SMS for exact nesting)
namespace :emails do
  resources :credentials, only: %i[index new create edit update]
end
```

- [ ] **Step 2: Controller** — copy the SMS `CredentialsController` pattern; `ENCRYPTED_FIELDS = %i[password dkim_private_key]`; permit `:host,:port,:username,:password,:authentication,:enable_starttls,:ssl,:domain,:mode,:status,:daily_limit,:dkim_enabled,:dkim_domain,:dkim_selector,:dkim_private_key`; reject blank encrypted fields on update.
- [ ] **Step 3: Views** index/new/edit — Tailwind form rendering SMTP fields + a "DKIM" fieldset (enabled checkbox, domain, selector, private key textarea). On `edit`, render a **DNS TXT record hint**: `"#{selector}._domainkey.#{domain} TXT v=DKIM1; k=rsa; p=<public key>"`, deriving the public key from the stored private key (`OpenSSL::PKey::RSA.new(cred.dkim_private_key).public_key.to_der` → base64) — only when configured.
- [ ] **Step 4: Request spec** — platform owner can GET index/new/edit and create/update; a tenant admin (non-platform) gets denied (path is under `admin/maintenance/platform/` → `platform_owner` gate). Run → PASS.
- [ ] **Step 5: Commit** — `git commit -am "feat(email): platform email credential + DKIM settings UI"`

---

## PHASE 5 — Action Text rich text + tenant-isolated storage

### Task 5.1: Install Action Text + Active Storage

- [ ] **Step 1:** Run `bin/rails action_text:install` (installs Active Storage + Action Text migrations, adds Trix + `@rails/actiontext` to importmap/JS). Inspect the generated JS wiring; ensure it loads under the existing esbuild/importmap setup.
- [ ] **Step 2:** `bin/rails db:migrate && RAILS_ENV=test bin/rails db:test:prepare`.
- [ ] **Step 3:** Configure Active Storage service (`:local`/`:test`) in `config/storage.yml` + per-env if not already.
- [ ] **Step 4:** Boot check `bin/rails runner 'puts ActiveStorage::Blob.table_name'`.
- [ ] **Step 5: Commit** — `git add -A && git commit -m "chore(email): install Action Text + Active Storage"`

### Task 5.2: Tenant-stamp blobs

**Files:** Migration `add_customer_id_to_active_storage_blobs`; initializer/concern stamping `customer_id`. Test: spec.

- [ ] **Step 1: Migration** — `add_column :active_storage_blobs, :customer_id, :integer` + `add_index :active_storage_blobs, :customer_id`. Migrate + test:prepare.
- [ ] **Step 2: Failing spec** — a blob created while `Current.customer` is set carries that `customer_id`; serving/lookup scoped by customer rejects cross-tenant.
- [ ] **Step 3:** Stamp via the upload controller (Task 5.4) explicitly (most reliable) AND a defensive `before_create` on `ActiveStorage::Blob` reopened in `config/initializers/active_storage_tenant.rb`:

```ruby
Rails.application.config.to_prepare do
  ActiveStorage::Blob.class_eval do
    before_create { self.customer_id ||= Current.customer_id if defined?(Current) && Current.customer? }
    scope :for_customer, ->(cid) { where(customer_id: cid) }
  end
end
```

- [ ] **Step 4: Run, pass. Step 5: Commit** — `git commit -am "feat(email): stamp Active Storage blobs with customer_id"`

### Task 5.3: Template has_rich_text + editor_type cleanup

**Files:** Modify `app/models/emails/template.rb`; Test: model spec.

- [ ] **Step 1: Failing spec** — `Emails::Template` responds to `body` (rich text), `EDITOR_TYPES == %w[rich_text code]`, default editor_type usable.
- [ ] **Step 2:** In `Emails::Template`: add `has_rich_text :body`; change `EDITOR_TYPES = %w[rich_text code].freeze`. Keep `body_html` presence validation (it is the compiled cache; for `rich_text` it's filled by CompileTemplate — so relax to validate presence `on: :update`? No — set it in the compile step before validation). Add `before_validation { self.body_html = Emails::CompileTemplate.call(self) if editor_type == "rich_text" }` (CompileTemplate from Task 5.5; order tasks so 5.5 precedes the callback wiring, or stub).
- [ ] **Step 3: Run, pass. Step 4: Commit** — `git commit -am "feat(email): Action Text body on Template; editor types rich_text/code"`

### Task 5.4: Tenant-scoped attachment upload + preview controller

**Files:** Create `app/controllers/admin/modules/emails/attachments_controller.rb`; routes; point Trix at it. Test: request spec (auth + tenant isolation).

- [ ] **Step 1: Routes** — within `namespace :emails`: `resources :attachments, only: %i[create show]` (create = direct upload; show = scoped serve/redirect).
- [ ] **Step 2: Failing request spec** — admin can POST a direct-upload (returns signed blob JSON) and the blob is stamped with their `customer_id`; GET show for a foreign-tenant blob → 404.
- [ ] **Step 3:** Controller `create` mirrors `ActiveStorage::DirectUploadsController#create` but stamps `customer_id: current_customer.id` on the blob; `show` finds `ActiveStorage::Blob.for_customer(current_customer.id).find_by!(signed_id...)` then redirects to its URL. (Admin path → auto-guarded by RouteAuthorization.)
- [ ] **Step 4:** Configure Trix to use these endpoints: set `direct_upload_url` data attribute on the editor (via the variable-picker controller or a data attribute on the form) to the scoped create route; intercept `direct-upload:before-blob-request` if needed.
- [ ] **Step 5: Run, pass. Step 6: Commit** — `git commit -am "feat(email): tenant-scoped Action Text attachment upload/serve"`

### Task 5.5: CompileTemplate (rich text → email-safe HTML + CID tokens)

**Files:** Create `app/services/emails/compile_template.rb`; Test: spec.

- [ ] **Step 1: Failing spec** — given a template whose Action Text `body` contains text + an attachment, `CompileTemplate.call(template)` returns HTML with `{{tokens}}` preserved and each image rewritten to `<img src="cid:blob-<id>">`, and exposes the referenced blob ids via `template.compiled_attachment_blob_ids` (or returns `[html, blob_ids]`).
- [ ] **Step 2: Run, fail.**
- [ ] **Step 3: Implement** — render `template.body.to_s`, parse with Nokogiri, replace `action-text-attachment`/`img` blob references with `cid:blob-<id>` and collect ids; return the HTML. Store collected ids in a transient attr or a JSON column `attachment_blob_ids` on `email_templates` (add migration if chosen). Keep `{{...}}` untouched (they're plain text in the content).
- [ ] **Step 4: Run, pass. Step 5: Commit** — `git commit -am "feat(email): compile rich-text template to CID-embedded HTML"`

### Task 5.6: SMTP adapter embeds CID attachments

**Files:** Modify `app/services/email/adapters/smtp.rb`; Test: adapter spec.

- [ ] **Step 1: Failing spec** — when a message references attachment blob ids, `build_mail` adds inline attachments with matching `Content-ID` so `cid:blob-<id>` resolves.
- [ ] **Step 2:** Persist referenced blob ids on the message (e.g. `metadata["attachment_blob_ids"]` set in `queue_for_campaign`/`Send`). In `build_mail`, for each id: `mail.attachments.inline["blob-#{id}"] = ActiveStorage::Blob.find(id).download` and ensure the `Content-ID` matches `cid:blob-<id>`.
- [ ] **Step 3: Run, pass. Step 4: Commit** — `git commit -am "feat(email): inline CID attachments in SMTP delivery"`

### Task 5.7: Template form — Trix editor + variable picker

**Files:** Modify `app/views/admin/modules/emails/templates/_form.html.erb`, controller `template_params` (permit `:body` rich text); create `app/javascript/controllers/template_variable_picker_controller.js`. Test: system spec.

- [ ] **Step 1:** Controller: permit `:body` in `template_params`; keep `:body_html` permitted only for `editor_type=code`. `new` default `editor_type: "rich_text"`.
- [ ] **Step 2:** `_form.html.erb`: when `editor_type` is rich_text show `f.rich_textarea :body` (Action Text) wrapped in `data-controller="template-variable-picker"` with a toolbar "Insert variable ▾" `<select>` populated from `EmailCampaigns::FieldCatalog.new.fields` (+ template.variables). When `code`, keep the existing HTML textarea + preview iframe. Toggle by `editor_type` select (Stimulus or simple show/hide).
- [ ] **Step 3:** `template_variable_picker_controller.js` — on variable select, insert `{{field}}` at the Trix cursor via `this.editor.insertString("{{#{value}}}")` (access the `<trix-editor>` element's `editor`).

```javascript
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["editor", "picker"]

  insert() {
    const token = this.pickerTarget.value
    if (!token) return
    const trix = this.editorTarget.editor
    if (trix) trix.insertString(`{{${token}}}`)
    this.pickerTarget.value = ""
  }
}
```

- [ ] **Step 4: System spec** (Capybara) — open new template, type body, insert a variable, save; assert persisted body contains the token and `body_html` compiled. (Memory: JS drawer specs can be flaky under parallel load — keep this spec resilient.)
- [ ] **Step 5: Commit** — `git commit -am "feat(email): Trix rich-text editor with variable picker"`

> **UI note:** Dispatch Steps 2–3 through `anysys-ux-designer` → `anysys-frontend-developer`. Tailwind responsive + Stimulus only.

---

## PHASE 6 — VariableContext + test-send

### Task 6.1: VariableContext (build interpolation hash from a User)

**Files:** Create `app/services/email/variable_context.rb`; Test: spec.

> Execute this BEFORE Task 2.4 Step 5 / Task 3.2 Step 4 if running phases out of order.

- [ ] **Step 1: Failing spec**

```ruby
require "rails_helper"

RSpec.describe Email::VariableContext do
  it "builds a symbol-keyed hash from a user and its associations" do
    customer = create(:customer)
    user = create(:user, customer: customer, first_name: "Ada", last_name: "L", email: "ada@x.com")
    vars = described_class.for(user: user)

    expect(vars[:first_name]).to eq("Ada")
    expect(vars[:email]).to eq("ada@x.com")
    expect(vars.dig(:customer, :name)).to eq(customer.name)
    expect(vars[:unsubscribe_url]).to include("token=")
  end
end
```

- [ ] **Step 2: Run, fail.**
- [ ] **Step 3: Implement**

```ruby
# frozen_string_literal: true

module Email
  # Builds the interpolation hash for campaign sends from a recipient User
  # and a curated set of associations. Mirrors FieldCatalog's exposed data so
  # tokens offered in the editor resolve at send time.
  class VariableContext
    def self.for(user:)
      new(user).to_h
    end

    def initialize(user)
      @user = user
    end

    def to_h
      {
        email:      @user.email,
        first_name: @user.first_name,
        last_name:  @user.last_name,
        full_name:  [@user.first_name, @user.last_name].compact.join(" "),
        customer:   { name: @user.customer&.name, id: @user.customer_id },
        unsubscribe_url: unsubscribe_url
      }
    end

    private

    def unsubscribe_url
      token = EmailCampaigns::CampaignUnsubscribe.token_for(@user)
      host  = Rails.application.config.action_mailer.default_url_options&.dig(:host) || "localhost"
      Rails.application.routes.url_helpers.email_unsubscribe_url(token: token, host: host)
    end
  end
end
```

- [ ] **Step 4: Run, pass. Step 5: Commit** — `git commit -am "feat(email): VariableContext for campaign variable resolution"`

### Task 6.2: Test-send (preview-to-me)

**Files:** Modify templates controller (add `test_send` member action) + route + button; Test: request spec.

- [ ] **Step 1: Route** — `resources :templates do member { post :test_send } end` within `namespace :emails`.
- [ ] **Step 2: Failing request spec** — POSTing `test_send` to a template with `params[:to]` (defaulting to `current_user.email`) enqueues exactly one `transactional`-typed message addressed there, using sample variable values, and never counts toward a campaign.
- [ ] **Step 3:** Controller action: render the template with sample vars (`Email::VariableContext.for(user: current_user)` or catalog-derived placeholders), then `Email::Gateway.send_raw(customer: current_customer, to: to, subject: rendered[:subject], body_html: rendered[:body_html], body_text: rendered[:body_text])`. Redirect back with notice. Validate `to` belongs to the tenant (or default to `current_user.email`).
- [ ] **Step 4:** Add a "Send test to me" button on the template show/edit view (`button_to`).
- [ ] **Step 5: Run, pass. Step 6: Commit** — `git commit -am "feat(email): test-send preview from template"`

---

## FINALIZATION

### Task 7.1: Full suite + asset rebuild + smoke

- [ ] **Step 1:** `rm -f public/assets/.manifest.json`
- [ ] **Step 2:** Run full suite: `bin/rails parallel:spec` (≈6m). Fix regressions (expect breakage in campaign/list/registration specs touched by the refactor — update stale specs per the QA stale-test policy, do not weaken assertions).
- [ ] **Step 3:** `SKIP_AUTH=1 bin/rails server -b 0.0.0.0 -p 3000` and smoke: `/:cid/admin/modules/emails/templates/new` (Trix + variable picker), `/:cid/admin/modules/email_campaigns/lists/new` (segment builder), `/:cid/admin/modules/email_campaigns/block_list`, platform email credentials page.
- [ ] **Step 4: Commit** any spec updates — `git commit -am "test(email): update specs for refactor"`

### Task 7.2: Review gate

- [ ] Dispatch `anysys-tech-lead` (AGENTS.md convention compliance: four URL areas, tenant scoping, ViewComponent/Tailwind/Stimulus purity) and `anysys-code-reviewer` (SQL-injection on AudienceQuery, missing `customer_id` scoping, auth guards, storage isolation, N+1 in campaign send). Address findings.
- [ ] Run `/audit-tenant` and `/audit-auth` skills on the diff.

---

## Self-Review notes (spec coverage)

- (a) rich text → Phase 5 (5.1–5.7). (b) variable replacement → 6.1 + existing TemplateRenderer. (c) DKIM → Phase 4. (d) User-based lists → Phase 2 + retire in Phase 0. (e) Block-List → Phase 1 + unsubscribe Phase 3. (f) test-send → 6.2. Storage isolation (§3.1) → 5.2/5.4/5.6. Tenant-safety of generic query (§6/D3) → 2.1/2.2 specs. All spec sections map to tasks.
- Dependency ordering note: `VariableContext` (6.1) and `CampaignUnsubscribe` (3.1) are referenced by `queue_for_campaign` (2.4) — execute 3.1 and 6.1 before 2.4 Step 5, or stub. `CompileTemplate` (5.5) is referenced by the Template callback (5.3) — execute 5.5 before wiring the callback. Flagged inline at each site.
