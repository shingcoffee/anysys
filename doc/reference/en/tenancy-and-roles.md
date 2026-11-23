---
title: "Tenancy and roles"
summary: "How an 8-digit customer id, Current, and the three reserved roles decide which URL a signed-in user may open."
---

## Summary

Every tenant is a `Customer` whose primary key is a random 8-digit id. The request copies that id into `Current` before any controller runs. Authorization then uses exactly three reserved roles on `Authentication::User` — `owner`, `admin`, and `member` — plus the path prefix. `platform_owner?` is the owner role on customer `81721200`, and that predicate is what opens `/admin/maintenance/platform` and flowcharts.

A second, editable role table (`roles` / `users_roles` / `role_permissions`) exists for grants. Those rows do not add a fourth reserved role and do not replace the path gate. See [Access grants](access-grants).

## Flow

```text
GET /:cid/...                         path_info, first segment = 8 digits
        |
        v
TenantContext#auto_set_tenant_from_path
        |
        |  Customer.find_by(id:)
        |  protected route + other tenant + signed in?
        |       platform_owner? -> Current.platform_owner_context
        |       anyone else     -> LandingPath (forbidden)
        v
Current.customer / Current.user
        |
        v
RouteAuthorization   (only if /:cid/admin or /:cid/member)
        |
        |  1. authenticate_user!
        |  2. enforce_route_role!
        |       platform or flowchart namespace -> platform_owner?
        |       /admin                          -> admin_or_owner?
        |       /member                         -> member?
        |         GET/HEAD + allow_admin_member_preview! -> admin_or_owner?
        |  3. authorize_route!  -> Ability
        v
Authentication::EnforcesMfa
        |
        v
controller action
```

Public URLs skip protected-route authorization and permit signed-in visitors from another tenant. They still receive the URL/host tenant. Publication, page audiences and protocol proof remain action-specific. Sign-in is described in [Authentication](authentication). The action router `GET /:cid/actions/:action_key` is a public URL; see [Audience flows](audience-flows).

[Page shortcuts](page-shortcuts) additionally select a public tenant from an exact `customers.domain` database binding or the default customer 81721200 when no customer prefix is present. Explicit customer prefixes win. Inactive bound customers return 404 without fallback. Trusted route context uses the established `set_current_tenant` guard; session state and submitted/query customer fields do not choose the destination. Shortcut management remains under `/:cid/admin/maintenance/page_shortcuts`, admin/owner-only and scoped to that URL customer even for an owner.

[Custom domains](custom-domains) are an optional customer profile attribute, not another route/grant subject. All protected platform actions/formats require the actual outer PATH_INFO CID `81721200`, even for the owner. A new/changed domain requires a direct CNAME to `anysys.net` and never relaxes admin/member ownership. See [Customers](customers).

## Implementation

### Customer id

`Customer` includes `RandomIdGeneratable` with `random_id digits: 8`, so new ids fall between `10000000` and `99999999`. `TenantContext::TENANT_PATH_PATTERN` and `RouteAuthorization`'s admin and member patterns all require exactly eight digits. The platform customer is the fixed id `Authentication::User::PLATFORM_CUSTOMER_ID` (`81_721_200`).

`Customer` also declares `enum :role, { owner: 0, admin: 1, member: 2 }`. That column is tenant metadata. Public sign-up writes `role: :admin` from `Authentication::CustomerSignup`. No application code calls `Customer#owner?`, `Customer#admin?`, or `Customer#member?` to admit a request. The predicates that `RouteAuthorization` uses live on `Authentication::User`.

On create, `Customer` calls `Roles::Operation::SeedReserved`, then `enable_required_feature_modules`, which activates every `FeatureModules::Module.required` row and runs that module's `provision!`. The seven module keys registered in `app/services/feature_modules` are `authentication`, `payment`, `email`, `sms`, `captcha`, `ai_assistant`, and `website`. Only `FeatureModules::Authentication::Registration` calls `mandatory!`. How a module is toggled is covered in [Module framework](module-framework).

### Request tenant

`ApplicationController` includes `TenantContext` first. `auto_set_tenant_from_path` matches `request.path_info` (not `request.path`, which prepends `SCRIPT_NAME`). On protected routes, when the signed-in user's customer differs:

- `platform_owner?` sets `Current.customer` to the URL tenant, `Current.platform_owner_context` to true, `Current.original_customer` to the owner's own customer, and `Current.acting_as_customer` to the URL tenant. `ApplicationController#platform_elevated_access?` is that flag plus `platform_owner?`.
- Every other signed-in user is redirected by `render_tenant_forbidden_error` to `Authentication::LandingPath.for(current_user)`.
- An anonymous request is not "another tenant". `Current.customer` becomes the URL customer and later filters decide whether sign-in is required.

`TenantScoped`, included by `Authentication::User` and by definition models, `belongs_to :customer, optional: true` and, on create, copies `Current.customer_id` when the row has none. `Current.shared_resources_mode` and `skip_tenant_customer_assignment!` leave `customer_id` null so a shared row can be stored. Reads of a shared page, flowchart, or entity go through `Versionable#resolved_current_version`: the customer's override head when one exists, otherwise the global default. Tenant-path saves write that override. The platform prefix is the only place that mutates the shared row. Details are in [Shared resources](shared-resources).

