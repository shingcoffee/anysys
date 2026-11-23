---
title: "Customers"
summary: "Platform-owner customer CRUD. Domain is an optional field on the customer profile, saved with the organization name. A new domain requires a direct CNAME. Trash, restore, and acting as a customer remain."
---

## Summary

`Admin::Maintenance::Platform::CustomersController` is the catalog of every `Customer`. Create, update, soft-delete, trash, and empty-trash all live on `/admin/maintenance/platform/customers`. Restore is `CustomerRestorationsController`. Switching tenants is `CustomerContextsController`: it redirects, and `TenantContext` rebuilds the request from the new URL.

The HTML index at `/81721200/admin/maintenance/platform/customers` shows the customer table only. Customers remains the sole platform-sidebar destination.

Domain is an optional attribute of the customer, edited on the same profile form as the organization name and shown on the profile. See [Custom domains](custom-domains). There is no separate domain management page.

The platform owner customer is `Authentication::User::PLATFORM_CUSTOMER_ID` (`81721200`). `Authentication::User#platform_owner?` is `owner?` on that customer. The three reserved roles are `owner`, `admin`, and `member` on the user, described on [tenancy and roles](tenancy-and-roles). This namespace is already limited to `platform_owner?` by `RouteAuthorization`.

## Flow

```text
/81721200/admin/maintenance/platform/customers (customer table)
        |
        |  RouteAuthorization: platform_owner?
        v
CustomersController
        |
        +-- index / show / edit / create / update
        |     Customer (8-digit id; show unscoped, otherwise default_scope visible)
        |     after_create: roles/modules; after_create_commit: Billing::Onboarding
        |     HTML index: customer table only
        |     HTML show: organization (including domain), primary contact, and account
        |     HTML edit / profile-update 422: the same profile form, including domain
        +-- destroy -> Customer#soft_delete (status inactive; 81721200 refused)
        +-- trash -> Customer.only_deleted
        +-- empty_trash -> Customers::Purge.call(customers: Customer.only_deleted)
        |
        v
CustomerRestorationsController#update -> Customer#restore

PATCH /:cid/admin/maintenance/platform/customer_context
        |
        v
redirect /:target_id/admin/dashboard
        |
        v
TenantContext#set_current_tenant
        |
        |  other tenant and platform_owner?
        v
Current.platform_owner_context
Current.acting_as_customer
        |
        v
Platform::ContextBannerComponent
```

## Implementation

`Customer` includes `SoftDeletable` with `deleted_status: :inactive` and `RandomIdGeneratable` with `digits: 8`. `default_scope { visible }` hides inactive rows from the index. `status` is `active` or `inactive`. `tier` is `basic`, `standard`, `premium`, or `enterprise`. `industry` is the enum loaded from `config/industries.yml`. `locale` is optional and must be blank or one of `I18n.available_locales`.

Only `CustomersController#show` uses `Customer.unscoped.find`, so the platform owner can view an inactive customer's profile, including its domain. Edit, update and destroy retain the default-scoped lookup; inactive profile Edit/Update still return 404.

`after_create` seeds reserved roles and provisions required modules. `Billing::Onboarding.call` runs after creation commits and restores Current. `skip_authentication_provisioner` lets public signup attach its real admin; see [Authentication](authentication).

`customer_params` permits name/alias/domain/address/contact/phone/tier/industry/locale. Lists use `ModuleEntriesResolver`. Soft-delete and restoration check actual outcomes. Empty-trash delegates the complete deleted selection to `Customers::Purge`, reporting its real deleted count only on success. Status/tier/role/industry enums validate invalid values instead of raising on assignment.

The index columns are Customer, Customer ID, Domain, Users, Modules, and Created. Customer shows the organization name, a building mark, and the short name underneath when one is set. Customer ID and Domain use a monospace treatment; a blank domain is an em dash. Users and Modules are right-aligned counts. Created is a relative time, with the exact timestamp on hover. The short name is not its own column. Search matches name, short name, domain, and customer ID. The trash table still lists name, short name, users, modules, and created time.

### Customer profile

Show and Edit use `AdminPageComponent`. Show renders `Platform::Customers::ProfileComponent`: Organization and Primary contact in the main column, Account beside them from the `xl` breakpoint. Organization includes the name and the optional domain. An active account's header shows status and service-plan badges, plus Edit profile and Move to trash. Customer `81721200` has no Move to trash. An inactive account replaces those actions with Restore (`restoration_admin_maintenance_platform_customer_path`) and an in-trash notice; Edit and Move to trash are omitted because inactive Edit/Update already return 404. The profile does not display `Customer#role`.

Edit GET and profile-update HTML 422 render `CustomerFormComponent` as Organization, Primary contact, and Service plan. Organization includes the name and an optional Domain field. The form also includes a read-only customer ID and no role control. The form wrapper is `w-full max-w-3xl`. Saving the form writes `customers.domain` with the other profile fields. See [Custom domains](custom-domains).

The central platform path check requires actual outer PATH_INFO CID `81721200` for every action/format, including JSON and wildcard Accept. Soft-delete keeps domain binding; inactive public requests return 404, restore makes it routable, and physical deletion removes it with the row.

