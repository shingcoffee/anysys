---
title: "Authentication module"
summary: "The mandatory feature module for tenant users, sign-up settings, and role grants, beside the platform sign-in stack."
---

## Summary

`FeatureModules::Authentication::Registration` is the feature module whose key is `authentication`. It is mandatory: every customer keeps it, and the maintenance toggle cannot turn it off. Enabling it provisions the first user. Customer admins then manage users and the audit ledger, and they edit self sign-up, password reset, roles, and grants.

Sign-in, Devise, MFA sessions, and route guards are the platform stack on [authentication](authentication). How a saved grant becomes a CanCan rule is [access grants](access-grants). This page is the module registration and its four admin surfaces. The registration base is [module framework](module-framework).

## Configuration checklist

At `/81721200/admin/maintenance/platform/module_settings/authentication`, choose the global customer-signup switch. Tenant settings separately control member signup, password reset, MFA, positive integer session timeout (minutes) and maximum failed attempts. `Authentication::Settings` and `User::TenantSecurityPolicy` enforce the latter two per account; missing/invalid/inactive values inherit Devise defaults. Anysys issues its own first-party tokens; see [OAuth](oauth).

## Flow

```text
Customer created / module enabled
        |
        v
FeatureModules::Authentication::Provisioner
        |  skip if any Authentication::User exists for the customer
        |  platform customer 81721200 -> owner role + pinned email
        |  every other customer -> admin role
        v
customer_feature_modules.configuration
        |
        +-- allow_registration       SignUpController
        +-- allow_password_reset     ForgetPasswordController
        +-- mfa_enabled              ModuleConfigsController
        |                            ModuleSubTogglesController
        +-- session_timeout          ModuleConfigsController -> account timeout_in
        +-- max_login_attempts       ModuleConfigsController -> Lockable hooks
        |
        v
Authentication::Settings
        |  signup/reset/MFA switches + timeout_in / maximum_attempts
        v
Public Devise controllers and Authentication::MfaObligation
```

The module declares no `before_request` hook. Admin and member sign-in stays on `RouteAuthorization`. Tenant MFA stays on `Authentication::EnforcesMfa`, which reads `Authentication::Settings`.

## Implementation

### Registration

`module_key` is `"authentication"`. `mandatory!` forces the `FeatureModules::Module` row to `active` and `required` on every `register!`. `entry_path` is `/auth/sign_in`. `default_exit` is the route `customer_home`.

`configuration_schema` exposes `mfa_enabled` (default false), `session_timeout` (default 30), and `max_login_attempts` (default 10). `configuration_keys` is that same list, so `Admin::ModuleConfigsController` may write those three keys and must not write `allow_registration` or `allow_password_reset`. Those two live only on their dedicated controllers.

### Four surfaces

| Surface | Path | Controller |
| --- | --- | --- |
| Entries | `/:cid/admin/modules/authentication/users` and `/events` | `Admin::Modules::Authentication::UsersController`, `UserActivationsController`, `UserMfaResetsController`, `UserTrustedDevicesController`, `EventsController` |
| Customer settings | `/:cid/admin/settings/modules/authentication` | `Admin::ModuleConfigsController` for MFA, timeout, and lockout keys; `SignUpController`, `ForgetPasswordController`, `RolesController`, `RoleGrantsController`, `UserRoleAssignmentsController` |
| Enable / disable | `/:cid/admin/maintenance/modules` | `Admin::Maintenance::ModulesController` lists it; `ModuleEnablementsController#destroy` refuses it because the module is required |
| Platform settings | `/:cid/admin/maintenance/platform/module_settings/:id` | `Admin::Maintenance::Platform::ModuleSettingsController` (no nested authentication namespace) |

`SettingsContributor#module_path` keeps this module's generic settings segment singular (`.../authentication`). The settings form posts to `key.pluralize` (`.../authentications`). `ModuleConfigsController#resolve_module_key` accepts the plural segment and singularizes it. Sidebar highlighting includes both paths.

`UsersController` lists users for `current_customer_id`. Create checks the `member` billing quota under a customer lock only when the requested role is member, then assigns a reserved role. Owner eligibility requires the pinned email/customer. Nested activation, MFA reset and device actions use the same tenant user scope. `EventsController` uses `Authentication::Event.for_customer`; the audit model is not `TenantScoped`. The user form prefills `first_name`, `last_name`, and `email` from the bound `@user`. The role selector explicitly selects the submitted `authentication_user[role]` when present on a validation rerender; otherwise it selects the user's reserved role from `@user.primary_role_key` (`member` for new users). Validation retries retain submitted non-password values. Password and confirmation fields are intentionally blank; leaving both blank on edit preserves the existing password.

`SignUpController` writes `allow_registration`. `ForgetPasswordController` writes `allow_password_reset`. Both call `CustomerAssignment#merge_configuration!`. `Authentication::Settings` returns false for those predicates when the assignment is missing or inactive, and it defaults sign-up to false and password reset to true.

