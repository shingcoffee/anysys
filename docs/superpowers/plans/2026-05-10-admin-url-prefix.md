# Admin URL Prefix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prefix all admin pages with `/admin/` so URLs become `/:customer_id/admin/*` while keeping auth and public endpoints at their current paths.

**Architecture:** Wrap admin routes in `scope "admin", as: nil` to preserve route helper names. Update all hardcoded string paths in Ruby, ERB, and JavaScript files. Tests update last since route helpers remain unchanged.

**Tech Stack:** Rails routes, Ruby services, ERB views, Stimulus JS controllers

---

## File Structure

**Routes & Menu (2 files):**
- `config/routes.rb` — restructure with admin scope
- `app/services/menu_registry.rb` — update path_proc lambdas

**Services (14 files):**
- `app/services/entities_contributor.rb`
- `app/services/pages_contributor.rb`
- `app/services/settings_contributor.rb`
- `app/services/maintenance_contributor.rb`
- `app/services/module_contribution.rb`
- `app/services/search/entities_source.rb`
- `app/services/search/modules_source.rb`
- `app/services/search/pages_source.rb`
- `app/services/feature_modules/exit_resolver.rb`
- `app/services/feature_modules/authentication/registration.rb`
- `app/services/feature_modules/email/registration.rb`
- `app/services/feature_modules/email_campaigns/registration.rb`
- `app/services/feature_modules/payment/registration.rb`
- `app/services/feature_modules/sms/registration.rb`

**Controllers (13 files):**
- `app/controllers/entities_controller.rb`
- `app/controllers/pages_controller.rb`
- `app/controllers/platform/customer_contexts_controller.rb`
- `app/controllers/platform/code_generators_controller.rb`
- `app/controllers/email/admin/templates_controller.rb`
- `app/controllers/email_campaigns/admin/campaigns_controller.rb`
- `app/controllers/email_campaigns/admin/lists_controller.rb`
- `app/controllers/email_campaigns/admin/subscribers_controller.rb`
- `app/controllers/payments/admin/merchant_accounts_controller.rb`
- `app/controllers/payments/admin/subscriptions_controller.rb`
- `app/controllers/payments/admin/transactions_controller.rb`
- `app/controllers/platform/sms/credentials_controller.rb`
- `app/controllers/platform/sms/templates_controller.rb`

**Components & Views (19+ files):**
- `app/components/topbar_component.html.erb`
- `app/components/page_builder/flow_item_component.rb`
- Multiple view files with hardcoded paths

**JavaScript (17 files):**
- Various Stimulus controllers and modules with fetch URLs

**Tests (~53 files):**
- Request, routing, component, system, and service specs

---

### Task 1: Update Routes File

**Files:**
- Modify: `config/routes.rb`

- [ ] **Step 1: Wrap admin routes in scope**

Edit `config/routes.rb`. The tenant-scoped section (lines 43-317) needs restructuring. Keep MFA, public pages, and payments outside the admin scope. Wrap everything else in `scope "admin", as: nil`.

Replace the entire `scope "/:customer_id"` block (lines 43-317) with:

```ruby
  scope "/:customer_id", constraints: { customer_id: /\d{8}/ } do
    # MFA / 2FA Routes (stay at /:customer_id/auth/mfa/*)
    scope "auth/mfa", as: :mfa, controller: "authentication/mfa" do
      get    "setup",         action: :setup,         as: :setup
      post   "confirm_setup", action: :confirm_setup,  as: :confirm_setup
      get    "verify",        action: :verify,         as: :verify
      post   "authenticate",  action: :authenticate,   as: :authenticate
      delete "disable",       action: :disable,         as: :disable
    end

    # Public page rendering — no authentication required
    get  'f/:token', to: 'public_pages#show',   as: :public_page
    post 'f/:token', to: 'public_pages#submit',  as: :public_page_submit

    # Payment public flow (customer checkout + result page)
    scope "payments", as: :payments do
      get  "checkout",              to: "payments/checkouts#show"
      post "checkout",              to: "payments/checkouts#create",  as: :checkout_create
      get  "payments/:id/status",   to: "payments/checkouts#status",  as: :payment_status
      get  "result/:payment_id",    to: "payments/results#show",      as: :result
    end

    # ========================================================================
    # Admin Routes - All authenticated admin pages under /admin/
    # ========================================================================
    scope "admin", as: nil do
      get "/", to: "landing#show", as: :dashboard_root

      # Browse views (read-only dashboard listings)
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

      # Per-module customer settings (b). Must come BEFORE the generic
      # `settings/modules/:module_key` route below, otherwise that route
      # swallows `payment/merchant_accounts` etc. as the module_key.
      scope "settings/modules", as: :settings_modules do
        # Payment: customer-managed merchant accounts
        scope "payment", as: :payment, module: "payments/admin" do
          resources :merchant_accounts, only: %i[index new create edit update]
        end
      end

      get   "settings/modules/:module_key",            to: "settings#module_config",        as: :settings_module
      patch "settings/modules/:module_key",            to: "settings#update_module_config", as: :settings_module_update
      get   "settings/modules/:module_key/:entry_key", to: "settings#module_config",        as: :settings_module_entry

      # Search
      get "search", to: "search#index", as: :search

      # Maintenance (owner only)
      scope :maintenance, as: :maintenance do
        get "/", to: "maintenances#show", as: :root
        resource :customer_profile, only: [:show, :edit, :update], controller: "maintenance/customer_profile"

        # Constants management
        resources :constants, controller: "maintenance/constants" do
          member do
            get :copy
          end
        end

        # Module management
        resources :modules, only: [:index], controller: "maintenance/modules" do
          member do
            post :enable
            post :disable
          end
        end
        # Entity management (full CRUD)
        resources :entities, controller: "maintenance/entities" do
          member do
            patch :restore
            get :entries
            get :copy
            get :template_preview
          end
          collection do
            get :trash
            delete :empty_trash
            get :template_fields
          end
          resources :entity_entries, only: [:destroy], path: 'entries'
        end

        # Flowcharts CRUD
        resources :flowcharts, controller: "maintenance/flowcharts" do
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
            get "validation/implicit_keys", to: "maintenance/flowchart_validation#implicit_keys", as: :validation_implicit_keys
          end
        end

        # Pages management (full CRUD)
        resources :pages, controller: "maintenance/pages" do
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
            resources :field_templates, only: [:index, :create, :update, :destroy], controller: "maintenance/field_templates"
          end
        end

        # Platform tools (platform owner only)
        scope "platform", as: :platform do
          # Customer management
          resources :customers, controller: "platform/customers" do
            member do
              patch :restore
            end
            collection do
              get :trash
              delete :empty_trash
            end
          end

          # Module settings
          resources :module_settings, controller: "platform/module_settings", only: [:index, :show, :update]

          # Per-module platform settings
          scope "module_settings", as: :module_settings do
            scope "sms", as: :sms, module: "platform/sms" do
              resources :credentials, only: %i[index new create edit update]
              resources :templates,   only: %i[index new create edit update destroy]
            end
          end

          # Industry templates
          resources :industry_templates, controller: "platform/industry_templates", only: %i[index show edit update] do
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

          # Code generators
          resources :code_generators, controller: "platform/code_generators", param: :path do
            collection do
              post :preview_source
            end
            member do
              post :validate
              get :preview
              post :test_run
            end
          end

          # Code generator IO params APIs (used by flowchart canvas)
          post "code_generators/:action_name/io_params",
            to: "code_generators/io_params#show",
            as: :code_generator_io_params,
            constraints: { action_name: /[A-Za-z0-9_]+/ }
          post "code_generators/element_types/:element_type/io_params",
            to: "code_generators/element_type_io_params#show",
            as: :code_generator_element_type_io_params,
            constraints: { element_type: /[A-Za-z0-9_]+/ }

          # Customer context switching
          resources :customer_contexts, only: [], controller: "platform/customer_contexts" do
            collection do
              get :search
              post :switch
              delete :clear
            end
          end
        end
      end

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
    end
  end
```

- [ ] **Step 2: Verify routes compile**

Run: `bin/rails routes | head -50`
Expected: Routes load without error, admin routes now show `/admin/` prefix

- [ ] **Step 3: Commit routes change**

```bash
git add config/routes.rb
git commit -m "refactor(routes): wrap admin routes in /admin/ scope

Moves all authenticated admin pages under /:customer_id/admin/*.
Auth routes, public pages, and payment checkout stay at current level.
Uses as: nil to preserve existing route helper names.

Co-Authored-By: Copilot Opus 4.5 <noreply@anthropic.com>"
```

---

### Task 2: Update Menu Registry

**Files:**
- Modify: `app/services/menu_registry.rb`

- [ ] **Step 1: Update path_proc lambdas**

Edit `app/services/menu_registry.rb`. Change all 6 `path_proc` lambdas to include `/admin/`:

```ruby
# frozen_string_literal: true

class MenuRegistry
  ITEMS = [
    MenuItem.new(key: :home,     label: "Home",
                 path_proc: ->(c) { "/#{c.id}/admin/" },
                 sidebar_contributor: nil),
    MenuItem.new(key: :entities, label: "Entities",
                 path_proc: ->(c) { "/#{c.id}/admin/entities" },
                 sidebar_contributor: EntitiesContributor),
    MenuItem.new(key: :pages,    label: "Pages",
                 path_proc: ->(c) { "/#{c.id}/admin/pages" },
                 sidebar_contributor: PagesContributor),
    MenuItem.new(key: :modules,  label: "Modules",
                 path_proc: ->(c) { "/#{c.id}/admin/modules" },
                 sidebar_contributor: ModulesContributor),
    MenuItem.new(key: :settings, label: "Settings",
                 path_proc: ->(c) { "/#{c.id}/admin/settings" },
                 sidebar_contributor: SettingsContributor),
    MenuItem.new(key: :maintenance, label: "Maintenance",
                 path_proc: ->(c) { "/#{c.id}/admin/maintenance" },
                 permitted_by: :owner?,
                 sidebar_contributor: MaintenanceContributor)
  ].freeze

  def self.for(user)
    return [] if user.nil?
    ITEMS.select { |i| i.permitted_for?(user) }
  end

  def self.item(key)
    ITEMS.find { |i| i.key == key }
  end
end
```

- [ ] **Step 2: Commit**

```bash
git add app/services/menu_registry.rb
git commit -m "refactor(menu): update MenuRegistry paths with /admin/ prefix

Co-Authored-By: Copilot Opus 4.5 <noreply@anthropic.com>"
```

---

### Task 3: Update Sidebar Contributors

**Files:**
- Modify: `app/services/entities_contributor.rb`
- Modify: `app/services/pages_contributor.rb`
- Modify: `app/services/settings_contributor.rb`
- Modify: `app/services/maintenance_contributor.rb`
- Modify: `app/services/module_contribution.rb`

- [ ] **Step 1: Update entities_contributor.rb**

In `app/services/entities_contributor.rb`, line 26, change:
```ruby
      path: "/#{customer_id}/entities/#{primary.id}",
```
to:
```ruby
      path: "/#{customer_id}/admin/entities/#{primary.id}",
```

- [ ] **Step 2: Update pages_contributor.rb**

In `app/services/pages_contributor.rb`, update two paths:

Line 21:
```ruby
      path: "/#{customer_id}/pages",
```
to:
```ruby
      path: "/#{customer_id}/admin/pages",
```

Line 35:
```ruby
        path: "/#{customer_id}/pages/entity/#{entity.id}",
```
to:
```ruby
        path: "/#{customer_id}/admin/pages/entity/#{entity.id}",
```

- [ ] **Step 3: Update settings_contributor.rb**

In `app/services/settings_contributor.rb`, line 34, change:
```ruby
        path: "/#{customer_id}/settings/modules/#{fm.key}",
```
to:
```ruby
        path: "/#{customer_id}/admin/settings/modules/#{fm.key}",
```

- [ ] **Step 4: Update maintenance_contributor.rb**

In `app/services/maintenance_contributor.rb`, update all 13 paths. Replace lines 26-43 with:

```ruby
    nodes = [
      leaf("Customer Profile", "/#{customer_id}/admin/maintenance/customer_profile", ICONS[:customer_profile]),
      leaf("Constants",        "/#{customer_id}/admin/maintenance/constants", ICONS[:constants]),
      leaf("Modules",          "/#{customer_id}/admin/maintenance/modules", ICONS[:modules]),
      leaf("Entities",         "/#{customer_id}/admin/maintenance/entities", ICONS[:entities]),
      leaf("Flowcharts",       "/#{customer_id}/admin/maintenance/flowcharts", ICONS[:flowcharts]),
      leaf("Pages",            "/#{customer_id}/admin/maintenance/pages", ICONS[:pages])
    ]

    # Platform items (only visible under platform owner customer 81721200)
    if customer_id.to_s == "81721200" && current_user&.platform_owner?
      nodes += [
        section_header("Platform"),
        leaf("Customers",           "/#{customer_id}/admin/maintenance/platform/customers", ICONS[:customers]),
        leaf("Module Settings",     "/#{customer_id}/admin/maintenance/platform/module_settings", ICONS[:module_settings]),
        leaf("Industry Templates",  "/#{customer_id}/admin/maintenance/platform/industry_templates", ICONS[:industry_templates]),
        leaf("Code Generators",     "/#{customer_id}/admin/maintenance/platform/code_generators", ICONS[:code_generators]),
        leaf("SMS Credentials",     "/#{customer_id}/admin/maintenance/platform/module_settings/sms/credentials", ICONS[:sms_credentials]),
        leaf("SMS Templates",       "/#{customer_id}/admin/maintenance/platform/module_settings/sms/templates", ICONS[:sms_templates])
      ]
    end
```

