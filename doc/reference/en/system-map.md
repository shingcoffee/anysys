---
title: "System map"
summary: "How tenants, URLs, builders, shared resources, and feature modules fit together."
---

## Summary

Anysys is a multi-tenant Rails application. A customer owns its records. Three reserved roles (`owner`, `admin`, `member`) decide which URL prefix a signed-in user may open. The product's own data model is not a set of fixed business tables. Customers shape records with the entity builder, behavior with the flowchart builder, and screens with the page builder. Feature modules (payments, email, and the rest) plug into that core through one registration file each.

Platform customer `81721200` is special. The owner of that customer can cross tenants and is the only user who can open platform maintenance, including this reference and the flowchart builder.

## Flow

```text
Request
  |
  +-- /:cid/admin/...                         admin or owner
  |     +-- /admin/maintenance/platform/...   platform owner only
  |     +-- /admin/maintenance/flowcharts...  platform owner only
  +-- /:cid/member/...                        member (admin may preview GET)
  +-- everything else                         public
        |
        v
RouteAuthorization  ->  TenantContext (Current.customer)
        |
        v
Customer-owned rows (customer_id)
        |
        +-- Entity (schema) ---- EntityEntry (property_data)
        +-- Flowchart ---------- ActivityGenerator --> Trailblazer::Activity
        +-- Page --------------- generate_content --> ERB, submit via public UUID
        +-- Constant
        |
        +-- FeatureModules::* enabled per customer
              entries | settings | maintenance toggle | platform settings
```

A launched page submits to `PublicPagesController`. That submission runs the page's flowchart. The flowchart is not interpreted step by step at request time. `ActivityGenerator` walks the graph and asks `CodeGenerators::GeneratorRegistry` for the Ruby that becomes a Trailblazer activity.

## Implementation

### Tenancy and roles

Almost every persisted row carries `customer_id`. `Authentication::User::PLATFORM_CUSTOMER_ID` is `81721200`. `platform_owner?` is true only when that user also has the reserved `owner` role. The owner role itself can be assigned only to `lingercoffee@gmail.com` on that customer (`eligible_for_owner_role?`).

`Customer` also has an enum named `role` (`owner`, `admin`, `member`). That column is not the signed-in user's role. User roles are `Role` and `UsersRole`.

`TenantScoped` fills `customer_id` on create and offers `for_current_customer` / `for_customer`. It does not install a `default_scope`. `Model.all` is every tenant until a caller scopes it. The comment at the top of `app/models/concerns/tenant_scoped.rb` that shows `Flowchart.all` as already scoped is stale.

`RouteAuthorization` classifies the path. Admin prefixes require `admin_or_owner?`. Member prefixes require `member?`, with one opt-in: a member controller may call `allow_admin_member_preview!` so a same-tenant admin or owner can GET the member screen. Platform and flowchart paths require `platform_owner?`. CanCan still runs afterwards. Platform owners receive `can :manage, :all`. Tenant admins also manage their tenant, then lose an explicit list of platform subjects.

There is no fourth role. Do not invent one in a controller or a checkbox.

### URL categories and module surfaces

Every route is admin, member, or public. A feature module then splits its admin UI into four places:

| Surface | Path | Who |
| --- | --- | --- |
| Entries | `/:customer_id/admin/modules/<module_key>` | customer users with module access |
| Customer settings | `/:customer_id/admin/settings/modules/<module_key>` | customer admins |
| Enable / disable | `/:customer_id/admin/maintenance/modules` | customer admin or owner |
| Platform settings | `/:customer_id/admin/maintenance/platform/module_settings` | platform owner, customer `81721200` |

The registered modules are `authentication`, `payment`, `email`, `sms`, `captcha`, `ai_assistant`, and `website`. Each one is a `FeatureModules::<Name>::Registration`. Billing, speech-to-text, announcements, and support tickets are real product surfaces, but they are not feature-module registrations. Their pages in this reference say which they are.

