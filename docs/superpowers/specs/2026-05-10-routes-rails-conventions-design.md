# Routes & Resources — Rails v8 Conventions Refactor

**Date:** 2026-05-10
**Status:** Approved (pending user review of this spec)
**Scope:** `config/routes.rb`, all controllers/views/JS/specs that reference renamed helpers, paths, controllers, or namespaces.

## Background

An audit of `config/routes.rb` (378 lines) surfaced ~30 deviations from Rails v8 conventions across naming, namespacing, REST modeling, helper prefixes, and parameter shadowing. The audit was performed against Rails v8.1.2 conventions and the project's AGENTS.md (which forbids backwards compatibility).

## Goals

1. Bring routes, controllers, and helpers into alignment with Rails v8 RESTful conventions.
2. Eliminate verb-style member/collection actions in favor of nested resources (where modeling improves).
3. Use `namespace` instead of `scope ... module:` where path == module.
4. Make singletons (settings, maintenance dashboard) use `resource` (singular) instead of `resources`.
5. Eliminate helper-name oddities (`browse_*` prefix, `payments_payment_status_path` stutter, double `as: :module_settings`).
6. Eliminate parameter shadowing (`param: :path`, `:action_name` segment).

## Non-Goals

- No view/UI redesign — this is plumbing only.
- No business-logic changes inside controllers — only class renames, file moves, and routing updates.
- No new features.
- No backwards compatibility — URLs change without redirects (per AGENTS.md).

## Strategy

A single PR with **six ordered commits**, each independently verifiable via `bundle exec rspec`.

| # | Phase | Risk |
|---|---|---|
| 1 | Routes-only quick wins | Trivial |
| 2 | `namespace :admin` + drop `browse_*` prefix | Mechanical sed |
| 3 | `scope module:` → `namespace`, fix singular/plural | Mechanical sed |
| 4 | Singleton controllers + Devise sign-in | Class renames |
| 5 | Param shadowing renames | Targeted |
| 6 | REST remodeling (verb actions → sub-resources) | Real modeling |

## Phase-by-Phase Specification

### Phase 1 — Routes-only quick wins

Edits to `config/routes.rb` only. No external callers affected (the helpers being changed are not in widespread use, verified during audit).

- **B3:** `scope "payments", as: :payments do ... get "payments/:id/status" ... get "result/:payment_id" end` produces `/:cid/payments/payments/:id/status` and `/:cid/payments/result/:payment_id`. The inner `payments/` is duplicated. Drop it: become `/:cid/payments/:id/status`.
- **B4:** `resources :module_settings ...` followed by `scope "module_settings", as: :module_settings do ... end` declares `as: :module_settings` twice. Drop the inner `as:` (rely on `resources`-generated helpers).
- **F3:** `as: :payments` on outer scope + `as: :payment_status` inside produces `payments_payment_status_path`. Restructure: drop outer `as:`, name inner routes directly: `payment_checkout_path`, `payment_status_path`, `payment_result_path`.
- **A5:** Delete empty directory `app/controllers/settings/`.

**Test:** `bundle exec rspec` green; check that no spec referenced the removed helpers.

### Phase 2 — `namespace :admin` and drop `browse_*` prefix

Currently: `scope "admin", as: nil do ... get "entities", to: "entities#index", as: :browse_entities ... end`. The `as: nil` strips the natural `admin_*` helper prefix; then ad-hoc `browse_*` reintroduces a prefix. Net effect: `browse_entities_path` instead of `admin_entities_path`.

**Change:** Convert to `namespace :admin do ... end`. Move all controllers under `scope "admin"` into `app/controllers/admin/` and re-namespace:

- `EntitiesController` → `Admin::EntitiesController`
- `PagesController` → `Admin::PagesController`
- `ModulesController` → `Admin::ModulesController`
- `ModuleEntriesController` → `Admin::ModuleEntriesController`
- `SettingsController` → `Admin::SettingsController` (will become singleton in Phase 4)
- `SearchController` → `Admin::SearchController`
- `LandingController` → `Admin::DashboardController` (singleton; `resource :dashboard, only: :show`; helper `admin_dashboard_path`; covers A2)

