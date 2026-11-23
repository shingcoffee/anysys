# Admin URL Prefix Design

**Date:** 2026-05-10  
**Status:** Draft

## Summary

Prefix all authenticated admin pages with `/admin/` so URLs become `/:customer_id/admin/*`. Public/integration endpoints and authentication routes remain at their current paths.

## Motivation

Separate admin-facing URLs from public/integration URLs for clearer organization and routing semantics. All pages accessible from the main menu tabs (Home, Entities, Pages, Modules, Settings, Maintenance) are admin pages and should live under a common `/admin/` prefix.

## URL Structure

### Moving to `/admin/`

| Before | After |
|--------|-------|
| `/:cid/` | `/:cid/admin/` |
| `/:cid/entities` | `/:cid/admin/entities` |
| `/:cid/entities/:id` | `/:cid/admin/entities/:id` |
| `/:cid/pages` | `/:cid/admin/pages` |
| `/:cid/modules/*` | `/:cid/admin/modules/*` |
| `/:cid/settings/*` | `/:cid/admin/settings/*` |
| `/:cid/maintenance/*` | `/:cid/admin/maintenance/*` |
| `/:cid/search` | `/:cid/admin/search` |

### Staying at Current Level (NOT moving)

| Path | Reason |
|------|--------|
| `/:cid/auth/*` | Devise authentication (gateway to admin) |
| `/:cid/f/:token` | Public page rendering |
| `/:cid/payments/checkout` | Public checkout flow |
| `/:cid/payments/result/*` | Payment result pages |
| `/payments/webhooks/*` | PSP webhooks (tenant-less) |
| `/unsubscribe/:token` | Email campaign unsubscribe |
| `*path` catch-all | Dynamic flowchart API |

## Implementation Approach

### Routes Strategy

Wrap all admin routes in `scope "admin"` with `as: nil` to preserve existing route helper names:

```ruby
scope "/:customer_id", constraints: { customer_id: /\d{8}/ } do
  # Auth routes stay at current level
  devise_for :users, path: "auth", ...
  
  scope "auth/mfa", as: :mfa, controller: "authentication/mfa" do
    # MFA routes...
  end

  # Public surfaces stay here
  get  'f/:token', to: 'public_pages#show'
  post 'f/:token', to: 'public_pages#submit'
  
  scope "payments", as: :payments do
    # Public checkout, result, status...
  end

  # === All admin routes ===
  scope "admin", as: nil do
    get "/", to: "landing#show", as: :dashboard_root
    
    # Browse views
    get "entities", ...
    get "pages", ...
    get "modules", ...
    get "settings", ...
    get "search", ...
    
    # Maintenance
    scope :maintenance, as: :maintenance do
      # All maintenance routes...
    end
  end
end
```

Using `as: nil` means route helpers like `browse_entities_path`, `maintenance_flowcharts_path` remain unchanged. Only hardcoded string paths need updating.

### Path Update Pattern

All hardcoded paths follow the same transformation:

**Ruby:**
```ruby
# Before
"/#{customer_id}/entities"
"/#{customer.id}/modules/payment/transactions"

# After
"/#{customer_id}/admin/entities"
"/#{customer.id}/admin/modules/payment/transactions"
```

**JavaScript:**
```javascript
// Before
`/${this.customerIdValue}/maintenance/pages/${id}`
`/${customerId}/maintenance/platform/code_generators/...`

// After
`/${this.customerIdValue}/admin/maintenance/pages/${id}`
`/${customerId}/admin/maintenance/platform/code_generators/...`
```

## Files to Update

### A. Routes & Menu System (2 files)

| File | Changes |
|------|---------|
| `config/routes.rb` | Wrap admin routes in `scope "admin", as: nil` |
| `app/services/menu_registry.rb` | Update 6 `path_proc` lambdas |

### B. Sidebar Contributors (5 files)

| File | Paths |
|------|-------|
| `app/services/entities_contributor.rb` | 1 |
| `app/services/pages_contributor.rb` | 2 |
| `app/services/settings_contributor.rb` | 1 |
| `app/services/maintenance_contributor.rb` | 13 |
| `app/services/module_contribution.rb` | 2 |

### C. Feature Module System (6 files)

| File | Notes |
|------|-------|
| `app/services/feature_modules/exit_resolver.rb` | 4 paths (some stay, some move) |
| `app/services/feature_modules/authentication/registration.rb` | 1 stays (auth/login), 1 moves |
| `app/services/feature_modules/email/registration.rb` | 3 paths move |
| `app/services/feature_modules/email_campaigns/registration.rb` | 4 paths move |
| `app/services/feature_modules/payment/registration.rb` | 1 stays (payments/checkout), 4 move |
| `app/services/feature_modules/sms/registration.rb` | 2 paths move |

### D. Search Sources (3 files)

| File | Paths |
|------|-------|
| `app/services/search/entities_source.rb` | 1 |
| `app/services/search/modules_source.rb` | 1 |
| `app/services/search/pages_source.rb` | 1 |

### E. Controllers (13 files)

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

### F. Components (2 files)

| File | Changes |
|------|---------|
| `app/components/page_builder/flow_item_component.rb` | 1 path |
| `app/components/topbar_component.html.erb` | Logo link |

### G. Views (17+ files)

- `app/views/settings/module_config.html.erb`
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
- Plus various index/show views with breadcrumb paths

### H. JavaScript (17 files)

- `app/javascript/controllers/flowchart_canvas_controller.js`
- `app/javascript/controllers/page_canvas_controller.js`
- `app/javascript/controllers/template_applier_controller.js`
- `app/javascript/controllers/template_selector_controller.js`
- `app/javascript/controllers/entity_form_controller.js`
- `app/javascript/controllers/entity_selector_controller.js`
- `app/javascript/controllers/inline_search_controller.js`
- `app/javascript/controllers/page_builder/tab_manager.js`
- `app/javascript/controllers/page_builder/field_manager.js`
- `app/javascript/controllers/page_builder/save_manager.js`
- `app/javascript/controllers/page_builder/command_palette_manager.js`
- `app/javascript/controllers/entity_form/association_manager.js`
- `app/javascript/controllers/property_editor/branch_manager.js`
- `app/javascript/controllers/property_editor/step_io/io_params_client.js`
- `app/javascript/controllers/property_editor/element_io/io_params_client.js`
- `app/javascript/flowchart/context_variable_provider.js`
- `app/javascript/flowchart/input_output_validation_service.js`

### I. Test Files (~53 files)

Request specs, routing specs, component specs, system specs, and service specs that contain hardcoded paths.

## Testing Strategy

1. **Route verification:** Run `rails routes` and verify all admin routes have `/admin/` prefix
2. **Grep verification:** Confirm no remaining `"/#{customer` patterns without `/admin/` (excluding auth/public paths)
3. **Unit tests:** Run full spec suite — route helper names unchanged, so most tests should pass after path updates
4. **Manual verification:** Test navigation through all menu tabs in browser

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Missed hardcoded path | Comprehensive grep patterns; test suite coverage |
| Broken bookmarks/links | One-time change; no redirect needed (internal app) |
| JavaScript fetch failures | Systematic update of all JS files with admin paths |

## Out of Scope

- Redirect from old URLs to new URLs (not needed for internal admin app)
- Changes to authentication flow
- Changes to public/integration endpoints
