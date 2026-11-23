---
title: "Access grants"
summary: "How RolePermission rows and the reserved-role short-circuits in Ability become the CanCan rules on each request."
---

## Summary

`Ability` is the CanCanCan ability CanCan constructs as `Ability.new(current_user)`. A platform owner receives `can :manage, :all` and returns. A user with the reserved `admin` role receives `can :manage, :all` except platform subjects and flowchart route subjects, and also returns. Everyone else who reaches this far — in practice a member, plus any custom roles assigned beside `member` — gets the fixed member-route list and then one rule per `RolePermission` from `RolePermissions::Operation::ResolveGrants`.

The path gate in [Tenancy and roles](tenancy-and-roles) runs first. A grant cannot open `/admin` for someone who is not `admin_or_owner?`, and it cannot open `/member` for someone who is not `member?`.

## Flow

```text
Customer create
        |
        v
Roles::Operation::SeedReserved
        |  system roles owner, admin, member  (locked_grants)
        |  admin: AccessPoints::Catalog -> RolePermission.insert_all!
        v
Settings UI
GET/PATCH /:cid/admin/settings/modules/authentication/roles/:role_id/grants
        |
        |  Admin::Settings::Modules::Authentication::RoleGrantsController
        |  GrantsEditorComponent + grants_editor_controller.js
        v
RoleGrants::Operation::Update
        |  refuses locked_grants
        |  refuses Platform and flowchart routes unless actor.owner?
        |  instance ids must exist on role.customer_id
        v
role_permissions
        |
        v
request
RouteAuthorization#authorize_route!
        |
        v
Ability#initialize
        |  platform_owner? -> manage :all, return
        |  reserved admin  -> manage :all, cannot platform + flowchart, return
        |  reserved member -> can manage member_route_subjects
        |  then each RolePermission -> apply_grant
        v
CanCan authorize! verb, :"route_<controller_path>"
```

Custom roles are created at `/:cid/admin/settings/modules/authentication/roles`. Assigning them to a user is `UserRoles::Operation::Assign` from `UserRoleAssignmentsController`. The user must keep exactly one reserved role in that assignment.

## Implementation

### Roles

`Role` belongs to `customer` and has many `role_permissions` and `users` through `users_roles`. `key` is unique per `customer_id`. `RESERVED_KEYS` is `owner`, `admin`, `member`. `reserved?` is membership in that list. `system` and `locked_grants` are booleans.

`Roles::Operation::SeedReserved` `find_or_create_by!` the three keys with `system: true` and `locked_grants: true`. For `admin` only, when the role has no permissions yet, it clears `Current.access_points_catalog`, builds `AccessPoints::Catalog.for(customer_id:)`, and `insert_all!`s one `RolePermission` per descriptor action. Groups whose key is `"platform"` or starts with `"admin.maintenance.platform"` are skipped. `assert_grant_shape!` mirrors `RolePermission`'s key-versus-id rules because `insert_all!` skips validations.

`Roles::Operation::Create` builds `system: false`, `locked_grants: false`, and validates with `Roles::Contract::Create` (`key` matches `[a-z0-9_]+`). `Update` refuses `role.system?`. `Destroy` refuses `role.system?`. The HTTP surface is `Admin::Settings::Modules::Authentication::RolesController`, scoped with `current_customer.roles`.

`UserRoles::Operation::Assign` locks the user and resolves role IDs through `user.customer.roles`. The accepted set contains exactly one reserved role. Reserved replacement updates the existing join in place; owner assignment is immutable even for the owner, and standalone deletion of the sole reserved join is rejected by `UserRoles::AssignmentPolicy`. The authentication single-user editor uses the same operation, retains supplemental custom roles and saves profile plus role in a rollback boundary. Assignment controllers return localized HTML/JSON failures and audit only successful changes.

### Catalog

`config/initializers/access_points.rb` calls `AccessPoints::Registry.install_default_providers!` after initialize. The providers, in order, are `RouteProvider`, `ModuleProvider`, `EntityClassProvider`, `EntityProvider`, `PageClassProvider`, `PageProvider`, and `PlatformProvider`.

`AccessPoints::Catalog.for` memoizes on `Current.access_points_catalog`. `groups` asks each `applicable?` provider for `Descriptor`s and buckets them by `group_key`. A descriptor carries `subject_type`, `subject_key`, `subject_id`, `actions`, `group_key`, and `label`.

