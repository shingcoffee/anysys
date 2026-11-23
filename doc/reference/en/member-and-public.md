---
title: "Member and public pages"
summary: "The member portal under /:cid/member and the public page at /:cid/page/:uuid, including the read-only admin preview of a member page."
---

## Summary

Member URLs live under `/:customer_id/member/`. `RouteAuthorization` admits `current_user.member?`. `Member::BaseController` adds `authorize_owned!` for a record that has `customer_id` and, when the record responds to `user_id`, that user. `Member::PagesController` and `Member::SurfacesController` call `allow_admin_member_preview!`, so a same-tenant admin or owner may GET the member render or a member surface.

`PublicPagesController` serves `/:customer_id/page/:uuid`. GET renders only a launched page whose audience set includes `public`. POST requires the viewer's audience, then sends the browser back to that audience's surface. `GET /:customer_id/actions/:action_key` is the public action router. How a page becomes HTML is [page rendering](page-rendering). The enroll pattern is [audience flows](audience-flows). Sign-in and the three roles are [authentication](authentication) and [tenancy and roles](tenancy-and-roles).

## Flow

```text
GET /:cid/member
        |
        |  RouteAuthorization: member?
        |  exception: allow_admin_member_preview! and GET/HEAD
        |             and admin_or_owner? (same tenant; TenantContext)
        v
Member::BaseController  (layout "member")
        |
        +-- DashboardsController     GET /:cid/member
        +-- ProfilesController       profile show / edit / update
        +-- SecuritiesController     security show
        +-- MfaController            setup + destroy on current_user
        +-- TrustedDevicesController destroy own device
        +-- PagesController          launched page, member in the set
        +-- Payments::*              own cards and card subscriptions
        +-- SurfacesController       /:cid/member/:key  (not builtin)
        +-- Pages source links       /:cid/member/pages/:id  (when enabled)

GET  /:cid/actions/:key Pages::ActionsController#show
        |  redirect to the page for page_runtime_audience
GET  /:cid/page/:uuid   PublicPagesController#show
        |  launched + public in the set, else 404
        |  counterpart -> 303
POST /:cid/page/:uuid   PublicPagesController#submit
        |  viewer's audience; refusal order otherwise
        v
public page | member page | admin page form
```

## Implementation

Public forms can additionally use chosen aliases, including root and nested paths, managed at `/:cid/admin/maintenance/page_shortcuts`. The publishing card displays the host-aware preferred alias when available, otherwise the canonical UUID URL. GET/HEAD and public-form POST aliases retain publication, the public-audience check, tenant and submission authorization; generated forms still submit to the canonical UUID endpoint. [Custom domains](custom-domains) are the optional domain on the customer profile, read live, with explicit-prefix priority and default customer 81721200; inactive customers return 404. Saving a new or changed domain requires a direct CNAME from that domain to `anysys.net`; failure blocks that save, while clearing the domain does not check DNS. Deployment publishes DNS and separately manages TLS/ingress/HostAuthorization. See [Page shortcuts](page-shortcuts).

`Member::BaseController` renders layout `member`. The layout reads that customer's `Website#theme` through `Websites::Theme`, the same tokens as `/:cid/site`. When the customer has no website, the public site defaults apply (light, azure, sans, spacious). The shell is a sticky top bar, a mobile sheet, and a short footer: site type, accent buttons, and hairline cards.

`Member::DashboardsController#show` is `resource :dashboard, path: ""`, so the member root is the dashboard. It greets from the hour and lists recent sign-in timestamps. `ProfilesController` updates `current_user` through `Member::Profiles::UpdateContract` with `:first_name`, `:last_name`, `:email`, and `:current_password`. `SecuritiesController#show` reads `mfa_required?`, the last sign-in, and `trusted_devices.active`. `MfaController` includes `Authentication::MfaEnrollment` and calls `Member::Mfa::Operation::Enable` and `Disable` with `current_user` and `params[:code]`. It never takes a target user id. `TrustedDevicesController#destroy` finds the device through `current_user.trusted_devices`.

`Member::PagesController#show` loads `Page.accessible.launched` and raises `RecordNotFound` unless `member` is in the exact set. A public-only page is not a member page. The preview opt-in does not widen that check.

