---
title: "Page rendering"
summary: "How a launched page becomes ERB, which audience may open it, and where submit runs the bound flowchart."
---

## Summary

`Page#generate_content` delegates to `PageContentGenerator`, which returns an ERB string. `PageRendering#prepare_page_render` sets `@content` to that string and `@form_action` to `POST /:cid/page/:uuid`. Public, member, and admin renders all `render inline: @content`. GET on the public UUID requires `public` in the exact audience set. POST requires the viewer's audience (`page.visible_to?(page_runtime_audience)`). The submit service is [flowchart-runtime](flowchart-runtime). Builder storage is [page-builder](page-builder). Audience routes are also described in [member-and-public](member-and-public). The enroll pattern and the action router are [audience-flows](audience-flows).

## Flow

```text
Page#generate_content
        |
        v
PageContentGenerator#generate
        |
        |  layout == "composite" -> CompositePageRenderer#render_modules
        |  else wizard / single form / content-only ERB
        v
@content

GET  /:cid/actions/:action_key Pages::ActionsController#show
        |  public URL; redirect to the page for page_runtime_audience
        |  public visitor + live member page of the same action -> continuation=
GET  /:cid/page/:uuid          PublicPagesController#show
        |  launched + public in the set, else 404
        |  counterpart for viewer audience -> 303 (prefill kept)
GET  /:cid/member/pages/:id    Member::PagesController#show
        |  launched + member in the set
GET  /:cid/admin/maintenance/pages/:id/render
        |  PageRendersController#show
        |  launched + admin in the set
GET  /:cid/admin/pages/:page_id/form
        |  Admin::PageFormsController#show
        |  launched + admin in the set
        v
prepare_page_render -> @page_prefill + render inline: @content
        |
        |  form posts to public_page_submit_path
        v
POST /:cid/page/:uuid          PublicPagesController#submit
        |
        |  authorize_submission! exact set (refusal order below)
        v
Pages::PublicSubmission.call
        |
        |  success + handoff? -> FeatureModules::Invocation.begin!
        v
redirect to the surface that audience can open
```

## Implementation

Public `Page` records can also render through arbitrary chosen URL aliases, including `/` and nested paths; see [Page shortcuts](page-shortcuts). Alias GET/HEAD retains the existing launch checks and requires `public` in the audience set, plus the selected customer's resolved shared definition. Alias POST is supported for public forms through the same submission authorization. `Pages::DistributionCardComponent` presents three independent audience switches, an action key, siblings, and the host-aware preferred public address from `PageShortcuts::PublicPath.public_page`, with `SCRIPT_NAME` and the request origin for sharing. Generated `@form_action` remains the canonical UUID submission path.

Host selection uses the live [custom domain](custom-domains) stored on the customer. The platform owner sets it on the customer profile. Explicit customer prefixes take priority; inactive customers return 404 rather than another tenant's form. Domain changes need no restart. Saving a new or changed domain checks a direct CNAME from that domain to `anysys.net`; failure leaves the stored domain unchanged. Clearing the domain does not check DNS. Deployment publishes DNS and separately manages TLS/ingress/HostAuthorization; rendering does not rerun that DNS check.

A generated field is marked required when the page configuration sets `required: true`, or when the bound entity or bridge-entity attribute has a `presence` validator that applies to the viewing audience (`EntityAttributeAudience.applying_audiences`). `PageContentGenerator` passes `required: true` into the form-field component, which draws the asterisk on the label and sets the HTML `required` attribute. The wizard will not advance until those fields are filled. Calculated, computed, and readonly attributes are not marked from the schema. An audience the validator does not apply to does not get the schema marker; the page's own `required` flag still does.

`PageConfigurationHelpers#generate_content` is `PageContentGenerator.new(self).generate`. `generate` returns `""` when `configuration` is blank. When `configuration_json["layout"]` is `"composite"`, `generate_composite` builds `CompositePageRenderer` with `configuration_json["modules"]` and `customer_id: tenant_customer_id` (`Current.customer_id` or `page.customer_id`). It then calls `PageContentGenerator::CompositeRenderer#render_module` for each tile. Otherwise it reads `pages` and `form_settings` (falling back to `settings`). An empty `pages` array, or a single page whose `fields` are empty, returns `""`. No input fields produces content-only ERB. More than one page produces a wizard. One page produces a single form. `wrap_with_runtime_controller` wraps that markup in a `div` whose `data-controller` is `condition-runtime`, with the page `rules` and `calculations` JSON on data attributes.