Helper renames (mechanical):

| Old helper | New helper |
|---|---|
| `browse_entities_path` | `admin_entities_path` |
| `browse_entity_path` | `admin_entity_path` |
| `browse_entity_entries_batch_destroy_path` | (becomes part of Phase 6 C1) |
| `browse_pages_path` | `admin_pages_path` |
| `browse_pages_by_entity_path` | (becomes part of Phase 6 C2) |
| `browse_pages_batch_update_path` | (becomes part of Phase 6 C3) |
| `browse_modules_path` | `admin_modules_path` |
| `browse_module_entry_path` | `admin_module_entry_path` |
| `dashboard_root_path` | `admin_dashboard_path` |
| `settings_path` | `admin_setting_path` (Phase 4) |
| `search_path` | `admin_search_path` |

**Test:** `bundle exec rspec`; grep for any remaining `browse_` or `dashboard_root` references.

### Phase 3 — `scope module:` → `namespace` + singular/plural fixes

Currently uses `scope "x", as: :x, module: "x/admin"` for six modules. This is verbose and fights the `namespace` convention.

**Decision on module structure:** The path `/admin/modules/<module>/...` and module class hierarchy `<Module>::Admin::*` will become path `/admin/modules/<module>/...` with class hierarchy `Admin::Modules::<Module>::*`. The AGENTS.md categorization is preserved (path stays the same), but controllers move to align with Rails namespace convention.

Rationale: under `namespace :admin`, the natural Rails layout is `Admin::*` controllers in `app/controllers/admin/`. Module controllers become `Admin::Modules::Email::TemplatesController` etc. This makes `scope module:` unnecessary.

