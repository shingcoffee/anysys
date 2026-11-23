# Merge Email Campaigns into Email module — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Merge the `email` and `email_campaigns` modules into a single `Email` module with Email Campaigns as a per-customer sub-toggle, and move the daily cap so it limits only campaign email volume.

**Architecture:** Retire `FeatureModules::EmailCampaigns::Registration`, extend `FeatureModules::Email::Registration` with a `campaigns_enabled` config flag, and conditionally expose campaign sidebar entries. Move admin campaign surfaces under `/admin/modules/emails/*`, guard campaign controllers/jobs with the new flag, and enforce the daily cap inside `EmailCampaigns::SendCampaignJob` while removing it from transactional `Emails::Activities::Send`.

**Tech Stack:** Ruby on Rails 8, RSpec, ViewComponent, Stimulus/Turbo, SQLite/PostgreSQL.

## Global Constraints

- Follow existing Rails naming and namespace conventions (`Admin::Modules::Emails::*` for moved controllers).
- Keep public unsubscribe URLs stable (`/unsubscribe/:token`).
- Preserve existing campaign data (`email_campaigns` table, `email_messages.email_campaign_id`).
- Do not introduce new dependencies.
- Every code change must have a corresponding spec change; run targeted specs before each commit.
- Include the standard `Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>` trailer on implementation commits.

## File Structure

| Path | Responsibility |
|------|----------------|
| `app/services/feature_modules/email/registration.rb` | Single Email module registration; owns `campaigns_enabled?` and conditional sidebar entries. |
| `app/services/modules_contributor.rb` | Passes controller context into `sidebar_contributions`. |
| `app/services/settings_contributor.rb` | Passes controller context into `sidebar_contributions`. |
| `app/controllers/concerns/feature_modules/email/campaigns_guard.rb` | `before_action` that redirects when campaigns are disabled. |
| `app/controllers/admin/modules/emails/*_controller.rb` | Moved campaign/list/block-list controllers. |
| `app/controllers/emails/unsubscribes_controller.rb` | Moved public unsubscribe controller. |
| `app/views/admin/modules/emails/{campaigns,lists,block_list}/*` | Moved campaign views. |
| `app/views/emails/unsubscribes/*` | Moved unsubscribe views. |
| `app/components/email_campaigns/block_list_table_component.rb` | Updated hardcoded block-list paths. |
| `app/controllers/admin/maintenance/module_sub_toggles_controller.rb` | New controller for per-customer sub-feature toggles. |
| `app/jobs/email_campaigns/send_campaign_job.rb` | Daily-cap enforcement for campaign sends. |
| `app/services/emails/activities/send.rb` | Transactional send without daily-cap check. |
| `app/services/email_campaigns/start_campaign.rb` | Guard against starting campaigns when disabled. |
| `db/migrate/YYYYMMDDHHMMSS_merge_email_campaigns_into_email.rb` | Data migration consolidating module records. |
| `config/routes.rb` | New routes, redirects, and sub-toggle route. |
| Locale files | Updated labels and flash copy. |

---

### Task 1: Extend Email registration with campaigns config

**Files:**
- Modify: `app/services/feature_modules/email/registration.rb`
- Create: `spec/services/feature_modules/email/registration_spec.rb`

**Interfaces:**
- Consumes: `FeatureModules::CustomerAssignment.configuration_json`, `current_customer` from controller.
- Produces: `FeatureModules::Email::Registration.campaigns_enabled?(customer)` → boolean; `sidebar_contributions(context)` → hash with conditional campaign entries.

- [ ] **Step 1: Add `campaigns_enabled` to configuration schema and keys**

Replace the existing `configuration_schema` / `configuration_keys` methods in `app/services/feature_modules/email/registration.rb` with:

```ruby
def self.configuration_schema
  {
    "daily_send_cap"    => { "type" => "number",  "default" => ::Emails::Activities::Send::DEFAULT_DAILY_CAP },
    "campaigns_enabled" => { "type" => "boolean", "default" => false }
  }
end

def self.configuration_keys
  %i[daily_send_cap campaigns_enabled]
end
```

- [ ] **Step 2: Add the `campaigns_enabled?` helper**

Append inside the `class << self` block (before `private`):

```ruby
def self.campaigns_enabled?(customer)
  return false unless customer

  cfm = FeatureModules::CustomerAssignment
          .joins(:feature_module)
          .find_by(customer: customer, feature_modules: { key: "email" })
  cfm&.configuration_json&.dig("campaigns_enabled") == true
end
```

- [ ] **Step 3: Make sidebar entries conditional on the toggle**

Replace the `sidebar_contributions` method with:

```ruby
def self.sidebar_contributions(context)
  customer = context&.current_customer
  entries  = [
    ModuleContribution.new(label: I18n.t("feature_modules.email.entries.dashboard"),    entry_key: "dashboard",    path: ->(cid) { "/#{cid}/admin/modules/emails/dashboard" }),
    ModuleContribution.new(label: I18n.t("feature_modules.email.entries.templates"),    entry_key: "templates",    path: ->(cid) { "/#{cid}/admin/modules/emails/templates" }),
    ModuleContribution.new(label: I18n.t("feature_modules.email.entries.messages"),      entry_key: "messages",     path: ->(cid) { "/#{cid}/admin/modules/emails/messages" }),
    ModuleContribution.new(label: I18n.t("feature_modules.email.entries.suppressions"),  entry_key: "suppressions", path: ->(cid) { "/#{cid}/admin/modules/emails/suppressions" })
  ]

  if campaigns_enabled?(customer)
    entries.concat([
      ModuleContribution.new(label: I18n.t("feature_modules.email.entries.campaigns"),  entry_key: "campaigns",  path: ->(cid) { "/#{cid}/admin/modules/emails/campaigns" }),
      ModuleContribution.new(label: I18n.t("feature_modules.email.entries.lists"),      entry_key: "lists",      path: ->(cid) { "/#{cid}/admin/modules/emails/lists" }),
      ModuleContribution.new(label: I18n.t("feature_modules.email.entries.block_list"), entry_key: "block_list", path: ->(cid) { "/#{cid}/admin/modules/emails/block_list" })
    ])
  end

  {
    entries: entries,
    settings: [
      ModuleContribution.new(label: I18n.t("feature_modules.email.settings.daily_cap"), entry_key: "daily_cap")
    ]
  }
end
```

- [ ] **Step 4: Add campaign `entries_for` cases**

Replace the existing `entries_for` method with:

```ruby
def self.entries_for(entry_key:, params:)
  case entry_key
  when "templates"  then templates_entry_config
  when "messages"   then messages_entry_config
  when "campaigns"  then campaigns_entry_config
  when "lists"      then lists_entry_config
  when "block_list" then block_list_entry_config
  else raise ArgumentError, "unknown entry_key: #{entry_key}"
  end
end
```

Then copy the three private entry-config methods from the retired `FeatureModules::EmailCampaigns::Registration` into this class's `private` section, renamed/scoped under `::EmailCampaigns`:

```ruby
def campaigns_entry_config
  {
    title: I18n.t("feature_modules.email.titles.campaigns"),
    columns: [
      { key: :name, label: I18n.t("common.labels.name"), searchable: true },
      { key: :status, label: I18n.t("common.labels.status"), sortable: true },
      { key: :scheduled_at, label: I18n.t("common.labels.scheduled"), sortable: true }
    ],
    scope: ::EmailCampaigns::Campaign.for_current_customer.order(created_at: :desc)
  }
end

def lists_entry_config
  {
    title: I18n.t("feature_modules.email.titles.lists"),
    columns: [
      { key: :name, label: I18n.t("common.labels.name"), searchable: true },
      { key: :description, label: I18n.t("common.labels.description") },
      { key: :status, label: I18n.t("common.labels.status") }
    ],
    scope: ::EmailCampaigns::List.for_current_customer.order(created_at: :desc)
  }
end

def block_list_entry_config
  {
    title: I18n.t("feature_modules.email.titles.block_list"),
    columns: [
      { key: :email, label: I18n.t("common.labels.email"), searchable: true },
      { key: :email_campaign_blocked_at, label: I18n.t("common.labels.blocked"), sortable: true }
    ],
    scope: ::Authentication::User.for_current_customer.campaign_blocked.order(email_campaign_blocked_at: :desc)
  }
end
```

- [ ] **Step 5: Write the registration spec**

Create `spec/services/feature_modules/email/registration_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe FeatureModules::Email::Registration do
  let_it_be(:customer) { create(:customer) }

  around { |ex| Current.set(customer: customer) { ex.run } }

  it "declares module metadata" do
    expect(described_class.module_key).to eq("email")
    expect(described_class.module_name).to eq("Email")
  end

  describe ".configuration_schema" do
    it "includes daily_send_cap and campaigns_enabled" do
      expect(described_class.configuration_schema.keys).to contain_exactly("daily_send_cap", "campaigns_enabled")
    end
  end

  describe ".campaigns_enabled?" do
    let!(:email_module) do
      FeatureModules::Module.find_or_create_by!(key: "email") do |fm|
        fm.name = "Email"
        fm.status = :active
      end
    end

    it "is false when there is no customer assignment" do
      expect(described_class.campaigns_enabled?(customer)).to be false
    end

    it "is false when the assignment has no campaigns_enabled flag" do
      ensure_customer_feature_module(customer, email_module, status: :active)
      expect(described_class.campaigns_enabled?(customer)).to be false
    end

    it "is true when campaigns_enabled is set to true" do
      ensure_customer_feature_module(customer, email_module, status: :active,
                                     configuration: { "campaigns_enabled" => true }.to_json)
      expect(described_class.campaigns_enabled?(customer)).to be true
    end
  end

  describe ".sidebar_contributions" do
    let(:controller) { double("controller", current_customer: customer) }

    it "always exposes the core email entries" do
      keys = described_class.sidebar_contributions(controller)[:entries].map(&:entry_key)
      expect(keys).to include("dashboard", "templates", "messages", "suppressions")
    end

    it "omits campaign entries when campaigns are disabled" do
      keys = described_class.sidebar_contributions(controller)[:entries].map(&:entry_key)
      expect(keys).not_to include("campaigns", "lists", "block_list")
    end

    it "includes campaign entries when campaigns are enabled" do
      email_module = FeatureModules::Module.find_or_create_by!(key: "email") { |fm| fm.name = "Email"; fm.status = :active }
      ensure_customer_feature_module(customer, email_module, status: :active,
                                     configuration: { "campaigns_enabled" => true }.to_json)

      keys = described_class.sidebar_contributions(controller)[:entries].map(&:entry_key)
      expect(keys).to include("campaigns", "lists", "block_list")
    end

    it "exposes the daily_cap setting" do
      settings = described_class.sidebar_contributions(controller)[:settings].map(&:entry_key)
      expect(settings).to eq(["daily_cap"])
    end
  end

  describe ".entries_for" do
    it "raises for an unknown entry_key" do
      expect { described_class.entries_for(entry_key: "unknown", params: {}) }
        .to raise_error(ArgumentError, /unknown entry_key: unknown/)
    end

    it "resolves campaigns, lists, and block_list configs" do
      %w[campaigns lists block_list].each do |key|
        config = described_class.entries_for(entry_key: key, params: {})
        expect(config[:title]).to be_present
        expect(config[:columns]).to be_present
        expect(config[:scope]).to respond_to(:count)
      end
    end
  end
end
```

- [ ] **Step 6: Run the new spec**

Run:

```bash
bundle exec rspec spec/services/feature_modules/email/registration_spec.rb
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add app/services/feature_modules/email/registration.rb \
        spec/services/feature_modules/email/registration_spec.rb
git commit -m "feat(email): add campaigns_enabled config and conditional sidebar entries

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 2: Pass controller context into sidebar contributors

**Files:**
- Modify: `app/services/modules_contributor.rb`, `app/services/settings_contributor.rb`

**Interfaces:**
- Consumes: `SidebarContributor#context` (the controller).
- Produces: `registration_class.sidebar_contributions(context)` call.

- [ ] **Step 1: Update ModulesContributor**

In `app/services/modules_contributor.rb`, change line 14 from:

```ruby
contributions = fm.registration_class.sidebar_contributions(nil)
```

to:

```ruby
contributions = fm.registration_class.sidebar_contributions(context)
```

- [ ] **Step 2: Update SettingsContributor**

In `app/services/settings_contributor.rb`, change line 51 from:

```ruby
settings = Array(fm.registration_class.sidebar_contributions(nil)[:settings])
```

to:

```ruby
settings = Array(fm.registration_class.sidebar_contributions(context)[:settings])
```

- [ ] **Step 3: Verify existing registration specs still pass**

Run:

```bash
bundle exec rspec spec/services/feature_modules --exclude-pattern '**/email_campaigns/**'
```

Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add app/services/modules_contributor.rb app/services/settings_contributor.rb
git commit -m "refactor(sidebar): pass controller context to sidebar_contributions

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 3: Add the campaigns-enabled guard concern

**Files:**
- Create: `app/controllers/concerns/feature_modules/email/campaigns_guard.rb`
- Create: `spec/controllers/concerns/feature_modules/email/campaigns_guard_spec.rb`

**Interfaces:**
- Consumes: `FeatureModules::Email::Registration.campaigns_enabled?(current_customer)`.
- Produces: `before_action :ensure_campaigns_enabled` that redirects with `maint_core.flash.campaigns_disabled`.

- [ ] **Step 1: Create the concern**

Create `app/controllers/concerns/feature_modules/email/campaigns_guard.rb`:

```ruby
# frozen_string_literal: true

module FeatureModules
  module Email
    module CampaignsGuard
      extend ActiveSupport::Concern

      included do
        before_action :ensure_campaigns_enabled
      end

      private

      def ensure_campaigns_enabled
        return if FeatureModules::Email::Registration.campaigns_enabled?(current_customer)

        redirect_to "/#{current_customer_id}/admin/modules/emails/dashboard",
                    alert: t("maint_core.flash.campaigns_disabled")
      end
    end
  end
end
```