`CompositePageRenderer` resolves owned/shared entities for an explicit customer, then queries entries only for that customer. It passes `scope: People::Ownership.scope(...)` into `FlowchartRuntime::QueryBuilder` for the viewer's audience, so a composite list of an owned entity on a member page shows only the viewer's rows and a public page of a person / owned / private entity lists nothing. Columns and sort fields use the effective audience-visible schema. Composite widths stack below `md`. Flowchart query steps never pass `scope:`; see [Flowchart runtime](flowchart-runtime).

Standalone composite specs establish `Current.customer`, clear the viewer and shared-resource mode, and restore the incoming context with `Current.set`. Their real entity/entry fixtures verify public column filtering, same-tenant admin-only values and an empty result when the active render tenant differs from the page's entity tenant. This tests the intended `Current.customer_id` precedence rather than changing the renderer to ignore the visited tenant.

`PageRendering` is included by `PublicPagesController`, `Member::PagesController`, `Admin::Maintenance::PageRendersController` and `Admin::PageFormsController`. `prepare_page_render(page, return_to: nil, quick_add: false, prefill: {})` sets:

`@form_action` to `public_page_submit_path(customer_id:, uuid: page.public_uuid, return_to:)`; a nil `return_to` adds no query parameter

`@content` to `page.generate_content`

`@page_quick_add` to `quick_add`, read by generated ERB through the `page_quick_add_enabled?` helper method

`@page_prefill` to the hash from `Pages::Prefill.values` (or the passed `prefill`). Generated inputs call `page_prefill_value(slug)`. Controllers pass `Pages::Prefill.values(page:, params:, audience: page_runtime_audience, viewer: page_runtime_user)`. Prefill keeps only fields visible to the audience, keeps a reference value only if it is one of the viewer's options, never prefills the owner reference, and never raises on malformed params. Submission validation is unchanged: prefill grants nothing.

Identity fields (`source: "identity"`) render as `identity[<key>]` (`PageContentGenerator::FormFields`). Email uses `html_type: email`. `FormParams#visible_field?` shows them to public and admin only; members get no identity inputs (`permit_identity` is `{}`). The generated form also emits hidden `_continuation` from `@page_continuation` when that ivar is present (`hidden_field_tag :_continuation, @page_continuation`). `PublicPagesController#assign_page_continuation` (GET `continuation`, captcha re-render `_continuation`) keeps the token only after `Pages::Continuation.verify` succeeds, so a forged query string never becomes HTML.

`public_pages/show.html.erb`, `member/pages/show.html.erb`, `admin/maintenance/page_renders/show.html.erb` and `admin/page_forms/show.html.erb` render that ERB with `render inline: @content` when it is present. The public controller uses layout `public_page`.

### Admin form fill-in

`GET /:cid/admin/pages/:page_id/form` (`admin_page_form_path(cid, page)`) is the admin data-entry surface for a form. `Admin::PageFormsController#show` loads `Page.accessible` (tenant-owned plus shared rows), 404s unless `launched? && visible_to?(:admin)`, and calls `prepare_page_render(@page, return_to: PageRendering::ADMIN_FORM_RETURN, quick_add: true)`. The view wraps the generated ERB in `AdminPageComponent` with the dashboard layout: breadcrumb **Forms** → page name, the page name as title, the page description (or a translated fill-in hint) underneath, and the form icon from `Admin::Pages::OpsTableComponent::FORM_ICON`. The card pads `p-4 sm:p-6`; the render logic is the same as the maintenance render, so wizards, rules, calculations and entity dropdowns behave identically. Fields required for the admin audience carry the asterisk on their labels, using the generator rule above.

The form still posts to `PublicPagesController#submit`, carrying `return_to=admin_form`. `post_submit_path` sends the admin back to `admin_page_form_path` only when `admin_form_return?` holds: the token equals `ADMIN_FORM_RETURN`, the viewer is `admin_or_owner?` on the same tenant (or the platform owner), and the page is `visible_to?(:admin)`. The parameter is a symbolic token, never a URL, so it cannot be used as an open redirect; any other value falls through to the existing audience rules.

