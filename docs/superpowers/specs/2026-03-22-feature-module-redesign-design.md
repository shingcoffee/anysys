# Feature Module Redesign: Auto-Discovery & Minimal UI

## Goal

Restructure feature modules to auto-discover models and routes by namespace convention, display them on the detail page, and redesign the UI to a minimal clean settings-panel style.

## Scope

1. Move `User` model into `Authentication::` namespace
2. Move auth controllers from `Auth::` / `Admin::` into `Authentication::` namespace
3. Build auto-discovery services for models and routes
4. Redesign feature module index and detail pages
5. Update all references, routes, Devise config, specs

---

## 1. Namespace Restructuring

### Model

| Before | After |
|--------|-------|
| `app/models/user.rb` (`User`) | `app/models/authentication/user.rb` (`Authentication::User`) |

All references to `User` throughout the codebase update to `Authentication::User`. This includes:
- Devise configuration (`devise_for`)
- Factory (`:user` → model_class)
- `current_user` return type (Devise handles this via the model class)
- All specs, helpers, and services referencing `User`
- `ApplicationController` helper methods
- Feature module initializer and provisioner/deprovisioner

### Controllers

| Before | After |
|--------|-------|
| `app/controllers/auth/sessions_controller.rb` (`Auth::SessionsController`) | `app/controllers/authentication/sessions_controller.rb` (`Authentication::SessionsController`) |
| `app/controllers/auth/registrations_controller.rb` (`Auth::RegistrationsController`) | `app/controllers/authentication/registrations_controller.rb` (`Authentication::RegistrationsController`) |
| `app/controllers/auth/passwords_controller.rb` (`Auth::PasswordsController`) | `app/controllers/authentication/passwords_controller.rb` (`Authentication::PasswordsController`) |
| `app/controllers/auth/mfa_controller.rb` (`Auth::MfaController`) | `app/controllers/authentication/mfa_controller.rb` (`Authentication::MfaController`) |
| `app/controllers/admin/users_controller.rb` (`Admin::UsersController`) | `app/controllers/authentication/admin/users_controller.rb` (`Authentication::Admin::UsersController`) |

### Views

Move correspondingly:
- `app/views/auth/` → `app/views/authentication/`
- `app/views/admin/users/` → `app/views/authentication/admin/users/`

### Routes

Update `config/routes.rb`:
- `devise_for :users` → `devise_for :users, class_name: 'Authentication::User'` with updated controller references
- MFA routes update controller references from `auth/mfa` to `authentication/mfa`
- Admin user routes move under `authentication/admin` namespace

---

## 2. Auto-Discovery Services

### ModuleModelDiscovery

**File**: `app/services/module_model_discovery.rb`

**Input**: `module_key` (string, e.g., `"authentication"`)

**Behavior**: Scans `app/models/<module_key>/` directory for `.rb` files. For each file, constantizes the class and extracts metadata.

**Output**: Array of hashes:
```ruby
[
  {
    name: "Authentication::User",
    table_name: "users",
    columns_count: 15,
    associations_count: 0
  }
]
```

Edge cases:
- Directory doesn't exist → returns `[]`
- File fails to constantize → skip it
- Abstract classes or concerns in the directory → skip (only include classes that inherit from `ApplicationRecord`)

### ModuleRouteDiscovery

**File**: `app/services/module_route_discovery.rb`

**Input**: `module_key` (string, e.g., `"authentication"`)

**Behavior**: Iterates `Rails.application.routes.routes`, selects routes whose `defaults[:controller]` starts with the module key (e.g., `authentication/`). Extracts HTTP method, path, route name, and controller#action.

**Output**: Array of hashes:
```ruby
[
  { method: "GET", path: "/:customer_id/auth/sign_in", name: "new_user_session", controller_action: "authentication/sessions#new" },
  { method: "POST", path: "/:customer_id/auth/sign_in", name: "user_session", controller_action: "authentication/sessions#create" },
  ...
]
```

Edge cases:
- No matching routes → returns `[]`
- Routes with multiple HTTP methods (e.g., `match ... via: :all`) → one entry per method
- Internal/engine routes → excluded

---

## 3. UI Redesign

### Index Page (`app/views/feature_modules/index.html.erb`)

Single-column list layout. Each module is a row rendered by `FeatureModuleListItemComponent`.

Row contents:
- Left: Module name (semibold), description (muted text)
- Right: Status pill (Required/Enabled/Available), action link (Details →)