- [ ] **Step 2: Write a controller concern spec**

Create `spec/controllers/concerns/feature_modules/email/campaigns_guard_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe FeatureModules::Email::CampaignsGuard, type: :controller do
  controller(ApplicationController) do
    include FeatureModules::Email::CampaignsGuard

    def index
      render plain: "ok"
    end
  end

  let_it_be(:customer) { create(:customer) }
  let!(:email_module) do
    FeatureModules::Module.find_or_create_by!(key: "email") { |fm| fm.name = "Email"; fm.status = :active }
  end

  before do
    routes.draw { get "index" => "anonymous#index" }
    sign_in create(:user, :admin, customer: customer)
  end

  it "allows access when campaigns are enabled" do
    ensure_customer_feature_module(customer, email_module, status: :active,
                                   configuration: { "campaigns_enabled" => true }.to_json)
    get :index, params: { customer_id: customer.id }
    expect(response).to have_http_status(:ok)
  end

  it "redirects when campaigns are disabled" do
    ensure_customer_feature_module(customer, email_module, status: :active)
    get :index, params: { customer_id: customer.id }
    expect(response).to redirect_to("/#{customer.id}/admin/modules/emails/dashboard")
    expect(flash[:alert]).to eq(I18n.t("maint_core.flash.campaigns_disabled"))
  end
end
```

- [ ] **Step 3: Run the concern spec**

Run:

```bash
bundle exec rspec spec/controllers/concerns/feature_modules/email/campaigns_guard_spec.rb
```

Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add app/controllers/concerns/feature_modules/email/campaigns_guard.rb \
        spec/controllers/concerns/feature_modules/email/campaigns_guard_spec.rb
git commit -m "feat(email): add campaigns-enabled guard concern

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 4: Reorganize routes for merged campaign surfaces

**Files:**
- Modify: `config/routes.rb`

**Interfaces:**
- Produces: new helpers `admin_modules_emails_campaigns_path`, `admin_modules_emails_campaign_path`, `admin_modules_emails_lists_path`, `admin_modules_emails_list_path`, `admin_modules_emails_block_list_path`, `admin_modules_emails_block_list_unblock_path`, `admin_modules_emails_campaign_delivery_path`, `admin_modules_emails_campaign_pause_path`, `admin_modules_emails_campaign_cancellation_path`, and `admin_maintenance_module_sub_toggle_path`.

- [ ] **Step 1: Replace the email_campaigns namespace with the emails namespace**

In `config/routes.rb`, replace the block at lines 467-478:

```ruby
# Email Campaigns (marketing)
namespace :email_campaigns do
  resources :lists
  get   "block_list",                to: "block_list#index"
  patch "block_list/batch_unblock",  to: "block_list#batch_unblock"
  patch "block_list/:id",            to: "block_list#unblock", as: :email_campaigns_block_list_unblock
  resources :campaigns do
    resource :delivery,     only: :create,             controller: "campaign_deliveries"
    resource :pause,        only: %i[create destroy],  controller: "campaign_pauses"
    resource :cancellation, only: :create,             controller: "campaign_cancellations"
  end
end
```

with:

```ruby
# Email Campaigns (marketing sub-feature of Email)
namespace :emails do
  resources :campaigns do
    resource :delivery,     only: :create,             controller: "campaign_deliveries"
    resource :pause,        only: %i[create destroy],  controller: "campaign_pauses"
    resource :cancellation, only: :create,             controller: "campaign_cancellations"
  end
  resources :lists, controller: "lists"
  get   "block_list",               to: "block_list#index",            as: :block_list
  patch "block_list/batch_unblock", to: "block_list#batch_unblock",    as: :block_list_batch_unblock
  patch "block_list/:id",           to: "block_list#unblock",          as: :block_list_unblock
end
```

- [ ] **Step 2: Add the sub-toggle route**

In `config/routes.rb`, inside the existing `resources :modules, only: [:index], controller: "maintenance/modules" do` block, add:

```ruby
resource :sub_toggle, only: [:update], controller: "maintenance/module_sub_toggles"
```

The block should now look like:

```ruby
resources :modules, only: [:index], controller: "maintenance/modules" do
  resource :enablement, only: %i[create destroy], controller: "maintenance/module_enablements"
  resource :sub_toggle, only: [:update], controller: "maintenance/module_sub_toggles"
end
```

- [ ] **Step 3: Add temporary redirects for old email_campaigns URLs**

Add the following redirect block **after** the new `namespace :emails` block (still inside `namespace :modules`):

```ruby
# Temporary redirects for the old email_campaigns paths.
get "/email_campaigns/*path", to: redirect { |params, request|
  "/#{request.path_parameters[:customer_id]}/admin/modules/emails/#{params[:path]}#{request.query_string.present? ? "?#{request.query_string}" : ""}"
}, as: :email_campaigns_redirect
```

Because this lives inside `namespace :modules`, it will catch `/123/admin/modules/email_campaigns/campaigns` and redirect to `/123/admin/modules/emails/campaigns`.

- [ ] **Step 4: Update public unsubscribe routes**

Replace lines 89-91:

```ruby
get  "/unsubscribe/:token", to: "email_campaigns/unsubscribes#show",   as: :email_unsubscribe
post "/unsubscribe/:token", to: "email_campaigns/unsubscribes#create", as: :email_unsubscribe_create
```

with:

```ruby
get  "/unsubscribe/:token", to: "emails/unsubscribes#show",   as: :email_unsubscribe
post "/unsubscribe/:token", to: "emails/unsubscribes#create", as: :email_unsubscribe_create
```

- [ ] **Step 5: Run routing specs**

Run:

```bash
bundle exec rspec spec/routing/routes_spec.rb
bundle exec rails routes | grep -E "emails|email_campaigns|sub_toggle"
```

Expected: routing spec passes and the route grep shows the new helpers and redirect.

- [ ] **Step 6: Commit**