| Provider | Subject | What it lists |
| --- | --- | --- |
| `RouteProvider` | `Route`, key = controller path | Admin routes from `Rails.application.routes`. Verbs map to `:read`, `:create`, `:update`, `:destroy`. Controllers `FlowchartVisibility.controller?` matches are omitted. |
| `ModuleProvider` | `Module`, key = module key | `FeatureModules::Module.available_for_customer`, action `:manage` |
| `EntityClassProvider` | `EntityClass`, key `"Entity"` | One collection descriptor, actions read/create/update/destroy |
| `EntityProvider` | `Entity`, id = row id | `Entity.where(customer_id:)` |
| `PageClassProvider` | `PageClass`, key `"Page"` | One collection descriptor |
| `PageProvider` | `Page`, id = row id | `Page.where(customer_id:)` |
| `PlatformProvider` | `Platform` | Only when `customer_id` is `81721200`. Keys: `customers`, `module_settings`, `industry_templates`, `code_generators` |

`RolePermission::SUBJECT_TYPES` also includes `FeaturePage`. `Ability#apply_grant` turns that type into `:"feature_<subject_key>"`. No registered provider emits `FeaturePage`, so the grants editor does not list it.

### Editor

`Admin::Settings::Modules::Authentication::GrantRouteLabel` localizes route names at render time using keys available in both English and Simplified Chinese. The `admin/maintenance/page_shortcuts` descriptor reuses `page_shortcuts.title`, so [Page shortcuts](page-shortcuts) has a distinct localized resource label in the permissions catalog. This is presentation metadata: the controller-path subject key, grant actions, admin/owner gate and tenant scoping remain the authorization contract.

Nested billing write controllers use their existing action labels: `admin/settings/billing/plan_changes` uses `settings_billing.subscription.cancel_change`, and `admin/settings/billing/invoice_payments` uses `comp_billing.invoice_detail.pay_invoice`. Their distinct localized suffixes identify cancellation and payment rather than collapsing both into the generic resource label.

The eight SMS audience/campaign controllers remain separate `Route` subjects under the SMS context. `AccessPoints::SmsRouteLabels` supplies shared, call-time translation keys to `RouteProvider` and `GrantRouteLabel`; the editor renders names such as **Module records — SMS — Contacts**, with the subsystem included once. Both locales define every resource suffix, so these routes do not collapse into “Other resources.” Existing Contacts/Audiences/Campaigns and Cancel campaigns translations are reused; consent, synchronization, launch and report labels live in paired `settings_people.grant_resources.sms_*` keys.

| Controller suffix under `admin/modules/sms/` | Resource label | Registered actions |
| --- | --- | --- |
| `contacts` | Contacts | read, create, update, destroy |
| `consent_events` | Consent events | create |
| `entity_syncs` | Contact synchronization | read, create |
| `segments` | Audiences | read, create, update, destroy |
| `campaigns` | Campaigns | read, create, update, destroy |
| `campaign_launches` | Launch campaigns | create |
| `campaign_cancellations` | Cancel campaigns | create |
| `campaign_reports` | Campaign reports | read |

Labels are presentation only: controller-path keys, HTTP-derived actions, reserved roles, SMS enablement and URL-tenant guards remain authoritative. Consent creation, campaign launch and cancellation are distinct actions; report access is read-only. Public signed unsubscribe URLs are not admin route grants. See [SMS audiences and campaigns](sms-campaigns).

The customer domain is a profile attribute, not a separate CanCan subject. Central platform authorization requires the actual outer PATH_INFO customer to be `81721200` for every format/action; query/body or nested target IDs cannot substitute. A new/changed domain requires a direct CNAME to `anysys.net` and confers no permission. See [Customers](customers) and [Custom domains](custom-domains).

`RoleGrantsController#show` loads the catalog for `current_customer.id` and a set of `"type:key:id:action"` strings from `role.role_permissions`. `GrantsEditorComponent` renders the matrix. `locked?` is `role.locked_grants?`. `owner_access?` is `role.key == "owner"`, and `granted?` is then true for every action. That is a display shortcut. The owner ability does not read these checkboxes.

`app/javascript/controllers/grants_editor_controller.js` `PATCH`es the update URL with JSON `{ role_grants: { added, removed } }`. Each item has `subject_type`, `subject_key`, `subject_id`, and `action`. `RoleGrantsController#update` permits those keys and calls `RoleGrants::Operation::Update`. `RoleGrants::Contract::Update` is a Reform form in `app/concepts/role_grants/contract/update.rb`. The controller does not call it.