- [ ] **Step 5: Update module_contribution.rb**

In `app/services/module_contribution.rb`, update two paths. Find the `base_path` method or path generation and change:

```ruby
    when :modules  then "/#{customer_id}/modules/#{module_key}/entries/#{entry_key}"
    when :settings then "/#{customer_id}/settings/modules/#{module_key}/#{entry_key}"
```
to:
```ruby
    when :modules  then "/#{customer_id}/admin/modules/#{module_key}/entries/#{entry_key}"
    when :settings then "/#{customer_id}/admin/settings/modules/#{module_key}/#{entry_key}"
```

- [ ] **Step 6: Commit**

```bash
git add app/services/entities_contributor.rb app/services/pages_contributor.rb app/services/settings_contributor.rb app/services/maintenance_contributor.rb app/services/module_contribution.rb
git commit -m "refactor(sidebar): update contributor paths with /admin/ prefix

Co-Authored-By: Copilot Opus 4.5 <noreply@anthropic.com>"
```

---

### Task 4: Update Search Sources

**Files:**
- Modify: `app/services/search/entities_source.rb`
- Modify: `app/services/search/modules_source.rb`
- Modify: `app/services/search/pages_source.rb`

- [ ] **Step 1: Update entities_source.rb**

In `app/services/search/entities_source.rb`, change:
```ruby
            .map { |e| { label: e.name, path: "/#{customer.id}/entities/#{e.id}", type: :entity } }
```
to:
```ruby
            .map { |e| { label: e.name, path: "/#{customer.id}/admin/entities/#{e.id}", type: :entity } }
```

- [ ] **Step 2: Update modules_source.rb**

In `app/services/search/modules_source.rb`, change:
```ruby
            path:  "/#{customer.id}/settings/modules/#{fm.key}",
```
to:
```ruby
            path:  "/#{customer.id}/admin/settings/modules/#{fm.key}",
```

- [ ] **Step 3: Update pages_source.rb**

In `app/services/search/pages_source.rb`, change:
```ruby
          .map { |p| { label: p.name, path: "/#{customer.id}/pages", type: :page } }
```
to:
```ruby
          .map { |p| { label: p.name, path: "/#{customer.id}/admin/pages", type: :page } }
```

- [ ] **Step 4: Commit**

```bash
git add app/services/search/entities_source.rb app/services/search/modules_source.rb app/services/search/pages_source.rb
git commit -m "refactor(search): update search source paths with /admin/ prefix

Co-Authored-By: Copilot Opus 4.5 <noreply@anthropic.com>"
```

---

### Task 5: Update Feature Module Registrations

**Files:**
- Modify: `app/services/feature_modules/exit_resolver.rb`
- Modify: `app/services/feature_modules/authentication/registration.rb`
- Modify: `app/services/feature_modules/email/registration.rb`
- Modify: `app/services/feature_modules/email_campaigns/registration.rb`
- Modify: `app/services/feature_modules/payment/registration.rb`
- Modify: `app/services/feature_modules/sms/registration.rb`

- [ ] **Step 1: Update exit_resolver.rb**

In `app/services/feature_modules/exit_resolver.rb`:

Line 15 — change `"customer_home"` to include `/admin/`:
```ruby
      "customer_home" => ->(customer) { "/#{customer.id}/admin" }
```

Line 84 — this path stays (public page):
```ruby
        "/#{@customer.id}/f/#{page.public_token}"
```

Line 86 — change to include `/admin/`:
```ruby
        "/#{@customer.id}/admin/pages/#{page.id}"
```

Line 92 — this is dynamic flowchart, stays as is:
```ruby
      "/#{@customer.id}/#{flowchart.uuid}/#{target['entity_slug']}"
```

Line 111 — change to include `/admin/`:
```ruby
      "/#{@customer.id}/admin"
```

- [ ] **Step 2: Update authentication/registration.rb**

