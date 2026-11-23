# Access-Point Catalog & RBAC Permissions — Design

**Date:** 2026-05-11
**Status:** Design (pending review)
**Owner:** Authentication module

---

## 1. Problem & Goals

The application currently authorizes admin-area access through a small set of role-tier helpers in `ApplicationController` (`require_owner!`, `require_admin_or_owner!`, `require_platform_owner!`, etc.) and a hardcoded `role` enum on `users` (`member`, `admin`, `owner`). 57 controllers call these helpers; several modules (Payments, Authentication user management) duplicate the pattern with their own copy-pasted helpers.

Limitations of the current state:

- **Coarse**: a user is either `admin` (everything in the admin area) or `member` (nothing). Cannot give a user "Email Campaigns admin only" or "Payments view-only."
- **Hardcoded**: roles and permissions live in code; customers cannot tailor authorization to their own org structure.
- **No instance-level grants**: cannot grant access to *one specific entity* or *one specific page*.
- **No cross-cutting catalog**: there is no single source of truth for "what protected resources exist in the application?" Audit/UX impossible.

### Goals

1. Replace the role enum + role-tier helpers with **role-based access control (RBAC)** using `cancancan`.
2. Provide **per-customer roles** — each customer may define custom roles in addition to three system-reserved roles (`owner`, `admin`, `member`).
3. Enumerate every protected access point through a **reusable, reliable catalog** that merges:
   - **Static** access points (controller routes under `/:cid/admin/...`, modules, resource classes, platform tools)
   - **Dynamic per-customer** access points (Entities, Pages, customer-enabled modules)
4. Allow grants at multiple scopes: module-level, page-level, resource-class-level, per-instance, per-action, customer-specific module settings, platform settings.
5. Surface UI under `/:cid/admin/settings/modules/authentication/*` for managing roles, grants, and user assignments.
6. **No hardcoded permission catalog** — what counts as an access point is computed from code surfaces and customer data, not from a hand-maintained constants file.

### Non-Goals

- Field-level permissions (e.g., "can see email but not phone"). Out of scope; can be added later via an attribute-policy extension.
- Direct user-permission grants outside roles (`users_permissions`). Out of scope; the multi-role model satisfies the immediate use case.
- Audit logging of permission checks (separate concern; the existing `FeatureModules::Log` pattern can be extended later).

---

## 2. Background

### Current authorization surface (snapshot)

- `Authentication::User` has `enum :role, { member: 0, admin: 1, owner: 2 }`.
- `User#platform_owner?` is computed: `owner? && customer_id == 81_721_200`.
- Authorization helpers in `ApplicationController`:
  `require_owner_role!`, `require_admin_role!`, `require_admin_or_owner!`, `require_owner!`, `require_platform_owner!`, `require_elevated_access!`.
- 57 controllers attach one of these via `before_action`; some modules define their own near-duplicates (`require_payment_admin_role!`, `require_user_admin_role!`).
- URL/resource categorization (per `AGENTS.md`):
  - `admin` → `/:cid/admin/...` — admin/owner only
  - `member` → `/:cid/member/...` — member only (not yet present)
  - `public` → everything else
- Module surfaces (4 areas per `AGENTS.md`):
  - **a) Entries & Records** → `/:cid/admin/modules/<module>/...`
  - **b) Customer Settings** → `/:cid/admin/settings/modules/<module>/...`
  - **c) Enable/Disable** → `/:cid/admin/maintenance/modules`
  - **d) Platform Settings** → `/:cid/admin/maintenance/platform/module_settings/...`

### Constraints (from AGENTS.md and user direction)

- Tech stack: Rails 8.1.2, Trailblazer family (Reform, Activity, Operation), dry-rb, ViewComponent, TailwindCSS, StimulusJS, RSpec.
- **No backward compatibility** — drop legacy role enum and helpers cleanly.
- Multi-tenant: every domain row carries `customer_id`.
- Authorization framework: `cancancan` (gem to be added).
- New UI must reuse the existing admin layout and styling (no new design system, no custom CSS).

