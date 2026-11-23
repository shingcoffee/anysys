# Email module — Merge Email Campaigns as a sub-module

**Date:** 2026-07-19  
**Scope:** Merge the `Email` and `Email Campaigns` modules into a single `Email` module, with Email Campaigns as a per-customer sub-feature. Move the daily cap so it applies only to campaign sending volume.  
**Status:** Design — awaiting implementation plan.

## 1. Goal

Today the application exposes two top-level modules:

- `email` — transactional templates, messages, suppressions, dashboard, and the daily send cap.
- `email_campaigns` — campaigns, lists, and block-list.

This design merges them into one module named **Email**. Email Campaigns becomes a sub-feature that can be toggled on/off per customer. The existing **Daily cap** setting under Email changes semantics: it now limits only campaign email volume; transactional sends are uncapped.

## 2. Out of scope

- No changes to public unsubscribe URLs (`/unsubscribe/:token`).
- No changes to the underlying `email_campaigns` table, `email_messages.email_campaign_id`, or campaign models.
- No new campaign-level throttling beyond the existing per-minute throttle.
- No UI redesign of the campaign/list/block-list pages beyond route/breadcrumb updates.

## 3. Module registry changes

### 3.1 Retire `FeatureModules::EmailCampaigns`

- Delete `app/services/feature_modules/email_campaigns/registration.rb`.
- Delete `app/services/feature_modules/email_campaigns/provisioner.rb`.
- After deploy, the `feature_modules` row with `key = "email_campaigns"` and its `customer_feature_modules` rows are removed by the data migration.

### 3.2 Extend `FeatureModules::Email::Registration`

File: `app/services/feature_modules/email/registration.rb`

- `module_key` remains `"email"` and `module_name` remains `"Email"`.
- Add `campaigns_enabled` to the per-tenant configuration:

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

- `sidebar_contributions` now receives the controller context and returns campaign entries only when the current customer has `campaigns_enabled == true`:

```ruby
def self.sidebar_contributions(controller)
  customer = controller.current_customer
  entries  = [
    ModuleContribution.new(... dashboard ...),
    ModuleContribution.new(... templates ...),
    ModuleContribution.new(... messages ...),
    ModuleContribution.new(... suppressions ...)
  ]

  if campaigns_enabled?(customer)
    entries.concat([
      ModuleContribution.new(... campaigns ...),
      ModuleContribution.new(... lists ...),
      ModuleContribution.new(... block_list ...)
    ])
  end

  { entries: entries, settings: [ ... daily_cap ... ] }
end
```

- Add a helper:

```ruby
def self.campaigns_enabled?(customer)
  return false unless customer

  cfm = FeatureModules::CustomerAssignment
          .joins(:feature_module)
          .find_by(customer: customer, feature_modules: { key: "email" })
  cfm&.configuration_json&.dig("campaigns_enabled") == true
end
```

- `entries_for` gains cases for `campaigns`, `lists`, and `block_list` (moved from the retired `email_campaigns` registration).

### 3.3 Pass controller context into `sidebar_contributions`

The sidebar contributors currently call `sidebar_contributions(nil)`. Update:

- `ModulesContributor#contribute`: `fm.registration_class.sidebar_contributions(context)`
- `SettingsContributor#contribute`: `fm.registration_class.sidebar_contributions(context)`

All existing registrations accept the argument and ignore it, so this is backward compatible.

## 4. Data migration

File: `db/migrate/YYYYMMDDHHMMSS_merge_email_campaigns_into_email.rb`.

1. Find the `email` module (`FeatureModules::Module.find_by!(key: "email")`).
2. Find the `email_campaigns` module (`FeatureModules::Module.find_by(key: "email_campaigns")`).
3. If the `email_campaigns` module exists:
   - For each active `FeatureModules::CustomerAssignment` where `feature_module_id = email_campaigns.id`:
     - Find or create the customer's `CustomerAssignment` for the `email` module.
     - Set `configuration["campaigns_enabled"] = true` (merge onto existing configuration).
     - Ensure the assignment status is `active`.
   - If the `email` module is `inactive` but `email_campaigns` is `active`, activate `email` so existing campaign customers are not locked out.
   - Delete the `email_campaigns` `CustomerAssignment` rows.
   - Delete the `email_campaigns` `FeatureModules::Module` row.

The migration must be reversible: in the down direction, re-create the `email_campaigns` module row and split assignments back out.

## 5. Routing and controller namespace

### 5.1 Admin routes

Move campaign surfaces under the Email namespace in `config/routes.rb`:

```ruby
namespace :emails do
  get  "dashboard", to: "dashboard#show"
  resources :templates do ... end
  resources :messages, only: %i[index show]
  resources :suppressions, only: :index
  resources :attachments, only: %i[create show]

  # Campaign sub-feature
  resources :campaigns do
    resource :delivery,     only: :create, controller: "campaign_deliveries"
    resource :pause,        only: %i[create destroy], controller: "campaign_pauses"
    resource :cancellation, only: :create, controller: "campaign_cancellations"
  end
  resources :lists, controller: "lists"
  get   "block_list",               to: "block_list#index"
  patch "block_list/batch_unblock", to: "block_list#batch_unblock"
  patch "block_list/:id",           to: "block_list#unblock", as: :block_list_unblock
end
```

