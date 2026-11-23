# Platform Owner Cross-Customer Access

## Overview

Enable platform owners (users with `role: :owner` under customer `81721200`) to access and manage any customer's resources through a context-switching mechanism. This supports administrative management with full CRUD capabilities, elevated privileges, and enhanced audit logging.

## Requirements

### Functional Requirements

1. **Context Switching** — Platform owners can switch to any customer's context via a customer selector UI
2. **Full CRUD** — Platform owners can create, read, update, and delete resources in the target customer's context
3. **Elevated Access** — Platform owners have privileges beyond regular customer owners (e.g., delete protected records, bypass validation rules)
4. **Visual Indication** — A prominent amber banner displays when acting in another customer's context
5. **Enhanced Audit** — Platform owner actions include additional metadata (original customer, target customer, platform context flag)
6. **Platform-Only Visibility** — Audit trail of platform interventions is visible only to platform admins, not affected customers

### Non-Functional Requirements

- Thread-safe context via `ActiveSupport::CurrentAttributes`
- Minimal changes to existing controllers (existing `.for_current_customer` calls work unchanged)
- Session-based persistence for context switching

### Out of Scope

- Customer-visible audit trail (platform interventions hidden from customers)
- Per-customer configurability of visibility
- Multi-tab isolation (session-based approach means all tabs share context)

## Architecture

### Current Attributes Extension

Extend `app/models/current.rb` with three new attributes:

| Attribute | Type | Purpose |
|-----------|------|---------|
| `platform_owner_context` | Boolean | `true` when platform owner is acting as another customer |
| `original_customer` | Customer | Platform owner's home customer (81721200) |
| `acting_as_customer` | Customer | Target customer being administered (same as `Current.customer`) |

When a platform owner switches context:
- `Current.customer` = target customer (for normal tenant scoping)
- `Current.platform_owner_context` = true
- `Current.original_customer` = customer 81721200
- `Current.acting_as_customer` = target customer

### TenantContext Enhancement

Modify `app/controllers/concerns/tenant_context.rb` to detect when a platform owner is accessing a customer other than their own:

```ruby
def platform_owner_acting_as_other_customer?(target_customer)
  return false unless current_user&.platform_owner?
  return false unless target_customer.present?
  target_customer.id != current_user.customer_id
end
```

When detected, set up the platform owner context and store in session for request persistence.

### Routes

```ruby
namespace :platform do
  resources :customer_contexts, only: [] do
    collection do
      get :search    # AJAX customer search
      post :switch   # Switch to target customer
      delete :clear  # Return to platform owner's own context
    end
  end
  
  resources :audit_logs, only: [:index, :show]  # Platform-only audit viewer
end
```

### Components

#### Platform::CustomerSwitcherComponent

- Renders only when `current_user.platform_owner?`
- Header dropdown with customer search (by name or ID)
- Shows current acting context when in platform owner mode
- Triggers `CustomerContextsController#switch` on selection

#### Platform::ContextBannerComponent

- Renders only when `Current.platform_owner_context?`
- Sticky amber banner at top of viewport
- Displays: "Platform Admin Mode — Acting as [Customer Name] (ID: 12345678)"
- "Return to Platform" link triggers `CustomerContextsController#clear`

### Authorization

Add to `ApplicationController`:

```ruby
def platform_elevated_access?
  Current.platform_owner_context? && current_user&.platform_owner?
end

def require_elevated_access!
  return if platform_elevated_access?
  # render forbidden response
end
```

**Elevated operations include:**
- Delete protected/system records
- Bypass certain validation rules
- Access soft-deleted records for recovery
- Modify locked/finalized entities

### Audit Logging

Enhance `Auditable` concern to append platform owner metadata when applicable:

```ruby
if Current.platform_owner_context?
  event.merge!(
    platform_owner_context: true,
    platform_owner_user_id: Current.user&.id,
    platform_owner_customer_id: Current.original_customer&.id,
    target_customer_id: Current.acting_as_customer&.id
  )
end
```

Platform audit viewer at `/platform/audit_logs`:
- Filterable by `platform_owner_context: true`
- Shows platform user, target customer, and action details
- Not exposed to customer owners

## Data Flow

```
Platform owner clicks "Switch Customer"
    ↓
CustomerContextsController#switch sets session[:platform_acting_as_customer_id]
    ↓
Redirect to /:target_customer_id/
    ↓
TenantContext detects platform owner + different customer
    ↓
Sets Current.customer, Current.platform_owner_context = true
    ↓
ContextBannerComponent renders amber banner
    ↓
All existing .for_current_customer calls work unchanged
    ↓
Elevated operations check platform_elevated_access?
    ↓
Audit logs capture platform owner metadata
    ↓
"Return to Platform" clears session, redirects home
```

## Files to Create

| File | Purpose |
|------|---------|
| `app/controllers/platform/customer_contexts_controller.rb` | Context switching actions |
| `app/controllers/platform/audit_logs_controller.rb` | Platform audit viewer |
| `app/components/platform/customer_switcher_component.rb` | Customer selector UI |
| `app/components/platform/customer_switcher_component.html.erb` | Switcher template |
| `app/components/platform/context_banner_component.rb` | Context banner UI |
| `app/components/platform/context_banner_component.html.erb` | Banner template |
| `app/views/platform/customer_contexts/search.json.jbuilder` | Search results JSON |
| `app/views/platform/audit_logs/index.html.erb` | Audit log listing |
| `app/views/platform/audit_logs/show.html.erb` | Audit log detail |

## Files to Modify

| File | Changes |
|------|---------|
| `app/models/current.rb` | Add `platform_owner_context`, `original_customer`, `acting_as_customer` attributes |
| `app/controllers/concerns/tenant_context.rb` | Add platform owner detection and context setup |
| `app/controllers/application_controller.rb` | Add `platform_elevated_access?` and `require_elevated_access!` helpers |
| `app/models/concerns/auditable.rb` | Append platform owner metadata to audit events |
| `config/routes.rb` | Add `platform` namespace routes |
| `app/views/layouts/dashboard.html.erb` | Integrate banner and switcher components |
| `app/views/layouts/application.html.erb` | Integrate banner component |

## Testing Strategy

### Unit Tests

- `Current` attributes set correctly during platform owner context
- `platform_owner_acting_as_other_customer?` returns correct values
- `platform_elevated_access?` authorization logic
- Audit metadata includes platform owner fields when applicable

### Component Tests

- `CustomerSwitcherComponent` renders only for platform owners
- `ContextBannerComponent` renders only in platform owner context
- Banner displays correct customer name and ID

### Controller Tests

- `CustomerContextsController#search` returns matching customers
- `CustomerContextsController#switch` sets session and redirects
- `CustomerContextsController#clear` clears session and redirects
- Non-platform-owners receive 403 forbidden

### Integration Tests

- Full context switch flow: select customer → navigate → see banner → perform CRUD → return
- Elevated access: platform owner can delete protected record, regular owner cannot
- Audit trail: platform owner action creates audit log with correct metadata