---

## 3. Architecture

### 3.1 High-level components

```
┌──────────────────────────────────────────────────────────────┐
│                  Controller Authorization                    │
│   ApplicationController.before_action :authorize_route!      │
│              (calls cancancan: authorize! ... )              │
└──────────────────────────────────────────────────────────────┘
                             ▲
                             │ asks Ability
┌──────────────────────────────────────────────────────────────┐
│                       Ability (cancancan)                    │
│   Built per request from current_user.roles → grants         │
│   • Owner reserved role → can :manage, :all (hardcoded)      │
│   • Other roles → rules derived from `roles_permissions`     │
└──────────────────────────────────────────────────────────────┘
                             ▲
                             │ reads grants
┌──────────────────────────────────────────────────────────────┐
│                       RBAC Data Model                        │
│   roles ─◇ users_roles ◇─ users                              │
│         └─◇ roles_permissions (polymorphic subject)          │
└──────────────────────────────────────────────────────────────┘
                             ▲
                             │ admin UI consults
┌──────────────────────────────────────────────────────────────┐
│              AccessPoints::Catalog (request-scoped)          │
│   Merges output of registered Providers:                     │
│   • RouteProvider     (admin-area routes)                    │
│   • ModuleProvider    (customer-enabled modules)             │
│   • EntityClassProvider, EntityProvider                      │
│   • PageProvider                                             │
│   • PlatformProvider  (platform-only when cid == 81721200)   │
└──────────────────────────────────────────────────────────────┘
```

### 3.2 Two layers, clearly separated

- **Authorization layer** (runtime, per request): `Ability` + cancancan. Answers "is this allowed?"
- **Catalog layer** (admin UI, on-demand): `AccessPoints::Catalog`. Answers "what access points exist for customer X?" — used only when rendering the role grants editor and resource pickers. Not in the request-authorization hot path.

The two layers share a vocabulary (subject type + subject key + action) so a grant created via the catalog UI is interpretable by the Ability.

---

## 4. Data Model

All four new tables are multi-tenant via `customer_id` (except `roles_permissions` which inherits its tenant scope through its `role`, which is per-customer — verified by validation).

### 4.1 `roles`

| Column | Type | Notes |
|---|---|---|
| `id` | bigint PK | |
| `customer_id` | bigint, NOT NULL, indexed | tenant scope |
| `key` | string, NOT NULL | slug; unique per `(customer_id, key)`; immutable after create |
| `name` | string, NOT NULL | human label |
| `description` | text, NULL | |
| `system` | boolean, NOT NULL, default false | true for the three reserved roles |
| `locked_grants` | boolean, NOT NULL, default false | true → grants cannot be edited via UI; true for reserved `admin` and `member` |
| `created_at`, `updated_at` | timestamps | |

Indexes:
- Unique `(customer_id, key)`
- `(customer_id)`

Reserved-role rows seeded per customer:
- `key="owner"`,  `system=true`, `locked_grants=true` (Ability hardcodes full access — grants column ignored)
- `key="admin"`,  `system=true`, `locked_grants=true`
- `key="member"`, `system=true`, `locked_grants=true`

### 4.2 `users_roles`

| Column | Type | Notes |
|---|---|---|
| `id` | bigint PK | |
| `user_id` | bigint, NOT NULL, FK | |
| `role_id` | bigint, NOT NULL, FK | |
| `created_at`, `updated_at` | timestamps | |

Indexes:
- Unique `(user_id, role_id)`
- `(role_id)`

Validation: `user.customer_id == role.customer_id`. A user may only hold roles within their own customer.

### 4.3 `roles_permissions` (the grant table)