### Entity quick add in dropdowns

An `entity_entries` dropdown's choices are rendered by `Entities::ReferenceOptions.call` in the generated template, for the viewing tenant (`Current.customer_id`, falling back to the page's customer), the viewer's audience, and `viewer: Current.user`. Rows come from `People::Ownership.scope`. Values are record ids; labels follow `Entities::ReferenceLabels`. A member page's dropdown to a person entity therefore lists only the member's own entry; a public page's dropdown to a person, owned or private entity renders no options; an open entity (a Course catalog) lists every tenant row. `query` lists (`PageContentGenerator::DynamicOptionsResolver`) pass the same `scope:` into `QueryBuilder`. `Entities::EntryDisplay` uses the same viewer: an in-scope reference shows its display field, an out-of-scope one shows the bare id (no label leak). Admin audience output is unscoped. The page-builder preview (`GET /:customer_id/admin/maintenance/pages/:page_id/field_options/:field_id`, and the same path under `maintenance/platform/pages`) finds the field anywhere on the page, including inside columns, and previews both sources as an admin of the URL tenant. See [Person linking](person-linking).

A select whose `dynamic_options.options_source` is `entity_entries` gets a last option **+ Add New** on admin renders (`/form` and the maintenance render, both `quick_add: true`). `PageContentGenerator::FormFields` emits `quick_add: page_entity_quick_add(entity_id, label_field)` for such selects unless the field boundary is read-only; multi-selects ignore it. `PageEntityQuickAddHelper#page_entity_quick_add` returns nil unless `page_quick_add_enabled?` and `current_user.admin_or_owner?`, then resolves the entity among the current customer's and shared active, non-bridge entities (memoized per render). It returns `Admin::Entities::QuickAddDialogComponent.opener(..., depth: 0)`: `{ url:, label:, title:, dialog: }`, where `url` is `new_admin_entity_entry_path(cid, entity, label_field:)` and `dialog` is `#entity-quick-add-dialog-0`. Public and member renders never set the flag, so their markup is unchanged.

`FormFields::SelectFieldComponent` with `quick_add:` appends a blank-valued option carrying `data-quick-add-option` after the other choices. It wraps the select in `<div class="contents" data-controller="entity-quick-add">` with the URL, the title and the `quick_add[:dialog]` outlet. The select is the `select` target and holds `change->entity-quick-add#change`. The add-new option is never the default: it comes last, and a list with no other choices keeps its blank placeholder even when `include_blank` is false. Without JavaScript, choosing it submits a blank.

`entity_quick_add_controller.js` restores the previous choice when **+ Add New** is picked and calls the outlet's `open({ url, title, onCreated })`. Both admin render views render `Admin::Entities::QuickAddDialogComponent` once at depth 0. It is a native `<dialog>` with the `entity-quick-add-dialog` controller. The controller loads the URL into the level's `entity-quick-add-frame-<depth>` Turbo frame and shows a loading template. It swaps in a failure template on `turbo:frame-missing` for its own frame only, ignoring the event when it bubbles up from a nested level's frame. It closes on Esc, backdrop click or Cancel, and clears the frame on close. The browser queues the `close` event, so a dialog reopened before it arrives is left as is. The dialog is full-screen on phones and a `max-w-3xl` card from `sm`. When the frame renders the created marker, the dialog closes. `onCreated({ id, label })` then selects the existing option with that value, or inserts a new option before **+ Add New**. It dispatches a bubbling `change` so rules and calculations rerun. The quick-add form's own reference dropdowns open a nested dialog one level deeper. The nesting and the frame responses are described in [Entity builder](entity-builder).

`PageVisibility::AUDIENCES` is `%w[admin member public]`. `visible_to?(audience)` is membership in the exact set. An unknown audience is false. A public-only page is not visible to `member` or `admin`.

`PublicPagesController#find_launched_page` loads `Page.accessible.launched` by `public_uuid`. `show` calls `authorize_public_view!`, which raises `RecordNotFound` unless `visible_to?(:public)`. A page without `public` 404s on `GET /:cid/page/:uuid` for every session. When the viewer's audience has a counterpart in the same action, `redirect_to_audience_counterpart!` sends a 303 to that surface and keeps sanitized `prefill`. `submit` calls `authorize_submission!`. `page_visible_to_current_viewer?` is `page.visible_to?(page_runtime_audience)`. A foreign-tenant admin or member is public. When the viewer's audience is not in the set, nothing is written and the first matching rule applies:

1. the page's action has a page for the viewer's audience: redirect there with `public_views.actions.continue_here` ("Continue with the form for your account.");
2. the viewer is anonymous and `member` or `admin` is in the set: store `stored_submission_return_path` (member surface if the page includes member, otherwise the admin render) and redirect to sign-in;
3. `public` is in the set: redirect back to the page with `public_views.actions.not_for_your_account` ("This form isn't available for your account.");
4. otherwise 404.

`post_submit_path` sends the viewer to the surface of their audience: member → `member_page_path`, admin → `admin_page_form_path`, else the preferred public location.

`submit` runs `Pages::PublicSubmission` inside `Invocation.with_submission`. After `FormParams.permit_parts`, `Pages::AudienceGuard` binds the owner and checks every other submitted reference (see **Owner binding** below). A `:rejected` result writes nothing and redirects back with the guard message (`common.errors.dynamic.profile_required`, `reference_not_allowed`, or `sign_in_required`). Missing flowchart returns method-not-allowed; other invalid/failed results redirect with the localized save error. For handoff, the activity completion block maps input and begins invocation before the submission savepoint commits. `start_page_handoff` re-permits through the same guard (`guarded_handoff_params`) so a forged owner reference cannot leak into the module mapping; a rejection hands over nothing. Handoff rejection rolls back business create/update and restores prior session invocation, then redirects with the module error; it never destroys an existing returned entry. See [Module framework](module-framework).

### Owner binding

`Pages::FormParams#visible_field?` (and `#required_field?`) hides the owner reference from the member audience, so a member Assignment page never renders the Student field. The submit boundary fills it.

`Pages::AudienceGuard.call(entity:, primary:, sections:, viewer:, audience:, customer_id:)` runs after permit and before the activity. Admin audience is a no-op. Unknown audiences are refused with `sign_in_required`.