### 5.2 Controller and view file moves

Move files from `admin/modules/email_campaigns/*` to `admin/modules/emails/*` and update class names:

| Old file | New file | New class |
|---|---|---|
| `controllers/admin/modules/email_campaigns/campaigns_controller.rb` | `controllers/admin/modules/emails/campaigns_controller.rb` | `Admin::Modules::Emails::CampaignsController` |
| `controllers/admin/modules/email_campaigns/campaign_deliveries_controller.rb` | `controllers/admin/modules/emails/campaign_deliveries_controller.rb` | `Admin::Modules::Emails::CampaignDeliveriesController` |
| `controllers/admin/modules/email_campaigns/campaign_pauses_controller.rb` | `controllers/admin/modules/emails/campaign_pauses_controller.rb` | `Admin::Modules::Emails::CampaignPausesController` |
| `controllers/admin/modules/email_campaigns/campaign_cancellations_controller.rb` | `controllers/admin/modules/emails/campaign_cancellations_controller.rb` | `Admin::Modules::Emails::CampaignCancellationsController` |
| `controllers/admin/modules/email_campaigns/lists_controller.rb` | `controllers/admin/modules/emails/lists_controller.rb` | `Admin::Modules::Emails::ListsController` |
| `controllers/admin/modules/email_campaigns/block_list_controller.rb` | `controllers/admin/modules/emails/block_list_controller.rb` | `Admin::Modules::Emails::BlockListController` |
| `views/admin/modules/email_campaigns/campaigns/*` | `views/admin/modules/emails/campaigns/*` | — |
| `views/admin/modules/email_campaigns/lists/*` | `views/admin/modules/emails/lists/*` | — |
| `views/admin/modules/email_campaigns/block_list/*` | `views/admin/modules/emails/block_list/*` | — |

### 5.3 Public unsubscribe

Keep the route:

```ruby
get  "/unsubscribe/:token", to: "emails/unsubscribes#show",   as: :email_unsubscribe
post "/unsubscribe/:token", to: "emails/unsubscribes#create", as: :email_unsubscribe_create
```

Move `controllers/email_campaigns/unsubscribes_controller.rb` to `controllers/emails/unsubscribes_controller.rb` and update the class to `Emails::UnsubscribesController`. Move the corresponding view files.

### 5.4 Redirects

Add temporary redirect routes so existing bookmarks to `/admin/modules/email_campaigns/*` continue to work:

```ruby
get "/admin/modules/email_campaigns/*path", to: redirect { |params, request|
  "/#{request.path_parameters[:cid]}/admin/modules/emails/#{params[:path]}#{request.query_string.present? ? "?#{request.query_string}" : ""}"
}
```

(Use the actual route helper conventions in the app.)

### 5.5 Path updates

Update all hardcoded paths and route helpers in:

- Campaign/list/block-list controllers and views.
- `BlockListTableComponent`.
- Breadcrumb and navigation translations.
- Any specs referencing the old paths.

## 6. Campaigns toggle

### 6.1 Maintenance UI

On `admin/maintenance/modules/index.html.erb`, when the `email` module is enabled, show a nested row:

```erb
<% if fm.key == "email" && enabled %>
  <div class="mt-3 pl-4 border-l-2 border-border-subtle">
    <%= form_with url: admin_maintenance_module_sub_toggle_path(current_customer_id, fm, key: "campaigns_enabled"), method: :patch do |f| %>
      <label class="flex items-center gap-2">
        <%= check_box_tag "enabled", "1", FeatureModules::Email::Registration.campaigns_enabled?(current_customer), onchange: "this.form.submit()" %>
        <span class="text-sm">Enable Email Campaigns</span>
      </label>
    <% end %>
  </div>
<% end %>
```

### 6.2 Toggle controller

Create `app/controllers/admin/maintenance/module_sub_toggles_controller.rb`:

```ruby
module Admin
  module Maintenance
    class ModuleSubTogglesController < ApplicationController
      dashboard_menu_item :maintenance

      def update
        feature_module = FeatureModules::Module.find(params[:module_id])
        key = params[:key].to_s
        # Whitelist only keys declared by the module's configuration_schema
        allowed = Array(feature_module.registration_class.configuration_keys).map(&:to_s)
        unless allowed.include?(key)
          redirect_to admin_maintenance_modules_path(current_customer_id), alert: "Invalid toggle"
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

Add the nested route:

```ruby
resources :modules, only: [:index], controller: "maintenance/modules" do
  resource :enablement, only: %i[create destroy], controller: "maintenance/module_enablements"
  resource :sub_toggle, only: [:update], controller: "maintenance/module_sub_toggles"