Polymorphic to support both abstract subjects (route, module, resource class) and per-instance subjects (Entity #42, Page #7) without exploding the row count.

| Column | Type | Notes |
|---|---|---|
| `id` | bigint PK | |
| `role_id` | bigint, NOT NULL, FK | |
| `subject_type` | string, NOT NULL | `"Route"`, `"Module"`, `"EntityClass"`, `"Entity"`, `"PageClass"`, `"Page"`, `"FeaturePage"`, `"Platform"` |
| `subject_key` | string, NULL | stable identifier (e.g., `"admin/maintenance/flowcharts"`, `"payments"`); NULL when `subject_id` is set and the type is purely instance-keyed |
| `subject_id` | bigint, NULL | set for instance subjects (Entity, Page); NULL for class/route/module |
| `action` | string, NOT NULL | `"read"`, `"create"`, `"update"`, `"destroy"`, `"manage"`, or custom (e.g., `"refund"`) |
| `created_at`, `updated_at` | timestamps | |

Indexes:
- `(role_id)`
- `(role_id, subject_type, subject_key)` (for class/abstract lookups)
- `(role_id, subject_type, subject_id)` (for instance lookups)

Constraint: at least one of `subject_key` or `subject_id` must be present.

### 4.4 No `permissions` master table

Earlier we considered a separate `permissions` table acting as a vocabulary master list. We **deliberately do not introduce one**, for two reasons:

1. **Per-customer dynamic subjects** (Entity, Page) would force one master row per customer-record, polluting the catalog.
2. **Vocabulary is computed**, not stored. The `AccessPoints::Catalog` derives subjects on demand from routes + customer data. There is nothing to keep in sync.

The `(subject_type, subject_key, subject_id, action)` quadruple in `roles_permissions` carries all the information the Ability needs.

---

## 5. Access-Point Catalog (the scanner)

### 5.1 Provider interface

```ruby
# app/services/access_points/provider.rb
module AccessPoints
  class Provider
    # @param customer_id [Integer]
    # @return [Array<AccessPoints::Descriptor>]
    def call(customer_id:) = raise NotImplementedError

    # Stable group identifier used by the UI (e.g., "modules.payments").
    def group_key = raise NotImplementedError

    # Human-friendly group label.
    def group_label = raise NotImplementedError

    # Whether this provider should run for the given customer.
    # Default: always run. Overridden by PlatformProvider.
    def applicable?(customer_id:) = true
  end
end
```

### 5.2 Descriptor (value object)

```ruby
# app/services/access_points/descriptor.rb
module AccessPoints
  class Descriptor < Dry::Struct
    attribute :subject_type, Types::Strict::String
    attribute :subject_key,  Types::Strict::String.optional
    attribute :subject_id,   Types::Strict::Integer.optional
    attribute :actions,      Types::Array.of(Types::Strict::Symbol)
    attribute :group_key,    Types::Strict::String
    attribute :label,        Types::Strict::String
    attribute :description,  Types::Strict::String.optional
  end
end
```

### 5.3 Concrete providers

| Provider | What it yields | Source |
|---|---|---|
| `RouteProvider` | One descriptor per controller#action group under `/:customer_id/admin/...`. `subject_type="Route"`, `subject_key=controller_path` (e.g., `"admin/maintenance/flowcharts"`). `actions` derived from collected HTTP verbs (`GET → :read`, `POST → :create`, `PATCH/PUT → :update`, `DELETE → :destroy`). | `Rails.application.routes.routes` |
| `ModuleProvider` | One descriptor per module enabled for the customer. `subject_type="Module"`, `subject_key=module.key`, `actions=[:manage]`. Coarse module-level grant (admin can grant "all of payments" without listing every payments route). | `FeatureModules::Module.available_for_customer(cid)` |
| `EntityClassProvider` | A single descriptor: `subject_type="EntityClass"`, `subject_key="Entity"`, `actions=[:read,:create,:update,:destroy]`. Class-level grant covering every Entity for the customer. | static |
| `EntityProvider` | One descriptor per `Entity` belonging to the customer. `subject_type="Entity"`, `subject_id=entity.id`, `actions=[:read,:update,:destroy]`. | `Entity.where(customer_id:)`, accessed lazily via search picker — not pre-rendered as a full list |
| `PageClassProvider` | A single descriptor: `subject_type="PageClass"`, `subject_key="Page"`, `actions=[:read,:create,:update,:destroy]`. Class-level grant covering every Page for the customer. | static |
| `PageProvider` | One descriptor per `Page` belonging to the customer. `subject_type="Page"`, `subject_id=page.id`, `actions=[:read,:update,:destroy]`. | `Page.where(customer_id:)`, lazy via search picker |
| `PlatformProvider` | Platform-only descriptors (industry templates, code generators, platform module settings, customer management). `subject_type="Platform"`, `subject_key` per feature. | static; `applicable?` returns true only when `customer_id == 81_721_200` |

`FeaturePage` `subject_type` is reserved for non-CRUD admin pages that don't fit the route-provider shape (e.g., search). Phase-1 leaves this empty; new module registrations may register their own provider yielding `FeaturePage` descriptors.

### 5.4 Registry

```ruby
# config/initializers/access_points.rb
AccessPoints::Registry.register(AccessPoints::RouteProvider.new)
AccessPoints::Registry.register(AccessPoints::ModuleProvider.new)
AccessPoints::Registry.register(AccessPoints::EntityClassProvider.new)
AccessPoints::Registry.register(AccessPoints::EntityProvider.new)
AccessPoints::Registry.register(AccessPoints::PageClassProvider.new)
AccessPoints::Registry.register(AccessPoints::PageProvider.new)
AccessPoints::Registry.register(AccessPoints::PlatformProvider.new)
```

Adding a new resource type = one new provider class + one register line. No schema change, no scanner script.

### 5.5 Catalog facade

```ruby
catalog = AccessPoints::Catalog.for(customer_id: 12_345_678)
catalog.groups
# => [
#   { key: "admin.maintenance", label: "Maintenance", descriptors: [...] },
#   { key: "modules.payments",  label: "Payments",    descriptors: [...] },
#   { key: "entities",          label: "Entities",    descriptors: [...], paginated: true },
#   ...
# ]

catalog.find(subject_type: "Entity", subject_id: 42)
catalog.find(subject_type: "Route", subject_key: "admin/maintenance/flowcharts")
```

Cached for the lifetime of the request via `Current.access_points_catalog ||= ...`. Lazy: high-cardinality providers (Entity, Page) only fully materialize when the UI explicitly asks for a search query.

---

## 6. Authorization (cancancan integration)

### 6.1 `Ability` class

```ruby
# app/models/ability.rb
class Ability
  include CanCan::Ability

  def initialize(user)
    return if user.blank?

    if user.has_reserved_role?(:owner)
      can :manage, :all
      return
    end

    grants = RolePermissions::ResolveGrants.call(role_ids: user.role_ids)
    grants.each { |g| apply_grant(g) }
  end

  private

  def apply_grant(g)
    actions = g.action == "manage" ? :manage : g.action.to_sym

    case g.subject_type
    when "Route"       then can actions, :"route_#{g.subject_key.tr('/', '_')}"
    when "Module"      then can actions, :"module_#{g.subject_key}"
    when "EntityClass" then can actions, Entity
    when "Entity"      then can actions, Entity, id: g.subject_id
    when "PageClass"   then can actions, Page
    when "Page"        then can actions, Page, id: g.subject_id
    when "FeaturePage" then can actions, :"feature_#{g.subject_key}"
    when "Platform"    then can actions, :"platform_#{g.subject_key}"
    end
  end
end
```

### 6.2 Controller usage

`ApplicationController` adds a single before_action that authorizes the *route subject*:

```ruby
before_action :authorize_route!, if: :admin_route?

private

def admin_route?
  request.path =~ %r{\A/\d{8}/admin(/|\z)}
end

def authorize_route!
  action = case request.method
           when "GET"           then :read
           when "POST"          then :create
           when "PATCH", "PUT"  then :update
           when "DELETE"        then :destroy
           else :read
           end
  authorize! action, :"route_#{controller_path.tr('/', '_')}"
end
```

For CRUD on real ActiveRecord resources, controllers add `load_and_authorize_resource` so cancancan also checks instance-level grants:

```ruby
class Admin::Maintenance::EntitiesController < ApplicationController
  load_and_authorize_resource :entity
  # ...
end
```

For custom actions (refunds, deliveries, etc.), explicit `authorize! :refund, payment` calls take over.

### 6.3 Removal of legacy helpers

Per the no-backward-compatibility rule, these are deleted in the cutover PR:

- `ApplicationController#require_owner_role!`
- `ApplicationController#require_admin_role!`
- `ApplicationController#require_admin_or_owner!`
- `ApplicationController#require_owner!`
- `ApplicationController#require_platform_owner!`
- `ApplicationController#require_elevated_access!`
- `Admin::Modules::Payments::BaseController#require_payment_admin_role!`
- `Admin::Modules::Authentication::*Controller#require_user_admin_role!`

All 57 `before_action :require_*!` call sites are removed; the `authorize_route!` before_action above plus `load_and_authorize_resource` cover them.

### 6.4 Access-denied handling

```ruby
rescue_from CanCan::AccessDenied do |exception|
  respond_to do |format|
    format.html { redirect_to root_path, alert: exception.message }
    format.json { render json: { error: "access_denied" }, status: :forbidden }
  end
end
```

Existing redirect-and-alert UX is preserved.

---

## 7. UI

All under `/:cid/admin/settings/modules/authentication/*`. Reuses the existing admin layout, dashboard chrome, and TailwindCSS conventions. ViewComponent + StimulusJS as elsewhere in the app.

### 7.1 Routes

```ruby
namespace :admin do
  namespace :settings do
    namespace :modules do
      namespace :authentication do
        resources :roles do
          resource :grants, only: %i[show update],
            controller: "role_grants"
        end
        resources :user_role_assignments,
          only: %i[index create destroy]
      end
    end
  end
end
```

### 7.2 Pages

**a) Roles index** — `/:cid/admin/settings/modules/authentication/roles`