No card shadows, no grid, no icons. Clean white rows separated by subtle gray borders. Page header with title "Feature Modules".

### Detail Page (`app/views/feature_modules/show.html.erb`)

Single-column, no tabs. Sections stack vertically with subtle dividers:

**1. Header**
- Back link
- Module name + status pill on one line
- Enable/disable button aligned right

**2. About**
- Key-value list: Module Key, Version, Status, Description
- Simple `<dl>` styling

**3. Models** (new section)
- Heading "Models"
- Table: Name, Table Name, Columns
- Data from `ModuleModelDiscovery.call(module_key)`
- Empty state: "No models found for this module."

**4. Routes** (new section)
- Heading "Routes"
- Table: HTTP Method (styled badge — green GET, blue POST, yellow PATCH, red DELETE), Path, Name, Action
- Data from `ModuleRouteDiscovery.call(module_key)`
- Empty state: "No routes found for this module."

**5. Configuration Schema**
- Heading "Configuration Schema"
- List of available settings with type, default, description
- Only shown if schema is non-empty

**6. My Configuration** (per-customer)
- Heading "My Configuration"
- Status info (active/suspended/not enabled, enabled_at)
- Configuration form (only if module is enabled and schema exists)
- "Enable this module to configure it." message if not enabled

**7. Required Module** (owner-only)
- Heading "Required Module"
- Toggle with warning text about affecting all customers
- Only visible to owners

### Components

**New**: `FeatureModuleListItemComponent` — renders a single row on the index page.

**Delete**: `FeatureModuleCardComponent` (replaced by list item).

**Reuse**: `BadgeComponent`, `ButtonComponent`, `AlertComponent`.

---

## 4. Testing

### Service Specs
- `spec/services/module_model_discovery_spec.rb` — tests discovery for authentication module, empty module, nonexistent module
- `spec/services/module_route_discovery_spec.rb` — tests route discovery for authentication, empty results

### Component Specs
- `spec/components/feature_module_list_item_component_spec.rb` — renders name, description, status, action link

### Request Specs
- Update `spec/requests/feature_modules_spec.rb` — verify models section, routes section render on show page
- Update auth-related request specs for new controller namespace

### Controller/Model Specs
- Move `spec/models/user_spec.rb` → `spec/models/authentication/user_spec.rb`
- Move `spec/requests/auth/` → `spec/requests/authentication/`
- Move `spec/requests/admin/users_spec.rb` → `spec/requests/authentication/admin/users_spec.rb`
- Update factory `:user` to reference `Authentication::User`

---

## 5. Files Summary

### New Files
- `app/models/authentication/user.rb`
- `app/controllers/authentication/sessions_controller.rb`
- `app/controllers/authentication/registrations_controller.rb`
- `app/controllers/authentication/passwords_controller.rb`
- `app/controllers/authentication/mfa_controller.rb`
- `app/controllers/authentication/admin/users_controller.rb`
- `app/views/authentication/` (moved from `app/views/auth/`)
- `app/views/authentication/admin/users/` (moved from `app/views/admin/users/`)
- `app/services/module_model_discovery.rb`
- `app/services/module_route_discovery.rb`
- `app/components/feature_module_list_item_component.rb`
- `app/components/feature_module_list_item_component.html.erb`

### Deleted Files
- `app/models/user.rb`
- `app/controllers/auth/sessions_controller.rb`
- `app/controllers/auth/registrations_controller.rb`
- `app/controllers/auth/passwords_controller.rb`
- `app/controllers/auth/mfa_controller.rb`
- `app/controllers/admin/users_controller.rb`
- `app/views/auth/` directory
- `app/views/admin/users/` directory
- `app/components/feature_module_card_component.rb`
- `app/components/feature_module_card_component.html.erb`

### Modified Files
- `config/routes.rb` — Devise + MFA + admin routes updated
- `app/views/feature_modules/index.html.erb` — redesigned
- `app/views/feature_modules/show.html.erb` — redesigned with models/routes sections
- `app/controllers/feature_modules_controller.rb` — pass discovery data to show
- `app/services/feature_modules/authentication/provisioner.rb` — `Authentication::User`
- `app/services/feature_modules/authentication/deprovisioner.rb` — `Authentication::User`
- `config/initializers/feature_modules.rb` — updated references
- `spec/factories/users.rb` — updated model class
- All auth-related specs — moved and updated