In `app/services/feature_modules/authentication/registration.rb`:

Line 25 — `entry_path` stays (auth path):
```ruby
      entry_path   { |customer| "/#{customer.id}/auth/login" }
```

Line 42 — change to include `/admin/`:
```ruby
              path: ->(customer_id) { "/#{customer_id}/admin/modules/authentication/users" },
```

- [ ] **Step 3: Update email/registration.rb**

In `app/services/feature_modules/email/registration.rb`:

Line 15:
```ruby
      entry_path { |customer| "/#{customer.id}/admin/modules/email/templates" }
```

Line 36:
```ruby
            ModuleContribution.new(label: "Templates", entry_key: "templates", path: ->(cid) { "/#{cid}/admin/modules/email/templates" }),
```

Line 37:
```ruby
            ModuleContribution.new(label: "Messages", entry_key: "messages", path: ->(cid) { "/#{cid}/admin/modules/email/messages" })
```

- [ ] **Step 4: Update email_campaigns/registration.rb**

In `app/services/feature_modules/email_campaigns/registration.rb`:

Line 13:
```ruby
      entry_path { |customer| "/#{customer.id}/admin/modules/email_campaigns/campaigns" }
```

Line 19:
```ruby
            ModuleContribution.new(label: "Subscribers", entry_key: "subscribers", path: ->(cid) { "/#{cid}/admin/modules/email_campaigns/subscribers" }),
```

Line 20:
```ruby
            ModuleContribution.new(label: "Lists", entry_key: "lists", path: ->(cid) { "/#{cid}/admin/modules/email_campaigns/lists" }),
```

Line 21:
```ruby
            ModuleContribution.new(label: "Campaigns", entry_key: "campaigns", path: ->(cid) { "/#{cid}/admin/modules/email_campaigns/campaigns" })
```

- [ ] **Step 5: Update payment/registration.rb**

In `app/services/feature_modules/payment/registration.rb`:

Line 13 — stays (public checkout):
```ruby
      entry_path   { |customer| "/#{customer.id}/payments/checkout" }
```

Line 38:
```ruby
              path: ->(cid) { "/#{cid}/admin/modules/payment/transactions" }
```

Line 43:
```ruby
              path: ->(cid) { "/#{cid}/admin/modules/payment/subscriptions" }
```

Line 48:
```ruby
              path: ->(cid) { "/#{cid}/admin/modules/payment/reconciliations" },
```

Line 57:
```ruby
              path: ->(cid) { "/#{cid}/admin/settings/modules/payment/merchant_accounts" },
```

- [ ] **Step 6: Update sms/registration.rb**

In `app/services/feature_modules/sms/registration.rb`:

Line 13:
```ruby
      entry_path { |customer| "/#{customer.id}/admin/modules/sms/messages" }
```

Line 34:
```ruby
              path: ->(cid) { "/#{cid}/admin/modules/sms/messages" }
```

- [ ] **Step 7: Commit**

```bash
git add app/services/feature_modules/exit_resolver.rb app/services/feature_modules/authentication/registration.rb app/services/feature_modules/email/registration.rb app/services/feature_modules/email_campaigns/registration.rb app/services/feature_modules/payment/registration.rb app/services/feature_modules/sms/registration.rb
git commit -m "refactor(modules): update feature module paths with /admin/ prefix

Keeps auth and public checkout paths at current level.

Co-Authored-By: Copilot Opus 4.5 <noreply@anthropic.com>"
```

---

### Task 6: Update Controllers

**Files:**
- Modify: `app/controllers/entities_controller.rb`
- Modify: `app/controllers/pages_controller.rb`
- Modify: `app/controllers/platform/customer_contexts_controller.rb`
- Modify: `app/controllers/platform/code_generators_controller.rb`
- Modify: `app/controllers/email/admin/templates_controller.rb`
- Modify: `app/controllers/email_campaigns/admin/campaigns_controller.rb`
- Modify: `app/controllers/email_campaigns/admin/lists_controller.rb`
- Modify: `app/controllers/email_campaigns/admin/subscribers_controller.rb`
- Modify: `app/controllers/payments/admin/merchant_accounts_controller.rb`
- Modify: `app/controllers/payments/admin/subscriptions_controller.rb`
- Modify: `app/controllers/payments/admin/transactions_controller.rb`
- Modify: `app/controllers/platform/sms/credentials_controller.rb`
- Modify: `app/controllers/platform/sms/templates_controller.rb`