Table: name | type (badge: System / Custom) | # users | # grants | actions. New / Edit / Delete buttons. System rows show disabled icons with tooltip "Reserved role." Layout mirrors the existing `Admin::Maintenance::EntitiesController#index` table.

**b) Role new / edit form**

Card layout: name, key (auto-suggested slug from name; immutable after create), description. System roles redirect to a read-only show.

**c) Role grants editor** — `/:cid/admin/settings/modules/authentication/roles/:id/grants`

The core UI. Two-pane layout:

- **Left pane**: catalog tree from `AccessPoints::Catalog.for(customer_id:)`, grouped by `group_key`. Groups (collapsible): Admin Routes / Modules / Maintenance / Settings / Platform / Entities / Pages. Each row inside a group is a descriptor with action checkboxes (`read / create / update / destroy / manage`).
- **Right pane**: selected-grants summary as chips. Click a chip → scroll into view in the left pane.
- For high-cardinality groups (Entities, Pages): the group renders a *search picker* (type-ahead) plus a "grant for ALL entities/pages" toggle that adds an `EntityClass` or `PageClass` descriptor instead of one descriptor per record.
- For system roles: same layout, but inputs disabled and a banner reads *"Reserved role — grants are seeded and cannot be modified."*
- Save: a single Stimulus controller posts a JSON diff (`{added: [...], removed: [...]}`) to `role_grants#update`. Server runs `RoleGrants::Update` (Trailblazer Operation) inside a transaction.