Show's title wraps instead of truncating. Edit profile and Move to trash — or Restore, when the account is inactive — stack on small screens. Long names and domains wrap. Both locales use paired I18n labels and native controls.

`CustomerContextsController#search` returns up to 20 `{ id, name }` rows, optionally filtered with `lower(name) LIKE`. `#update` reads the target from the POST body `customer_id` or from `target_customer_id` (body or query) and redirects to `/:id/admin/dashboard`. The path segment stays `81721200`. Act as links to `/81721200/admin/maintenance/platform/customer_context?target_customer_id=<id>`. `#destroy` calls `clear_platform_owner_context` and redirects to the signed-in user's own `/admin/dashboard`. `Platform::ContextBannerComponent` returns with DELETE on that same `81721200` path. `TenantContext#set_current_tenant` loads the customer from the first 8-digit path segment. When that customer is not the user's customer, only `platform_owner?` continues, via `setup_platform_owner_context`. `Current` holds `platform_owner_context`, `original_customer`, and `acting_as_customer` for that request. `Platform::ContextBannerComponent` renders when `Current.platform_owner_context?`.

The sidebar leaves are `MaintenanceContributor`, shown when the URL customer is `81721200` and `current_user.platform_owner?`. See [dashboard](dashboard).

## Where to pay attention

### Route audit: ownership-aware purge and truthful lifecycle outcomes

`Customers::Purge.call(customers:, delete_customers: true)` returns `success?`, `deleted_count`, dependency counts and error code. It enumerates customer-owned rows without default scopes, follows database and logical version/content/head edges plus polymorphic attachments/rich text, nullifies internal pointers, and deletes in dependency order in one transaction. Foreign surviving dependencies block the whole operation. Shared parents/platform credentials and content referenced by surviving lines are retained. Direct Customer destruction uses the same owned-record purge.

This is primary-database cleanup, not provider cancellation or guaranteed storage-file deletion: SQL deletes do not execute each child's callback. Review outstanding financial/provider work before relying on external cleanup. URL context switching remains request-local; [Billing](billing) history rules and [Shared resources](shared-resources) ownership remain separate constraints.

:::note
Purge, enum, restoration and platform-path regressions are authored, not executed here. No live dependency/schema or storage cleanup run is evidenced.
:::

:::attention
Central role and actual outer-path identity guards apply before customer lookup. Owner identity alone cannot authorize another CID's platform prefix; nested restoration target IDs and body/query values cannot replace `81721200`. See [Tenancy and roles](tenancy-and-roles).
:::

:::attention
`CustomersController#customer_params` omits `:role`. The customer detail page and `CustomerFormComponent` do not display or edit `Customer#role`. The column remains on `Customer`. The three reserved roles that authorize requests are `Authentication::User#owner?`, `#admin?`, and `#member?`, assigned through `UsersRole`.
:::

:::attention
Soft-delete is distinct from physical purge. Empty-trash succeeds only if the complete ownership-aware selection can be deleted; restore checks the validating result rather than always flashing success. `Customer#soft_delete` refuses customer `81721200`. `Customers::Purge` leaves that row in place when asked to delete customers (empty trash). Dependent cleanup before a hard destroy still runs. Restore is `PATCH /:cid/admin/maintenance/platform/customers/:id/restoration` so the outer `:customer_id` and the trashed customer's `:id` stay distinct.
:::

:::attention
Acting as another tenant is the URL, stored on `Current` for one request. `CustomerContextsController#update` only redirects. A later request to `/81721200/...` sets `platform_owner_context` back to false because `signed_in_other_tenant?` is false on the owner's own customer.
:::

## Key code

```ruby
# app/controllers/admin/maintenance/platform/customers_controller.rb
def customer_params
  params.require(:customer).permit(
    :name,
    :alias,
    :domain,
    :address,
    :contact,
    :phone,
    :tier,
    :industry,
    :locale
  )
end
```

```ruby
# app/controllers/concerns/tenant_context.rb
def set_current_tenant(customer_id, required)
  return unless customer_id.present?

  customer = Customer.find_by(id: customer_id)

  if customer && signed_in_other_tenant?(customer) && route_protection_required?
    return render_tenant_forbidden_error unless current_user.platform_owner?

    setup_platform_owner_context(customer)
  else
    Current.customer = customer
    clear_platform_owner_context
  end

  render_tenant_not_found_error(customer_id) if required && Current.customer.nil?
end
```

```ruby
# app/models/authentication/user.rb
PLATFORM_CUSTOMER_ID = 81_721_200

def platform_owner?
  owner? && eligible_for_owner_role?
end
```

```ruby
# app/controllers/admin/maintenance/platform/customer_restorations_controller.rb
class CustomerRestorationsController < BaseRestorationsController
  restorable finder: -> { Customer.only_deleted.find(params[:id]) },
             redirect: -> { admin_maintenance_platform_customers_path(current_customer_id) },
             flash_key: "maint_platform.flash.customers.restored"
end
```
