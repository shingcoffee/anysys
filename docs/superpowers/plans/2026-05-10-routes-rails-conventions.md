# Rails v8 Routes & Conventions Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bring `config/routes.rb` and the controller layer into Rails v8 RESTful conventions, eliminating verb-style member actions, `scope ... module:` constructs, the `browse_*` helper prefix, singleton plurals, and parameter shadowing.

**Architecture:** Six ordered commits transform the routes file and the controllers/views/specs that reference its helpers. Each commit is independently verifiable via `bundle exec rspec`. The transform is structural (no business logic changes).

**Tech Stack:** Rails 8.1.2, RSpec, Devise, ViewComponent, Stimulus.

**Spec:** `docs/superpowers/specs/2026-05-10-routes-rails-conventions-design.md`

---

## Pre-flight

Before starting, confirm baseline:

- [ ] **Step 0.1: Verify clean baseline**

Run: `bundle exec rspec --fail-fast 2>&1 | tail -10`
Expected: No failures (or document the existing failures so we don't blame the refactor).

- [ ] **Step 0.2: Note any pre-existing failures**

If pre-existing failures exist, list them. Each phase should leave them intact (no regressions, no new failures).

---

## Phase 1: Routes-only quick wins

**Files:**
- Modify: `config/routes.rb`
- Delete: `app/controllers/settings/` (empty directory)

### Task 1.1: Fix B3 — duplicate `payments/payments/` segment

- [ ] **Step 1.1.1: Edit `config/routes.rb` lines 58–63**

Find:
```ruby
    # Payment public flow (customer checkout + result page)
    scope "payments", as: :payments do
      get  "checkout",              to: "payments/checkouts#show"
      post "checkout",              to: "payments/checkouts#create",  as: :checkout_create
      get  "payments/:id/status",   to: "payments/checkouts#status",  as: :payment_status
      get  "result/:payment_id",    to: "payments/results#show",      as: :result
    end
```

Replace with:
```ruby
    # Payment public flow (customer checkout + result page)
    scope "payments" do
      get  "checkout",            to: "payments/checkouts#show",   as: :payment_checkout
      post "checkout",            to: "payments/checkouts#create", as: :payment_checkout_create
      get  ":id/status",          to: "payments/checkouts#status", as: :payment_status
      get  "result/:payment_id",  to: "payments/results#show",     as: :payment_result
    end
```

This also fixes F3 (helper stutter `payments_payment_status_path` → `payment_status_path`).

- [ ] **Step 1.1.2: Find and update callers**

Run: `grep -rn "payments_payment_status_path\|payments_checkout_path\|payments_checkout_create_path\|payments_result_path" --include="*.rb" --include="*.erb" --include="*.js"`

For each match, rename:
- `payments_payment_status_path` → `payment_status_path`
- `payments_checkout_path` → `payment_checkout_path`
- `payments_checkout_create_path` → `payment_checkout_create_path`
- `payments_result_path` → `payment_result_path`

- [ ] **Step 1.1.3: Run focused specs**

Run: `bundle exec rspec spec/requests/payments/ spec/components/payments/`
Expected: All pass.

### Task 1.2: Fix B4 — duplicate `as: :module_settings`

- [ ] **Step 1.2.1: Edit `config/routes.rb` lines 198–206**

Find:
```ruby
            # Module settings
            resources :module_settings, controller: "platform/module_settings", only: [:index, :show, :update]

            # Per-module platform settings
            scope "module_settings", as: :module_settings do
              scope "sms", as: :sms, module: "platform/sms" do
                resources :credentials, only: %i[index new create edit update]
                resources :templates,   only: %i[index new create edit update destroy]
              end
            end
```

Replace with:
```ruby
            # Module settings (platform-wide config index + per-module update)
            resources :module_settings, controller: "platform/module_settings", only: [:index, :show, :update]

            # Per-module platform settings (path nested under module_settings; helpers
            # generated directly without redundant prefix to avoid `module_settings_module_settings_*`).
            scope "module_settings" do
              scope "sms", as: :module_settings_sms, module: "platform/sms" do
                resources :credentials, only: %i[index new create edit update]
                resources :templates,   only: %i[index new create edit update destroy]
              end
            end
```

- [ ] **Step 1.2.2: Find and rename callers**

Run: `grep -rn "module_settings_module_settings_\|module_settings_sms_credential\|module_settings_sms_template" --include="*.rb" --include="*.erb" --include="*.js"`

If any helper of form `module_settings_module_settings_sms_*` exists, rename to `module_settings_sms_*`. (Note the parent `resources :module_settings` already produces `module_settings_path`, `module_setting_path`. The `as: :module_settings_sms` here gives clean `module_settings_sms_credentials_path` etc.)

- [ ] **Step 1.2.3: Run platform specs**

Run: `bundle exec rspec spec/requests/maintenance/`
Expected: All pass.

### Task 1.3: Delete empty `app/controllers/settings/` directory

- [ ] **Step 1.3.1: Verify directory is empty**

Run: `ls -la app/controllers/settings/`
Expected: Empty (no files).

- [ ] **Step 1.3.2: Delete directory**

Run: `rmdir app/controllers/settings/`
Expected: Success.

### Task 1.4: Phase 1 commit

- [ ] **Step 1.4.1: Verify full suite**

Run: `bundle exec rspec`
Expected: Same pass/fail count as baseline (no new failures).

- [ ] **Step 1.4.2: Commit**

```bash
git add config/routes.rb
git commit -m "refactor(routes): phase 1 — quick wins (B3, B4, F3, A5)

- Drop duplicate 'payments/' segment in checkout/status routes
- Eliminate payments_payment_status_path stutter (F3)
- Drop redundant as: :module_settings on inner platform scope (B4)
- Remove empty app/controllers/settings/ directory (A5)"
```

---

## Phase 2: `namespace :admin` + drop `browse_*` prefix

This phase moves all controllers under the existing `scope "admin"` into the `Admin::` namespace, eliminating the `browse_*` prefix and the `LandingController` → `DashboardController` rename.

**Files affected:** ~20 controllers, ~40 views, ~30 specs.

### Task 2.1: Move browse-area controllers to Admin namespace

- [ ] **Step 2.1.1: Move controller files**

Run:
```bash
mkdir -p app/controllers/admin
git mv app/controllers/entities_controller.rb app/controllers/admin/entities_controller.rb
git mv app/controllers/entity_entries_controller.rb app/controllers/admin/entity_entries_controller.rb
git mv app/controllers/pages_controller.rb app/controllers/admin/pages_controller.rb
git mv app/controllers/modules_controller.rb app/controllers/admin/modules_controller.rb
git mv app/controllers/module_entries_controller.rb app/controllers/admin/module_entries_controller.rb
git mv app/controllers/settings_controller.rb app/controllers/admin/settings_controller.rb
git mv app/controllers/search_controller.rb app/controllers/admin/search_controller.rb
git mv app/controllers/landing_controller.rb app/controllers/admin/dashboard_controller.rb
git mv app/controllers/maintenances_controller.rb app/controllers/admin/maintenance_controller.rb
```

- [ ] **Step 2.1.2: Re-namespace each moved class**

For each moved file, wrap class in `module Admin`. Example for `app/controllers/admin/entities_controller.rb`:

Before:
```ruby
class EntitiesController < ApplicationController
```

After:
```ruby
module Admin
  class EntitiesController < ApplicationController
```

(Add closing `end` at file bottom.)

Apply to all 9 moved files. For `dashboard_controller.rb` (was `landing_controller.rb`), also rename class:

Before:
```ruby
class LandingController < ApplicationController
  set_tenant_from_route_params
  before_action :authenticate_user!

  def show
```

After:
```ruby
module Admin
  class DashboardController < ApplicationController
    set_tenant_from_route_params
    before_action :authenticate_user!

    def show
```

For `maintenance_controller.rb` (was `maintenances_controller.rb`), also rename class `MaintenancesController` → `Admin::MaintenanceController`.

- [ ] **Step 2.1.3: Move existing namespaced maintenance controllers under Admin**

Run:
```bash
git mv app/controllers/maintenance app/controllers/admin/maintenance
git mv app/controllers/platform app/controllers/admin/maintenance/platform
git mv app/controllers/code_generators app/controllers/admin/maintenance/platform/code_generators
```

For each file under `app/controllers/admin/maintenance/`, wrap class in `module Admin`. Example for `app/controllers/admin/maintenance/flowcharts_controller.rb`:

Before:
```ruby
module Maintenance
  class FlowchartsController < ApplicationController
```

After:
```ruby
module Admin
  module Maintenance
    class FlowchartsController < ApplicationController
```

(Add extra closing `end` at file bottom.)

For platform: `Platform::CustomersController` → `Admin::Maintenance::Platform::CustomersController` (3 levels of nesting, 3 closing `end`s).

For code generators (under `Platform::CodeGenerators`): re-namespace as `Admin::Maintenance::Platform::CodeGenerators::IoParamsController` etc.

### Task 2.2: Move view directories

- [ ] **Step 2.2.1: Move views**

Run:
```bash
mkdir -p app/views/admin
git mv app/views/entities app/views/admin/entities
git mv app/views/pages app/views/admin/pages
git mv app/views/modules app/views/admin/modules
git mv app/views/module_entries app/views/admin/module_entries
git mv app/views/settings app/views/admin/settings
git mv app/views/landing app/views/admin/dashboard
git mv app/views/maintenances app/views/admin/maintenance
git mv app/views/maintenance app/views/admin/maintenance_pages_old
```

Wait — that conflicts. Resolve in two steps:

```bash
git mv app/views/maintenance app/views/admin/maintenance_resources
mkdir -p app/views/admin/maintenance
git mv app/views/maintenances/* app/views/admin/maintenance/
rmdir app/views/maintenances
git mv app/views/admin/maintenance_resources/* app/views/admin/maintenance/
rmdir app/views/admin/maintenance_resources
```

- [ ] **Step 2.2.2: Search for unused view dirs**

Run: `find app/views -type d -empty -delete`

- [ ] **Step 2.2.3: Move admin search view**

Run:
```bash
mkdir -p app/views/admin/search
git mv app/views/search/* app/views/admin/search/ 2>/dev/null
rmdir app/views/search 2>/dev/null
```

(Skip if `app/views/search/` doesn't exist.)

### Task 2.3: Update routes file

- [ ] **Step 2.3.1: Edit `config/routes.rb` to use namespace :admin**

Find lines 68–254 (the `scope "admin", as: nil do ... end` block).

Replace `scope "admin", as: nil do` with `namespace :admin do`.

Inside, drop all `as: :browse_*` and replace verb-style routes with conventional naming. Specifically replace lines 69–105:

```ruby
      get "/", to: "landing#show", as: :dashboard_root

      # Browse views (read-only dashboard listings)
      scope do
        # Entities browser
        get "entities",     to: "entities#index", as: :browse_entities
        get "entities/:id", to: "entities#show",  as: :browse_entity
        delete "entities/:id/entries/batch", to: "entities#batch_destroy_entries", as: :browse_entity_entries_batch_destroy

        # Pages browser
        get  "pages",                   to: "pages#index",        as: :browse_pages
        get  "pages/entity/:entity_id", to: "pages#by_entity",    as: :browse_pages_by_entity
        post "pages/batch",             to: "pages#batch_update", as: :browse_pages_batch_update

        # Modules browser
        get "modules",                                  to: "modules#index",       as: :browse_modules
        get "modules/:module_key/entries/:entry_key",  to: "module_entries#show", as: :browse_module_entry

        # Settings
        get "settings",                                to: "settings#show",          as: :settings
```

With (note this is preliminary — Phase 6 adjusts the verb-action routes further; for Phase 2 we just rename helpers):

```ruby
      resource :dashboard, only: :show

      # Browse views (read-only dashboard listings)
      resources :entities, only: %i[index show] do
        delete "entries/batch", on: :member, to: "entities#batch_destroy_entries", as: :batch_destroy_entries
      end

      resources :pages, only: :index do
        collection do
          get  "entity/:entity_id", to: "pages#by_entity", as: :by_entity
          post "batch",             to: "pages#batch_update", as: :batch_update
        end
      end

      resources :modules, only: :index do
        get "entries/:entry_key", on: :member, to: "module_entries#show", as: :entry, param: :module_key
      end

      get "settings", to: "settings#show", as: :setting
```

Also lines 105–107:
```ruby
        # Search
        get "search", to: "search#index", as: :search
```
becomes (no change needed; under namespace this becomes `admin_search_path`):
```ruby
      get "search", to: "search#index", as: :search
```

- [ ] **Step 2.3.2: Update inner controller paths to drop redundant Admin:: prefix**

Inside the new `namespace :admin do` block, route `to:` strings stay relative (Rails resolves them inside the namespace). E.g., `to: "entities#index"` resolves to `Admin::EntitiesController#index`. No change needed in the route strings.

But for explicit controller references, the `controller:` option auto-resolves. Verify by running:

Run: `bin/rails routes 2>&1 | head -30`
Expected: Routes show `Admin::EntitiesController` etc.

- [ ] **Step 2.3.3: Verify the `as: nil` removal from the outer scope**

The line `scope "admin", as: nil do` is now `namespace :admin do`. Helper prefix becomes `admin_*`.

### Task 2.4: Run helper rename across codebase

- [ ] **Step 2.4.1: Find and replace all browse_ helpers**

Run these `find`/`sed` commands:

```bash
# browse_entities -> admin_entities
grep -rl "browse_entities_path\|browse_entities_url" app spec | xargs sed -i 's/browse_entities_path/admin_entities_path/g; s/browse_entities_url/admin_entities_url/g'

# browse_entity -> admin_entity
grep -rl "browse_entity_path\|browse_entity_url" app spec | xargs sed -i 's/browse_entity_path/admin_entity_path/g; s/browse_entity_url/admin_entity_url/g'

# browse_entity_entries_batch_destroy -> batch_destroy_entries_admin_entity (Rails generates from member action)
grep -rl "browse_entity_entries_batch_destroy_path\|browse_entity_entries_batch_destroy_url" app spec | xargs sed -i 's/browse_entity_entries_batch_destroy_path/batch_destroy_entries_admin_entity_path/g; s/browse_entity_entries_batch_destroy_url/batch_destroy_entries_admin_entity_url/g'

# browse_pages -> admin_pages
grep -rl "browse_pages_path\|browse_pages_url" app spec | xargs sed -i 's/browse_pages_path/admin_pages_path/g; s/browse_pages_url/admin_pages_url/g'

# browse_pages_by_entity -> by_entity_admin_pages (collection action)
grep -rl "browse_pages_by_entity_path\|browse_pages_by_entity_url" app spec | xargs sed -i 's/browse_pages_by_entity_path/by_entity_admin_pages_path/g; s/browse_pages_by_entity_url/by_entity_admin_pages_url/g'

# browse_pages_batch_update -> batch_update_admin_pages
grep -rl "browse_pages_batch_update_path\|browse_pages_batch_update_url" app spec | xargs sed -i 's/browse_pages_batch_update_path/batch_update_admin_pages_path/g; s/browse_pages_batch_update_url/batch_update_admin_pages_url/g'

# browse_modules -> admin_modules
grep -rl "browse_modules_path\|browse_modules_url" app spec | xargs sed -i 's/browse_modules_path/admin_modules_path/g; s/browse_modules_url/admin_modules_url/g'

# browse_module_entry -> entry_admin_module
grep -rl "browse_module_entry_path\|browse_module_entry_url" app spec | xargs sed -i 's/browse_module_entry_path/entry_admin_module_path/g; s/browse_module_entry_url/entry_admin_module_url/g'

# dashboard_root -> admin_dashboard
grep -rl "dashboard_root_path\|dashboard_root_url" app spec | xargs sed -i 's/dashboard_root_path/admin_dashboard_path/g; s/dashboard_root_url/admin_dashboard_url/g'

# settings_path -> admin_setting_path (singleton in Phase 4 but path is fine here)
grep -rl "\bsettings_path\b\|\bsettings_url\b" app spec | xargs sed -i 's/\bsettings_path\b/admin_setting_path/g; s/\bsettings_url\b/admin_setting_url/g'

# settings_module_path -> admin_module_config_path (this changes again in Phase 4)
grep -rl "settings_module_path\|settings_module_url" app spec | xargs sed -i 's/settings_module_path/admin_settings_module_path/g; s/settings_module_url/admin_settings_module_url/g'

grep -rl "settings_module_update_path" app spec | xargs sed -i 's/settings_module_update_path/admin_settings_module_update_path/g'
grep -rl "settings_module_entry_path" app spec | xargs sed -i 's/settings_module_entry_path/admin_settings_module_entry_path/g'
grep -rl "settings_modules_payment_merchant_account_path" app spec | xargs sed -i 's/settings_modules_payment_merchant_account_path/admin_settings_modules_payment_merchant_account_path/g'
grep -rl "settings_modules_payment_merchant_accounts_path" app spec | xargs sed -i 's/settings_modules_payment_merchant_accounts_path/admin_settings_modules_payment_merchant_accounts_path/g'
grep -rl "edit_settings_modules_payment_merchant_account_path" app spec | xargs sed -i 's/edit_settings_modules_payment_merchant_account_path/edit_admin_settings_modules_payment_merchant_account_path/g'
grep -rl "new_settings_modules_payment_merchant_account_path" app spec | xargs sed -i 's/new_settings_modules_payment_merchant_account_path/new_admin_settings_modules_payment_merchant_account_path/g'

# search_path (in admin context) -> admin_search_path
# Need to scope this carefully — only change references inside admin views/controllers
grep -rln "search_path" app/views/admin/ app/controllers/admin/ spec/requests/search_spec.rb 2>/dev/null | xargs -r sed -i 's/\bsearch_path\b/admin_search_path/g'
```

- [ ] **Step 2.4.2: Update controller class references in views and specs**

Many specs and views reference controller classes by name (e.g., `MaintenancesController.action_methods`). Run:

```bash
grep -rln "LandingController\b" app spec | xargs -r sed -i 's/\bLandingController\b/Admin::DashboardController/g'
grep -rln "MaintenancesController\b" app spec | xargs -r sed -i 's/\bMaintenancesController\b/Admin::MaintenanceController/g'
grep -rln "EntitiesController\b" app spec | grep -v admin/maintenance | xargs -r sed -i 's/\bEntitiesController\b/Admin::EntitiesController/g'
grep -rln "PagesController\b" app spec | grep -v admin/maintenance | xargs -r sed -i 's/\bPagesController\b/Admin::PagesController/g'
grep -rln "ModulesController\b" app spec | grep -v admin/maintenance | xargs -r sed -i 's/\bModulesController\b/Admin::ModulesController/g'
grep -rln "ModuleEntriesController\b" app spec | xargs -r sed -i 's/\bModuleEntriesController\b/Admin::ModuleEntriesController/g'
grep -rln "SettingsController\b" app spec | xargs -r sed -i 's/\bSettingsController\b/Admin::SettingsController/g'
grep -rln "SearchController\b" app spec | xargs -r sed -i 's/\bSearchController\b/Admin::SearchController/g'
grep -rln "EntityEntriesController\b" app spec | xargs -r sed -i 's/\bEntityEntriesController\b/Admin::EntityEntriesController/g'
```

For maintenance controllers, prefix with `Admin::`:
```bash
grep -rln "Maintenance::FlowchartsController\b" app spec | xargs -r sed -i 's/\bMaintenance::FlowchartsController\b/Admin::Maintenance::FlowchartsController/g'
grep -rln "Maintenance::EntitiesController\b" app spec | xargs -r sed -i 's/\bMaintenance::EntitiesController\b/Admin::Maintenance::EntitiesController/g'
grep -rln "Maintenance::PagesController\b" app spec | xargs -r sed -i 's/\bMaintenance::PagesController\b/Admin::Maintenance::PagesController/g'
grep -rln "Maintenance::ConstantsController\b" app spec | xargs -r sed -i 's/\bMaintenance::ConstantsController\b/Admin::Maintenance::ConstantsController/g'
grep -rln "Maintenance::ModulesController\b" app spec | xargs -r sed -i 's/\bMaintenance::ModulesController\b/Admin::Maintenance::ModulesController/g'
grep -rln "Maintenance::CustomerProfileController\b" app spec | xargs -r sed -i 's/\bMaintenance::CustomerProfileController\b/Admin::Maintenance::CustomerProfileController/g'
grep -rln "Maintenance::FieldTemplatesController\b" app spec | xargs -r sed -i 's/\bMaintenance::FieldTemplatesController\b/Admin::Maintenance::FieldTemplatesController/g'
grep -rln "Maintenance::FlowchartValidationController\b" app spec | xargs -r sed -i 's/\bMaintenance::FlowchartValidationController\b/Admin::Maintenance::FlowchartValidationController/g'
grep -rln "Maintenance::UsersController\b" app spec | xargs -r sed -i 's/\bMaintenance::UsersController\b/Admin::Maintenance::UsersController/g'
grep -rln "Platform::CustomersController\b" app spec | xargs -r sed -i 's/\bPlatform::CustomersController\b/Admin::Maintenance::Platform::CustomersController/g'
grep -rln "Platform::CustomerContextsController\b" app spec | xargs -r sed -i 's/\bPlatform::CustomerContextsController\b/Admin::Maintenance::Platform::CustomerContextsController/g'
grep -rln "Platform::CodeGeneratorsController\b" app spec | xargs -r sed -i 's/\bPlatform::CodeGeneratorsController\b/Admin::Maintenance::Platform::CodeGeneratorsController/g'
grep -rln "Platform::IndustryTemplatesController\b" app spec | xargs -r sed -i 's/\bPlatform::IndustryTemplatesController\b/Admin::Maintenance::Platform::IndustryTemplatesController/g'
grep -rln "Platform::ModuleSettingsController\b" app spec | xargs -r sed -i 's/\bPlatform::ModuleSettingsController\b/Admin::Maintenance::Platform::ModuleSettingsController/g'
grep -rln "Platform::Sms::CredentialsController\b" app spec | xargs -r sed -i 's/\bPlatform::Sms::CredentialsController\b/Admin::Maintenance::Platform::Sms::CredentialsController/g'
grep -rln "Platform::Sms::TemplatesController\b" app spec | xargs -r sed -i 's/\bPlatform::Sms::TemplatesController\b/Admin::Maintenance::Platform::Sms::TemplatesController/g'
grep -rln "CodeGenerators::IoParamsController\b" app spec | xargs -r sed -i 's/\bCodeGenerators::IoParamsController\b/Admin::Maintenance::Platform::CodeGenerators::IoParamsController/g'
grep -rln "CodeGenerators::ElementTypeIoParamsController\b" app spec | xargs -r sed -i 's/\bCodeGenerators::ElementTypeIoParamsController\b/Admin::Maintenance::Platform::CodeGenerators::ElementTypeIoParamsController/g'
```

- [ ] **Step 2.4.3: Update routes for maintenance controllers**

Edit `config/routes.rb` lines 108–253. The block already lives inside `scope "admin"` (now `namespace :admin`), so all `controller: "maintenance/foo"` references resolve correctly relative to the new namespace. But the explicit `controller:` strings need updating:

Find each `controller: "maintenance/X"` and change to `controller: "admin/maintenance/X"`. Same for `controller: "platform/X"` → `controller: "admin/maintenance/platform/X"`.

Note: this is required because `controller:` strings are absolute paths to controller files, not namespace-relative. Verify by running:

Run: `bin/rails routes 2>&1 | grep -i flowchart | head -3`
Expected: Routes resolve to `Admin::Maintenance::FlowchartsController`.

### Task 2.5: Phase 2 verification

- [ ] **Step 2.5.1: Run full test suite**

Run: `bundle exec rspec 2>&1 | tail -20`
Expected: Pass count >= baseline. Fix any failures (most will be missed `*_path` references — grep again and update).

- [ ] **Step 2.5.2: Check for stragglers**

Run: `grep -rn "browse_\|dashboard_root\|MaintenancesController\|LandingController" app spec --include="*.rb" --include="*.erb" --include="*.js"`
Expected: No matches.

- [ ] **Step 2.5.3: Commit**

```bash
git add -A
git commit -m "refactor(routes): phase 2 — namespace :admin, drop browse_* prefix (F1, F2, A2)

- Move browse-area controllers under Admin:: namespace
- Move maintenance/platform controllers under Admin::Maintenance::
- Convert scope 'admin', as: nil to namespace :admin
- Rename LandingController -> Admin::DashboardController (singleton)
- Rename MaintenancesController -> Admin::MaintenanceController (singleton)
- Rename all browse_* helpers to admin_*"
```

---

## Phase 3: `scope module:` → `namespace`, fix singular/plural

This phase converts six `scope "x", as: :x, module: "x/admin"` blocks into clean `namespace` blocks, and standardizes singular/plural.

### Task 3.1: Move module controllers under Admin::Modules

- [ ] **Step 3.1.1: Move directories**

```bash
mkdir -p app/controllers/admin/modules
git mv app/controllers/email/admin app/controllers/admin/modules/emails
git mv app/controllers/email_campaigns/admin app/controllers/admin/modules/email_campaigns
git mv app/controllers/sms/admin app/controllers/admin/modules/sms
git mv app/controllers/payments/admin app/controllers/admin/modules/payments
git mv app/controllers/authentication/admin app/controllers/admin/modules/authentication
```

- [ ] **Step 3.1.2: Re-namespace each moved class**

For each moved file, change the namespace wrapper. Example for `app/controllers/admin/modules/emails/templates_controller.rb`:

Before:
```ruby
module Email
  module Admin
    class TemplatesController < ApplicationController
```

After:
```ruby
module Admin
  module Modules
    module Emails
      class TemplatesController < ApplicationController
```

Apply consistently. Note `Email` → `Emails` (plural for module name).

For payments: keep plural `Payments` (already plural).
For email_campaigns: stays as `EmailCampaigns`.
For sms: `Sms` (acronym, singular).
For authentication: `Authentication`.

- [ ] **Step 3.1.3: Move module views**

```bash
mkdir -p app/views/admin/modules
git mv app/views/email/admin app/views/admin/modules/emails 2>/dev/null
git mv app/views/email_campaigns/admin app/views/admin/modules/email_campaigns 2>/dev/null
git mv app/views/sms/admin app/views/admin/modules/sms 2>/dev/null
git mv app/views/payments/admin app/views/admin/modules/payments 2>/dev/null
git mv app/views/authentication/admin app/views/admin/modules/authentication 2>/dev/null

# clean up empty dirs
find app/views -type d -empty -delete
find app/controllers -type d -empty -delete
```

### Task 3.2: Update routes — module section

- [ ] **Step 3.2.1: Replace module scope blocks in `config/routes.rb`**

Find lines 270–319 (the `scope "modules", as: :modules do` block).

Replace:
```ruby
      # ----- Modules: Entries & Records (a) -----
      scope "modules", as: :modules do
        # Authentication
        scope "authentication", as: :authentication, module: "authentication/admin" do
          resources :users, except: [:destroy] do
            member do
              patch :activate
              patch :deactivate
              patch :reset_mfa
            end
          end
        end

        # Email (transactional)
        scope "email", as: :email, module: "email/admin" do
          resources :templates
          resources :messages, only: %i[index show]
        end

        # Email Campaigns (marketing)
        scope "email_campaigns", as: :email_campaigns, module: "email_campaigns/admin" do
          resources :subscribers
          resources :lists
          resources :campaigns do
            member do
              post :send_now
              post :pause
              post :resume
              post :cancel
            end
          end
        end

        # SMS
        scope "sms", as: :sms, module: "sms/admin" do
          resources :messages, only: %i[index show]
          post "send", to: "/sms/sends#create", as: :send
        end

        # Payment
        scope "payment", as: :payment, module: "payments/admin" do
          resources :transactions, only: %i[index show] do
            member { post :refund }
          end
          resources :subscriptions, only: %i[index show] do
            member { post :cancel }
          end
          resources :reconciliations, only: %i[index show]
        end
      end
```

With:
```ruby
      # ----- Modules: Entries & Records (a) -----
      namespace :modules do
        # Authentication
        namespace :authentication do
          resources :users, except: [:destroy] do
            member do
              patch :activate
              patch :deactivate
              patch :reset_mfa
            end
          end
        end

        # Email (transactional) — path 'emails' (plural per convention)
        namespace :emails do
          resources :templates
          resources :messages, only: %i[index show]
        end

        # Email Campaigns (marketing)
        namespace :email_campaigns do
          resources :subscribers
          resources :lists
          resources :campaigns do
            member do
              post :send_now
              post :pause
              post :resume
              post :cancel
            end
          end
        end

        # SMS
        namespace :sms do
          resources :messages, only: %i[index show]
          post "send", to: "sms/sends#create", as: :send
        end

        # Payment — path 'payments' (plural matching module class)
        namespace :payments do
          resources :transactions, only: %i[index show] do
            member { post :refund }
          end
          resources :subscriptions, only: %i[index show] do
            member { post :cancel }
          end
          resources :reconciliations, only: %i[index show]
        end
      end
```

(Phase 6 will further refactor verb actions; this phase only changes the wrapping.)

- [ ] **Step 3.2.2: Update `settings/modules/payment` scope (b-area)**

Find lines 93–98 in routes:
```ruby
        scope "settings/modules", as: :settings_modules do
          # Payment: customer-managed merchant accounts
          scope "payment", as: :payment, module: "payments/admin" do
            resources :merchant_accounts, only: %i[index new create edit update]
          end
        end
```

Replace with:
```ruby
        namespace :settings do
          namespace :modules do
            namespace :payments do
              resources :merchant_accounts, only: %i[index new create edit update],
                controller: "admin/modules/payments/merchant_accounts"
            end
          end
        end
```

The `controller:` override points to the existing controller (which moved to `Admin::Modules::Payments::MerchantAccountsController` in Step 3.1). This avoids creating a duplicate controller for the b-area; both a-area and b-area share the same merchant_accounts controller.

If the spec wanted distinct controllers, this would split here — but per the spec's Phase 3 section, sharing is acceptable since the controller already serves merchant accounts customer-side.

- [ ] **Step 3.2.3: Update `platform/module_settings/sms` scope (d-area)**

Find lines 200–206:
```ruby
            # Per-module platform settings
            scope "module_settings" do
              scope "sms", as: :module_settings_sms, module: "platform/sms" do
                resources :credentials, only: %i[index new create edit update]
                resources :templates,   only: %i[index new create edit update destroy]
              end
            end
```

Replace with:
```ruby
            namespace :module_settings do
              namespace :sms, module: "admin/maintenance/platform/sms" do
                resources :credentials, only: %i[index new create edit update]
                resources :templates,   only: %i[index new create edit update destroy]
              end
            end
```

(The `module:` override here is necessary because the controllers are at `Admin::Maintenance::Platform::Sms::*` rather than `Admin::Maintenance::Platform::ModuleSettings::Sms::*`. Acceptable trade-off.)

- [ ] **Step 3.2.4: Update SMS sends controller location**

Find `app/controllers/sms/sends_controller.rb`:

```bash
git mv app/controllers/sms/sends_controller.rb app/controllers/admin/modules/sms/sends_controller.rb
```

Update class wrapping from `module Sms` to `module Admin; module Modules; module Sms`.

Update routes line:
```ruby
          post "send", to: "sms/sends#create", as: :send
```
becomes (now relative to `namespace :modules`):
```ruby
          post "send", to: "sms/sends#create", as: :send
```
(no change — Rails resolves `sms/sends` relative to the `Admin::Modules::` prefix imposed by the surrounding namespaces).

Verify: Run `bin/rails routes 2>&1 | grep "modules/sms/send"` — expected: `Admin::Modules::Sms::SendsController#create`.

### Task 3.3: Update helper renames across codebase

- [ ] **Step 3.3.1: Rename module helpers**

```bash
# Email module: emails (was email)
grep -rln "modules_email_templates_path\|modules_email_template_path\|modules_email_messages_path\|modules_email_message_path" app spec | xargs -r sed -i \
  -e 's/modules_email_templates_path/admin_modules_emails_templates_path/g' \
  -e 's/modules_email_template_path/admin_modules_emails_template_path/g' \
  -e 's/modules_email_messages_path/admin_modules_emails_messages_path/g' \
  -e 's/modules_email_message_path/admin_modules_emails_message_path/g' \
  -e 's/edit_modules_email_template_path/edit_admin_modules_emails_template_path/g' \
  -e 's/new_modules_email_template_path/new_admin_modules_emails_template_path/g'

# Email campaigns
for verb in '' 'edit_' 'new_'; do
  for r in subscriber list campaign; do
    grep -rln "${verb}modules_email_campaigns_${r}" app spec | xargs -r sed -i "s/${verb}modules_email_campaigns_${r}/${verb}admin_modules_email_campaigns_${r}/g"
  done
done
grep -rln "modules_email_campaigns_subscribers_path\|modules_email_campaigns_lists_path\|modules_email_campaigns_campaigns_path" app spec | xargs -r sed -i \
  -e 's/modules_email_campaigns_subscribers_path/admin_modules_email_campaigns_subscribers_path/g' \
  -e 's/modules_email_campaigns_lists_path/admin_modules_email_campaigns_lists_path/g' \
  -e 's/modules_email_campaigns_campaigns_path/admin_modules_email_campaigns_campaigns_path/g'
# Member actions for campaigns
for action in send_now pause resume cancel; do
  grep -rln "${action}_modules_email_campaigns_campaign_path" app spec | xargs -r sed -i "s/${action}_modules_email_campaigns_campaign_path/${action}_admin_modules_email_campaigns_campaign_path/g"
done

# SMS
grep -rln "modules_sms_messages_path\|modules_sms_message_path\|modules_sms_send_path" app spec | xargs -r sed -i \
  -e 's/modules_sms_messages_path/admin_modules_sms_messages_path/g' \
  -e 's/modules_sms_message_path/admin_modules_sms_message_path/g' \
  -e 's/modules_sms_send_path/admin_modules_sms_send_path/g'

# Payment -> payments
for r in transactions transaction subscriptions subscription reconciliations reconciliation; do
  grep -rln "modules_payment_${r}_path" app spec | xargs -r sed -i "s/modules_payment_${r}_path/admin_modules_payments_${r}_path/g"
done
grep -rln "refund_modules_payment_transaction_path" app spec | xargs -r sed -i 's/refund_modules_payment_transaction_path/refund_admin_modules_payments_transaction_path/g'
grep -rln "cancel_modules_payment_subscription_path" app spec | xargs -r sed -i 's/cancel_modules_payment_subscription_path/cancel_admin_modules_payments_subscription_path/g'

# Authentication
for r in users user; do
  grep -rln "modules_authentication_${r}_path\b" app spec | xargs -r sed -i "s/modules_authentication_${r}_path/admin_modules_authentication_${r}_path/g"
done
for action in activate deactivate reset_mfa edit new; do
  grep -rln "${action}_modules_authentication_user_path" app spec | xargs -r sed -i "s/${action}_modules_authentication_user_path/${action}_admin_modules_authentication_user_path/g"
done
```

- [ ] **Step 3.3.2: Rename b-area (settings/modules/payment) helpers**

```bash
# After phase 2 these became admin_settings_modules_payment_*; now rename to admin_settings_modules_payments_*
for prefix in '' 'edit_' 'new_'; do
  grep -rln "${prefix}admin_settings_modules_payment_merchant_account" app spec | xargs -r sed -i "s/${prefix}admin_settings_modules_payment_merchant_account/${prefix}admin_settings_modules_payments_merchant_account/g"
done
grep -rln "admin_settings_modules_payment_merchant_accounts_path" app spec | xargs -r sed -i 's/admin_settings_modules_payment_merchant_accounts_path/admin_settings_modules_payments_merchant_accounts_path/g'
```

- [ ] **Step 3.3.3: Rename d-area (platform/module_settings/sms) helpers**

```bash
for prefix in '' 'edit_' 'new_'; do
  for r in credential template; do
    grep -rln "${prefix}admin_maintenance_platform_module_settings_sms_${r}" app spec | xargs -r sed -i "s/${prefix}admin_maintenance_platform_module_settings_sms_${r}/${prefix}admin_maintenance_platform_module_settings_sms_${r}/g"
  done
done
# (No-op transformation; these names were already correct after phase 2 because `as: :module_settings_sms` was preserved.)
```

### Task 3.4: Phase 3 verification

- [ ] **Step 3.4.1: Run full test suite**

Run: `bundle exec rspec 2>&1 | tail -20`
Expected: Pass.

- [ ] **Step 3.4.2: Verify no `scope ... module:` remains**

Run: `grep -n "scope.*module:" config/routes.rb`
Expected: Only one match (the d-area `namespace :sms, module: "admin/maintenance/platform/sms"` — acceptable per spec).

- [ ] **Step 3.4.3: Commit**

```bash
git add -A
git commit -m "refactor(routes): phase 3 — namespace conversion + plural normalization (B1, B2, E)

- Convert all scope...module: blocks to namespace
- Move module controllers under Admin::Modules::*
- Standardize plural module paths: payment->payments, email->emails
- Update all module-area helpers to admin_modules_* prefix"
```

---

## Phase 4: Singleton controllers + Devise sign-in

### Task 4.1: Convert `MaintenanceController` to singular singleton

The controller class was already renamed in Phase 2 (`Admin::MaintenanceController`). Now switch the route from path-only to `resource`.

- [ ] **Step 4.1.1: Edit `config/routes.rb` maintenance scope**

Find:
```ruby
        scope :maintenance, as: :maintenance do
          get "/", to: "maintenances#show", as: :root
```

Replace with:
```ruby
        resource :maintenance, only: :show, controller: "admin/maintenance"
        scope :maintenance, as: :maintenance do
```

(Drop the `get "/"` line; the `resource :maintenance, only: :show` produces `admin_maintenance_path` → `/admin/maintenance` → `Admin::MaintenanceController#show`. Then the existing `scope :maintenance` block continues to host nested resources.)

- [ ] **Step 4.1.2: Update helper references**

Run:
```bash
grep -rln "admin_maintenance_root_path\|admin_maintenance_root_url" app spec | xargs -r sed -i \
  -e 's/admin_maintenance_root_path/admin_maintenance_path/g' \
  -e 's/admin_maintenance_root_url/admin_maintenance_url/g'
```

### Task 4.2: Convert `SettingsController` to singular `SettingController`

- [ ] **Step 4.2.1: Rename controller class and file**

```bash
git mv app/controllers/admin/settings_controller.rb app/controllers/admin/setting_controller.rb
```

Edit `app/controllers/admin/setting_controller.rb`:

Before:
```ruby
module Admin
  class SettingsController < ApplicationController
```

After:
```ruby
module Admin
  class SettingController < ApplicationController
```

Note: this controller currently has multiple actions (`show`, `module_config`, `update_module_config`). Split:

- Keep `show` here.
- Move `module_config` and `update_module_config` to a new `Admin::ModuleConfigsController` (Step 4.3).

After splitting, `Admin::SettingController` has only `show`.

- [ ] **Step 4.2.2: Move views**

```bash
mkdir -p app/views/admin/setting
git mv app/views/admin/settings/show.html.erb app/views/admin/setting/show.html.erb 2>/dev/null
```

If `app/views/admin/settings/` has additional files (for module_config), keep them and move with the new controller in Step 4.3.

- [ ] **Step 4.2.3: Update routes**

Find in `config/routes.rb`:
```ruby
      get "settings", to: "settings#show", as: :setting
```

(After Phase 2, this should be one of the lines. The Phase 2 sed already gave us `admin_setting_path` from this `as: :setting`, so the helper is correct.) Replace with:

```ruby
      resource :setting, only: :show, controller: "admin/setting"
```

This produces `admin_setting_path` (singular), same as before — no helper rename needed.

### Task 4.3: Extract `Admin::ModuleConfigsController`

- [ ] **Step 4.3.1: Create new controller**

Create `app/controllers/admin/module_configs_controller.rb`:

```ruby
# frozen_string_literal: true

module Admin
  class ModuleConfigsController < ApplicationController
    set_tenant_from_route_params
    before_action :authenticate_user!

    def show
      # ... move body from old SettingsController#module_config
    end

    def update
      # ... move body from old SettingsController#update_module_config
    end
  end
end
```

(Read the existing `app/controllers/admin/setting_controller.rb` to copy the action bodies. Update internal references — `params[:module_key]` becomes `params[:key]`.)

- [ ] **Step 4.3.2: Decide on entry-key sub-route**

Run: `grep -rn "settings_module_entry_path\|admin_settings_module_entry_path" app spec`

If matches exist, model as nested resource. Otherwise drop.

Per pre-flight grep: only `app/services/module_contribution.rb:37` builds the URL as a string, not via helper. Decision: keep the route alive but rename helper.

- [ ] **Step 4.3.3: Update routes**

Find:
```ruby
      get   "settings/modules/:module_key",            to: "settings#module_config",        as: :settings_module
      patch "settings/modules/:module_key",            to: "settings#update_module_config", as: :settings_module_update
      get   "settings/modules/:module_key/:entry_key", to: "settings#module_config",        as: :settings_module_entry
```

(After Phase 2 sed, these helpers became `admin_settings_module_path`, `admin_settings_module_update_path`, `admin_settings_module_entry_path`.)

Replace the three lines with:
```ruby
      resources :module_configs, only: %i[show update], param: :key,
        controller: "admin/module_configs", path: "settings/modules" do
        get ":entry_key", on: :member, action: :show, as: :entry
      end
```

This produces:
- `admin_module_config_path(key: ...)` → `GET /admin/settings/modules/:key`
- `admin_module_config_path(key: ..., method: :patch)` → `PATCH /admin/settings/modules/:key`
- `entry_admin_module_config_path(key: ..., entry_key: ...)` → `GET /admin/settings/modules/:key/:entry_key`

- [ ] **Step 4.3.4: Update helper references and string-built URLs**

```bash
grep -rln "admin_settings_module_path\|admin_settings_module_url" app spec | xargs -r sed -i \
  -e 's/admin_settings_module_path/admin_module_config_path/g' \
  -e 's/admin_settings_module_url/admin_module_config_url/g'

grep -rln "admin_settings_module_update_path" app spec | xargs -r sed -i 's/admin_settings_module_update_path/admin_module_config_path/g'

grep -rln "admin_settings_module_entry_path" app spec | xargs -r sed -i 's/admin_settings_module_entry_path/entry_admin_module_config_path/g'
```

Update `app/services/module_contribution.rb:37` URL (was `/admin/settings/modules/#{module_key}/#{entry_key}`) — no change to URL pattern since the path stayed `/admin/settings/modules/:key/:entry_key`. But replace the manual string-build with helper:

Edit `app/services/module_contribution.rb:37`. Find:
```ruby
when :settings then "/#{customer_id}/admin/settings/modules/#{module_key}/#{entry_key}"
```

Replace with:
```ruby
when :settings
  Rails.application.routes.url_helpers.entry_admin_module_config_path(
    customer_id: customer_id, key: module_key, entry_key: entry_key
  )
```

- [ ] **Step 4.3.5: Update keyword param renames**

`SettingsController#module_config` likely reads `params[:module_key]`. The new route uses `:key`. Update the moved actions in `Admin::ModuleConfigsController` to read `params[:key]`.

Run: `grep -n "params\[:module_key\]" app/controllers/admin/module_configs_controller.rb`
For each match, change to `params[:key]`.

(But the entry-key sub-route uses `:entry_key`, that's preserved.)

### Task 4.4: A4 — remove root sign_in route, redirect to Devise

- [ ] **Step 4.4.1: Edit `config/routes.rb`**

Find lines 15–16:
```ruby
  root "home#index"
  post "/", to: "home#sign_in", as: :root_sign_in
```

Replace with:
```ruby
  root "home#index"
```

- [ ] **Step 4.4.2: Update home/index template**

Find the form action that posts to `/`:

Run: `grep -rn "root_sign_in_path\|root_sign_in_url" app spec`

For each match, update form action to `user_session_path(customer_id: ...)` (Devise default).

Read `app/views/home/index.html.erb`:

Run: `grep -n "form_with\|form_for\|action=" app/views/home/index.html.erb | head`

Identify the sign-in form. Update its `url:` to use Devise's `user_session_path`. The Devise routes are scoped under `/:customer_id/auth/`, so the form needs the customer_id from the input field.

If the form currently submits to `root_sign_in_path` because customer_id is unknown until form submission, restructure: redirect to `/<customer_id>/auth/sign_in` after entering customer_id (a two-step flow), or keep a thin shim controller action that resolves customer_id and redirects to Devise.

**Decision:** Keep current behavior by routing the post to `Authentication::SessionsController#resolve_and_create` instead. Edit `home_controller.rb` to remove `sign_in` action. Add new action to authentication sessions controller.

This is a semi-significant flow change. **Alternative:** keep `home#sign_in` action but rename route to fit convention. Per AGENTS.md (no backwards compat), do the proper thing.

Concretely:
1. In `config/routes.rb`, after the `root` line:
   ```ruby
   post "/sign_in", to: "authentication/customer_resolutions#create", as: :customer_sign_in
   ```
2. Create `app/controllers/authentication/customer_resolutions_controller.rb`:
   ```ruby
   # frozen_string_literal: true

   module Authentication
     class CustomerResolutionsController < ApplicationController
       def create
         # Move logic from HomeController#sign_in here.
         # Resolve tenant from params, then sign user in (or redirect to /:cid/auth/sign_in).
       end
     end
   end
   ```
3. Read `app/controllers/home_controller.rb`. Move the body of `sign_in` action into `CustomerResolutionsController#create`. Delete `sign_in` action and route.

4. Update `app/views/home/index.html.erb` form: change `url: root_sign_in_path` to `url: customer_sign_in_path`.

5. Update specs:
   ```bash
   grep -rln "root_sign_in_path\|root_sign_in_url" app spec | xargs -r sed -i \
     -e 's/root_sign_in_path/customer_sign_in_path/g' \
     -e 's/root_sign_in_url/customer_sign_in_url/g'
   ```

### Task 4.5: Phase 4 verification

- [ ] **Step 4.5.1: Run full test suite**

Run: `bundle exec rspec 2>&1 | tail -20`
Expected: Pass.

- [ ] **Step 4.5.2: Manual smoke test**

Restart server: `rm -f public/assets/.manifest.json && bin/rails server -b 0.0.0.0 -p 3000`

Test in browser:
- Sign in flow works
- Dashboard loads at `/<cid>/admin`
- Maintenance page loads at `/<cid>/admin/maintenance`
- Settings page loads at `/<cid>/admin/settings`
- Module settings page loads at `/<cid>/admin/settings/modules/sms` (or another module key)

- [ ] **Step 4.5.3: Commit**

```bash
git add -A
git commit -m "refactor(routes): phase 4 — singleton controllers + Devise sign-in (A1, A3, A4)

- Convert MaintenancesController to singular Admin::MaintenanceController
- Convert SettingsController to singular Admin::SettingController
- Extract Admin::ModuleConfigsController for keyed module configuration
- Move root POST sign-in to dedicated CustomerResolutionsController"
```

---

## Phase 5: Parameter shadowing renames

### Task 5.1: D1 — `param: :path` → `param: :slug` for code generators

- [ ] **Step 5.1.1: Edit `config/routes.rb` code_generators block**

Find:
```ruby
            resources :code_generators, controller: "platform/code_generators", param: :path do
```

(After Phase 2, this is `controller: "admin/maintenance/platform/code_generators"`.)

Replace with:
```ruby
            resources :code_generators,
              controller: "admin/maintenance/platform/code_generators",
              param: :slug do
```

- [ ] **Step 5.1.2: Update controller**

Read `app/controllers/admin/maintenance/platform/code_generators_controller.rb`:

Run: `grep -n "params\[:path\]\|params\.permit.*:path" app/controllers/admin/maintenance/platform/code_generators_controller.rb`

For each match, change `params[:path]` → `params[:slug]`. (Preserve any genuine `path` params that aren't the route param — likely none.)

- [ ] **Step 5.1.3: Update specs and views**

```bash
grep -rln "code_generator_path\|admin_maintenance_platform_code_generator_path" app spec | head
```

The helper signature changes from `(customer_id, path: 'X')` to `(customer_id, slug: 'X')`. But Rails actually generates `(customer_id, id)` since `param:` only affects parsing, not the helper signature when called positionally. Verify:

Run: `bin/rails routes 2>&1 | grep -E "code_generators?\s" | head`

Expected: `/:customer_id/admin/maintenance/platform/code_generators/:slug`

For positional callers, no change. For named callers using `path:`, rename to `slug:`:

```bash
grep -rln "code_generator_path.*path:" app spec | xargs -r sed -i 's/code_generator_path(\([^)]*\)path:/code_generator_path(\1slug:/g'
```

(Edit each match manually if regex is too complex.)

### Task 5.2: D2 — `:action_name` → `:generator_action`

- [ ] **Step 5.2.1: Edit `config/routes.rb`**

Find:
```ruby
            post "code_generators/:action_name/io_params",
              to: "code_generators/io_params#show",
              as: :code_generator_io_params,
              constraints: { action_name: /[A-Za-z0-9_]+/ }
```

(After Phase 2: `to: "admin/maintenance/platform/code_generators/io_params#show"`.)

Replace with:
```ruby
            post "code_generators/:generator_action/io_params",
              to: "admin/maintenance/platform/code_generators/io_params#show",
              as: :code_generator_io_params,
              constraints: { generator_action: /[A-Za-z0-9_]+/ }
```

- [ ] **Step 5.2.2: Update controller**

Edit `app/controllers/admin/maintenance/platform/code_generators/io_params_controller.rb`:

Run: `grep -n "params\[:action_name\]" app/controllers/admin/maintenance/platform/code_generators/io_params_controller.rb`

For each match, replace `params[:action_name]` with `params[:generator_action]`.

- [ ] **Step 5.2.3: Update Stimulus JS clients**

Edit `app/javascript/controllers/property_editor/step_io/io_params_client.js:18`:

Find:
```javascript
const response = await fetch(`/${customerId}/admin/maintenance/platform/code_generators/${encodeURIComponent(action)}/io_params`, {
```

The URL pattern is unchanged (`/:generator_action/io_params` — same shape). The `action` JS variable is still passed positionally. No change needed here.

Verify in spec: `bundle exec rspec spec/system/code_generator_*_spec.rb 2>&1 | tail -10`

### Task 5.3: D3 — `f/:token` → `forms/:token`

- [ ] **Step 5.3.1: Edit `config/routes.rb`**

Find lines 54–55:
```ruby
    # Public page rendering — no authentication required
    get  'f/:token', to: 'public_pages#show',   as: :public_page
    post 'f/:token', to: 'public_pages#submit',  as: :public_page_submit
```

Replace with:
```ruby
    # Public page rendering — no authentication required
    get  "forms/:token", to: "public_pages#show",   as: :public_page
    post "forms/:token", to: "public_pages#submit", as: :public_page_submit
```

- [ ] **Step 5.3.2: Update string URL builders**

Run: `grep -rn "/f/" app --include="*.rb" --include="*.erb" --include="*.js"`

For each match, update path. Specifically:

Edit `app/services/feature_modules/exit_resolver.rb:82`:

Find:
```ruby
"/#{@customer.id}/f/#{page.public_token}"
```

Replace with:
```ruby
"/#{@customer.id}/forms/#{page.public_token}"
```

Edit `app/controllers/public_pages_controller.rb:6` (comment):

Find:
```ruby
# URL: /:customer_id/f/:token
```

Replace with:
```ruby
# URL: /:customer_id/forms/:token
```

- [ ] **Step 5.3.3: Search test fixtures**

Run: `grep -rn "/f/" spec --include="*.rb"`

Update each match.

### Task 5.4: Phase 5 verification

- [ ] **Step 5.4.1: Run full test suite**

Run: `bundle exec rspec 2>&1 | tail -20`
Expected: Pass.

- [ ] **Step 5.4.2: Manual smoke test (code generator UI)**

Restart server. In browser, open a flowchart with a code-generator step element. Verify the property editor loads IO params from `/admin/maintenance/platform/code_generators/<action>/io_params`. Check Network tab for 200 response.

- [ ] **Step 5.4.3: Manual smoke test (public form)**

Open a published page's public URL: `/<cid>/forms/<token>`. Verify it renders.

- [ ] **Step 5.4.4: Commit**

```bash
git add -A
git commit -m "refactor(routes): phase 5 — eliminate parameter shadowing (D1, D2, D3)

- Rename param :path -> :slug for code_generators (D1)
- Rename :action_name segment -> :generator_action (D2)
- Rename /f/:token -> /forms/:token for public pages (D3)"
```

---

## Phase 6: REST remodeling

Each task replaces verb-style member/collection actions with nested resources. Each task is its own commit for easier review.

### Task 6.1: C1 — Entities batch destroy → nested entry resource

- [ ] **Step 6.1.1: Edit routes**

After Phase 2 the route is:
```ruby
      resources :entities, only: %i[index show] do
        delete "entries/batch", on: :member, to: "entities#batch_destroy_entries", as: :batch_destroy_entries
      end
```

Replace with:
```ruby
      resources :entities, only: %i[index show] do
        resources :entries, only: [], controller: "admin/entity_entries" do
          collection do
            delete :batch, action: :batch_destroy
          end
        end
      end
```

- [ ] **Step 6.1.2: Move action**

Read `app/controllers/admin/entities_controller.rb`. Find `batch_destroy_entries` action.

Move its body to `app/controllers/admin/entity_entries_controller.rb` as `batch_destroy` action.

Delete `batch_destroy_entries` from `EntitiesController`.

- [ ] **Step 6.1.3: Update helper references**

```bash
grep -rln "batch_destroy_entries_admin_entity_path" app spec | xargs -r sed -i \
  's/batch_destroy_entries_admin_entity_path/batch_admin_entity_entries_path/g'
```

- [ ] **Step 6.1.4: Run focused specs**

Run: `bundle exec rspec spec/requests/entities_spec.rb spec/requests/entity_entries_spec.rb`
Expected: Pass.

- [ ] **Step 6.1.5: Commit**

```bash
git add -A
git commit -m "refactor(routes): C1 — model entity entries batch destroy as nested resource"
```

### Task 6.2: C2 — Pages by_entity → nested resource

- [ ] **Step 6.2.1: Edit routes**

Find (after Phase 2):
```ruby
      resources :pages, only: :index do
        collection do
          get  "entity/:entity_id", to: "pages#by_entity", as: :by_entity
          post "batch",             to: "pages#batch_update", as: :batch_update
        end
      end
```

Split into:
```ruby
      resources :entities, only: [] do
        resources :pages, only: :index, controller: "admin/entity_pages"
      end

      resources :pages, only: :index do
        collection do
          patch :batch, action: :batch_update
        end
      end
```

(C3 is also handled here: `post "batch"` → `patch :batch`.)

- [ ] **Step 6.2.2: Create new controller**

Create `app/controllers/admin/entity_pages_controller.rb`:

```ruby
# frozen_string_literal: true

module Admin
  class EntityPagesController < ApplicationController
    set_tenant_from_route_params
    before_action :authenticate_user!

    def index
      # Move body from old PagesController#by_entity here.
      # Use params[:entity_id] (already set by nested resource).
    end
  end
end
```

Read `app/controllers/admin/pages_controller.rb`. Find `by_entity` action. Copy body to new controller (drop `by_entity` from PagesController).

- [ ] **Step 6.2.3: Move view**

```bash
mkdir -p app/views/admin/entity_pages
git mv app/views/admin/pages/by_entity.html.erb app/views/admin/entity_pages/index.html.erb 2>/dev/null
```

(If file doesn't exist, `by_entity` may render `index.html.erb` directly — confirm by reading the action.)

- [ ] **Step 6.2.4: Update helpers**

```bash
grep -rln "by_entity_admin_pages_path" app spec | xargs -r sed -i 's/by_entity_admin_pages_path/admin_entity_pages_path/g'
```

Note: `admin_entity_pages_path(entity_id: 5)` is the new helper.

### Task 6.3: C3 — Pages batch update is PATCH (already in 6.2)

- [ ] **Step 6.3.1: Update existing helper**

The helper `batch_update_admin_pages_path` becomes `batch_admin_pages_path`:

```bash
grep -rln "batch_update_admin_pages_path" app spec | xargs -r sed -i \
  's/batch_update_admin_pages_path/batch_admin_pages_path/g'
```

- [ ] **Step 6.3.2: Update HTTP method in views**

Read `app/views/admin/pages/index.html.erb` lines 29–32. The `method: :post` references must become `method: :patch`:

```bash
grep -rln 'batch_admin_pages_path.*method: :post' app | xargs -r sed -i 's/method: :post/method: :patch/g'
```

(Verify with read.)

- [ ] **Step 6.3.3: Run pages specs**

Run: `bundle exec rspec spec/requests/pages_spec.rb spec/requests/maintenance/pages_spec.rb`
Expected: Pass.

- [ ] **Step 6.3.4: Commit C2 + C3 together**

```bash
git add -A
git commit -m "refactor(routes): C2, C3 — pages by_entity nested + batch is PATCH"
```

### Task 6.4: C4 — Module entries with `:key` param

- [ ] **Step 6.4.1: Edit routes**

Find (after Phase 2):
```ruby
      resources :modules, only: :index do
        get "entries/:entry_key", on: :member, to: "module_entries#show", as: :entry, param: :module_key
      end
```

Replace with:
```ruby
      resources :modules, only: :index, param: :key do
        resources :entries, only: :show, param: :key, controller: "admin/module_entries"
      end
```

- [ ] **Step 6.4.2: Update controller params**

Edit `app/controllers/admin/module_entries_controller.rb`:

Run: `grep -n "params\[:module_key\]\|params\[:entry_key\]" app/controllers/admin/module_entries_controller.rb`

Replace:
- `params[:module_key]` → `params[:module_key]` (no change — Rails generates this from nested `:key` param of parent)

Actually with nested resources Rails uses `params[:module_key]` for parent and `params[:id]` for child (because child param is `:key`, child id appears as `:key`).

Verify by `bin/rails routes 2>&1 | grep "modules.*entries" | head`. Adjust controller accordingly.

- [ ] **Step 6.4.3: Update helpers**

```bash
grep -rln "entry_admin_module_path" app spec | xargs -r sed -i \
  's/entry_admin_module_path/admin_module_entry_path/g'
```

- [ ] **Step 6.4.4: Run module entries specs**

Run: `bundle exec rspec spec/requests/module_entries_spec.rb spec/requests/modules_spec.rb`
Expected: Pass.

- [ ] **Step 6.4.5: Commit**

```bash
git add -A
git commit -m "refactor(routes): C4 — model module entries with :key params"
```

### Task 6.5: C5 — Flowchart sub-resources

This is the largest single C-task. It introduces 4 new controllers under `Admin::Maintenance::`.

- [ ] **Step 6.5.1: Create new controllers**

Create `app/controllers/admin/maintenance/flowchart_versions_controller.rb`:
```ruby
# frozen_string_literal: true

module Admin
  module Maintenance
    class FlowchartVersionsController < ApplicationController
      set_tenant_from_route_params
      before_action :authenticate_user!

      def index
        # Move body from FlowchartsController#versions
      end

      def create
        # Move body from FlowchartsController#restore_version
      end
    end
  end
end
```

Create `app/controllers/admin/maintenance/flowchart_statuses_controller.rb`:
```ruby
# frozen_string_literal: true

module Admin
  module Maintenance
    class FlowchartStatusesController < ApplicationController
      set_tenant_from_route_params
      before_action :authenticate_user!

      def create
        # Move body from FlowchartsController#activate
      end

      def destroy
        # Move body from FlowchartsController#deactivate
      end
    end
  end
end
```

Create `app/controllers/admin/maintenance/flowchart_traces_controller.rb`:
```ruby
# frozen_string_literal: true

module Admin
  module Maintenance
    class FlowchartTracesController < ApplicationController
      set_tenant_from_route_params
      before_action :authenticate_user!

      def create
        # Move body from FlowchartsController#trace
      end
    end
  end
end
```

Create `app/controllers/admin/maintenance/flowchart_documents_controller.rb`:
```ruby
# frozen_string_literal: true

module Admin
  module Maintenance
    class FlowchartDocumentsController < ApplicationController
      set_tenant_from_route_params
      before_action :authenticate_user!

      def show
        # Move body from FlowchartsController#generate_docs
      end
    end
  end
end
```

For each `# Move body from X` placeholder: read the corresponding action in `app/controllers/admin/maintenance/flowcharts_controller.rb`, copy the body verbatim, paste into the new controller's action. Then delete the original action.

- [ ] **Step 6.5.2: Edit routes**

Find:
```ruby
          resources :flowcharts, controller: "admin/maintenance/flowcharts" do
            member do
              patch :autosave
              patch :restore
              get :copy
              post :trace
              get :versions
              post :restore_version
              get :generate_docs
              post :activate
              post :deactivate
            end
            collection do
              get :trash
              delete :empty_trash
              get "validation/implicit_keys", to: "admin/maintenance/flowchart_validation#implicit_keys", as: :validation_implicit_keys
            end
          end
```

Replace with:
```ruby
          resources :flowcharts, controller: "admin/maintenance/flowcharts" do
            member do
              patch :autosave
              patch :restore
              get :copy
            end
            collection do
              get :trash
              delete :empty_trash
              get "validation/implicit_keys", to: "admin/maintenance/flowchart_validation#implicit_keys", as: :validation_implicit_keys
            end
            resources :versions, only: %i[index create], controller: "admin/maintenance/flowchart_versions"
            resource :status, only: %i[create destroy], controller: "admin/maintenance/flowchart_statuses"
            resources :traces, only: :create, controller: "admin/maintenance/flowchart_traces"
            resource :document, only: :show, controller: "admin/maintenance/flowchart_documents"
          end
```

- [ ] **Step 6.5.3: Move views**

```bash
mkdir -p app/views/admin/maintenance/flowchart_versions
git mv app/views/admin/maintenance/flowcharts/versions.html.erb app/views/admin/maintenance/flowchart_versions/index.html.erb 2>/dev/null

mkdir -p app/views/admin/maintenance/flowchart_documents
git mv app/views/admin/maintenance/flowcharts/generate_docs.html.erb app/views/admin/maintenance/flowchart_documents/show.html.erb 2>/dev/null
```

(Skip if files don't exist — actions may render JSON only.)

- [ ] **Step 6.5.4: Update helpers**

```bash
# versions
grep -rln "versions_admin_maintenance_flowchart_path" app spec | xargs -r sed -i \
  's/versions_admin_maintenance_flowchart_path/admin_maintenance_flowchart_versions_path/g'
grep -rln "restore_version_admin_maintenance_flowchart_path" app spec | xargs -r sed -i \
  's/restore_version_admin_maintenance_flowchart_path/admin_maintenance_flowchart_versions_path/g'

# status
grep -rln "activate_admin_maintenance_flowchart_path" app spec | xargs -r sed -i \
  's/activate_admin_maintenance_flowchart_path/admin_maintenance_flowchart_status_path/g'
grep -rln "deactivate_admin_maintenance_flowchart_path" app spec | xargs -r sed -i \
  's/deactivate_admin_maintenance_flowchart_path/admin_maintenance_flowchart_status_path/g'

# traces
grep -rln "trace_admin_maintenance_flowchart_path" app spec | xargs -r sed -i \
  's/trace_admin_maintenance_flowchart_path/admin_maintenance_flowchart_traces_path/g'

# documents
grep -rln "generate_docs_admin_maintenance_flowchart_path" app spec | xargs -r sed -i \
  's/generate_docs_admin_maintenance_flowchart_path/admin_maintenance_flowchart_document_path/g'
```

Important: callers of activate/deactivate now use the same helper but different HTTP methods. Update views/specs to use:
- `method: :post` for activate (became `create`)
- `method: :delete` for deactivate (became `destroy`)

```bash
grep -rln "admin_maintenance_flowchart_status_path" app spec
```

For each match, verify the HTTP method is correct. Read each match and update if needed.

For `restore_version` callers: update to send POST to `admin_maintenance_flowchart_versions_path` (because `create` action). Already POST in old version — should be fine.

For `versions` callers: update to GET on `admin_maintenance_flowchart_versions_path`. Same — was GET.

- [ ] **Step 6.5.5: Run flowchart specs**

Run: `bundle exec rspec spec/requests/maintenance/flowcharts_spec.rb spec/requests/maintenance/`
Expected: Pass.

- [ ] **Step 6.5.6: Commit**

```bash
git add -A
git commit -m "refactor(routes): C5 — flowchart verb actions to sub-resources

- versions/restore_version -> resources :versions
- activate/deactivate -> resource :status
- trace -> resources :traces
- generate_docs -> resource :document"
```

### Task 6.6: C6 — Pages sub-resources

- [ ] **Step 6.6.1: Create new controllers**

Create four files under `app/controllers/admin/maintenance/`:

`page_publications_controller.rb`:
```ruby
# frozen_string_literal: true

module Admin
  module Maintenance
    class PagePublicationsController < ApplicationController
      set_tenant_from_route_params
      before_action :authenticate_user!

      def create
        # Move body from PagesController#publish
      end

      def destroy
        # Move body from PagesController#unpublish
      end
    end
  end
end
```

`page_previews_controller.rb`:
```ruby
# frozen_string_literal: true

module Admin
  module Maintenance
    class PagePreviewsController < ApplicationController
      set_tenant_from_route_params
      before_action :authenticate_user!

      def show   # GET preview
        # Move body from PagesController#preview (GET branch)
      end

      def create  # POST preview
        # Move body from PagesController#preview (POST branch)
      end
    end
  end
end
```

`page_field_options_controller.rb`:
```ruby
# frozen_string_literal: true

module Admin
  module Maintenance
    class PageFieldOptionsController < ApplicationController
      set_tenant_from_route_params
      before_action :authenticate_user!

      def show
        # Move body from PagesController#field_options
      end
    end
  end
end
```

`page_module_data_controller.rb`:
```ruby
# frozen_string_literal: true

module Admin
  module Maintenance
    class PageModuleDataController < ApplicationController
      set_tenant_from_route_params
      before_action :authenticate_user!

      def show
        # Move body from PagesController#module_data
      end
    end
  end
end
```

Read `app/controllers/admin/maintenance/pages_controller.rb`. For each action listed (publish, unpublish, preview GET/POST, field_options, module_data), copy the body to the new controller and delete from PagesController.

- [ ] **Step 6.6.2: Edit routes**

Find:
```ruby
          resources :pages, controller: "admin/maintenance/pages" do
            member do
              patch :autosave
              patch :restore
              patch :publish
              patch :unpublish
              get :copy
              get :preview
              post :preview
              post :apply_template
              get "field_options/:field_id", action: :field_options, as: :field_options
              get "module_data/:module_id",  action: :module_data,   as: :module_data
            end
            collection do
              get :trash
              delete :empty_trash
              get :entity_flows
              resources :field_templates, only: [:index, :create, :update, :destroy], controller: "admin/maintenance/field_templates"
            end
          end
```

Replace with:
```ruby
          resources :pages, controller: "admin/maintenance/pages" do
            member do
              patch :autosave
              patch :restore
              get :copy
              post :apply_template
            end
            collection do
              get :trash
              delete :empty_trash
              get :entity_flows
              resources :field_templates, only: [:index, :create, :update, :destroy], controller: "admin/maintenance/field_templates"
            end
            resource :publication, only: %i[create destroy], controller: "admin/maintenance/page_publications"
            resources :previews, only: %i[show create], controller: "admin/maintenance/page_previews"
            resources :field_options, only: :show, param: :field_id, controller: "admin/maintenance/page_field_options"
            resources :module_data, only: :show, param: :module_id, controller: "admin/maintenance/page_module_data"
          end
```

- [ ] **Step 6.6.3: Update helpers**

```bash
# publication (publish/unpublish -> create/destroy)
grep -rln "publish_admin_maintenance_page_path" app spec | xargs -r sed -i \
  's/publish_admin_maintenance_page_path/admin_maintenance_page_publication_path/g'
grep -rln "unpublish_admin_maintenance_page_path" app spec | xargs -r sed -i \
  's/unpublish_admin_maintenance_page_path/admin_maintenance_page_publication_path/g'

# previews
grep -rln "preview_admin_maintenance_page_path" app spec | xargs -r sed -i \
  's/preview_admin_maintenance_page_path/admin_maintenance_page_previews_path/g'

# field_options
grep -rln "field_options_admin_maintenance_page_path" app spec | xargs -r sed -i \
  's/field_options_admin_maintenance_page_path/admin_maintenance_page_field_option_path/g'

# module_data
grep -rln "module_data_admin_maintenance_page_path" app spec | xargs -r sed -i \
  's/module_data_admin_maintenance_page_path/admin_maintenance_page_module_datum_path/g'
```

Note: `module_data` Rails inflector singularizes to `module_datum` — verify with `bin/rails routes`. If unwanted, override:
```ruby
inflect.uncountable %w[module_data]
```
in `config/initializers/inflections.rb`.

- [ ] **Step 6.6.4: Update HTTP methods in views**

Search for any remaining publish/unpublish callers and ensure correct method:
- publish was PATCH → now POST (create)
- unpublish was PATCH → now DELETE (destroy)

```bash
grep -rn "admin_maintenance_page_publication_path" app spec
```

For each match, read context and update `method:` keyword arg.

- [ ] **Step 6.6.5: Run pages specs**

Run: `bundle exec rspec spec/requests/maintenance/pages_spec.rb`
Expected: Pass.

- [ ] **Step 6.6.6: Commit**

```bash
git add -A
git commit -m "refactor(routes): C6 — page verb actions to sub-resources

- publish/unpublish -> resource :publication
- preview GET/POST -> resources :previews
- field_options/:field_id -> resources :field_options
- module_data/:module_id -> resources :module_data"
```

### Task 6.7: C7 — Industry templates seeds

- [ ] **Step 6.7.1: Create new controllers**

Create `app/controllers/admin/maintenance/platform/industry_template_default_seeds_controller.rb`:
```ruby
# frozen_string_literal: true

module Admin
  module Maintenance
    module Platform
      class IndustryTemplateDefaultSeedsController < ApplicationController
        set_tenant_from_route_params
        before_action :authenticate_user!

        def create
          # Move body from IndustryTemplatesController#seed_defaults
        end

        def destroy
          # Move body from IndustryTemplatesController#reset_defaults
        end
      end
    end
  end
end
```

Create `app/controllers/admin/maintenance/platform/industry_template_new_template_seeds_controller.rb`:
```ruby
# frozen_string_literal: true

module Admin
  module Maintenance
    module Platform
      class IndustryTemplateNewTemplateSeedsController < ApplicationController
        set_tenant_from_route_params
        before_action :authenticate_user!

        def create
          # Move body from IndustryTemplatesController#seed_new_templates
        end
      end
    end
  end
end
```

Read `app/controllers/admin/maintenance/platform/industry_templates_controller.rb`. Move the three action bodies. Delete from IndustryTemplatesController.

- [ ] **Step 6.7.2: Edit routes**

Find:
```ruby
            resources :industry_templates, controller: "admin/maintenance/platform/industry_templates", only: %i[index show edit update] do
              member do
                post :add_template
                delete :remove_template
                get :template_cards
              end
              collection do
                post :seed_defaults
                post :seed_new_templates
                post :reset_defaults
              end
            end
```

Replace with:
```ruby
            resources :industry_templates, controller: "admin/maintenance/platform/industry_templates", only: %i[index show edit update] do
              member do
                post :add_template
                delete :remove_template
                get :template_cards
              end
              collection do
                resource :default_seed, only: %i[create destroy],
                  controller: "admin/maintenance/platform/industry_template_default_seeds"
                resource :new_template_seed, only: :create,
                  controller: "admin/maintenance/platform/industry_template_new_template_seeds"
              end
            end
```

- [ ] **Step 6.7.3: Update helpers**

```bash
grep -rln "seed_defaults_admin_maintenance_platform_industry_templates_path" app spec | xargs -r sed -i \
  's/seed_defaults_admin_maintenance_platform_industry_templates_path/admin_maintenance_platform_industry_templates_default_seed_path/g'

grep -rln "reset_defaults_admin_maintenance_platform_industry_templates_path" app spec | xargs -r sed -i \
  's/reset_defaults_admin_maintenance_platform_industry_templates_path/admin_maintenance_platform_industry_templates_default_seed_path/g'

grep -rln "seed_new_templates_admin_maintenance_platform_industry_templates_path" app spec | xargs -r sed -i \
  's/seed_new_templates_admin_maintenance_platform_industry_templates_path/admin_maintenance_platform_industry_templates_new_template_seed_path/g'
```

Update HTTP methods (was POST for all three; now POST for create, DELETE for destroy):
- `seed_defaults` → POST → POST (no change)
- `reset_defaults` → POST → DELETE (change!)
- `seed_new_templates` → POST → POST (no change)

Find and update `reset_defaults` callers:
```bash
grep -rn "admin_maintenance_platform_industry_templates_default_seed_path" app spec
```

For each context that was `reset_defaults`, change `method: :post` → `method: :delete`.

- [ ] **Step 6.7.4: Run specs**

Run: `bundle exec rspec spec/requests/maintenance/ -e "industry"`
Expected: Pass.

- [ ] **Step 6.7.5: Commit**

```bash
git add -A
git commit -m "refactor(routes): C7 — industry template seed actions to sub-resources"
```

### Task 6.8: C8 — Email campaign delivery

- [ ] **Step 6.8.1: Create new controllers**

Create three controllers under `app/controllers/admin/modules/email_campaigns/`:

`campaign_deliveries_controller.rb`:
```ruby
# frozen_string_literal: true

module Admin
  module Modules
    module EmailCampaigns
      class CampaignDeliveriesController < ApplicationController
        set_tenant_from_route_params
        before_action :authenticate_user!

        def create
          # Move body from CampaignsController#send_now
        end
      end
    end
  end
end
```

`campaign_pauses_controller.rb`:
```ruby
# frozen_string_literal: true

module Admin
  module Modules
    module EmailCampaigns
      class CampaignPausesController < ApplicationController
        set_tenant_from_route_params
        before_action :authenticate_user!

        def create  # pause
          # Move body from CampaignsController#pause
        end

        def destroy  # resume
          # Move body from CampaignsController#resume
        end
      end
    end
  end
end
```

`campaign_cancellations_controller.rb`:
```ruby
# frozen_string_literal: true

module Admin
  module Modules
    module EmailCampaigns
      class CampaignCancellationsController < ApplicationController
        set_tenant_from_route_params
        before_action :authenticate_user!

        def create  # cancel
          # Move body from CampaignsController#cancel
        end
      end
    end
  end
end
```

Read `app/controllers/admin/modules/email_campaigns/campaigns_controller.rb`. Move the four action bodies. Delete originals.

- [ ] **Step 6.8.2: Edit routes**

Find (post-Phase 3):
```ruby
        namespace :email_campaigns do
          resources :subscribers
          resources :lists
          resources :campaigns do
            member do
              post :send_now
              post :pause
              post :resume
              post :cancel
            end
          end
        end
```

Replace with:
```ruby
        namespace :email_campaigns do
          resources :subscribers
          resources :lists
          resources :campaigns do
            resource :delivery, only: :create, controller: "admin/modules/email_campaigns/campaign_deliveries"
            resource :pause, only: %i[create destroy], controller: "admin/modules/email_campaigns/campaign_pauses"
            resource :cancellation, only: :create, controller: "admin/modules/email_campaigns/campaign_cancellations"
          end
        end
```

- [ ] **Step 6.8.3: Update helpers**

```bash
grep -rln "send_now_admin_modules_email_campaigns_campaign_path" app spec | xargs -r sed -i \
  's/send_now_admin_modules_email_campaigns_campaign_path/admin_modules_email_campaigns_campaign_delivery_path/g'

grep -rln "pause_admin_modules_email_campaigns_campaign_path" app spec | xargs -r sed -i \
  's/pause_admin_modules_email_campaigns_campaign_path/admin_modules_email_campaigns_campaign_pause_path/g'
grep -rln "resume_admin_modules_email_campaigns_campaign_path" app spec | xargs -r sed -i \
  's/resume_admin_modules_email_campaigns_campaign_path/admin_modules_email_campaigns_campaign_pause_path/g'

grep -rln "cancel_admin_modules_email_campaigns_campaign_path" app spec | xargs -r sed -i \
  's/cancel_admin_modules_email_campaigns_campaign_path/admin_modules_email_campaigns_campaign_cancellation_path/g'
```

Update HTTP methods:
- `send_now` POST → still POST
- `pause` POST → still POST (create)
- `resume` POST → DELETE (destroy)
- `cancel` POST → still POST

Find resume callers and change method:
```bash
grep -rn "admin_modules_email_campaigns_campaign_pause_path" app spec
```

For contexts that were `resume`, change `method: :post` → `method: :delete`.

- [ ] **Step 6.8.4: Run campaign specs**

Run: `bundle exec rspec spec/requests/email_campaigns* spec/system/email_campaigns* 2>&1 | tail -10`
Expected: Pass.

- [ ] **Step 6.8.5: Commit**

```bash
git add -A
git commit -m "refactor(routes): C8 — campaign verb actions to sub-resources

- send_now -> resource :delivery
- pause/resume -> resource :pause (create/destroy)
- cancel -> resource :cancellation"
```

### Task 6.9: C9 — MFA verb actions to sub-resources

- [ ] **Step 6.9.1: Split MfaController into three controllers**

Create `app/controllers/authentication/mfa_setups_controller.rb`:
```ruby
# frozen_string_literal: true

module Authentication
  class MfaSetupsController < ApplicationController
    set_tenant_from_route_params
    before_action :authenticate_user!

    def show
      # Move body from MfaController#setup
    end

    def create
      # Move body from MfaController#confirm_setup
    end
  end
end
```

Create `app/controllers/authentication/mfa_sessions_controller.rb`:
```ruby
# frozen_string_literal: true

module Authentication
  class MfaSessionsController < ApplicationController
    set_tenant_from_route_params
    # Note: NOT authenticate_user! — verify happens before full auth
    before_action :authenticate_pre_mfa_user!  # adjust to match existing logic

    def show
      # Move body from MfaController#verify
    end

    def create
      # Move body from MfaController#authenticate
    end
  end
end
```

Read `app/controllers/authentication/mfa_controller.rb`. Determine the existing before_action filters used by `verify` vs `setup`/`disable`. Mirror them in the new controllers (verify often runs without full authentication; the others require it).

Edit `app/controllers/authentication/mfa_controller.rb` to keep only `disable`:
```ruby
# frozen_string_literal: true

module Authentication
  class MfaController < ApplicationController
    set_tenant_from_route_params
    before_action :authenticate_user!

    def destroy
      # Was named `disable` — body unchanged
    end
  end
end
```

(Rename existing `disable` to `destroy`.)

- [ ] **Step 6.9.2: Edit routes**

Find lines 45–51:
```ruby
    scope "auth/mfa", as: :mfa, controller: "authentication/mfa" do
      get    "setup",         action: :setup,         as: :setup
      post   "confirm_setup", action: :confirm_setup,  as: :confirm_setup
      get    "verify",        action: :verify,         as: :verify
      post   "authenticate",  action: :authenticate,   as: :authenticate
      delete "disable",       action: :disable,         as: :disable
    end
```

Replace with:
```ruby
    scope "auth" do
      resource :mfa_setup, only: %i[show create], controller: "authentication/mfa_setups",
        path: "mfa/setup"
      resource :mfa_session, only: %i[show create], controller: "authentication/mfa_sessions",
        path: "mfa/session"
      resource :mfa, only: :destroy, controller: "authentication/mfa", path: "mfa"
    end
```

The paths produced:
- `GET  /:cid/auth/mfa/setup`     → `MfaSetupsController#show`
- `POST /:cid/auth/mfa/setup`     → `MfaSetupsController#create`
- `GET  /:cid/auth/mfa/session`   → `MfaSessionsController#show`
- `POST /:cid/auth/mfa/session`   → `MfaSessionsController#create`
- `DELETE /:cid/auth/mfa`         → `MfaController#destroy`

(Note: original used `/auth/mfa/verify` and `/auth/mfa/authenticate`. New paths consolidate to `/auth/mfa/session` (GET = show form, POST = create session). Acceptable per spec.)

- [ ] **Step 6.9.3: Update helpers**

```bash
grep -rln "mfa_setup_path\|mfa_setup_url" app spec | xargs -r sed -i 's/mfa_setup_path/mfa_setup_path/g'  # no change

grep -rln "mfa_confirm_setup_path" app spec | xargs -r sed -i \
  's/mfa_confirm_setup_path/mfa_setup_path/g'

grep -rln "mfa_verify_path" app spec | xargs -r sed -i \
  's/mfa_verify_path/mfa_session_path/g'

grep -rln "mfa_authenticate_path" app spec | xargs -r sed -i \
  's/mfa_authenticate_path/mfa_session_path/g'

grep -rln "mfa_disable_path" app spec | xargs -r sed -i \
  's/mfa_disable_path/mfa_path/g'
```

Update HTTP methods in views/specs that used the old verb-named helpers (POST for confirm_setup/authenticate, DELETE for disable). The new paths use the same HTTP methods naturally for create/destroy.

- [ ] **Step 6.9.4: Move views**

```bash
mkdir -p app/views/authentication/mfa_setups
mkdir -p app/views/authentication/mfa_sessions
mkdir -p app/views/authentication/mfa
git mv app/views/authentication/mfa/setup.html.erb app/views/authentication/mfa_setups/show.html.erb 2>/dev/null
git mv app/views/authentication/mfa/verify.html.erb app/views/authentication/mfa_sessions/show.html.erb 2>/dev/null
```

(Keep `mfa/disable.html.erb` if it exists, rename to `mfa/destroy.html.erb` if needed; or delete if `destroy` only redirects.)

- [ ] **Step 6.9.5: Run MFA specs**

Run: `bundle exec rspec spec/requests/authentication/ spec/system/mfa_spec.rb 2>&1 | tail -10`
Expected: Pass. Also manually test MFA setup flow in browser.

- [ ] **Step 6.9.6: Commit**

```bash
git add -A
git commit -m "refactor(routes): C9 — MFA verb actions to sub-resources

- setup/confirm_setup -> resource :mfa_setup
- verify/authenticate -> resource :mfa_session
- disable -> resource :mfa#destroy"
```

### Task 6.10: C10 — Customer contexts

- [ ] **Step 6.10.1: Edit routes**

Find (post-Phase 2):
```ruby
            resources :customer_contexts, only: [], controller: "admin/maintenance/platform/customer_contexts" do
              collection do
                get :search
                post :switch
                delete :clear
              end
            end
```

Replace with:
```ruby
            resource :customer_context, only: %i[update destroy], controller: "admin/maintenance/platform/customer_contexts"
            resources :customer_context_searches, only: :index, controller: "admin/maintenance/platform/customer_context_searches"
```

- [ ] **Step 6.10.2: Rename actions in CustomerContextsController**

Edit `app/controllers/admin/maintenance/platform/customer_contexts_controller.rb`:

Rename:
- `def switch` → `def update`
- `def clear` → `def destroy`
- Move `def search` body to a new `Admin::Maintenance::Platform::CustomerContextSearchesController#index`.

Create `app/controllers/admin/maintenance/platform/customer_context_searches_controller.rb`:
```ruby
# frozen_string_literal: true

module Admin
  module Maintenance
    module Platform
      class CustomerContextSearchesController < ApplicationController
        set_tenant_from_route_params
        before_action :authenticate_user!

        def index
          # Move body from CustomerContextsController#search
        end
      end
    end
  end
end
```

- [ ] **Step 6.10.3: Update helpers**

```bash
grep -rln "search_admin_maintenance_platform_customer_contexts_path" app spec | xargs -r sed -i \
  's/search_admin_maintenance_platform_customer_contexts_path/admin_maintenance_platform_customer_context_searches_path/g'

grep -rln "switch_admin_maintenance_platform_customer_contexts_path" app spec | xargs -r sed -i \
  's/switch_admin_maintenance_platform_customer_contexts_path/admin_maintenance_platform_customer_context_path/g'

grep -rln "clear_admin_maintenance_platform_customer_contexts_path" app spec | xargs -r sed -i \
  's/clear_admin_maintenance_platform_customer_contexts_path/admin_maintenance_platform_customer_context_path/g'
```

Update HTTP methods in callers:
- `switch` was POST → now PATCH (update)
- `clear` was DELETE → still DELETE

Find switch callers and change `method: :post` → `method: :patch`:
```bash
grep -rn "admin_maintenance_platform_customer_context_path" app spec
```

(Manual check per match.)

- [ ] **Step 6.10.4: Run specs**

Run: `bundle exec rspec spec/requests/maintenance/platform/customer_contexts_spec.rb 2>&1 | tail -10`
Expected: Pass. (If the spec file path differs, adjust.)

- [ ] **Step 6.10.5: Commit**

```bash
git add -A
git commit -m "refactor(routes): C10 — customer context to singleton + searches resource"
```

### Task 6.11: C11 — SMS send absolute path

This was already partly addressed in Phase 3 Step 3.2.4. Verify and clean up.

- [ ] **Step 6.11.1: Verify SMS send route is properly nested**

Run: `bin/rails routes 2>&1 | grep "modules/sms"`
Expected: Includes `POST /:customer_id/admin/modules/sms/sends → admin/modules/sms/sends#create`.

If the post route still uses `to: "/sms/sends#create"` (absolute), edit `config/routes.rb`:

Find:
```ruby
        namespace :sms do
          resources :messages, only: %i[index show]
          post "send", to: "sms/sends#create", as: :send
        end
```

Replace with:
```ruby
        namespace :sms do
          resources :messages, only: %i[index show]
          resources :sends, only: :create
        end
```

- [ ] **Step 6.11.2: Update controller class name**

Verify `app/controllers/admin/modules/sms/sends_controller.rb` exists (moved in Phase 3) with class `Admin::Modules::Sms::SendsController`.

- [ ] **Step 6.11.3: Update helpers**

```bash
# Old: admin_modules_sms_send_path (singular helper from `as: :send`)
# New: admin_modules_sms_sends_path (plural from `resources :sends`)
grep -rln "admin_modules_sms_send_path" app spec | xargs -r sed -i \
  's/admin_modules_sms_send_path/admin_modules_sms_sends_path/g'
```

- [ ] **Step 6.11.4: Run SMS specs**

Run: `bundle exec rspec spec/requests/sms/`
Expected: Pass.

- [ ] **Step 6.11.5: Commit**

```bash
git add -A
git commit -m "refactor(routes): C11 — SMS send under proper namespace as resources :sends"
```

---

## Final verification

### Task 7.1: Full suite + smoke tests

- [ ] **Step 7.1.1: Run full RSpec**

Run: `bundle exec rspec 2>&1 | tail -20`
Expected: Same pass/fail count as baseline (zero regressions).

- [ ] **Step 7.1.2: Verify success criteria from spec**

Run each:
```bash
grep -rE "browse_" --include="*.rb" --include="*.erb" --include="*.js" app spec
# Expected: zero matches

grep -E "scope.*module:" config/routes.rb
# Expected: zero matches (or only the documented exception in Phase 3.2.3)

grep -E "MaintenancesController|LandingController" app spec
# Expected: zero matches

bin/rails routes 2>&1 | grep -E "payments/payments|module_settings_module_settings"
# Expected: zero matches
```

- [ ] **Step 7.1.3: Manual browser smoke test**

Restart server: `rm -f public/assets/.manifest.json && bin/rails server -b 0.0.0.0 -p 3000`

Test in browser (every flow that was modified):
1. Login (POST `/sign_in` resolves customer; redirect to `/<cid>/auth/sign_in` if needed)
2. Dashboard `/<cid>/admin`
3. Maintenance `/<cid>/admin/maintenance`
4. Settings `/<cid>/admin/settings`
5. Module settings `/<cid>/admin/settings/modules/<key>`
6. Create flowchart, activate it, deactivate it
7. View flowchart versions, restore one
8. Create/publish/unpublish a page
9. Switch customer context (platform owner)
10. Send/pause/resume/cancel a campaign
11. MFA setup flow
12. Public form rendering at `/<cid>/forms/<token>`
13. Code generator UI (property editor IO params loading)

Document any failures inline.

- [ ] **Step 7.1.4: Final commit + PR**

If all tests pass and smoke tests pass, no further commits needed (each phase committed independently).

```bash
git log --oneline -20
```

Verify the commit log shows the six phase commits + sub-task commits.

---

## Self-Review Notes

After writing this plan, the following items deserve attention during execution:

1. **The Phase 2 view-directory move has a name conflict** (`app/views/maintenance` vs `app/views/maintenances`). Step 2.2.1 documents the resolution, but the executor must follow the alternative two-step sequence carefully.

2. **Inflection edge cases** (`module_data` → `module_datum`) may need an `inflections.rb` override (Step 6.6.3). Check `bin/rails routes` output before assuming pluralization.

3. **MFA before_actions** (Step 6.9.1) need attention — the `verify` action runs in a partially authenticated state. Mirror the existing controller's filter chain when splitting.

4. **The `as: :module_settings_sms`** approach in Phase 1 (Task 1.2) works but makes the inner namespace's helpers idiosyncratic. Phase 3 Step 3.2.3 then reorganizes these. Resist the urge to "fix" the Phase 1 names early — they're transitional.

5. **Several `# Move body from X` placeholders** in Phase 6 controllers require reading the source file, copying, and pasting. The executor must verify no method dependencies are missed (private helpers, before_actions). When private helpers are shared, extract to a concern like `Admin::Maintenance::FlowchartActions`.

6. **Spec file renames are not in this plan** — when a controller splits, existing specs may need to follow. The plan relies on `bundle exec rspec` per phase to surface broken specs; the executor should rename spec files to match new controllers as those failures appear.