**d) User role assignments** — `/:cid/admin/settings/modules/authentication/user_role_assignments`

Table: users × their roles. Filter by role; search by name/email. Row click → modal with multi-select role picker. Save → `UserRoles::Assign` operation.

### 7.3 ViewComponents

- `Admin::Settings::Modules::Authentication::RolesTableComponent`
- `Admin::Settings::Modules::Authentication::RoleFormComponent`
- `Admin::Settings::Modules::Authentication::GrantsEditorComponent`
- `Admin::Settings::Modules::Authentication::AccessPointGroupComponent`
- `Admin::Settings::Modules::Authentication::AccessPointRowComponent`
- `Admin::Settings::Modules::Authentication::ResourcePickerComponent`
- `Admin::Settings::Modules::Authentication::UserRolesTableComponent`
- `Admin::Settings::Modules::Authentication::UserRoleAssignmentDialogComponent`

### 7.4 Sidebar contributor

`FeatureModules::Authentication::Registration#sidebar_contributions` (extended) adds two `settings`-area entries:
- "Roles"
- "User Role Assignments"

Both gated by the new `authorize? :read, :"route_admin_settings_modules_authentication_roles"` etc. — admins see them, members don't.

### 7.5 Forms (Reform)

- `Roles::Contracts::Create` / `Roles::Contracts::Update` — name, key (create-only), description.
- `RoleGrants::Contracts::Update` — `added: Array, removed: Array` of `{subject_type, subject_key, subject_id, action}`.
- `UserRoles::Contracts::Assign` — `user_id, role_ids: Array`.