`RolesController` creates supplemental custom roles through `Roles::Operation::Create`; reserved grants stay locked. `RoleGrantsController` loads the customer catalog and applies added/removed grant hashes. Assignment/removal and the single-user editor use `Authentication::MutationAudit.roles` for actual `role_granted`/`role_revoked` deltas; controllers no longer emit duplicate success events. See [Access grants](access-grants).

Platform configuration for this module is the shared overview / configuration / developer panes. `apply_customer_signup!` runs only when the module key is `authentication` and writes `Authentication::PlatformSettings#allow_customer_signup`. That singleton is the public customer sign-up switch (`Authentication::CustomerRegistrationsController`). It is separate from a tenant's `allow_registration`, which gates `Authentication::RegistrationsController` at `/:cid/auth/sign_up`.

### Provision and deprovision

`Provisioner.call` returns immediately when the customer already has any `Authentication::User`. Otherwise it creates a confirmed active user. Customer `81721200` gets `Authentication::User::PLATFORM_OWNER_EMAIL` and the system `owner` role. Other customers prefer `customer.contact` when it is an email, else `admin@<parameterized-name>.local`, and the system `admin` role. If that email is taken, the local part gains `+<customer.id>`. The platform-owner email is never rewritten.

`Deprovisioner.call` sets every active user for that customer to `inactive`. It does not delete rows.

## Where to pay attention

### Route audit: effective configuration and user mutations

`ForgetPasswordController#update` persists false for omitted/blank/whitespace `enabled`, preserving sibling config; a missing stored key defaults to true. Registration/MFA default to false. Timeout/attempt keys are enforced per account, including changes on an already loaded User; Devise class defaults remain unchanged.

Profile plus reserved-role updates are transactional; owner identity/assignment cannot be demoted, and self-deactivation or self-admin-MFA-reset is refused. Member creates consume the [Billing](billing) member counter; admin creates do not. See [Authentication](authentication) and [Access grants](access-grants).

:::note
Reset-toggle, admin-user and role-assignment regressions are authored, not run here. Supplemental-role CRUD remains an existing surface; no new reserved role is added.
:::

:::attention
`FeatureModules::Authentication::Registration` calls `mandatory!`. `Admin::Maintenance::ModuleEnablementsController#destroy` stops when `feature_module.required?`. `Admin::Maintenance::Platform::ModuleSettingsController#apply_status!` and `#apply_required!` return immediately for a mandatory module. `FeatureModules::Authentication::Deprovisioner` still marks users `inactive` if it is invoked. `FeatureModules::Authentication::Provisioner` then returns as soon as any user row exists, so those users stay inactive. The deprovisioner comment that re-enabling reactivates them does not match `Provisioner`.
:::

:::attention
Tenant MFA applies to admins/owners, while members enroll voluntarily. `Settings#timeout_in(default:)` and `#maximum_attempts(default:)` accept JSON integers or decimal integer strings greater than zero; invalid values inherit current class defaults. User instance hooks keep tenant policy out of global Devise configuration.
:::

:::attention
`FeatureModules::Authentication::Registration` documents that it has no per-request hook. A second MFA gate used to live on the registration and drifted from `Authentication::EnforcesMfa`. Sign-in for admin and member prefixes stays on [authentication](authentication). Do not add `before_request` here to re-check MFA.
:::

:::attention
`RoleGrants::Operation::Update` rejects a role with `locked_grants`. It rejects subject type `Platform`, and a `Route` whose key `FlowchartVisibility.controller?` accepts, unless `actor.owner?`. An instance grant (`Entity` or `Page`) must exist on `role.customer_id`. The editor is this module. The runtime that applies `RolePermission` rows is [access grants](access-grants).
:::

## Key code

```ruby
# app/services/feature_modules/authentication/registration.rb
mandatory!

def self.configuration_keys
  %i[mfa_enabled session_timeout max_login_attempts]
end

def self.provision!(customer)
  FeatureModules::Authentication::Provisioner.call(customer)
end

def self.deprovision!(customer)
  FeatureModules::Authentication::Deprovisioner.call(customer)
end
```

```ruby
# app/services/feature_modules/authentication/provisioner.rb
def self.call(customer)
  return if ::Authentication::User.where(customer_id: customer.id).exists?

  platform_owner_customer = customer.id == ::Authentication::User::PLATFORM_CUSTOMER_ID
```

```ruby
# app/services/authentication/settings.rb
def signup_enabled?
  module_active? && bool(config["allow_registration"], default: false)
end

def password_reset_enabled?
  module_active? && bool(config["allow_password_reset"], default: true)
end

def mfa_enabled?
  module_active? && bool(config["mfa_enabled"], default: false)
end
```

```ruby
# app/concepts/role_grants/operation/update.rb
OWNER_ONLY_SUBJECT_TYPES = %w[Platform].freeze

def self.call(role:, added: [], removed: [], actor: nil)
  return Result.new(success?: false, model: role,
                    errors: { base: [I18n.t("auth.errors.role_grants_locked")] }) if role.locked_grants?
```