- [ ] **Step 1: Update entities_controller.rb**

Find and replace all hardcoded redirect paths. Change:
```ruby
    return redirect_to "/#{current_customer.id}/entities/#{first.id}" if first
```
to:
```ruby
    return redirect_to "/#{current_customer.id}/admin/entities/#{first.id}" if first
```

And:
```ruby
    redirect_to "/#{current_customer.id}/entities/#{@entity.id}", notice: "#{ids.size} entries deleted."
```
to:
```ruby
    redirect_to "/#{current_customer.id}/admin/entities/#{@entity.id}", notice: "#{ids.size} entries deleted."
```

- [ ] **Step 2: Update pages_controller.rb**

Change:
```ruby
    redirect_to "/#{current_customer.id}/pages", notice: "#{ids.size} pages updated."
```
to:
```ruby
    redirect_to "/#{current_customer.id}/admin/pages", notice: "#{ids.size} pages updated."
```

- [ ] **Step 3: Update platform/customer_contexts_controller.rb**

Change:
```ruby
      redirect_to "/#{@customer.id}/", notice: "Now acting as #{@customer.name}"
```
to:
```ruby
      redirect_to "/#{@customer.id}/admin/", notice: "Now acting as #{@customer.name}"
```

And:
```ruby
      redirect_to "/#{current_user.customer_id}/", notice: "Returned to platform context"
```
to:
```ruby
      redirect_to "/#{current_user.customer_id}/admin/", notice: "Returned to platform context"
```

- [ ] **Step 4: Update platform/code_generators_controller.rb**

Change all paths like:
```ruby
          path: "/#{current_customer_id}/maintenance/platform/code_generators/#{relative.gsub('/', '%2F')}"
```
to:
```ruby
          path: "/#{current_customer_id}/admin/maintenance/platform/code_generators/#{relative.gsub('/', '%2F')}"
```

- [ ] **Step 5: Update email/admin/templates_controller.rb**

Change all redirects:
```ruby
          redirect_to "/#{current_customer.id}/modules/email/templates", notice: "Template created"
```
to:
```ruby
          redirect_to "/#{current_customer.id}/admin/modules/email/templates", notice: "Template created"
```

(Apply same pattern to all redirect_to calls in the file)

- [ ] **Step 6: Update email_campaigns/admin/campaigns_controller.rb**

Change all redirects from `/modules/email_campaigns/campaigns` to `/admin/modules/email_campaigns/campaigns`.

- [ ] **Step 7: Update email_campaigns/admin/lists_controller.rb**

Change all redirects from `/modules/email_campaigns/lists` to `/admin/modules/email_campaigns/lists`.

- [ ] **Step 8: Update email_campaigns/admin/subscribers_controller.rb**

Change all redirects from `/modules/email_campaigns/subscribers` to `/admin/modules/email_campaigns/subscribers`.

- [ ] **Step 9: Update payments/admin controllers**

For `merchant_accounts_controller.rb`, `subscriptions_controller.rb`, and `transactions_controller.rb`, add `/admin` after the customer ID in all redirect paths.

- [ ] **Step 10: Update platform/sms controllers**

For `credentials_controller.rb` and `templates_controller.rb`, add `/admin` after the customer ID in all redirect paths.

- [ ] **Step 11: Commit**

```bash
git add app/controllers/entities_controller.rb app/controllers/pages_controller.rb app/controllers/platform/customer_contexts_controller.rb app/controllers/platform/code_generators_controller.rb app/controllers/email/admin/templates_controller.rb app/controllers/email_campaigns/admin/campaigns_controller.rb app/controllers/email_campaigns/admin/lists_controller.rb app/controllers/email_campaigns/admin/subscribers_controller.rb app/controllers/payments/admin/merchant_accounts_controller.rb app/controllers/payments/admin/subscriptions_controller.rb app/controllers/payments/admin/transactions_controller.rb app/controllers/platform/sms/credentials_controller.rb app/controllers/platform/sms/templates_controller.rb
git commit -m "refactor(controllers): update redirect paths with /admin/ prefix

Co-Authored-By: Copilot Opus 4.5 <noreply@anthropic.com>"
```

---

### Task 7: Update Components

**Files:**
- Modify: `app/components/topbar_component.html.erb`
- Modify: `app/components/page_builder/flow_item_component.rb`

- [ ] **Step 1: Update topbar_component.html.erb**