- **Member.** The owner reference of the primary entity, and of each filled bridge section, is stripped from the permitted input and set to `People::Ownership.person_entry_id(viewer, person_entity_id)`. No linked entry: rejected with `common.errors.dynamic.profile_required` (`%{entity}` is the person entity's display name: "Your account isn't linked to a %{entity} profile yet."). When the page is bound to a person entity and a bridge section's owner *is* the back-reference to that new row (an Enrollment section on a Student page), `Pages::BridgeEntries` still writes the new primary id; the guard does not override it. Every other submitted reference whose target is a person, owned or private entity must be inside `People::Ownership.reachable_ids`; otherwise rejected with `common.errors.dynamic.reference_not_allowed` (`%{field}`: "%{field}: you can't choose this record."). A reference to an open entity is not checked beyond today's tenant validation. Back-references on bridge sections are stripped so a forged id never reaches the flowchart or a module handoff.
- **Public.** A primary of kind `owned` or `private` is rejected with `common.errors.dynamic.sign_in_required` ("Sign in to submit this form."), and so is any filled bridge section of those kinds. An empty bridge section is ignored and the primary may still save — a public Student page therefore never creates enrollments. Filled references follow the same `reachable_ids` rule; the public scope for person / owned / private is empty, so those picks are refused with `reference_not_allowed`.
- **Admin.** No binding and no extra checks.

`Pages::PublicSubmission` seeds `ctx[:current_person_ids]` from `People::Ownership.person_entry_ids` only for a same-tenant viewer. A signed-in user of another tenant is public here; their own tenant's person entries never enter this run. Anonymous and unlinked viewers get `{}`. See [Person linking](person-linking) and [Flowchart runtime](flowchart-runtime).

It also seeds `ctx[:identity]` from `FormParams.permit_identity` (string keys; only the identity fields placed on a person-entity page; public and admin only; members `{}`) and `ctx[:continuation]` from `Pages::Continuation.verify(params[:_continuation])` (symbol keys `{ action_key:, prefill: }` or nil). Identity never enters `ctx[:params]`. A missing, tampered, expired, wrong-purpose, or oversized token is nil; the submission still succeeds.

`post_submit_path` uses `page_runtime_audience`: member → `member_page_path`, admin → `admin_page_form_path`, otherwise the preferred public location. The `return_to=admin_form` token still marks a fill-in submit; it is a symbolic token, never a URL.

`Member::PagesController` includes `allow_admin_member_preview!`, loads a launched accessible page by id, and requires `visible_to?(:member)`. `PageRendersController#show` uses `definition_scope(Page)` and requires `launched?` and `visible_to?(:admin)`.

`Admin::Pages::OpsTableComponent` shares the entries list's toolbar, sortable headers and footer (count, numbered pages, rows per page; `per_page` is a URL param). Each row has a primary action. When the page is `launched? && visible_to?(:admin)` it is **Fill in**, which opens `admin_page_form_path` in the same tab; otherwise it is **Preview** in a new tab (`target="_blank"`, `rel="noopener noreferrer"`). Clicking the row (through `row-link`) or the page name runs that action, and the actions cell repeats it as a bordered icon button whose label shows from `lg` (`aria-label` "Fill in <name>"). Desktop widths live on the `th` cells: the page column takes the remaining space with a form icon tile, name and entity subtitle; Audience shows from `md`, Status is `w-28`, Updated shows from `lg`. Below `md`, rows become cards with the same icon, primary link, status, audience and time. Status shows as a Live / Draft pill.

`Admin::Pages::RowMenuComponent` renders the row menu in this order: **Manage access** (the `page-publishing` slide-over), then **Preview** and **Open in new tab**, then **Launch** or **Take offline** (shown in red). **Open in new tab** appears only for fill-in-able pages and opens `admin_page_form_path` with `target="_blank"`, `rel="noopener noreferrer"` and `data-turbo-frame="_top"`. Both owned and shared pages retain the visited customer prefix; shared pages resolve that customer's effective definition. **Preview** remains available for drafts.

`Page#launch!` in `PageLaunchLifecycle` raises `ActiveRecord::RecordInvalid` when `launch_errors` is present, then sets `launched: true`. `take_offline!` sets `launched: false`. Shared-page launch and audience updates are rejected off the platform prefix by `guard_shared_global_writes`. See [shared-resources](shared-resources).

### Identity fields and continuation

Account fields on a person-entity form are not entity attributes. They post as `identity[first_name]`, `identity[last_name]`, `identity[email]` and reach only `ctx[:identity]`. Generic record steps never write them. See [Page builder](page-builder) and [Flowchart runtime](flowchart-runtime).

`Pages::Continuation` signs `{ action_key, prefill }` with purpose `page_continuation` and a 3-day expiry. The token carries no URL and no customer id. `Pages::ActionsController` appends `continuation=` only when a public visitor is sent to a public page of an action that also has a live member page. After confirm or sign-in, `People::Claim.complete!` builds `/:cid/actions/:key` in the **user's** tenant. The public enrollment walkthrough is [Audience flows](audience-flows).

`PublicPagesController` includes `CaptchaProtectable` and defines `handle_captcha_rejection`, which re-assigns the continuation and re-renders `:show`. The class does not call `protect_with_captcha`. `PageContentGenerator` does not reference captcha. URL throttling, when `Captcha::UrlMatcher` returns a rule, is `Captcha::RackGate`. `Page#captcha_enabled?` reads `configuration_json["captcha"]["enabled"]`. Public registration pages that collect email should turn on captcha (the page flag plus a URL throttle on `/:cid/page/<public_uuid>`). See [Captcha](captcha).

### Reusable field component API

`FormFields::BaseFieldComponent` accepts `input_only: false` and extra HTML attributes. An explicit `id:` takes precedence over the generated `field_<parameterized field_name>` ID. With `input_only: true`, the base template renders the control without its outer wrapper/label, and `input_attributes` omits default themed input classes. The consuming adapter supplies its own `class:`, accessible label or legend, help/error markup, and `aria:` attributes such as `invalid` and `describedby`.

- `CheckboxFieldComponent` emits one checkbox using merged input attributes, the explicit `checked:` argument and `value: "1"`.
- `RadioFieldComponent` retains individual option labels, forwards merged input attributes, and compares selected values as strings. The first option uses the field ID; later options use `<id>_1`, `<id>_2`, etc. The adapter supplies the group fieldset/legend.
- `ToggleFieldComponent` retains switch chrome, forwards merged attributes to its checkbox, sets `value: "1"`, derives checked state from `checked?`, and uses its own `sr-only peer` input classes. It omits the default title/description and marks an invalid track when `aria: { invalid: "true" }` is supplied.

Boolean hidden `"0"` inputs and multi-select blank sentinels belong to the consuming form, not these controls. `Admin::Entities::EntryFieldComponent` uses this API and owns the linked labels/help/errors; see [Entity builder](entity-builder). `input_only` is a presentation option, not input filtering or authorization.

## Where to pay attention

### Route audit: rendered controls, parameter shapes and calculations

Generated Ruby arguments neutralize both Ruby interpolation and ERB delimiters; composite IDs/listen events are HTML-escaped. Runtime controls preserve password/hidden types (no password value echo or hidden label), multi-select and multiple-file `[]` names, disabled calculated fields, multipart form/wizard encoding and a valid wizard submit button.

`Pages::FormParams` filters rendering/submission against accessible schemas and the visited-tenant audience, including nested columns. Fields are read through `Page#input_fields` (columns flattened, layout elements dropped). For the member audience, `visible_field?` is false for the owner reference (it is filled server-side) and for identity fields. Primary `entity[slug]` and declared bridge `assoc[section][slug]` accept only writable scalar/array/upload shapes. Identity posts as `identity[<key>]` and is permitted separately (`permit_identity`); it never merges into `permit_parts`. `FormParams.permit_parts` returns `[primary, sections]`; `Pages::AudienceGuard` then rewrites the owner slugs and may reject the submit before anything is written. The activity always receives the (possibly rebound) primary attributes flat in `ctx[:params]` and the bridge sections in `ctx[:association_params]`, and `PublicSubmission` writes the bridge rows itself after the run creates the primary entry (see [Flowchart runtime](flowchart-runtime)). A missing or foreign target fails with `common.errors.dynamic.association_target_missing`; an unresolvable bridge section with `association_unavailable`. Base-model fields are metadata-only: they are not rendered, and nonempty/malformed `base[...]` is rejected before execution with `base_model_submission_not_supported`. There is no base-record resolver/write adapter. Dynamic option labels/values/order and composite columns enforce the same audience and the ownership row scope; inaccessible sources return empty options. Entity-entry dropdowns are bounded to 200.

An unbound UI preview renders only source-free controls inside disabled fieldsets and accepts no submitted values. An unresolved metadata binding or explicitly entity-sourced control cannot use that preview path. Generator UI specs use `PageRuntimeHelpers#build_runtime_ui_page` to bind a real tenant-owned entity with schemas for the declared inputs, including nested columns; security specs supply independent schemas so omitted, hidden and foreign attributes still exercise the production boundary.

`PageContentGenerator#generate_fields` drops a section the viewer can see none of. Fields split into runs at each `section` element. A run with at least one input field (fields inside columns count) where `Pages::FormParams#visible_field?` is false for all of them is removed, together with its heading, the divider right before it and its layout elements. Runs without input fields render as usual. This happens per request, for the viewer's audience. A divider whose label is the generator default (`maint_core.pages.generator.layout.divider` in any locale) renders without a label.

`Pages::RulesEngine#apply` removes client-authored calculation targets, evaluates dependencies topologically using server results and monotonically removes hidden inputs/recalculates dependents. Cyclic/duplicate/unavailable calculated dependencies stay absent rather than trusting submitted intermediates. Submission executes the effective tenant flowchart and launched accessible subflows; see [Flowchart runtime](flowchart-runtime), [Shared resources](shared-resources), [Member and public](member-and-public).

:::note
The 2026-10-11 targeted runtime verification passed 508 examples across 28 files on `storage/runtime_final_verify.sqlite3`. It executed generated ERB, real activity/subflow loading, submission and handoff rollback, upload-byte preservation, public audience isolation and settings journeys. System journeys used RackTest; the form-conditions system file checks configuration/generated markup, not browser JavaScript. Commands and evidence are recorded in `docs/audits/2026-10-11-rspec-verification.md` and `/tmp/opencode/runtime_final_verify.log`.
:::

:::attention
`EntityAttributeAudience.for_user(user, customer_id:)` grants a role audience only within the explicit visited tenant or to the fixed platform owner. Foreign admin/member sessions and missing tenant identity resolve to public across render, nested fields, dropdowns, composite lists, validators and retained-data handoff. `PageRendering#page_runtime_user` filters submission attribution; PublicSubmission also filters directly supplied viewers. The real session actor remains intact for Warden, page-level authorization and request auditing. Form actions use resolved `current_customer_id`, including aliases.
:::

:::attention
`PublicPagesController#authorize_public_view!` requires `Page#visible_to?(:public)` on GET. A page without `public` in the set 404s on `GET /:cid/page/:uuid` for every session. Those audiences use `Member::PagesController#show` and `Admin::PageFormsController#show` (or the maintenance render). When the action has a counterpart for the viewer, GET is a 303, not a 404.
:::

:::attention
A signed-in admin cannot submit a public-only page. `page_runtime_audience` is `admin`, which is not in the set, so POST writes nothing and follows the refusal rules (`continue_here` if an admin counterpart exists, otherwise `not_for_your_account`). Test the public form signed out, or add the admin audience.
:::

:::attention
`PageRendering#prepare_page_render` always sets `@form_action` to `public_page_submit_path`. Member and admin screens post to `PublicPagesController#submit`. `authorize_submission!` uses `page.visible_to?(page_runtime_audience)`. Anonymous failures that match rule 2 redirect to sign-in and store `stored_submission_return_path`. `return_to=admin_form` only changes where a qualifying admin lands after success; it grants no access.
:::

:::attention
Shared definition lookup admits NULL-customer entities, while all entry queries retain the explicit runtime tenant. Shared pages use `Current.customer_id`; missing tenant never widens entry access.
:::

:::attention
`PublicSubmission` requires a launched accessible flowchart and nonblank effective activity. `AudienceGuard` runs after permit and before the activity: a `:rejected` result writes nothing. Handoff runs after activity success but before business commit; `start_page_handoff` re-permits through the guard. Rejection rolls back new or existing record changes, never compensates by deleting the returned record.
:::

:::attention
Do not treat an empty member or public dropdown as "show everything". `People::Ownership.scope` fails closed: no viewer, another tenant's viewer, an unknown audience, or a missing owner link returns no rows. Flowchart runtime never uses that scope.
:::

:::attention
A tampered or expired continuation is nil, not an error. Registration still succeeds; after confirm the member lands on the default path instead of the remembered action. Do not treat a missing `_continuation` as a failed submit.
:::

## Key code

```ruby
# app/controllers/concerns/page_rendering.rb
  def prepare_page_render(page, return_to: nil, quick_add: false, prefill: {})
    @form_action = public_page_submit_path(customer_id: current_customer_id, uuid: page.public_uuid,
                                           return_to: return_to)
    @page_quick_add = quick_add
    @page_prefill = prefill
    @content = page.generate_content
  end
```

```ruby
# app/models/concerns/page_configuration_helpers.rb
  def generate_content
    PageContentGenerator.new(self).generate
  end
```

```ruby
# app/models/concerns/page_visibility.rb
  AUDIENCES = %w[admin member public].freeze

  def visible_to?(audience)
    key = audience.to_s
    return false unless AUDIENCES.include?(key)

    public_send("audience_#{key}")
  end
```

```ruby
# app/services/pages/form_params.rb
Pages::FormParams.permit(page: page, entity: page.entity,
                       params: params, audience: :public)
Pages::FormParams.permit_identity(page: page, entity: page.entity,
                                  params: params, audience: :public)
```

```ruby
# app/controllers/public_pages_controller.rb
  def assign_page_continuation
    token = params[:continuation].presence || params[:_continuation]
    return unless token.is_a?(String)

    @page_continuation = token if Pages::Continuation.verify(token)
  end
```

```ruby
# app/services/pages/continuation.rb
  def self.verify(token)
    # { action_key:, prefill: } or nil — never raises
  end
```

```ruby
# app/services/composite_page_renderer.rb
  def resolve_entity(entity_id)
    return nil unless entity_id && @customer_id
    Entity.find_by(id: entity_id, customer_id: [@customer_id, nil])
  end
```

```ruby
# app/controllers/member/pages_controller.rb
    allow_admin_member_preview!

    def show
      @page = Page.accessible.launched.find(params[:id])
      raise ActiveRecord::RecordNotFound unless @page.visible_to?(:member)

      prepare_page_render(@page)
    end
```