`Current.page_shortcuts_lookup` is a presentation-only, immutable identity snapshot for one explicit customer, installed by the public website/Page controllers' around-action. Public-link helpers use it only when its customer ID matches their explicit argument; routing and authorization never infer a tenant from it. It is restored after rendering/submission and reset between requests. See [Page shortcuts](page-shortcuts).

Isolated specs that set `Current` directly use `after { Current.reset }` teardown, including when assertions fail. Do not use `Current.customer_id = nil` for cleanup: the ID setter ignores blank values and leaves the previous tenant in place.

### Reserved roles

Service specs that establish a tenant must use a block-scoped `Current.set` and restore it after each example, including examples that deliberately switch tenants. The AI reply/cancellation specs follow this boundary. Specs exercising real commits cannot rely on fixture rollback: `spec/jobs/billing/finalize_invoice_job_spec.rb` tracks and destroys only the platform customer/owner it creates for manual settlement, preserving an existing owner's credentials and records. The platform-context, public-path and HomeSite fixtures still create their own customer `81721200`; an unexpected existing row remains an isolation failure.

`Authentication::User::RESERVED_ROLE_KEYS` is `owner`, `admin`, `member`. `owner?`, `admin?`, and `member?` are true when `reserved_role_keys` contains that key. `reserved_role_keys` is the `key` of each associated `Role` with `system: true`. `primary_role_key` walks the same list in that order and falls back to `"member"` when the user has no reserved role.

`admin_or_owner?` is `admin? || owner?`. `platform_owner?` is `owner? && eligible_for_owner_role?`: customer `81721200` plus case-insensitive pinned email `lingercoffee@gmail.com`. Owner identity and assignment cannot be changed after persistence.

`UsersRole` refuses an `owner` system role unless `eligible_for_owner_role?` is true, and it refuses a role whose `customer_id` differs from the user's. `Roles::Operation::SeedReserved` creates the three system roles for every customer with `locked_grants: true`. `FeatureModules::Authentication::Provisioner` attaches `owner` on customer `81721200` and `admin` on every other customer, and only when that customer has no users yet. Public customer sign-up sets `skip_authentication_provisioner` and assigns `admin` itself, so the provisioner does not also create a generated admin.

`Authentication::LandingPath` sends `primary_role_key == "member"` to `member_dashboard_path`. Everyone else with a customer id goes to `admin_assistant_path`. A user with no role row therefore lands on the member surface, where `enforce_route_role!` denies them.

### URL categories

`RouteAuthorization` is included from `ApplicationController` and is the only prefix gate. Controllers under these prefixes do not add their own `authenticate_user!` or role `before_action`.

| Path | Who passes `enforce_route_role!` |
| --- | --- |
| `/:cid/admin/maintenance/platform` and any controller path starting `admin/maintenance/platform/` | `platform_owner?` |
| `/:cid/admin/maintenance/flowcharts` and any controller `FlowchartVisibility.controller?` matches (the path contains `flowchart`) | `platform_owner?` |
| `/:cid/admin/maintenance/entity_domains`, `.../entities/:id/domain_membership`, and any controller `EntityDomainVisibility.controller?` matches | `platform_owner?` |
| other `/:cid/admin` | `admin_or_owner?` |
| `/:cid/member` | `member?`. Same-tenant `admin_or_owner?` may `GET`/`HEAD` when the controller called `allow_admin_member_preview!` |
| anything else | no role filter |

`Member::PagesController` and `Member::SurfacesController` call `allow_admin_member_preview!`. Writes stay member-only. `TenantContext` still blocks a different tenant. After the role check, `authorize_route!` calls CanCan `authorize!` with the verb mapped to `:read`, `:create`, `:update`, or `:destroy` and the subject `:"route_#{controller_path}"` (slashes become underscores). CanCan builds that ability with `Ability.new(current_user)`. What the ability contains is [Access grants](access-grants).

`FlowchartVisibility.allowed?` is the same `platform_owner?` test for sidebar, assistant mentions, and editor links. HTTP denial is still `RouteAuthorization`, not a second filter on the flowchart controller. Entity domains follow the same pattern through `EntityDomainVisibility`. `OwnerOnlySurfaces` lists both surfaces and is the single list read by `RouteAuthorization`, the `Ability` deny rule, `AccessPoints::RouteProvider`, and `RoleGrants::Operation::Update`; add a new owner-only surface there. See [Entity builder](entity-builder).

The dashboard's `MenuRegistry` uses `platform_owner?` to show the top-level Maintenance navigation entry in both the desktop menu and mobile drawer. A tenant admin cannot see that entry, even under customer `81721200`; navigation visibility does not narrow the existing `admin_or_owner?` authorization for tenant maintenance URLs. See [Dashboard](dashboard).