`RoleGrants::Operation::Update` returns a failure when `role.locked_grants?`. `add_grant!` raises `PlatformGrantForbidden` when the actor is not `owner?` and the subject is type `Platform`, or type `Route` whose key `FlowchartVisibility.controller?` matches. An instance subject (`Entity` or `Page`) must have a row with that id and `customer_id` equal to `role.customer_id`. The permission is then `create!`, so `RolePermission` validations run. `remove_grant!` `destroy_all`s the matching type, action, key, and id.

`RolePermission::ACTIONS` is `read`, `create`, `update`, `destroy`, `manage`. Key-based types require `subject_key` and forbid `subject_id`. Instance types require `subject_id` and forbid `subject_key`. A check constraint requires one of key or id.

### Ability

`Ability#initialize` sets `@customer_id` from `user.customer_id` or, if the user is nil, `Current.customer_id`. A blank user gets an empty ability.

`platform_owner?` is `can :manage, :all` and `return`. Reserved `admin` (`has_reserved_role?(:admin)`) is `can :manage, :all`, then `cannot :manage` on `platform_owner_subjects` and on any symbol for which `FlowchartVisibility.route_subject?` is true (the symbol starts with `route_admin_maintenance_flowchart`), then `return`. Seeded admin `RolePermission` rows are not read on this path. The `cannot` list is wider than `PlatformProvider`: it also names `platform_announcements`, `platform_support_tickets`, `platform_customer_context`, `platform_sms`, `platform_captcha`, and `platform_ai_assistant`.

Reserved `member` adds `can :manage` for `member_route_subjects`:

- `route_member_dashboards`, `route_member_profiles`, `route_member_securities`, `route_member_mfa`, `route_member_trusted_devices`, `route_member_payments`, `route_member_pages`, `route_member_surfaces`
- `route_member_payments_payment_methods`, `route_member_payments_subscriptions`, `route_member_payments_subscription_cancellations`

`grants_for` loads `RolePermission.where(role_id: user.role_ids)`. `apply_grant` drops blank actions and actions outside `RolePermission::ACTIONS`. `manage` stays `:manage`. Other actions are symbols. Subject translation:

| `subject_type` | CanCan subject |
| --- | --- |
| `Route` | `:"route_<controller>"` with slashes as underscores. Skipped when `FlowchartVisibility.controller?` matches the key. |
| `Module` | `:"module_<key>"` |
| `FeaturePage` | `:"feature_<key>"` |
| `Platform` | `:"platform_<key>"` |
| `EntityClass` | the `Entity` class, no id and no `customer_id` |
| `PageClass` | the `Page` class, no id and no `customer_id` |
| `Entity` or `Page` | `can action, klass, id:, customer_id:`. Skipped when id or `@customer_id` is blank. `@customer_id` is the user's customer, including when a platform owner is viewing another tenant. Platform owners never reach this method. |

Because admin and platform owner return first, a custom role attached to an admin never changes `Ability`. `UserRoles::Operation::Assign` still allows custom roles next to exactly one reserved role. Those extra rows affect CanCan when the reserved role is `member`, because the member branch does not return before `grants_for`. They do not affect the URL role gate: `/admin` still requires `admin_or_owner?`.

`RouteAuthorization#authorize_route!` is `authorize! verb_action, :"route_#{controller_path.tr('/', '_')}"`. A new member controller has to be added to `Ability#member_route_subjects` or a member's implicit rule will not cover it. A new platform-only subject has to be added to `platform_owner_subjects` or the admin `can :manage, :all` will allow it at the CanCan layer. `RouteAuthorization` remains the path gate for `/admin/maintenance/platform`.

Flowchart steps that check ability call `Ability.new(user)` from the generated `authorize` element (`CodeGenerators::ElementTypes::Process::Security::AuthorizeGenerator`). That is the same class.

## Where to pay attention

### Route audit: assignment and authorization invariants

Supplemental-role CRUD adds no reserved role and cannot bypass the URL gate. `UsersRole` protects tenant equality, single reserved assignment, owner pinning and sole-reserved deletion. Mounted registration/provisioning paths atomically save account plus reserved role; raw model creation is a low-level API whose callers supply assignment explicitly. `Assign.call(user:, role_ids:, actor: nil, request: nil)` and guarded removal record actual role deltas through `Authentication::MutationAudit.roles`, transactionally with the mutation and logged after commit. See [Tenancy and roles](tenancy-and-roles) and [Authentication module](authentication-module).