**Singular/plural fixes (B1, B2):**
- Path `payment` → `payments` (matches `Payments::*` namespace, plural like other modules).
- All module paths plural: `payments`, `emails`, `email_campaigns`, `sms` (already), `authentication` (already singular but treat as proper noun), `payments`.
- Decision for `authentication`: keep singular path `authentication` (it's a domain noun, not pluralizable in this context — like `application`).
- Decision for `email`: rename path to `emails` to match plural convention.
- Decision for `sms`: keep `sms` (acronym, not a count noun).

**Controller moves:**

| Old class | New class | Old path |
|---|---|---|
| `Email::Admin::TemplatesController` | `Admin::Modules::Emails::TemplatesController` | `app/controllers/email/admin/` → `app/controllers/admin/modules/emails/` |
| `Email::Admin::MessagesController` | `Admin::Modules::Emails::MessagesController` | same |
| `EmailCampaigns::Admin::*` | `Admin::Modules::EmailCampaigns::*` | same pattern |
| `Sms::Admin::MessagesController` | `Admin::Modules::Sms::MessagesController` | same |
| `Payments::Admin::*` | `Admin::Modules::Payments::*` | same |
| `Authentication::Admin::UsersController` | `Admin::Modules::Authentication::UsersController` | same |

**Settings/Modules (`b` category) parallel restructure:**

`scope "settings/modules" do scope "payment", module: "payments/admin" ... end` becomes `namespace :settings do namespace :modules do namespace :payments do ... end end end`. Controller `Payments::Admin::MerchantAccountsController` (already exists for setting use) splits — settings-side becomes `Admin::Settings::Modules::Payments::MerchantAccountsController`.

**Maintenance/Platform parallel restructure:**

`scope "platform", as: :platform do scope "module_settings", as: :module_settings do scope "sms", as: :sms, module: "platform/sms" do ... end end end` becomes `namespace :platform do namespace :module_settings do namespace :sms do ... end end end`. Class `Platform::Sms::CredentialsController` → `Admin::Maintenance::Platform::ModuleSettings::Sms::CredentialsController`.

(This produces deep namespaces. That's the cost of Rails convention; the alternative would be to flatten paths, but AGENTS.md mandates the four-area categorization.)

**Test:** `bundle exec rspec`; check view partials for old constant references.

### Phase 4 — Singleton controllers + Devise sign-in

- **A1:** `MaintenancesController#show` is a singleton dashboard. Rename to `Admin::MaintenanceController` (singular), use `resource :maintenance, only: :show`. Path `/admin/maintenance` unchanged. File `app/controllers/maintenances_controller.rb` → `app/controllers/admin/maintenance_controller.rb`.
- **A3:** `SettingsController#show` is a singleton. Already moved to `Admin::SettingsController` in Phase 2; convert to singular `Admin::SettingController` with `resource :setting, only: :show`. Helper `admin_setting_path`.
  - The `module_config` and `update_module_config` actions are NOT singleton — they're keyed by `module_key`. Move to `Admin::ModuleConfigsController` with `resources :module_configs, only: [:show, :update], param: :key`. Mount under `namespace :settings`: `namespace :settings { resources :module_configs, only: [:show, :update], param: :key }`.
  - The `:entry_key` sub-route (`get "settings/modules/:module_key/:entry_key"`) is preserved as a nested resource: `resources :module_configs do resources :entries, only: :show, param: :key end` (only if grep confirms the route has callers; otherwise drop). Decision deferred to plan: grep first, then decide.
- **A4:** `post "/", to: "home#sign_in", as: :root_sign_in` duplicates Devise sessions. Remove this route; update any caller (login form action) to point at `user_session_path` (Devise default).
- **A2:** Already handled in Phase 2 (`LandingController` → `Admin::DashboardsController`).

**Test:** `bundle exec rspec`; manually verify login flow works.

### Phase 5 — Parameter shadowing renames

- **D1:** `resources :code_generators, ..., param: :path` shadows Rails' `path` helper. Rename to `param: :slug`. Affects `:id` references in `Platform::CodeGeneratorsController`, JS fetchers, and specs.
- **D2:** `post "code_generators/:action_name/io_params"` collides with Rails' internal `action_name`. Rename segment to `:generator_action`. Update controller params and JS.
- **D3:** `f/:token` is cryptic. Rename to `forms/:token`. Update any QR-code generation, email templates, or JS that builds public-page URLs.

**Test:** `bundle exec rspec`; grep for hardcoded `/f/` strings; manually test public page rendering.

### Phase 6 — REST remodeling

Each item below is one logical commit. Each replaces verb-style member/collection actions with nested resources.

#### C1 — Entities batch destroy
`delete "entities/:id/entries/batch" → entities#batch_destroy_entries` →
```ruby
resources :entities do
  resources :entries, only: [], controller: "entity_entries" do
    collection { delete :batch, action: :batch_destroy }
  end
end
```
Move `batch_destroy_entries` action from `EntitiesController` to `Admin::EntityEntriesController#batch_destroy`.

#### C2 — Pages by_entity
`get "pages/entity/:entity_id" → pages#by_entity` →
```ruby
resources :entities, only: [] do
  resources :pages, only: :index, controller: "entity_pages"
end
```
New `Admin::EntityPagesController#index` (or keep as `Admin::PagesController` action variant — decision: new controller for cleaner separation).

#### C3 — Pages batch update
`post "pages/batch" → pages#batch_update` →
```ruby
resources :pages do
  collection do
    patch :batch
  end
end
```
Method action stays `pages#batch` (verb prefix dropped). Verb is `PATCH` not `POST` (it's an update).

#### C4 — Module entries with `:key`
`get "modules/:module_key/entries/:entry_key" → module_entries#show` →
```ruby
resources :modules, only: [:index], param: :key do
  resources :entries, only: :show, param: :key, controller: "module_entries"
end
```

#### C5 — Flowchart sub-resources
Current member: `:autosave, :restore, :copy, :trace, :versions, :restore_version, :generate_docs, :activate, :deactivate`.

Restructure:
```ruby
resources :flowcharts do
  member do
    patch :autosave        # KEEP (incremental update idiom)
    patch :restore         # KEEP (soft-delete recovery idiom)
    get :copy              # KEEP (shows new form pre-filled — display action)
  end
  resources :versions, only: [:index, :create], controller: "flowchart_versions"
  resource :status, only: [:create, :destroy], controller: "flowchart_statuses"  # activate/deactivate
  resources :traces, only: :create, controller: "flowchart_traces"
  resource :document, only: :show, controller: "flowchart_documents"  # generate_docs
end
```

Action mapping:
- `versions` (GET) → `Admin::Maintenance::FlowchartVersionsController#index`
- `restore_version` (POST) → `Admin::Maintenance::FlowchartVersionsController#create`
- `activate` (POST) → `Admin::Maintenance::FlowchartStatusesController#create`
- `deactivate` (POST) → `Admin::Maintenance::FlowchartStatusesController#destroy`
- `trace` (POST) → `Admin::Maintenance::FlowchartTracesController#create`
- `generate_docs` (GET) → `Admin::Maintenance::FlowchartDocumentsController#show`

#### C6 — Pages sub-resources
Current member: `:autosave, :restore, :publish, :unpublish, :copy, :preview (GET), :preview (POST), :apply_template, field_options/:field_id, module_data/:module_id`.

Restructure:
```ruby
resources :pages do
  member do
    patch :autosave        # KEEP
    patch :restore         # KEEP
    get :copy              # KEEP
    post :apply_template   # KEEP (could be resource :template_application, but YAGNI — single action)
  end
  resource :publication, only: [:create, :destroy], controller: "page_publications"  # publish/unpublish
  resources :previews, only: [:show, :create], controller: "page_previews"  # GET preview, POST preview
  resources :field_options, only: :show, param: :field_id, controller: "page_field_options"
  resources :module_data, only: :show, param: :module_id, controller: "page_module_data"
end
```

#### C7 — Industry templates seeds
Current: `seed_defaults`, `seed_new_templates`, `reset_defaults`.

Restructure:
```ruby
resources :industry_templates, only: %i[index show edit update] do
  member do
    post :add_template
    delete :remove_template
    get :template_cards
  end
  collection do
    resource :default_seed, only: [:create, :destroy], controller: "industry_template_default_seeds"
    resource :new_template_seed, only: :create, controller: "industry_template_new_template_seeds"
  end
end
```
- `seed_defaults` (POST) → `IndustryTemplateDefaultSeedsController#create`
- `reset_defaults` (POST) → `IndustryTemplateDefaultSeedsController#destroy` (semantically: destroy the seeded state, then re-seed; since both endpoints exist, model destroy as reset)
- `seed_new_templates` (POST) → `IndustryTemplateNewTemplateSeedsController#create`

#### C8 — Email campaign delivery
Current member: `send_now, pause, resume, cancel`.

Restructure:
```ruby
resources :campaigns do
  resource :delivery, only: :create, controller: "campaign_deliveries"  # send_now
  resource :pause, only: [:create, :destroy], controller: "campaign_pauses"  # create=pause, destroy=resume
  resource :cancellation, only: :create, controller: "campaign_cancellations"
end
```

#### C9 — MFA verb actions
Current: `setup` (GET), `confirm_setup` (POST), `verify` (GET), `authenticate` (POST), `disable` (DELETE).

Restructure:
```ruby
scope "auth/mfa", as: :mfa do
  resource :mfa_setup, only: [:show, :create], controller: "authentication/mfa_setups"
    # show=setup form, create=confirm_setup
  resource :mfa_session, only: [:show, :create], controller: "authentication/mfa_sessions"
    # show=verify form, create=authenticate
  resource :mfa, only: :destroy, controller: "authentication/mfa"
    # destroy=disable
end
```
Splits `Authentication::MfaController` into three controllers.

#### C10 — Customer contexts
Current: `search`, `switch`, `clear` (all collection).

Restructure:
```ruby
namespace :platform do
  resource :customer_context, only: [:update, :destroy], controller: "customer_contexts"
    # update=switch, destroy=clear
  resources :customer_context_searches, only: :index
end
```

#### C11 — SMS send (absolute path escape)
Current: `post "send", to: "/sms/sends#create"` — escapes the surrounding `scope "sms", as: :sms, module: "sms/admin"`.

Restructure:
```ruby
namespace :sms do
  resources :messages, only: %i[index show]
  resources :sends, only: :create
end
```
Move `Sms::SendsController` to `Admin::Modules::Sms::SendsController`. Path becomes `/admin/modules/sms/sends`.

## Testing Strategy

- After each commit: `bundle exec rspec` must pass with zero failures.
- Where helpers are renamed across spec files, the rename is mechanical (find/replace).
- Where Phase 6 introduces new controllers, **existing test bodies move** to spec files matching the new controller (e.g., `spec/requests/maintenance/flowcharts/activate_spec.rb` → `spec/requests/maintenance/flowchart_statuses/create_spec.rb`). Test logic does not change — only paths and controller class references.
- After Phase 5 (param renames): manually verify code generator UI works end-to-end (it's the most JS-heavy area).
- After Phase 4 (Devise sign-in): manually verify login flow.
- After Phase 6 (REST remodeling): manually verify each remodeled feature in browser (flowchart activate/deactivate, page publish/unpublish, campaign send, MFA setup, customer context switch).

## File Inventory (high-level)

### Controllers moved/renamed
- ~25 controllers re-namespaced under `Admin::*`
- ~6 module controllers re-namespaced under `Admin::Modules::*`
- ~2 controllers renamed singular (`MaintenanceController`, `SettingController`)
- ~12 new controllers created for Phase 6 sub-resources

### Files affected by helper renames
- `config/routes.rb` (full rewrite)
- ~15 view templates referencing changed helpers (sidebar, breadcrumbs, links)
- ~5 JS Stimulus controllers with hardcoded paths
- ~30 spec files referencing renamed helpers/paths

### View directories that move
- Views follow controllers: `app/views/maintenance/` → `app/views/admin/maintenance/`, etc.

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| Spec suite has 480 files; helper renames could miss occurrences | After each commit, grep for old helper names; commit fails if any remain |
| Hardcoded URL strings in JS/views | Audit all `/admin/`, `/maintenance/`, `/settings/`, `/modules/` string literals; convert to URL helpers where possible |
| Sidebar contributors break (each module has a sidebar contributor) | Each phase that moves controllers also updates sidebar contributors |
| Devise sessions form submits to old `root_sign_in` path | Phase 4 audits the home/sign-in view template |
| Public page URLs (`/f/:token`) embedded in QR codes, emails, external links | Phase 5 D3 explicitly audits QR component, email templates, and any seed data; user-facing breaking change is acknowledged (AGENTS.md authorizes) |
| Code generator JS uses `:path` and `:action_name` params | Phase 5 D1/D2 audits all `code_generators` Stimulus controllers and fetch URLs |

## Success Criteria

1. All routes pass `bundle exec rspec`.
2. `grep -rE "browse_" --include="*.rb" --include="*.erb" --include="*.js"` returns zero results outside `node_modules`/`tmp`.
3. `grep -rE "scope.*module:" config/routes.rb` returns zero results.
4. No controller class is plural for a singleton concept (maintenance, setting).
5. No verb-style member action remains for state transitions (activate, publish, send_now, pause, etc.) — all modeled as sub-resources.
6. No path duplicates (`payments/payments/`).
7. All four module categorization areas (entries, customer settings, enable/disable, platform settings) preserved per AGENTS.md.
8. Manual smoke test: login, dashboard, create flowchart, activate flowchart, publish page, switch customer context, send campaign, MFA setup — all work.