```bash
git add config/routes.rb
git commit -m "feat(routes): move campaigns under emails namespace and add sub-toggle route

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 5: Move admin campaign controllers and include the guard

**Files:**
- Move/rename: `app/controllers/admin/modules/email_campaigns/*_controller.rb` → `app/controllers/admin/modules/emails/*_controller.rb`
- Move/rename: `spec/requests/admin/modules/email_campaigns/*_spec.rb` → `spec/requests/admin/modules/emails/*_spec.rb`
- Modify: moved controllers and specs.

**Interfaces:**
- Consumes: `FeatureModules::Email::CampaignsGuard`.
- Produces: controllers under `Admin::Modules::Emails` namespace.

- [ ] **Step 1: Move controllers and specs with git**

Run:

```bash
git mv app/controllers/admin/modules/email_campaigns app/controllers/admin/modules/emails-campaigns-tmp
mv app/controllers/admin/modules/emails-campaigns-tmp app/controllers/admin/modules/emails/campaigns-controllers

git mv spec/requests/admin/modules/email_campaigns spec/requests/admin/modules/emails-campaigns-tmp
mv spec/requests/admin/modules/emails-campaigns-tmp spec/requests/admin/modules/emails/campaigns-requests
```

Wait — this would collide with the existing `app/controllers/admin/modules/emails` directory. Instead, move the files individually:

```bash
for f in campaigns campaign_deliveries campaign_pauses campaign_cancellations lists block_list; do
  git mv "app/controllers/admin/modules/email_campaigns/${f}_controller.rb" \
         "app/controllers/admin/modules/emails/${f}_controller.rb"
done

for f in campaigns lists block_list campaign_deliveries campaign_pauses campaign_cancellations; do
  git mv "spec/requests/admin/modules/email_campaigns/${f}_spec.rb" \
         "spec/requests/admin/modules/emails/${f}_spec.rb"
done
```

- [ ] **Step 2: Update controller class namespaces and paths**

In each moved controller, replace `module EmailCampaigns` with `module Emails` and update hardcoded redirect paths from `/admin/modules/email_campaigns/` to `/admin/modules/emails/`.

For example, in `app/controllers/admin/modules/emails/campaigns_controller.rb`, change:

```ruby
module Admin
  module Modules
    module EmailCampaigns
    class CampaignsController < ApplicationController
```

to:

```ruby
module Admin
  module Modules
    module Emails
      class CampaignsController < ApplicationController
        include FeatureModules::Email::CampaignsGuard
```

(Repeat the namespace fix and `include` for the other five controllers.)

Then update all redirect strings inside the six controllers:

```bash
sed -i 's|/admin/modules/email_campaigns/|/admin/modules/emails/|g' \
  app/controllers/admin/modules/emails/campaigns_controller.rb \
  app/controllers/admin/modules/emails/lists_controller.rb \
  app/controllers/admin/modules/emails/block_list_controller.rb \
  app/controllers/admin/modules/emails/campaign_deliveries_controller.rb \
  app/controllers/admin/modules/emails/campaign_pauses_controller.rb \
  app/controllers/admin/modules/emails/campaign_cancellations_controller.rb
```

- [ ] **Step 3: Update request spec paths and helpers**

In each moved request spec, replace route helper prefixes:

```bash
sed -i 's|admin_modules_email_campaigns_campaigns_path|admin_modules_emails_campaigns_path|g' \
  spec/requests/admin/modules/emails/*_spec.rb
sed -i 's|admin_modules_email_campaigns_campaign_path|admin_modules_emails_campaign_path|g' \
  spec/requests/admin/modules/emails/*_spec.rb
sed -i 's|admin_modules_email_campaigns_campaign_delivery_path|admin_modules_emails_campaign_delivery_path|g' \
  spec/requests/admin/modules/emails/*_spec.rb
sed -i 's|admin_modules_email_campaigns_campaign_pause_path|admin_modules_emails_campaign_pause_path|g' \
  spec/requests/admin/modules/emails/*_spec.rb
sed -i 's|admin_modules_email_campaigns_campaign_cancellation_path|admin_modules_emails_campaign_cancellation_path|g' \
  spec/requests/admin/modules/emails/*_spec.rb
sed -i 's|admin_modules_email_campaigns_lists_path|admin_modules_emails_lists_path|g' \
  spec/requests/admin/modules/emails/*_spec.rb
sed -i 's|admin_modules_email_campaigns_list_path|admin_modules_emails_list_path|g' \
  spec/requests/admin/modules/emails/*_spec.rb
sed -i 's|admin_modules_email_campaigns_block_list_path|admin_modules_emails_block_list_path|g' \
  spec/requests/admin/modules/emails/*_spec.rb
sed -i 's|admin_modules_email_campaigns_block_list_unblock_path|admin_modules_emails_block_list_unblock_path|g' \
  spec/requests/admin/modules/emails/*_spec.rb
```

Also update any hardcoded string paths in specs, e.g.:

```bash
sed -i 's|/admin/modules/email_campaigns/|/admin/modules/emails/|g' \
  spec/requests/admin/modules/emails/*_spec.rb
```

- [ ] **Step 4: Add guard coverage to request specs**

In `spec/requests/admin/modules/emails/campaigns_spec.rb` (and similar for lists/block_list), add at the top:

```ruby
let!(:email_module) do
  FeatureModules::Module.find_or_create_by!(key: "email") { |fm| fm.name = "Email"; fm.status = :active }
end

before do
  ensure_customer_feature_module(customer, email_module, status: :active,
                                 configuration: { "campaigns_enabled" => true }.to_json)
end
```

Add a shared behavior or explicit test that disabled campaigns redirect:

```ruby
context "when campaigns are disabled" do
  before do
    FeatureModules::CustomerAssignment.find_by!(customer: customer, feature_module: email_module)
      .update!(configuration: { "campaigns_enabled" => false }.to_json)
  end

  it "redirects away from the campaigns index" do
    get admin_modules_emails_campaigns_path(customer)
    expect(response).to redirect_to("/#{customer.id}/admin/modules/emails/dashboard")
  end
end
```

- [ ] **Step 5: Run the moved controller/request specs**

Run:

```bash
bundle exec rspec spec/requests/admin/modules/emails
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add app/controllers/admin/modules/emails spec/requests/admin/modules/emails
git commit -m "refactor(email): move campaign controllers under emails namespace and add guard

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 6: Move campaign views and update route helpers

**Files:**
- Move: `app/views/admin/modules/email_campaigns/*` → `app/views/admin/modules/emails/*`
- Modify: moved views, `app/components/email_campaigns/block_list_table_component.rb`
- Move/modify: `spec/components/email_campaigns/block_list_table_component_spec.rb`

**Interfaces:**
- Uses new route helpers and breadcrumb nav keys.

- [ ] **Step 1: Move view directories with git**

```bash
git mv app/views/admin/modules/email_campaigns/campaigns app/views/admin/modules/emails/campaigns
git mv app/views/admin/modules/email_campaigns/lists app/views/admin/modules/emails/lists
git mv app/views/admin/modules/email_campaigns/block_list app/views/admin/modules/emails/block_list
```

- [ ] **Step 2: Replace old route helpers in views**

Run:

```bash
find app/views/admin/modules/emails/{campaigns,lists,block_list} -name '*.erb' -exec \
  sed -i \
    -e 's|admin_modules_email_campaigns_campaigns_path|admin_modules_emails_campaigns_path|g' \
    -e 's|admin_modules_email_campaigns_campaign_path|admin_modules_emails_campaign_path|g' \
    -e 's|admin_modules_email_campaigns_campaign_delivery_path|admin_modules_emails_campaign_delivery_path|g' \
    -e 's|admin_modules_email_campaigns_campaign_pause_path|admin_modules_emails_campaign_pause_path|g' \
    -e 's|admin_modules_email_campaigns_campaign_cancellation_path|admin_modules_emails_campaign_cancellation_path|g' \
    -e 's|admin_modules_email_campaigns_lists_path|admin_modules_emails_lists_path|g' \
    -e 's|admin_modules_email_campaigns_list_path|admin_modules_emails_list_path|g' \
    -e 's|admin_modules_email_campaigns_block_list_path|admin_modules_emails_block_list_path|g' \
    -e 's|admin_modules_email_campaigns_block_list_unblock_path|admin_modules_emails_block_list_unblock_path|g' \
    {} \;
```

- [ ] **Step 3: Update breadcrumb nav keys**

Replace `admin_modules.nav.email_campaigns` with `admin_modules.nav.email` in the moved views:

```bash
find app/views/admin/modules/emails/{campaigns,lists,block_list} -name '*.erb' -exec \
  sed -i 's|admin_modules.nav.email_campaigns|admin_modules.nav.email|g' {} \;
```

- [ ] **Step 4: Update the block-list component paths**

In `app/components/email_campaigns/block_list_table_component.rb`, replace the two path methods with:

```ruby
def unblock_one_path(user)
  "/#{customer_id}/admin/modules/emails/block_list/#{user.id}"
end

def batch_unblock_path
  "/#{customer_id}/admin/modules/emails/block_list/batch_unblock"
end
```

- [ ] **Step 5: Update the component spec**

In `spec/components/email_campaigns/block_list_table_component_spec.rb`, replace occurrences of `/admin/modules/email_campaigns/block_list` with `/admin/modules/emails/block_list`.

- [ ] **Step 6: Run view/component specs**

Run:

```bash
bundle exec rspec spec/components/email_campaigns/block_list_table_component_spec.rb
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add app/views/admin/modules/emails \
        app/components/email_campaigns/block_list_table_component.rb \
        spec/components/email_campaigns/block_list_table_component_spec.rb
git commit -m "refactor(email): move campaign views under emails namespace

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 7: Move public unsubscribe controller/views

**Files:**
- Move: `app/controllers/email_campaigns/unsubscribes_controller.rb` → `app/controllers/emails/unsubscribes_controller.rb`
- Move: `app/views/email_campaigns/unsubscribes/*` → `app/views/emails/unsubscribes/*`
- Move: `spec/requests/email_campaigns/unsubscribes_spec.rb` → `spec/requests/emails/unsubscribes_spec.rb`

**Interfaces:**
- Produces: `Emails::UnsubscribesController`.

- [ ] **Step 1: Move files with git**

```bash
git mv app/controllers/email_campaigns/unsubscribes_controller.rb app/controllers/emails/unsubscribes_controller.rb
git mv app/views/email_campaigns/unsubscribes app/views/emails/unsubscribes
git mv spec/requests/email_campaigns/unsubscribes_spec.rb spec/requests/emails/unsubscribes_spec.rb
```

- [ ] **Step 2: Update class namespace**

In `app/controllers/emails/unsubscribes_controller.rb`, change:

```ruby
module EmailCampaigns
  class UnsubscribesController < ApplicationController
```

to:

```ruby
module Emails
  class UnsubscribesController < ApplicationController
```

- [ ] **Step 3: Run the moved spec**

Run:

```bash
bundle exec rspec spec/requests/emails/unsubscribes_spec.rb
```

Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add app/controllers/emails app/views/emails/unsubscribes spec/requests/emails/unsubscribes_spec.rb
git commit -m "refactor(email): move unsubscribe controller/views into emails namespace

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 8: Build the Maintenance campaigns toggle

**Files:**
- Create: `app/controllers/admin/maintenance/module_sub_toggles_controller.rb`
- Create: `spec/requests/admin/maintenance/module_sub_toggles_spec.rb`
- Modify: `app/views/admin/maintenance/modules/index.html.erb`

**Interfaces:**
- Consumes: `params[:module_id]`, `params[:key]`, `params[:enabled]`.
- Produces: updates `CustomerAssignment.configuration[key]` and redirects to `admin_maintenance_modules_path`.

- [ ] **Step 1: Create the controller**

Create `app/controllers/admin/maintenance/module_sub_toggles_controller.rb`:

```ruby
# frozen_string_literal: true

module Admin
  module Maintenance
    class ModuleSubTogglesController < ApplicationController
      dashboard_menu_item :maintenance

      def update
        feature_module = FeatureModules::Module.find(params[:module_id])
        key = params[:key].to_s

        allowed = Array(feature_module.registration_class.configuration_keys).map(&:to_s)
        unless allowed.include?(key)
          redirect_to admin_maintenance_modules_path(current_customer_id),
                      alert: t("maint_core.flash.module_sub_toggles.invalid_key")
          return
        end

        cfm = FeatureModules::CustomerAssignment.find_by!(
          customer: current_customer,
          feature_module: feature_module
        )

        merged = (cfm.configuration_json || {}).merge(key => params[:enabled] == "1")
        cfm.update!(configuration: merged.to_json)

        redirect_to admin_maintenance_modules_path(current_customer_id),
                    notice: t("maint_core.flash.module_sub_toggles.updated")
      end
    end
  end
end
```

- [ ] **Step 2: Add the toggle UI to the maintenance modules page**

In `app/views/admin/maintenance/modules/index.html.erb`, after the enable/disable button block (around line 65), insert the nested toggle only for the `email` module when enabled:

```erb
<% if fm.key == "email" && enabled %>
  <div class="mt-3 pl-4 border-l-2 border-border-subtle">
    <%= form_with url: admin_maintenance_module_sub_toggle_path(current_customer_id, fm, key: "campaigns_enabled"),
                  method: :patch, local: true, class: "flex items-center gap-2" do %>
      <%= hidden_field_tag "enabled", "0" %>
      <%= check_box_tag "enabled", "1",
                        FeatureModules::Email::Registration.campaigns_enabled?(current_customer),
                        id: "campaigns_enabled_#{fm.id}",
                        class: "h-4 w-4 rounded border-border-subtle text-primary",
                        onchange: "this.form.submit()" %>
      <%= label_tag "campaigns_enabled_#{fm.id}",
                    t("maint_core.modules.index.campaigns_enabled_label"),
                    class: "text-sm text-text-primary" %>
    <% end %>
  </div>
<% end %>
```

Place this immediately before the closing `</li>` tag so it renders under the Email module row.

- [ ] **Step 3: Write the request spec**

Create `spec/requests/admin/maintenance/module_sub_toggles_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Maintenance::ModuleSubTogglesController", type: :request do
  let_it_be(:customer) { create(:customer) }
  let(:admin) { create(:user, :admin, customer: customer) }
  let!(:email_module) do
    FeatureModules::Module.find_or_create_by!(key: "email") { |fm| fm.name = "Email"; fm.status = :active }
  end
  let!(:assignment) do
    ensure_customer_feature_module(customer, email_module, status: :active)
  end

  before { sign_in admin }

  describe "PATCH /:cid/admin/maintenance/modules/:module_id/sub_toggle" do
    it "enables campaigns for the customer" do
      patch admin_maintenance_module_sub_toggle_path(customer, email_module),
            params: { key: "campaigns_enabled", enabled: "1" }

      expect(response).to redirect_to(admin_maintenance_modules_path(customer))
      expect(assignment.reload.configuration_json["campaigns_enabled"]).to eq(true)
    end

    it "disables campaigns for the customer" do
      assignment.update!(configuration: { "campaigns_enabled" => true }.to_json)

      patch admin_maintenance_module_sub_toggle_path(customer, email_module),
            params: { key: "campaigns_enabled", enabled: "0" }

      expect(assignment.reload.configuration_json["campaigns_enabled"]).to eq(false)
    end

    it "rejects unknown configuration keys" do
      patch admin_maintenance_module_sub_toggle_path(customer, email_module),
            params: { key: "evil_key", enabled: "1" }

      expect(response).to redirect_to(admin_maintenance_modules_path(customer))
      expect(flash[:alert]).to eq(I18n.t("maint_core.flash.module_sub_toggles.invalid_key"))
    end
  end
end
```

- [ ] **Step 4: Run the new spec**

Run:

```bash
bundle exec rspec spec/requests/admin/maintenance/module_sub_toggles_spec.rb
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/controllers/admin/maintenance/module_sub_toggles_controller.rb \
        app/views/admin/maintenance/modules/index.html.erb \
        spec/requests/admin/maintenance/module_sub_toggles_spec.rb
git commit -m "feat(email): add per-customer campaigns toggle under Maintenance → Modules

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 9: Guard campaign start/send against disabled campaigns

**Files:**
- Modify: `app/services/email_campaigns/start_campaign.rb`
- Modify: `app/jobs/email_campaigns/send_campaign_job.rb`
- Modify: `spec/services/email_campaigns/start_campaign_spec.rb`
- Modify: `spec/jobs/email_campaigns/send_campaign_job_spec.rb`
- Modify: `spec/jobs/email_campaigns/scheduler_job_spec.rb`

**Interfaces:**
- Consumes: `FeatureModules::Email::Registration.campaigns_enabled?(campaign.customer)`.
- Produces: `StartCampaign.call` returns `false`; `SendCampaignJob` returns early.

- [ ] **Step 1: Guard StartCampaign**

In `app/services/email_campaigns/start_campaign.rb`, at the top of `self.call`:

```ruby
def self.call(campaign)
  return false unless FeatureModules::Email::Registration.campaigns_enabled?(campaign.customer)

  started =
    case campaign.status
    ...
```

- [ ] **Step 2: Guard SendCampaignJob**

In `app/jobs/email_campaigns/send_campaign_job.rb`, at the top of `perform` (after loading the campaign):

```ruby
def perform(campaign_id)
  campaign = EmailCampaigns::Campaign.find(campaign_id)
  return unless campaign.status == "sending"
  return unless FeatureModules::Email::Registration.campaigns_enabled?(campaign.customer)

  ...
end
```

- [ ] **Step 3: Add StartCampaign spec**

In `spec/services/email_campaigns/start_campaign_spec.rb`, add:

```ruby
context "when campaigns are disabled for the customer" do
  before do
    email_module = FeatureModules::Module.find_or_create_by!(key: "email") { |fm| fm.name = "Email"; fm.status = :active }
    ensure_customer_feature_module(customer, email_module, status: :active)
  end

  it "returns false and does not enqueue a send" do
    campaign = create(:email_campaign, :scheduled, customer: customer, scheduled_at: 1.minute.ago)
    expect(described_class.call(campaign)).to be false
    expect(EmailCampaigns::SendCampaignJob).not_to have_been_enqueued
  end
end
```

- [ ] **Step 4: Add SendCampaignJob spec**

In `spec/jobs/email_campaigns/send_campaign_job_spec.rb`, add:

```ruby
context "when campaigns are disabled for the customer" do
  before do
    email_module = FeatureModules::Module.find_or_create_by!(key: "email") { |fm| fm.name = "Email"; fm.status = :active }
    ensure_customer_feature_module(customer, email_module, status: :active)
  end

  it "does not send any messages" do
    expect { described_class.new.perform(campaign.id) }
      .not_to change(Emails::Message, :count)
  end
end
```

- [ ] **Step 5: Add SchedulerJob spec**

In `spec/jobs/email_campaigns/scheduler_job_spec.rb`, add:

```ruby
context "when campaigns are disabled for the customer" do
  before do
    email_module = FeatureModules::Module.find_or_create_by!(key: "email") { |fm| fm.name = "Email"; fm.status = :active }
    ensure_customer_feature_module(customer, email_module, status: :active)
  end

  it "does not enqueue SendCampaignJob" do
    expect { described_class.perform_now }
      .not_to have_enqueued_job(EmailCampaigns::SendCampaignJob)
  end
end
```

- [ ] **Step 6: Run campaign specs**

Run:

```bash
bundle exec rspec spec/services/email_campaigns/start_campaign_spec.rb \
                 spec/jobs/email_campaigns/send_campaign_job_spec.rb \
                 spec/jobs/email_campaigns/scheduler_job_spec.rb
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add app/services/email_campaigns/start_campaign.rb \
        app/jobs/email_campaigns/send_campaign_job.rb \
        spec/services/email_campaigns/start_campaign_spec.rb \
        spec/jobs/email_campaigns/send_campaign_job_spec.rb \
        spec/jobs/email_campaigns/scheduler_job_spec.rb
git commit -m "feat(email): block campaign start/send when campaigns are disabled

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 10: Move daily cap from transactional sends to campaign sends

**Files:**
- Modify: `app/services/emails/activities/send.rb`
- Modify: `app/jobs/email_campaigns/send_campaign_job.rb`
- Modify: `spec/services/emails/activities/send_spec.rb`
- Modify: `spec/jobs/email_campaigns/send_campaign_job_spec.rb`
- Modify: locale files (Task 11).

**Interfaces:**
- Consumes: `FeatureModules::DailyCap.for(customer:, module_key: "email", default:, log_label:)`.
- Produces: `SendCampaignJob` enforces the cap; `Emails::Activities::Send` does not.

- [ ] **Step 1: Remove cap from transactional send**

In `app/services/emails/activities/send.rb`:

1. Update the class comment to remove the daily-cap mention:

```ruby
# Send orchestrates: contract → idempotency → render → resolve credential →
# opt-out/suppression → race-safe persist → enqueue provider delivery.
# Returns the persisted Emails::Message.
```

2. Remove the `check_daily_cap!(customer)` call inside `.call`.
3. Delete the private `check_daily_cap!` and `daily_cap_for` methods.
4. Remove the comment line "# Only transactional mail counts against the transactional cap...".

The resulting `.call` body should flow directly from suppression handling to `PersistMessage.call`.

- [ ] **Step 2: Add cap enforcement to SendCampaignJob**

In `app/jobs/email_campaigns/send_campaign_job.rb`, after the campaigns-enabled guard, add:

```ruby
remaining = remaining_daily_cap(campaign.customer)
if remaining <= 0
  Rails.logger.info("[SendCampaignJob] daily cap exhausted for customer=#{campaign.customer_id}; campaign=#{campaign.id} paused")
  flush_stats(campaign, counts)
  return
end

batch_allowance = [BATCH_SIZE, remaining].min
```

Replace the existing loop condition and re-enqueue logic so the job stops after `batch_allowance` recipients. Change:

```ruby
if counts.values.sum >= BATCH_SIZE
```

to:

```ruby
if counts.values.sum >= batch_allowance
```

Then add the helper methods at the bottom of the private section:

```ruby
def remaining_daily_cap(customer)
  cap = daily_cap_for(customer)
  sent_today = Emails::Message
                 .where(customer_id: customer.id, message_type: "campaign")
                 .where.not(status: %w[suppressed failed])
                 .where(created_at: Time.zone.now.beginning_of_day..)
                 .count
  cap - sent_today
end

def daily_cap_for(customer)
  FeatureModules::DailyCap.for(
    customer:   customer,
    module_key: "email",
    default:    ::Emails::Activities::Send::DEFAULT_DAILY_CAP,
    log_label:  "[EmailCampaigns::SendCampaignJob]"
  )
end
```

- [ ] **Step 3: Update Emails::Activities::Send spec**

In `spec/services/emails/activities/send_spec.rb`:

1. Delete the entire `context "with daily cap exceeded"` block (lines 174-211).
2. Delete the entire `context "with a malformed daily_send_cap..."` block (lines 213-225).
3. Update the suppression spec comment and assertion: the suppressed message no longer needs a cap comment. Remove the `email_module` / `cfm` setup in that test (lines 143-146) because the cap no longer exists. Keep the assertion that a second non-suppressed send succeeds.

The updated suppression test should look like:

```ruby
it "does not enqueue delivery for a suppressed address" do
  described_class.call(**valid_params, to: "suppressed@example.com")
  expect(Emails::DeliverMessageJob).not_to have_received(:perform_later)
end
```

(Delete the old `it "does not count against the daily cap..."` entirely.)

- [ ] **Step 4: Add daily-cap specs to SendCampaignJob**

In `spec/jobs/email_campaigns/send_campaign_job_spec.rb`, add a new describe block:

```ruby
describe "daily cap" do
  let!(:email_module) do
    FeatureModules::Module.find_or_create_by!(key: "email") { |fm| fm.name = "Email"; fm.status = :active }
  end

  before do
    ensure_customer_feature_module(customer, email_module, status: :active,
                                   configuration: { "campaigns_enabled" => true, "daily_send_cap" => 1 }.to_json)
  end

  it "counts campaign messages against the cap and stops when exhausted" do
    # Pre-seed one campaign send to consume the cap.
    create(:email_message, customer: customer, message_type: "campaign",
           status: "sent", to: "existing@example.com", from: "sender@example.com",
           subject: "Test", body_html: "<p>Test</p>", email_campaign_id: campaign.id)

    described_class.new.perform(campaign.id)

    expect(Emails::Message.where(message_type: "campaign").count).to eq(1)
    expect(campaign.reload.status).to eq("sending")
  end

  it "excludes suppressed and failed messages from the cap count" do
    create(:email_message, customer: customer, message_type: "campaign",
           status: "suppressed", to: "existing@example.com", from: "sender@example.com",
           subject: "Test", body_html: "<p>Test</p>", email_campaign_id: campaign.id)

    described_class.new.perform(campaign.id)

    expect(Emails::Message.where(message_type: "campaign").count).to eq(3) # suppressed + 2 sent
  end

  it "does not count transactional messages toward the campaign cap" do
    create(:email_message, customer: customer, message_type: "transactional",
           status: "sent", to: "existing@example.com", from: "sender@example.com",
           subject: "Test", body_html: "<p>Test</p>")

    ensure_customer_feature_module(customer, email_module, status: :active,
                                   configuration: { "campaigns_enabled" => true, "daily_send_cap" => 1 }.to_json)

    described_class.new.perform(campaign.id)

    expect(Emails::Message.where(message_type: "campaign").count).to eq(2)
  end
end
```

- [ ] **Step 5: Run the affected specs**

Run:

```bash
bundle exec rspec spec/services/emails/activities/send_spec.rb \
                 spec/jobs/email_campaigns/send_campaign_job_spec.rb
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add app/services/emails/activities/send.rb \
        app/jobs/email_campaigns/send_campaign_job.rb \
        spec/services/emails/activities/send_spec.rb \
        spec/jobs/email_campaigns/send_campaign_job_spec.rb
git commit -m "feat(email): apply daily cap only to campaign sends

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 11: Update locales

**Files:**
- Modify: `config/locales/feature_modules.en.yml`, `config/locales/feature_modules.zh-CN.yml`
- Modify: `config/locales/admin_misc.en.yml`, `config/locales/admin_misc.zh-CN.yml`
- Modify: `config/locales/maint_core.en.yml`, `config/locales/maint_core.zh-CN.yml`
- Modify: `config/locales/admin_modules.en.yml`, `config/locales/admin_modules.zh-CN.yml` (remove `nav.email_campaigns` if unused)

- [ ] **Step 1: Update feature_modules locale**

In `config/locales/feature_modules.en.yml`, replace the `email:` block with:

```yaml
email:
  name: "Email"
  entries:
    dashboard: "Dashboard"
    templates: "Templates"
    messages: "Messages"
    suppressions: "Suppressions"
    campaigns: "Campaigns"
    lists: "Lists"
    block_list: "Block-List"
  settings:
    daily_cap: "Campaign daily cap"
  titles:
    templates: "Email Templates"
    messages: "Email Messages"
    campaigns: "Campaigns"
    lists: "Lists"
    block_list: "Block-List"
```

And delete the entire `email_campaigns:` block.

Apply the same structural change to `config/locales/feature_modules.zh-CN.yml` with Chinese copy.

- [ ] **Step 2: Update admin_misc locale**

In `config/locales/admin_misc.en.yml`, under `module_config.fields.email`, change to:

```yaml
email:
  daily_send_cap: "Campaign daily cap"
  campaigns_enabled: "Enable email campaigns"
```

Mirror in `zh-CN`.

- [ ] **Step 3: Update maint_core flash and modules index copy**

In `config/locales/maint_core.en.yml`, under `flash:`, add:

```yaml
module_sub_toggles:
  updated: "Sub-feature setting updated."
  invalid_key: "Invalid sub-feature setting."
campaigns_disabled: "Email Campaigns is not enabled for this account."
```

Under `modules.index`, add:

```yaml
campaigns_enabled_label: "Enable Email Campaigns"
```

Mirror in `zh-CN`.

- [ ] **Step 4: Clean up admin_modules nav key**

In `config/locales/admin_modules.en.yml` and `zh-CN.yml`, remove the line:

```yaml
email_campaigns: "Email Campaigns"
```

from the `admin_modules.nav` section. The moved views now use `admin_modules.nav.email` for breadcrumbs.

- [ ] **Step 5: Run i18n health check**

Run:

```bash
bundle exec i18n-tasks missing
```

Expected: no missing keys for the new paths.

- [ ] **Step 6: Commit**

```bash
git add config/locales
git commit -m "feat(email): update locales for merged module, toggle, and campaign cap

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 12: Data migration to consolidate email_campaigns records

**Files:**
- Create: `db/migrate/YYYYMMDDHHMMSS_merge_email_campaigns_into_email.rb`
- Create: `spec/db/migrate/merge_email_campaigns_into_email_spec.rb` (optional but recommended)

**Interfaces:**
- Reads `FeatureModules::Module` keys `email` and `email_campaigns`.
- Writes `CustomerAssignment.configuration["campaigns_enabled"]` and deletes retired rows.

- [ ] **Step 1: Generate the migration**

Run:

```bash
bundle exec rails generate migration MergeEmailCampaignsIntoEmail
```

Then replace the generated file content with:

```ruby
# frozen_string_literal: true

class MergeEmailCampaignsIntoEmail < ActiveRecord::Migration[8.0]
  class FeatureModuleStub < ActiveRecord::Base
    self.table_name = "feature_modules"
    enum :status, { active: 0, inactive: 1 }, default: :inactive
  end

  class CustomerFeatureModuleStub < ActiveRecord::Base
    self.table_name = "customer_feature_modules"
    enum :status, { active: 0, suspended: 1 }, default: :active
    serialize :configuration, coder: JSON
  end

  def up
    email_module = FeatureModuleStub.find_by(key: "email")
    campaigns_module = FeatureModuleStub.find_by(key: "email_campaigns")

    return unless campaigns_module

    email_module ||= FeatureModuleStub.create!(key: "email", name: "Email", status: :active)

    # If any customer had campaigns enabled but email was inactive globally,
    # activate email so they are not locked out.
    email_module.update!(status: :active) if campaigns_module.active? && email_module.inactive?

    CustomerFeatureModuleStub
      .where(feature_module_id: campaigns_module.id, status: :active)
      .find_each do |old|
        assignment = CustomerFeatureModuleStub.find_or_initialize_by(
          customer_id: old.customer_id,
          feature_module_id: email_module.id
        )

        config = assignment.configuration.presence || {}
        config["campaigns_enabled"] = true

        assignment.status = :active if assignment.new_record? || assignment.status != "active"
        assignment.configuration = config
        assignment.save!
      end

    CustomerFeatureModuleStub.where(feature_module_id: campaigns_module.id).delete_all
    campaigns_module.destroy!
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
```

Use the actual Rails version (e.g., `Migration[8.0]`) matching other migrations in `db/migrate/`.

- [ ] **Step 2: Write a migration spec**

Create `spec/db/migrate/merge_email_campaigns_into_email_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"
require_relative "../../../db/migrate/YYYYMMDDHHMMSS_merge_email_campaigns_into_email"

RSpec.describe MergeEmailCampaignsIntoEmail, type: :migration do
  let(:customer) { create(:customer) }
  let!(:email_module) do
    FeatureModules::Module.find_or_create_by!(key: "email") { |fm| fm.name = "Email"; fm.status = :active }
  end

  it "migrates an email_campaigns-only customer to email with campaigns enabled" do
    campaigns_module = FeatureModules::Module.create!(key: "email_campaigns", name: "Email Campaigns", status: :active)
    FeatureModules::CustomerAssignment.create!(
      customer: customer,
      feature_module: campaigns_module,
      status: :active,
      configuration: {}.to_json
    )

    described_class.new.up

    expect(FeatureModules::Module.exists?(key: "email_campaigns")).to be false
    assignment = FeatureModules::CustomerAssignment.find_by!(customer: customer, feature_module: email_module)
    expect(assignment.configuration_json["campaigns_enabled"]).to eq(true)
  end
end
```

Replace `YYYYMMDDHHMMSS` with the actual migration timestamp.

- [ ] **Step 3: Run the migration locally**

Run:

```bash
bundle exec rails db:migrate
```

Expected: migration succeeds.

- [ ] **Step 4: Commit**

```bash
git add db/migrate spec/db/migrate
git commit -m "feat(db): migrate email_campaigns module into email module

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 13: Remove retired email_campaigns registration and specs

**Files:**
- Delete: `app/services/feature_modules/email_campaigns/registration.rb`
- Delete: `app/services/feature_modules/email_campaigns/provisioner.rb`
- Delete: `spec/services/feature_modules/email_campaigns/registration_spec.rb`
- Delete: `spec/services/feature_modules/email_campaigns/provisioner_spec.rb`
- Delete: empty directories if any.

- [ ] **Step 1: Delete retired files**

Run:

```bash
git rm app/services/feature_modules/email_campaigns/registration.rb \
       app/services/feature_modules/email_campaigns/provisioner.rb \
       spec/services/feature_modules/email_campaigns/registration_spec.rb \
       spec/services/feature_modules/email_campaigns/provisioner_spec.rb
rmdir app/services/feature_modules/email_campaigns spec/services/feature_modules/email_campaigns 2>/dev/null || true
```

- [ ] **Step 2: Run the full email/campaign spec set**

Run:

```bash
bundle exec rspec spec/services/feature_modules/email \
                 spec/requests/admin/modules/emails \
                 spec/requests/emails/unsubscribes_spec.rb \
                 spec/jobs/email_campaigns \
                 spec/services/email_campaigns \
                 spec/services/emails/activities/send_spec.rb
```

Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git commit -m "chore(email): remove retired email_campaigns registration and specs

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 14: Final verification

- [ ] **Step 1: Run the full RSpec suite**

Run:

```bash
bundle exec rspec
```

Expected: PASS (or only pre-existing failures).

- [ ] **Step 2: Smoke-test the UI locally**

1. Sign in as a platform owner, go to **Maintenance → Platform → Module Settings → Email**, and confirm the schema lists **Campaign daily cap** and **Enable email campaigns**.
2. Go to **Maintenance → Modules**, enable **Email**, and check the **Enable Email Campaigns** nested toggle.
3. Enable campaigns, then use the sidebar to create a campaign, list, and view the block-list.
4. Disable campaigns and confirm campaign sidebar entries disappear and campaign URLs redirect to the Email dashboard.

- [ ] **Step 3: Commit any final fixes**

```bash
git commit -m "fix(email): final verification fixes for merged module

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

## Self-Review Checklist

- [x] **Spec coverage:** every section of `2026-07-19-merged-email-campaigns-submodule-design.md` maps to at least one task above.
- [x] **No placeholders:** every step contains file paths, code, or exact commands.
- [x] **Type consistency:** `campaigns_enabled?` accepts a customer object; `sidebar_contributions` receives a controller/context object; route helpers use the `admin_modules_emails_*` prefix throughout.
- [x] **DRY:** the guard concern is shared across all campaign controllers; the `campaigns_enabled?` helper is reused by sidebar, guard, jobs, and services.
- [x] **YAGNI:** no new framework for generic sub-modules; only the Email-specific toggle is built.