`Member::Payments::PaymentMethodsController` and `SubscriptionsController` call `require_payments_module!` (`FeatureModules::Module.enabled?` for `"payment"`, otherwise `head :not_found`). Their comments state they are not preview surfaces. Payment methods use `for_current_customer` and `for_user(current_user.id)`, and the index lists `chargeable` rows. `setup_intent` calls `Payments::Activities::VaultCard` for provider `"stripe"`. `destroy` calls `Payments::Gateway.detach_token` and `mark_removed!`. If `detach_token` raises `Payments::Errors::Error`, the action still `mark_removed!` and redirects with the removed notice. Subscriptions have no `user_id`; the scope joins `Payments::PaymentMethod` owned by the current user. Non-card subscriptions (`payment_method_id` nil) are outside this list. `SubscriptionCancellationsController#create` calls `Payments::Activities::CancelSubscription`. Gateway behavior is [payments](payments).

`Member::SurfacesController` loads `Member::Surfaces.fetch` and 404s when the surface is disabled or the descriptor is a `Member::Sources::BuiltinSurface`. Builtin home, profile, and security are the dedicated controllers above. `Member::Sources::Builtin::ENTRIES` points at those paths. The routes declare `namespace :payments` before `resources :surfaces, path: ":key"` so `:key` does not swallow `/payments`. Index and show call `index.scope` with `current_user`. Show then `authorize_surface_record!`: an `EntityEntry` only has to match `current_user.customer_id` (owned rows such as enrollments have no `user_id` of their own); other records still go through `authorize_owned!`. `Entities::EntryDisplay.prime!` attaches labels for the member audience and the signed-in viewer.

### Entity surfaces

`Member::Sources::Entities` lists the tenant's own entities and shared entities (`customer_id` NULL) that are still visible (default scope). A **private** entity, a trashed entity, and a bridge that is not `:owned` yield no surface. Person and owned entities (including an owned Enrollment-style bridge) default on; an open entity defaults off and, when an admin turns it on, lists every tenant row (a catalog).

`Member::Surface#default_enabled?` is true unless `default_enabled` is `false`. `member_surface_settings.enabled` is nullable with no default: nil inherits. `SurfaceSetting#enabled_or(default)` and `NullSurfaceSetting#enabled_or(default)` replace a bare `enabled?`. `Member::EffectiveSurface#enabled?` is `@settings.enabled_or(@descriptor.default_enabled?)`. An overlay-only edit (label change, `enabled` not submitted) keeps nil and the default.

`Member::EntitySurfaceBuilder.call(entity:, customer:)` always scopes with `People::Ownership.scope(..., audience: "member", viewer: user)`. An admin previewing therefore sees only rows linked to themselves. Index columns, detail rows and search omit Calculated attributes, attributes with `visibility.member: false`, and the owner reference (it is always the signed-in member). `enabled_for` compares `user.customer_id` with the visited `customer.id`, so a shared entity still gates on the visitor's tenant. See [Person linking](person-linking).

### Pages source and row actions

`Member::Sources::Pages` (key `:pages`, position after entities, editable) adds one `BuiltinSurface` per launched, active tenant or shared page with `member` in the set: key `page_<id>`, label = page name, `path_seg` `pages/<id>`, `default_enabled: false`. Offline, trashed, admin-only and public-only pages are skipped. When a tenant page and a shared page share an action key and the member audience, only `Pages::ActionResolver.page_for` is listed. `Member::Navigation` builds `/:cid/member/pages/<id>`. `Member::SurfacesController` 404s `surfaces/page_<id>`. Locale: `admin_settings.member.sources.pages.name` "Pages" / 「页面」, `description` "Launched pages members can open." / 「会员可打开的已上线页面。」

An entity surface may set a row action (`row_action_key`, `row_action_field`, optional `row_action_label`; overlay keys on `Member::SurfaceSetting`). `Member::EffectiveSurface#row_action` returns `{ action_key:, field:, label: }` or nil. The member index (`SurfaceIndexComponent` / `IndexTableComponent`) renders a button on table rows and stacked mobile cards linking to `Pages::ActionLink.path` with `prefill[<field>]=<row id>`. Default label is `member.entity_surfaces.row_action_default` "Open". Settings copy lives under `comp_admin.member_surface.row_action_*` and `settings_people.member.row_action`. A row action without a field fails `admin_settings.errors.validations.row_action_invalid` ("The row action needs an action key and a target field."). Composite list tiles accept `config.row_action` and render a trailing link (`public_views.composite.row_action_default`). See [Audience flows](audience-flows).