:::note
Role model/operation and assignment request regressions were written but have not been run in this integration. Rejection handling and stable join identity are source-inspected, not runtime-certified.
:::

:::attention
`Ability#initialize` returns inside the `platform_owner?` branch and inside `has_reserved_role?(:admin)`. `RolePermissions::Operation::ResolveGrants` does not run for those users. The admin rows `Roles::Operation::SeedReserved` inserts are locked by `locked_grants` and are not the rules admin requests use.
:::

:::attention
`RoleGrants::Operation::Update` rejects `locked_grants` before it writes. `Roles::Operation::SeedReserved` sets `locked_grants` on `owner`, `admin`, and `member`. The grants editor can change a custom role. It cannot change the three reserved roles.
:::

:::attention
`RoleGrants::Operation::Update.owner_only_grant?` treats `Platform` and flowchart `Route` keys as owner-only, and the actor test is `actor.owner?`. `GrantsEditorComponent#owner_access?` only changes which boxes look checked for `role.key == "owner"`. Saving still goes through the operation.
:::

:::attention
`Ability#apply_grant` maps `EntityClass` to `can action, Entity` and `PageClass` to `can action, Page` with no `customer_id` condition. Instance rows go through `grant_instance`, which adds `id` and `customer_id: user.customer_id`. A class grant authorizes the class. Tenant scoping of the query stays in the controller or scope that loads the rows.
:::

:::note
`AccessPoints::Registry` has no `FeaturePage` provider. A `FeaturePage` permission can still be stored and `Ability` will translate it, but `GrantsEditorComponent` will not show a checkbox for it.
:::

## Key code

```ruby
# app/models/ability.rb
    if user.platform_owner?
      # Platform owner customer (81721200) — full access across every
      # tenant and every platform-scoped subject.
      can :manage, :all
      return
    end

    if user.has_reserved_role?(:admin)
      # Tenant admin — full access inside their own customer, but no
      # implicit access to platform-scoped subjects or flowchart routes.
      # Those surfaces are also gated by RouteAuthorization; these cannot
      # rules keep `authorize_route!` honest if a controller is remounted.
      can :manage, :all
      cannot :manage, platform_owner_subjects
      cannot :manage, Symbol do |subject|
        FlowchartVisibility.route_subject?(subject)
      end
      return
    end

    if user.has_reserved_role?(:member)
      # Tenant member — implicit access to every member route within
      # their own customer. Member routes don't carry per-action
      # role_permission rows; the URL-prefix gate (RouteAuthorization)
      # plus per-record ownership checks (Member::BaseController#
      # authorize_owned!) provide the actual security. This rule lets the
      # CanCan layer pass for any /:cid/member/* request.
      can :manage, member_route_subjects
    end

    grants_for(user).each { |g| apply_grant(g) }
```

```ruby
# app/models/ability.rb
  def grant_instance(action, klass, id)
    return if id.blank?
    return if customer_id.blank?

    can action, klass, id: id, customer_id: customer_id
  end
```

```ruby
# app/concepts/role_grants/operation/update.rb
      def self.owner_only_grant?(subject_type, subject_key)
        type = subject_type.to_s
        return true if OWNER_ONLY_SUBJECT_TYPES.include?(type)
        return true if type == "Route" && FlowchartVisibility.controller?(subject_key)

        false
      end
```

```ruby
# app/concepts/roles/operation/seed_reserved.rb
        return if admin_role.role_permissions.exists? # idempotent

        Current.access_points_catalog = nil
        catalog = AccessPoints::Catalog.for(customer_id: customer.id)
```

```ruby
# app/controllers/concerns/route_authorization.rb
  def authorize_route!
    authorize! verb_action, route_subject
  end

  def verb_action
    VERB_TO_ACTION.fetch(request.method, :read)
  end

  def route_subject
    :"route_#{controller_path.tr('/', '_')}"
  end
```

```ruby
# app/models/role_permission.rb
  ACTIONS = %w[read create update destroy manage].freeze

  KEY_BASED_TYPES      = %w[Route Module FeaturePage Platform EntityClass PageClass].freeze
  INSTANCE_BASED_TYPES = %w[Entity Page].freeze
```