In `app/components/topbar_component.html.erb`, line 14, change:
```erb
      <%= link_to "/#{customer.id}/", class: "inline-flex items-center gap-2.5 text-text-primary group" do %>
```
to:
```erb
      <%= link_to "/#{customer.id}/admin/", class: "inline-flex items-center gap-2.5 text-text-primary group" do %>
```

- [ ] **Step 2: Update page_builder/flow_item_component.rb**

In `app/components/page_builder/flow_item_component.rb`, change:
```ruby
        "/#{customer_id}/flowcharts/#{flowchart.id}"
```
to:
```ruby
        "/#{customer_id}/admin/maintenance/flowcharts/#{flowchart.id}"
```

- [ ] **Step 3: Commit**

```bash
git add app/components/topbar_component.html.erb app/components/page_builder/flow_item_component.rb
git commit -m "refactor(components): update component paths with /admin/ prefix

Co-Authored-By: Copilot Opus 4.5 <noreply@anthropic.com>"
```

---

### Task 8: Update Views

**Files:**
- Multiple view files with hardcoded `link_to` paths

- [ ] **Step 1: Find and update all view files with hardcoded paths**

Run this command to find all files:
```bash
grep -rln 'link_to.*/#{' --include="*.erb" app/views/
```

For each file found, add `/admin` after `#{current_customer_id}` or `#{customer.id}` in the path (excluding auth paths).

Key files to update:
- `app/views/settings/module_config.html.erb` — line with `/maintenance/modules`
- `app/views/pages/index.html.erb`
- `app/views/pages/by_entity.html.erb`
- `app/views/modules/index.html.erb`
- `app/views/entities/index.html.erb`
- `app/views/maintenances/show.html.erb`
- `app/views/maintenance/flowcharts/index.html.erb`
- `app/views/email/admin/templates/_form.html.erb`
- `app/views/email_campaigns/admin/subscribers/_form.html.erb`
- `app/views/email_campaigns/admin/subscribers/show.html.erb`
- `app/views/email_campaigns/admin/lists/_form.html.erb`
- `app/views/email_campaigns/admin/lists/show.html.erb`
- `app/views/email_campaigns/admin/campaigns/_form.html.erb`
- `app/views/email_campaigns/admin/campaigns/show.html.erb`
- `app/views/platform/customers/select.html.erb`
- `app/views/customers/select.html.erb`

Example change in `app/views/settings/module_config.html.erb`:
```erb
          <%= link_to "/#{current_customer_id}/maintenance/modules", class: "btn btn-primary" do %>
```
to:
```erb
          <%= link_to "/#{current_customer_id}/admin/maintenance/modules", class: "btn btn-primary" do %>
```

- [ ] **Step 2: Commit**

```bash
git add app/views/
git commit -m "refactor(views): update view paths with /admin/ prefix

Co-Authored-By: Copilot Opus 4.5 <noreply@anthropic.com>"
```

---

### Task 9: Update JavaScript Files

**Files:**
- All 17 JavaScript files listed in spec

- [ ] **Step 1: Update flowchart_canvas_controller.js**

Find all fetch URLs and add `/admin` after the customer ID:
```javascript
// Before
`/${this.customerIdValue}/flowcharts/${this.idValue}`
// After
`/${this.customerIdValue}/admin/maintenance/flowcharts/${this.idValue}`
```

Apply to all fetch calls in the file.

- [ ] **Step 2: Update page_canvas_controller.js**

Change:
```javascript
`/${this.customerIdValue}/maintenance/pages/${this.idValue}/autosave`
```
to:
```javascript
`/${this.customerIdValue}/admin/maintenance/pages/${this.idValue}/autosave`
```

- [ ] **Step 3: Update template_applier_controller.js**

Change:
```javascript
`/${this.customerIdValue}/maintenance/pages/${this.pageIdValue}/apply_template`
```
to:
```javascript
`/${this.customerIdValue}/admin/maintenance/pages/${this.pageIdValue}/apply_template`
```

- [ ] **Step 4: Update template_selector_controller.js**

Change:
```javascript
`/${this.customerIdValue}/maintenance/entities/${entityId}.json`
```
to:
```javascript
`/${this.customerIdValue}/admin/maintenance/entities/${entityId}.json`
```

- [ ] **Step 5: Update entity_form_controller.js**

Change all paths like:
```javascript
`/${this.customerIdValue}/maintenance/entities/base_model_fields?model=...`
`/${this.customerIdValue}/maintenance/entities/template_fields?key=...`
```
to include `/admin/`.

- [ ] **Step 6: Update entity_selector_controller.js**