`PublicPagesController` includes `PageRendering` and `CaptchaProtectable`, layout `"public_page"`. `find_launched_page` is `Page.accessible.launched.find_by!(public_uuid:)`. `authorize_public_view!` requires `visible_to?(:public)`. `authorize_submission!` requires `page.visible_to?(page_runtime_audience)`. Otherwise nothing is written: counterpart with `continue_here`, anonymous sign-in store, public `not_for_your_account`, or 404. `post_submit_path` follows `page_runtime_audience`. `Pages::PublicSubmission` runs the submit. Handoff uses `FeatureModules::Invocation.begin!`.

## Where to pay attention

### Route audit: self-service and overlay invariants

MFA setup enables only on POST; HEAD never claims an OTP or enables enforcement. A prefetch GET does not plant `otp_secret`. Profile/MFA credential conflicts use the localized `409 stale_credentials` response described in [Authentication](authentication). Member preview requires the actor's own tenant as well as GET/HEAD; card/subscription controllers do not opt in.

`Member::Settings::Operation::Update` resolves the entire editable-surface batch before writing under a customer lock. Omitted enabled/overlay values preserve saved settings; nil inherits defaults, blank display copy removes its override, and visibility `[]` hides all optional choices. Protected non-hideable descriptor fields remain visible. Descriptor scope and detail ownership remain authoritative.

Foreign sessions may open public content but resolve to public field audience in the visited tenant; the fixed platform owner retains the explicit runtime exception. Submission attribution, validators, options and handoff use that same tenant-aware policy without replacing the real session actor. Payment saved-card attribution remains same-tenant only. Submission/handoff share a rollback boundary; see [Page rendering](page-rendering) and [Module framework](module-framework).

Member MFA uses `Authentication::MutationAudit.mfa` to record committed enable/disable outcomes with actor and before/after facts; rejected, HEAD and no-op requests produce no success event.

:::note
Member MFA, overlays and public-submission regressions are authored, not executed here; browser journeys remain pending.
:::

:::attention
`RouteAuthorization.allow_admin_member_preview!` is called from `Member::PagesController` and `Member::SurfacesController`. The gate then allows same-tenant `admin_or_owner?` on GET and HEAD. POST, PATCH, PUT, and DELETE stay `member?`-only. `Member::Payments::PaymentMethodsController` and `SubscriptionsController` do not opt in. `TenantContext` still rejects a signed-in user who opens another customer's `/member` URL unless they are `platform_owner?`. Surface descriptor scopes run with `current_user`, so an admin preview cannot list another member's rows.
:::

:::attention
`Member::BaseController#authorize_owned!` raises `ActiveRecord::RecordNotFound` when `customer_id` differs from `current_user.customer_id`, or when the record has `user_id` and it is not `current_user.id`. `Member::PagesController` does not call it: a page is tenant-owned, and the gate is `accessible`, `launched`, and `visible_to?(:member)`.
:::

:::attention
`PublicPagesController#authorize_public_view!` 404s a page that does not include `public`, for every viewer. POST `#submit` uses the exact-set refusal rules and writes nothing when the viewer's audience is missing. After sign-in, Devise must return to `stored_submission_return_path`, not to `public_page_path`.
:::

:::attention
`Member::SurfacesController#load_surface` raises `RecordNotFound` when the descriptor `is_a?(Member::Sources::BuiltinSurface)`. Profile, security, and the member home stay on `ProfilesController`, `SecuritiesController`, and `DashboardsController`. The catch-all `path: ":key"` is declared after those routes and after `namespace :payments`.
:::

## Key code

```ruby
# app/controllers/concerns/route_authorization.rb
def allow_admin_member_preview!
  self.admin_member_preview_allowed = true
end
```

```ruby
# app/controllers/concerns/route_authorization.rb
if member_path?
  return if current_user.member?
  return if admin_member_preview_allowed && (request.get? || request.head?) &&
            current_user.admin_or_owner? && current_user.customer_id == current_customer_id

  raise CanCan::AccessDenied, t("common.errors.authorization.member_required")
end
```

```ruby
# app/controllers/member/base_controller.rb
def authorize_owned!(record)
  raise ActiveRecord::RecordNotFound unless record &&
    record.customer_id == current_user.customer_id &&
    (!record.respond_to?(:user_id) || record.user_id == current_user.id)
end
```

```ruby
# app/controllers/member/pages_controller.rb
class PagesController < BaseController
  include PageRendering

  allow_admin_member_preview!

  def show
    @page = Page.accessible.launched.find(params[:id])
    raise ActiveRecord::RecordNotFound unless @page.visible_to?(:member)

    prepare_page_render(@page)
  end
end
```

```ruby
# app/controllers/public_pages_controller.rb
def authorize_public_view!
  raise ActiveRecord::RecordNotFound unless @page.visible_to?(:public)
end
```