### 7.6 Trailblazer operations

- `Roles::Create`, `Roles::Update`, `Roles::Destroy` (rejects when `system: true`)
- `Roles::SeedReserved(customer:)` (idempotent)
- `RoleGrants::Update(role:, added:, removed:)` — rejects when `role.locked_grants?`; transactional
- `UserRoles::Assign(user:, role_ids:)` — same-customer validation
- `RolePermissions::ResolveGrants(role_ids:)` — fetches grants for the Ability

---

## 8. Migration & Bootstrap

### 8.1 Sequence

1. **Add `cancancan` gem.** Bundle install.

2. **Schema migrations** (single PR):
   - `create_roles`
   - `create_users_roles`
   - `create_role_permissions`

3. **Seed reserved roles** (`db/seeds/reserved_roles.rb`):
   - For every existing `Customer`, run `Roles::SeedReserved`. Creates `owner`, `admin`, `member` rows with `system: true, locked_grants: true`.
   - Seed grants for `admin` and `member` from a derivation rule applied to live `AccessPoints::Catalog.for(customer_id:)`:
     - `admin` → all descriptors with all their actions, **except** the `Platform` group.
     - `member` → no admin-area descriptors (preserves current state).
   - `owner` gets no grant rows; `Ability` hardcodes full access.