HTML `CanCan::AccessDenied` redirects to `Authentication::LandingPath`. If that path is the path that was just denied, the response is `403` plain text so the redirect cannot loop. JSON is `{ error: "access_denied" }` with status `403`.

Member record checks are a third layer: `Member::BaseController#authorize_owned!` raises `ActiveRecord::RecordNotFound` unless `customer_id` matches and, when the record has `user_id`, that id matches `current_user.id`. See [Member and public](member-and-public).

## Where to pay attention

### Route audit: path, actor and attribution invariants

`enforce_platform_path_identity!` reads the outer eight-digit PATH_INFO segment, independent of nested customer IDs, query/body input and mount prefixes. Wrong platform prefixes return 404 for HTML and JSON. Public foreign sessions do not select the destination tenant; `current_tenant_user` returns a user only when their customer matches the URL tenant, including for an owner. Use it for saved-card/member attribution.

Member preview additionally requires `current_user.customer_id == current_customer_id`; owner cross-tenant authorization does not widen it. Public field privilege uses `EntityAttributeAudience.for_user(user, customer_id:)`, admitting only same-tenant roles or the fixed owner and retaining foreign visitors as public. Reserved joins replace in place and cannot be removed standalone; mounted account creation atomically assigns one, while raw User creation remains a low-level caller responsibility. See [Access grants](access-grants), [Payments](payments), [Member and public](member-and-public).

:::note
Path, mounted/format, public-audience and role boundaries are source-documented. On 2026-10-12 the parallel RSpec suite passed **25,266 examples, 0 failures**. Runtime acceptance outside that suite still needs its own evidence.
:::

:::attention
`Authentication::User#platform_owner?` requires owner and the pinned customer/email. An admin of customer `81721200` fails it. The centralized role filter and platform path-identity check are separate boundaries.
:::

:::attention
Match `request.path_info` in `TenantContext#tenant_path` and `RouteAuthorization#authorization_path`. `request.path` includes `SCRIPT_NAME`. A mount prefix would miss both `TENANT_PATH_PATTERN` and the admin/member regexes, leave `Current.customer` unset, and skip authentication on `/:cid/admin`.
:::

:::attention
`RouteAuthorization.allow_admin_member_preview!` admits `admin_or_owner?` only when `request.get?` or `request.head?`. `POST`, `PATCH`, `PUT`, and `DELETE` on that member controller still require `member?`. `Member::PagesController` and `Member::SurfacesController` are the opt-ins in the tree today.
:::

:::attention
`UserRoles::AssignmentPolicy` and `Authentication::OwnerIdentity` protect owner assignment and identity. Eligibility requires customer `81721200` and `lingercoffee@gmail.com`; `Customer#role` does not authorize requests.
:::

:::note
`Authentication::EnforcesMfa` runs after `RouteAuthorization` because `ApplicationController` includes it last. The MFA decision itself is documented in [Authentication](authentication).
:::

## Key code

```ruby
# app/models/authentication/user.rb
    PLATFORM_CUSTOMER_ID = 81_721_200
    PLATFORM_OWNER_EMAIL = "lingercoffee@gmail.com"

    # Check if user belongs to platform owner customer (81721200) with owner role.
    # These users can access platform-wide management features.
    def platform_owner?
      owner? && eligible_for_owner_role?
    end

    # The owner role is reserved for a single, specific user. See AGENTS.md
    # "Reserved Roles & Access Rules". Used by UsersRole to gate assignment.
    def eligible_for_owner_role?
      customer_id == PLATFORM_CUSTOMER_ID &&
        email.to_s.downcase.strip == PLATFORM_OWNER_EMAIL
    end
```

```ruby
# app/controllers/concerns/route_authorization.rb
  def enforce_route_role!
    if platform_namespace? || flowchart_namespace?
      return if current_user.platform_owner?
      raise CanCan::AccessDenied, t("common.errors.authorization.platform_owner_required")
    end

    if admin_path?
      return if current_user.admin_or_owner?
      raise CanCan::AccessDenied, t("common.errors.authorization.admin_required")
    end

    if member_path?
      return if current_user.member?
      return if admin_member_preview_allowed && (request.get? || request.head?) &&
                current_user.admin_or_owner? && current_user.customer_id == current_customer_id

      raise CanCan::AccessDenied, t("common.errors.authorization.member_required")
    end
  end
```

```ruby
# app/controllers/concerns/tenant_context.rb
    if customer && signed_in_other_tenant?(customer) && route_protection_required?
      return render_tenant_forbidden_error unless current_user.platform_owner?

      setup_platform_owner_context(customer)
    else
      Current.customer = customer
      clear_platform_owner_context
    end
```

```ruby
# app/services/user_roles/assignment_policy.rb
UserRoles::AssignmentPolicy.validate(join)
UserRoles::AssignmentPolicy.removable?(join)
```

```ruby
# app/models/concerns/versionable.rb
  def resolved_current_version(cid = Current.customer_id)
    line_cid = override_customer_id(cid)
    return current_version if line_cid.nil?
    customer_head_for(line_cid)&.current_version || current_version
  end
```