end
```

### 6.3 Runtime guards

When campaigns are disabled for a customer:

- Campaign controllers (`Admin::Modules::Emails::CampaignsController`, `ListsController`, `BlockListController`) redirect to the Email dashboard with an alert.
- `EmailCampaigns::StartCampaign.call` returns `false` immediately, so scheduled/manual sends and reconciliation do not start.
- `EmailCampaigns::SendCampaignJob` returns immediately if the campaign's customer has campaigns disabled.

Introduce a small concern or helper for the controller guard:

```ruby
module Admin::Modules::Emails::CampaignsEnabled
  extend ActiveSupport::Concern

  included do
    before_action :ensure_campaigns_enabled
  end

  private

  def ensure_campaigns_enabled
    unless FeatureModules::Email::Registration.campaigns_enabled?(current_customer)
      redirect_to "/#{current_customer_id}/admin/modules/emails/dashboard",
                  alert: t("maint_core.flash.campaigns_disabled")
    end
  end
end
```

## 7. Daily cap

### 7.1 Remove cap from transactional sends

In `app/services/emails/activities/send.rb`:

- Remove the `check_daily_cap!(customer)` call.
- Remove the private `check_daily_cap!` and `daily_cap_for` methods (or keep `daily_cap_for` only if reused by campaigns).

Transactional sends — including template test sends and flowchart email actions — no longer count against any cap.

### 7.2 Apply cap to campaign sends

In `app/jobs/email_campaigns/send_campaign_job.rb`, at the start of `perform`:

```ruby
def perform(campaign_id)
  campaign = EmailCampaigns::Campaign.find(campaign_id)
  return unless campaign.status == "sending"
  return unless FeatureModules::Email::Registration.campaigns_enabled?(campaign.customer)

  remaining = remaining_daily_cap(campaign.customer)
  if remaining <= 0
    Rails.logger.info("Campaign #{campaign.id} paused by daily cap for customer #{campaign.customer_id}")
    return
  end

  # existing batch logic, but cap the batch size
  batch_allowance = [BATCH_SIZE, remaining].min
  # ... process up to batch_allowance recipients, then return without re-enqueuing
end
```

Add helpers:

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

When the allowance is exhausted mid-campaign:

- Flush stats for the messages already sent in this run.
- Return without re-enqueuing.
- The campaign remains in `sending` state. The next scheduler tick or manual retry will resume only after the daily window resets.

### 7.3 Settings label

Update `config/locales/feature_modules.en.yml` and `feature_modules.zh-CN.yml`:

```yaml
email:
  settings:
    daily_cap: "Campaign daily cap"
```

Add translation keys for the new toggle and flash messages in `config/locales/maint_core.en.yml` / `zh-CN.yml`.

## 8. Testing

### 8.1 Unit / service specs

- `FeatureModules::Email::Registration`:
  - returns campaign entries when `campaigns_enabled` is true.
  - omits campaign entries when false.
  - `campaigns_enabled?` reads from `CustomerAssignment.configuration`.
- `Emails::Activities::Send`:
  - no longer raises `DailyCapExceeded`.
  - does not count messages against a cap.
- `EmailCampaigns::SendCampaignJob`:
  - counts only `message_type: "campaign"` messages.
  - excludes `suppressed` and `failed` statuses.
  - stops sending when the cap is reached.
  - returns early when campaigns are disabled.

### 8.2 Job specs

- `EmailCampaigns::SchedulerJob` does not enqueue `SendCampaignJob` for customers with campaigns disabled.
- `EmailCampaigns::StartCampaign` returns false when campaigns disabled.

### 8.3 Request / controller specs

- Campaign/list/block-list controllers redirect with an alert when campaigns are disabled.
- Maintenance modules page toggle persists `campaigns_enabled`.
- `Admin::Maintenance::ModuleSubTogglesController` rejects unknown keys.

### 8.4 Routing specs

- Old `/admin/modules/email_campaigns/*` paths redirect to `/admin/modules/emails/*`.
- New routes resolve to the moved controllers.

### 8.5 Data migration spec

- Customers with only `email_campaigns` enabled get an active Email assignment with `campaigns_enabled: true`.
- Customers with both enabled keep their Email assignment and gain `campaigns_enabled: true`.
- Customers with only `email` enabled keep `campaigns_enabled: false`.
- The `email_campaigns` module row and its assignments are removed.

## 9. Backwards compatibility & rollout

- Existing campaign data (`email_campaigns` table, `email_messages`, lists) is untouched.
- Public unsubscribe URLs remain stable.
- Old admin URLs redirect to the new paths.
- Platform owners who previously enabled `email_campaigns` for customers will see those customers automatically get Email + campaigns enabled after the migration.
- The daily cap value stored in `CustomerAssignment.configuration["daily_send_cap"]` is preserved; only what it counts changes.

## 10. Open questions

None remaining after clarifying discussion:

- Toggle is per-customer under **Maintenance → Modules → Email**.
- Disabled campaigns hide sidebar entries and block sends.
- Cap enforcement skips remaining sends until the next day when the allowance is exhausted.