Two registrations do not follow the entries path. Captcha has no Modules index. The assistant UI is `/:customer_id/admin/assistant`, not `/:customer_id/admin/modules/ai_assistant`. The website list and editor live under `/:customer_id/admin/modules/website`. Public websites and public form pages use host-aware clean paths or chosen aliases through [Page shortcuts](page-shortcuts); canonical `/:customer_id/site` and form-page UUID endpoints remain available. Customer mappings are managed at `/:customer_id/admin/maintenance/page_shortcuts`.

### Custom domains

[Custom domains](custom-domains) are an optional `customers.domain` value on each customer, edited on the customer profile with the organization name. Customers is the single owner-only platform-sidebar destination. There is no domain management page. Live lookup chooses an unprefixed public request's tenant, explicit prefixes win, and inactive customers return 404. A new or changed domain requires a direct answer-section CNAME to `anysys.net`. `CustomDomains::CnameVerifier.call` returns `:verified` or `:unverified`. Commits take effect without restart; deployment publishes DNS and separately manages TLS, ingress, and host authorization.

### Builders

The [entity builder](entity-builder) stores a schema. Entries store JSON values that must match that schema. The [flowchart builder](flowchart-builder) stores a graph bound to an entity. The [page builder](page-builder) stores a layout whose fields post through a flowchart. The [website builder](website-builder) is a feature module for public sites, separate from maintenance pages. [Code generators](code-generators) are the vocabulary the flowchart compiler is allowed to emit.

### Shared resources

Entities, pages, flowcharts, and constants may be shared (`customer_id` NULL). Creating, renaming, launching, and deleting the global row happens only on `/81721200/admin/maintenance/platform/...`. A save on a tenant maintenance URL writes that customer's override and does not change the global definition. Reads go through `resolved_current_version`, which prefers the customer's head and otherwise the global default. See [shared resources](shared-resources).

### Shell

The admin home is [dashboard](dashboard). Sidebar sections are contributed by subclasses of `SidebarContributor` (`MaintenanceContributor`, and the contributors for modules, settings, pages, and entities). Platform leaves are added only for the platform owner on customer `81721200`.

### Production container

The production image is `ruby:3.2.8-alpine`, built from the root `Dockerfile`. `docker build` / `docker run`, the required `RAILS_MASTER_KEY` and `APP_HOST`, and the `/rails/storage` volume are on [Docker image](docker-image).

## Where to pay attention

:::attention
Do not read `current_version` for a shared entity, page, or flowchart when you mean "what this customer sees". `Versionable#resolved_current_version` applies the override head. A tenant-path save, including a save by the platform owner while the URL customer is `81721200`, writes an override line. It does not update the global default. Global identity changes belong on the platform prefix only.
:::

:::attention
`ActivityGenerator#generate` returns `nil` when the flowchart has no name or no elements, and it can return `nil` again after a structural validation failure. Callers must treat `nil` as "no activity", not as an empty string. Unsupported structural element types raise `ActivityGenerator::Error` instead.
:::

:::attention
Flowchart screens are owner-only even on a tenant URL. `FlowchartVisibility` and `RouteAuthorization#flowchart_namespace?` both apply. Hiding the sidebar link is not the authorization check. A public form still runs that flowchart on submit. Customers execute graphs they are not allowed to open.
:::

:::attention
New module URLs have to land in one of the four surfaces above. A vendor for payments, captcha, or email is a new file under that module's provider directory, not a new table or a new settings screen.
:::

## Key code

```ruby
# app/models/concerns/versionable.rb
def resolved_current_version(cid = Current.customer_id)
  line_cid = override_customer_id(cid)
  return current_version if line_cid.nil?
  customer_head_for(line_cid)&.current_version || current_version
end
```

```ruby
# app/services/activity_generator.rb
def generate
  return nil if flowchart.name.blank? || elements.empty?

  validation_errors = validate_structure
```

```ruby
# app/controllers/concerns/page_rendering.rb
def prepare_page_render(page)
  @form_action = public_page_submit_path(customer_id: params[:customer_id], uuid: page.public_uuid)
  @content = page.generate_content
end
```