Change:
```javascript
`/${this.customerIdValue}/flowcharts.json`
```
to:
```javascript
`/${this.customerIdValue}/admin/maintenance/flowcharts.json`
```

- [ ] **Step 7: Update inline_search_controller.js**

Verify paths returned from search are used correctly (paths come from backend, already updated in Task 4).

- [ ] **Step 8: Update page_builder/*.js files**

Update `tab_manager.js`, `field_manager.js`, `save_manager.js`, `command_palette_manager.js` — add `/admin` to all fetch URLs.

- [ ] **Step 9: Update entity_form/association_manager.js**

Change:
```javascript
`/${this.customerIdValue}/maintenance/entities.json`
```
to:
```javascript
`/${this.customerIdValue}/admin/maintenance/entities.json`
```

- [ ] **Step 10: Update property_editor/*.js files**

Update `branch_manager.js`, `step_io/io_params_client.js`, `element_io/io_params_client.js` — add `/admin` to all maintenance paths.

- [ ] **Step 11: Update flowchart/*.js files**

Update `context_variable_provider.js`, `input_output_validation_service.js` — add `/admin` to validation paths.

- [ ] **Step 12: Commit**

```bash
git add app/javascript/
git commit -m "refactor(js): update JavaScript fetch URLs with /admin/ prefix

Co-Authored-By: Copilot Opus 4.5 <noreply@anthropic.com>"
```

---

### Task 10: Update Test Files

**Files:**
- ~53 test files with hardcoded paths

- [ ] **Step 1: Run test suite to identify failures**

Run: `bundle exec rspec --fail-fast`
Expected: Some tests will fail due to path mismatches

- [ ] **Step 2: Update spec files systematically**

For each failing spec, add `/admin` after the customer ID in test paths.

Key patterns to search and replace:
```ruby
# Before
"/#{customer.id}/entities"
"/#{customer.id}/modules/"
"/#{customer.id}/settings/"
"/#{customer.id}/maintenance/"
"/#{customer.id}/pages"
"/#{customer.id}/search"
"/#{customer.id}/"  # (when it's the dashboard, not auth)

# After
"/#{customer.id}/admin/entities"
"/#{customer.id}/admin/modules/"
"/#{customer.id}/admin/settings/"
"/#{customer.id}/admin/maintenance/"
"/#{customer.id}/admin/pages"
"/#{customer.id}/admin/search"
"/#{customer.id}/admin/"
```

Do NOT change paths for:
- `/#{customer.id}/auth/`
- `/#{customer.id}/f/`
- `/#{customer.id}/payments/`

- [ ] **Step 3: Run full test suite**

Run: `bundle exec rspec`
Expected: All tests pass

- [ ] **Step 4: Commit**

```bash
git add spec/
git commit -m "test: update test paths with /admin/ prefix

Co-Authored-By: Copilot Opus 4.5 <noreply@anthropic.com>"
```

---

### Task 11: Final Verification

- [ ] **Step 1: Verify routes**

Run: `bin/rails routes | grep admin | head -30`
Expected: All admin routes show `/:customer_id/admin/` prefix

- [ ] **Step 2: Grep for missed paths**

Run: `grep -rn '"/#{customer' --include="*.rb" --include="*.erb" app/ | grep -v '/admin/' | grep -v '/auth/' | grep -v '/f/' | grep -v '/payments/'`
Expected: No results (all admin paths updated)

Run: `grep -rn 'customerIdValue}/' --include="*.js" app/javascript/ | grep -v '/admin/'`
Expected: No results (all JS paths updated)

- [ ] **Step 3: Run full test suite**

Run: `bundle exec rspec`
Expected: All tests pass

- [ ] **Step 4: Manual browser verification**

Start server: `rm -f public/assets/.manifest.json && bin/rails server -b 0.0.0.0 -p 3000`

Test navigation:
1. Sign in at `/:cid/auth/sign_in`
2. Verify redirect to `/:cid/admin/`
3. Click through all menu tabs (Home, Entities, Pages, Modules, Settings, Maintenance)
4. Verify URLs show `/admin/` prefix
5. Test public page access at `/:cid/f/:token` still works
6. Test payment checkout at `/:cid/payments/checkout` still works

- [ ] **Step 5: Final commit (if any fixes needed)**

```bash
git add -A
git commit -m "fix: address any remaining path issues from verification

Co-Authored-By: Copilot Opus 4.5 <noreply@anthropic.com>"
```