4. **Backfill existing users** (data migration):
   - For each user, create one `users_roles` row matching their current `users.role` enum value (mapped to the seeded reserved role of the same key in the user's customer).

5. **Code cutover** (single PR):
   - Reimplement `User#owner?`, `#admin?`, `#admin_or_owner?`, `#member?`, `#platform_owner?` to query `users_roles → roles.key`. Call sites continue working unchanged.
   - Add `Ability` class.
   - Add `authorize_route!` before_action in `ApplicationController`.
   - Add `rescue_from CanCan::AccessDenied`.
   - Delete legacy `require_*!` helpers and all `before_action :require_*!` call sites.
   - Add `load_and_authorize_resource` to CRUD controllers that need instance-level checks.
   - Replace per-controller duplicated helpers (`require_payment_admin_role!`, `require_user_admin_role!`).

6. **Drop `users.role` column** (final migration after smoke verification).

### 8.2 Hooking new customer creation

`Customers::Create` operation adds a step calling `Roles::SeedReserved.(customer: model)` so every new customer is born with the three reserved roles and seeded grants.

### 8.3 Adding new modules going forward

No schema change. Two paths:

- If the module is purely route-driven, the `RouteProvider` picks up the new admin routes automatically.
- If the module exposes special access points (a dynamic per-record concept, etc.), the module ships its own `AccessPoints::Provider` and registers it via `AccessPoints::Registry.register(...)` from its initializer.

---

## 9. Multi-tenant & cross-customer concerns

- All RBAC tables carry `customer_id` (directly or transitively). The `users_roles` validator forbids cross-customer assignment.
- Platform-owner staff (customer `81_721_200`) have their own roles in their own customer. When they act into another customer (the existing `Current.platform_owner_context`), authorization continues to use **their** roles — they retain access through their roles regardless of the target customer's role definitions. The current `Current.platform_owner_context?` and `setup_platform_owner_context` flow is untouched.
- `PlatformProvider` only contributes descriptors when `customer_id == 81_721_200`, so platform staff's role grants editor shows the platform-only access points; non-platform customers' role editors do not.

---

## 10. Testing Strategy

| Layer | Coverage | Files |
|---|---|---|
| Models | Reserved roles can't be edited/deleted; `users_roles` rejects cross-customer; `roles_permissions` polymorphic resolution | `spec/models/role_spec.rb`, `spec/models/users_role_spec.rb`, `spec/models/role_permission_spec.rb` |
| Providers | Each provider returns correct descriptors for given `customer_id`; route provider derives correct actions from HTTP verbs; entity provider scopes by customer | `spec/services/access_points/route_provider_spec.rb` and siblings |
| Catalog | Merges providers, correct grouping, request-scoped caching, search picker scoping | `spec/services/access_points/catalog_spec.rb` |
| Ability | Owner reserved → `:manage, :all`; admin role grants seeded correctly; per-instance grant restricts to one record; missing grants → `AccessDenied` | `spec/models/ability_spec.rb` |
| Operations | `Roles::Create/Update/Destroy` (rejects system), `Roles::SeedReserved` (idempotent), `RoleGrants::Update` (transactional, rejects locked), `UserRoles::Assign` (same-customer) | `spec/concepts/roles/...`, `spec/concepts/role_grants/...`, `spec/concepts/user_roles/...` |
| Request specs | Each new admin settings route returns 200 for permitted users, 403 for unauthorized; existing admin routes still gate as before; system role mutations rejected | `spec/requests/admin/settings/modules/authentication/...` |
| Component specs | Grants editor renders catalog groups, pre-checks granted descriptors, disables system role inputs, search picker filters by query | `spec/components/admin/settings/modules/authentication/...` |
| Migration | Backfill task assigns correct role to every existing user; seeded reserved-role grants reproduce the prior `require_*!` behavior across a representative sample of admin routes | `spec/tasks/migrate_user_roles_spec.rb` |

**Regression baseline:** snapshot the current authorization behavior of every controller using `before_action :require_*!` (HTTP status for member / admin / owner / platform_owner). After cutover, re-run the same matrix. Failure to match for any pre-existing protected action blocks the migration PR.

---

## 11. Risks & Mitigations

| Risk | Mitigation |
|---|---|
| Misseeded `admin` role grants leave admins locked out of routes they previously had | Regression-baseline snapshot test; manual smoke test on a clone before cutover |
| Customer creates a custom role with no grants and assigns it to a real user | Ability silently grants nothing; user sees access-denied. Acceptable — same UX as today's `member` role. UI shows a "0 grants" warning on the role row |
| Owner accidentally locks themselves out by misconfiguring | Owner is hardcoded `can :manage, :all`; cannot be locked out |
| High-cardinality entity/page grants cause `roles_permissions` bloat | The `EntityClass` "all entities" grant covers the common case in one row. Per-instance grants are admin-driven and few in practice. Monitor table size in production |
| Authorization on every admin request adds latency | Ability is built once per request from a small grant set (worst case: a few hundred rows for a heavily-customized role). Use `pluck` and avoid N+1 in `ResolveGrants` |
| Adding a new module forgets to register a provider for special access points | Documented in module-creation checklist; routes alone cover most modules |

---

## 12. Open questions

None blocking. Items to revisit during implementation:

- Whether `subject_key` for routes should be the controller path (`admin/maintenance/flowcharts`) or the route name (`admin_maintenance_flowcharts`). Going with controller path for stability against route-name renames.
- Whether to add a `users_permissions` table for one-off direct grants in a later iteration (deferred — not part of this scope).
