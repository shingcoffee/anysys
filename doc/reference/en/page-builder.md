---
title: "Page builder"
summary: "How the maintenance page editor stores a form, launches it, and binds it to a compiled flowchart."
---

## Summary

A maintenance page is a versioned form definition, not a marketing site. The operations list at `/:customer_id/admin/pages` calls these records **Forms** (including its title, sidebar, table, and search). The editor lives at `/:customer_id/admin/maintenance/pages` and, for shared pages, at `/:customer_id/admin/maintenance/platform/pages`. The public visitor path is `GET` and `POST /:customer_id/page/:public_uuid`, documented in [Page rendering](page-rendering). The Website feature module is a different composer; see [Website builder](website-builder).

`Page` stores identity on the parent (`name`, `description`, `audience_admin`, `audience_member`, `audience_public`, `action_key`, `launched`, `public_uuid`, `content`, `customer_id`) and stores the form on the versioned `configuration` attribute. `reload_definition_from_head!` loads that JSON from `Versionable#resolved_current_version`. The configuration object needs `pages` (an array of sections, each with a `fields` array) and `metadata` (`entity_id`, `entity_name`). The editor also writes `form_settings`, `wizard_settings`, `rules`, `calculations`, `theme`, and `captcha`. `form_settings.flowchart_id` is the binding to a launched flowchart. Customers never open the flowchart editor; the page still names that id.

On a normal save, `PagesController#update` writes `content` from `PageContentGenerator`. A tenant override of a shared page saves `configuration` only and leaves the parent `content` column alone. `PageRendering#prepare_page_render` sets the form action to the public UUID submit path and sets `@content` from `page.generate_content`.

## Flow

```text
page-builder (app/views/admin/maintenance/pages/_editor.html.erb)
        |
        |  PATCH page[configuration] + page[updated_at]
        v
Admin::Maintenance::PagesController#update
        |  409 if the client stamp is stale
        |  tenant override: configuration only
        |  otherwise also content = generate_content
        v
PageConfigurationContent.store!
        |
        v
PageVersion --> current_version_id
            or page_customer_heads

Launch (platform prefix for a shared page)
        |
        v
Page#launch!   (entity active, fields present, rules and calculations intact)
        |
        v
launched = true

Admin render / public GET
        |
        v
PageRendering#prepare_page_render
        |  @form_action = public page UUID submit path
        |  @content     = page.generate_content
        v
POST /:customer_id/page/:uuid
        |
        v
Pages::PublicSubmission
        |  form_settings.flowchart_id
        |  Pages::SubmissionProcess (Flowchart.accessible.launched)
        v
compiled activity     see flowchart-runtime
```

Preview (`PagePreviewsController`) renders either the posted configuration through `PageContentGenerator` or the stored `content`, with the same public submit path when `public_uuid` is present. It uses layout `preview` and does not require the page to be launched.

## Implementation

### Model

`Page` includes `Versionable` (`PageVersion`, `PageConfigurationContent`, snapshot `:configuration`, `page_customer_heads`), `PageVisibility`, `PageEntityBinding`, `PageLaunchLifecycle`, and `PageConfigurationHelpers`. Soft delete uses status `:inactive`. `name` validates presence and length (`1..100`) without uniqueness or slug generation, so multiple pages may share the same name. `before_create :assign_public_uuid` sets `public_uuid` from `SecureRandom.uuid`. `configuration_json` defaults missing `rules` and `calculations` to empty arrays.

`PageEntityBinding#entity` looks up `metadata["entity_id"]`. A shared page searches `Entity.shared`. A customer-owned page searches its own entities plus shared entities. `entity_id=` writes `entity_id` and `entity_name` into metadata. A shared page must bind a shared entity (`shared_page_binds_shared_entity`). Create runs `Pages::ConfigurationComposer` with `page[layout_template]` and `page[theme_preset]`, which fills field pages from the bound entity when that entity yields fields. Quota item key is `"page"`, skipped for a shared create.

`Page#fields` flattens `pages[].fields`. `generate_content` delegates to `PageContentGenerator`, which maps HTML input types to `FormFields::*Component` classes and returns ERB. `handoff?` is `form_settings.after_submit == "handoff"`. Captcha is `configuration_json["captcha"]["enabled"]`; which vendor renders is `Captcha::ProviderSettings.active`.

`PageVisibility::AUDIENCES` is `%w[admin member public]`. `visible_to?(audience)` is membership in the exact set; an unknown audience is false. `visible_audiences` returns the set in that order. `Page.for_audience(audience)` is the SQL scope. A page needs at least one audience (`page_audiences_blank`). `pages.action_key` is a nullable string matching `/\A[a-z][a-z0-9_]{1,62}\z/` (`page_action_key_invalid`); blank stores nil. `Pages::VisibilityContract` posts `page[visible_audiences][]` and `page[action_key]`, maps them onto the three booleans, and re-runs dropdown, required-field, `audience_errors` and `action_errors` when a live page gains an audience or changes its key. Save holds `Customer.lock.find(page.customer_id || Authentication::User::PLATFORM_CUSTOMER_ID)` so two concurrent launches cannot both take the same action slot. See [Audience flows](audience-flows).

`Page#launch!` raises `ActiveRecord::RecordInvalid` when `launch_errors` is non-empty: the bound entity must be active, `fields` must not be empty, rule condition and action ids must still exist, calculation `target_field_id`s must still exist, and the checks under "Launch checks" must pass. `take_offline!` sets `launched` to false. `PageLaunchesController` and `PageVisibilitiesController` both call `guard_shared_global_writes`, so a shared page is launched, taken offline, or retargeted only on the platform prefix.

### Launch checks

`launch_errors` also runs `Pages::LaunchChecks`. It reads fields through `Page#input_fields` (columns flattened) for every audience in `visible_audiences`, against the tenant's current entity definition:

- **Dropdowns.** An `entity_entries` field blocks launch when its target is missing or trashed (`reference_target_inactive`), or when its display field can't label a choice for an audience (`reference_label_hidden`, which names the audience).
- **Required fields.** Every attribute with a `presence` or `acceptance` validator that applies to an audience (`EntityAttributeAudience.applying_audiences`) needs a field on the form (`required_field_missing`). The entity's own attributes match by `property_slug` on fields whose source is neither `base_model`, `bridge`, nor `identity`. A link entity with at least one field on the form is checked against fields with its `source_section` (the link's id or name), skipping the reference back to the entity (`required_link_field_missing`). Calculated and computed attributes never count, and a default value doesn't satisfy the check, because submissions don't apply defaults. The owner reference is exempt for the member audience (`owner_filled_for?`): `FormParams` hides it and the submit boundary fills it.
- **Ownership audiences.** `LaunchChecks#audience_errors` runs on launch and when an audience is added to a live page. A page bound to an owned bridge may have only the member audience (`bridge_page_member_only`: "A form on a link entity can only be opened by members"). A page bound to an `owned` or `private` entity, or carrying a filled owned/private bridge section, may not include the public audience (`owned_entity_public_audience`, `%{entity}`: "%{entity} records belong to members, so Public can't submit this form"). Admin-only and admin+member sets are allowed. A reference whose target is `person`, `owned` or `private` on a page with the public audience, or whose target is `private` on a page with the member audience, fails `reference_private_for_audience` (`%{field}`, `%{target}`, `%{audience}`: "%{field}: %{target} records aren't visible to %{audience}, so the dropdown would be empty"). A reference to an open entity passes for every audience. Audiences are the exact `Page#visible_audiences` set.
- **Action slot.** `LaunchChecks#action_errors` refuses a second live page in the same owner with the same `action_key` and audience (`action_audience_taken`, `%{audience}`, `%{action}`: "Another live form already handles %{audience} for action %{action}"). A tenant page and a shared page may share a key; the tenant page wins at resolve time. Taking a page offline frees the slot. A trashed page keeps its launch state, so restoring it is refused with the same message while another live page holds the slot.
- **Identity fields.** `LaunchChecks#identity_errors` fails `identity_field_not_person` (`maint_core.errors.page_launch.identity_field_not_person`: "Name and email fields need a form on a person entity" / 「姓名和邮箱字段仅可用于人员实体的表单」) when any field with `source: "identity"` sits on a page whose bound entity is not a person entity. Identity errors run as part of `Page#launch_errors` (not when `VisibilityContract` only widens audiences). See **Identity fields (Account)** below.
- **Submission process.** A page with `form_settings.flowchart_id` needs that flowchart to resolve through `Pages::SubmissionProcess`, the lookup `Pages::PublicSubmission` uses (`Flowchart.accessible.launched`, plus the entity-mismatch rule for customer flowcharts). Otherwise launch is blocked with `submission_process_offline`. Tenant admins read these messages, so none of them says "flowchart".

`Page#submission_blockers` is the required-field and submission-process part (not the ownership audience errors or action collisions). Widening a launched page's audiences through `Pages::VisibilityContract` re-runs the dropdown, required-field, `audience_errors` and `action_errors` checks for the added audiences (and `action_errors` for every audience when the key changes), and refuses the change if any fail. Narrowing, and offline pages, aren't checked. `AiAssistant::Assistant::GeneratePage` reports a generated form that fails these checks as skipped, with the reason.

### Generated layout

`EntityFieldOrganizer` leaves calculated and computed attributes out of generated forms and the builder palette, on the entity and on its links. `PageFieldPopulator` copies an attribute's `description` into `help_text`, and labels each link section with the related entity's display label. `PageTemplateApplier::FieldGrouper` and `LayoutElementBuilder` translate the headings and layout labels they write (`maint_core.pages.generator.*`) at generation time. Link fields always get their own "Linked: <entity>" section, in both the source and attribute-groups modes. `LayoutElementBuilder.element_defaults` raises `ArgumentError` for any type other than `divider`, `spacer` and `heading`.

### Identity fields (Account)

When the bound entity is a person entity, the editor sidebar (`app/views/admin/maintenance/pages/_editor.html.erb`) adds an **Account** group (`maint_core.pages.editor.identity_group` "Account" / 「账号」; help `identity_group_help` "Creates the member's sign-in account." / 「用于创建会员登录账号。」) with First name, Last name and Email (`People::IDENTITY_KEYS`; labels from `member.profiles.show.fields.<key>`). Each item uses `source: "identity"` and renders as `identity[<key>]`. A Course (or any non-person) page does not show the group. `EntityFieldOrganizer` never offers a person entity's account columns (`first_name`, `last_name`, `email` on `Authentication::User`) as base-model fields — those columns reach a form only as identity fields.

Launch fails `identity_field_not_person` when an identity field sits on a non-person page. `Pages::LaunchChecks#identity_errors` is part of `Page#launch_errors`.

Public registration pages that collect email should turn on captcha (page flag plus a URL throttle). See [Captcha](captcha) and [Page rendering](page-rendering). The public enrollment walkthrough is [Audience flows](audience-flows).

### Status badges

The forms list (`Admin::Pages::OpsTableComponent`, on the card and the row) and the page header show at most one badge from `Pages::FormHealth`:

- **Can't be submitted** (`variant: :danger`): the page is launched and `submission_blockers` isn't empty. The tooltip lists the blockers.
- **Out of date** (`variant: :warning`): otherwise, when `Page#entity_out_of_date?` is true, meaning `entity_version_id` differs from the entity version the tenant sees. Hand-built pages have no `entity_version_id` and are never out of date.

One `Pages::LaunchChecks::Lookup` serves the whole list, so queries grow with distinct entities and flowcharts, not rows.

### Assistant-generated forms

`AiAssistant::Assistant::GeneratePage` is the assistant-only policy boundary for both the explicit `generate_page` tool and automatic forms after successful entity creates/approved updates. It calls `Pages::Activities::CreateFromEntityVersion` with `shared: false`, then calls `Page#launch!` on success. The new row keeps the column defaults (admin on, member and public off), so the form launches for admins/owner only.

Creation (including restoring/rebuilding a recyclable inactive page), version creation, audiences and launch run inside `Page.transaction(requires_new: true)`, so a launch failure rolls them back even when generation already has an outer transaction. Other unsuccessful activity results also roll back. `ActiveRecord::RecordInvalid` or `RecordNotSaved` returns `ok: false`, `skipped: :launch_failed` and `ai_assistant.assistant.apply_page_skipped` with the validation reason, falling back to `apply_errors.page_launch_failed` when no reason is available. The wrapper reports neither a page nor a created name after failure; an entity operation already completed remains applied.

`:page_exists` reuses the live page with the exact `customer_id` and `entity_version_id` without changing its launch state or audiences. The entity must belong to that same customer. The shared `CreateFromEntityVersion` activity still binds the form to the launched shared **Create Entity Entry** flowchart; its manual entity-version page creation does not adopt the assistant's automatic launch policy. Shared global launch/audiences remain platform-path only. Website marketing pages are separate `WebsitePage` resources and keep their own publication workflow. See [AI assistant](ai-assistant).

### Controller

`Admin::Maintenance::PagesController` uses `SharedResourceMode`. Tenant override permits only `:configuration`. A full save permits `name`, `description`, `configuration`, `entity_id`, and `captcha_enabled`. `stale_client_edit?` is true when `page[updated_at]` is missing, unparsable, or older than the row (0.001 second slack). The JSON response is status `conflict` (409) with `server_updated_at`.

`entity_flows` returns launched flowcharts for an entity (`Flowchart.for_current_customer.where(entity_id:).launched`) plus `Flowchart.shared.launched`. The editor's `TabManager` fetches that JSON. Edit also loads `Flowchart.accessible.referenceable` for the binding control. `PageManager#_buildFlowchartBindingHtml` writes the selected id into `configuration.form_settings.flowchart_id`.

Other maintenance routes:

- `FieldTemplatesController` — JSON CRUD for `FieldTemplate` (`customer_id`, `built_in`) through `FieldTemplates::Create`, `Update`, and `Delete`. Built-in rows refuse delete. The canvas command palette and field manager call `.../pages/field_templates`.
- `PageTemplateApplicationsController` — applies `PageLayoutTemplates.find(template_key)` onto an existing page. `all` and `find` translate each template's `name` and `description` at call time from `layout_catalog.templates.<key>`. Category and group labels use `layout_catalog.categories` and `layout_catalog.groups`. The English strings in each template `DEFINITION` stay the source text. Preview-row sample field labels stay in that definition.
- `PageFieldOptionsController#show` — options for a field whose `dynamic_options.options_source` is `"query"`.
- `PageModuleDataController#show` — `CompositePageRenderer` for one entry in `configuration_json["modules"]`.
- `PageRendersController#show` — launched pages visible to `:admin`, then `prepare_page_render`.
- Versions: `PageVersionsController`, line-scoped, cap 50.

Tenant page URLs are admin or owner. The platform prefix is `platform_owner?` only. Flowchart screens linked from this editor are still owner-only; see [Flowchart builder](flowchart-builder).

### Stimulus

The live editor is `page_builder_controller.js` (`page-builder`). It delegates to `UndoRedoManager`, `ViewportManager`, `TabManager`, `DragDropManager`, `FieldManager`, `PageManager`, `PropertyManager`, `SaveManager`, `KeyboardManager`, `SelectionManager`, `InserterManager`, `RulesManager`, `CalculationsManager`, `InlineEditManager`, `ClipboardManager`, `ResizeManager`, `CommandPaletteManager`, `ZoomManager`, drag helpers, and `ContextMenuManager`. `SaveManager` PATCHes configuration JSON and sends `updated_at` plus `If-Unmodified-Since`. Preview posts the current configuration through `previewForm`.

`page_settings_controller.js` only switches panels inside the settings modal. `page_visibility_controller.js` treats the three audience switches as independent; when one remains on, it disables that switch and exposes the reason through the server-passed `data-page-visibility-last-audience-value` (`comp_misc.distribution.last_audience`: "A form needs at least one audience."). Hidden inputs keep a disabled last switch in the POST (`page[visible_audiences][]`). The distribution card also posts `page[action_key]`, lists siblings from `Pages::ActionResolver.siblings`, and shows a URL row per enabled audience. Admin is a normal switch. `page_list_controller.js` filters the index.

`page_canvas_controller.js` and `page_toolbar_controller.js` state in source that they have no ERB mount and that `page-builder` replaced them. `entity_selector_controller.js` and `property_palette_controller.js` still query for a `page-canvas` element.

### Row actions

Settings / Member can attach a row action to an entity surface: action key (select of keys that have a launched member page), target field (slug), and optional button label (default `member.entity_surfaces.row_action_default` "Open"). Each list row links to `Pages::ActionLink.path` with `prefill[<field>]=<row id>`. Composite list tiles accept `config.row_action` with the same keys and render a trailing link column. Prefill is display-only; see [Audience flows](audience-flows) and [Member and public](member-and-public).

### Public submit

`PublicPagesController` includes `PageRendering`. `show` loads a launched page by `public_uuid` and 404s unless `public` is in the set; a viewer whose audience has a counterpart in the same action is redirected (303) there. `submit` requires the viewer's audience (`page_visible_to_current_viewer?` is `page.visible_to?(page_runtime_audience)`), then `Pages::PublicSubmission`. That service reads `form_settings.flowchart_id`, resolves it through `Pages::SubmissionProcess` (`Flowchart.accessible.launched`, the same lookup the launch check uses), and refuses a blank `activity`, a missing entity, or an entity that does not match the flowchart. After permit, `Pages::AudienceGuard` binds the owner reference and may return `:rejected` with nothing written; see [Page rendering](page-rendering). How the activity runs is [Flowchart runtime](flowchart-runtime). `prepare_page_render` always points the form at `public_page_submit_path` for the page UUID and sets `@content` from `page.generate_content`.

## Where to pay attention

:::attention
`PageRendering#prepare_page_render` is the render seam for admin and public GETs. It sets `@form_action` to `public_page_submit_path` for `page.public_uuid` and sets `@content` from `page.generate_content`. Preview can instead pass an unsaved configuration into `PageContentGenerator` and fall back to `"#"` when `public_uuid` is absent. Do not point the form at the maintenance update URL.
:::

:::attention
`Admin::Maintenance::PagesController#update` writes `content` only when configuration was posted and `tenant_override?` is false. A customer fork, including customer `81721200` on a tenant URL, stores the body on `page_customer_heads` through `resolved_current_version` and leaves the shared row's `content` column unchanged. Launch and audiences of that shared row are `guard_shared_global_writes` on `PageLaunchesController` and `PageVisibilitiesController`. The tenant entity picker also lists owned bridges (`People::Ownership.kind` is `:owned`); shared-resources mode does not.
:::

:::attention
`Pages::PublicSubmission` executes only when `form_settings.flowchart_id` resolves to a launched flowchart with a non-blank `activity`. `ActivityGenerator#generate` returns `nil` for an unnamed or empty graph, so a page can be launched and still be non-executable. The binding control lists `referenceable` flowcharts (`status: launched`).
:::

:::attention
`page_canvas_controller.js` parses a flat `fields` array and its own file header says it has no ERB mount. The editor that ships is `page-builder` on `_editor.html.erb`, and `Page#configuration_json` requires a `pages` array. Saving through the old flat shape drops the structure `Page` validates.
:::

## Key code

```ruby
# app/controllers/concerns/page_rendering.rb
  def prepare_page_render(page)
    @form_action = public_page_submit_path(customer_id: params[:customer_id], uuid: page.public_uuid)
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
# app/controllers/admin/maintenance/pages_controller.rb
        if params.dig(:page, :configuration).present? && !tenant_override?(@page)
          unless @page.update(content: @page.generate_content)
            raise ActiveRecord::Rollback
          end
        end
```

```ruby
# app/models/concerns/page_launch_lifecycle.rb
  def launch_errors
    msgs = []
    msgs << I18n.t("maint_core.errors.page_launch.entity_missing") unless entity&.active?
    msgs << I18n.t("maint_core.errors.page_launch.no_fields") if fields.empty?
    msgs.concat(orphan_rule_errors)
    msgs.concat(orphan_calculation_errors)
    checks = Pages::LaunchChecks.new(self)
    msgs.concat(checks.reference_errors)
    msgs.concat(checks.audience_errors)
    msgs.concat(checks.identity_errors)
    msgs.concat(checks.action_errors)
    msgs.concat(checks.submission_blockers)
    msgs
  end
```

```ruby
# app/services/pages/public_submission.rb
    def bind_flowchart_and_entity!
      record = SubmissionProcess.flowchart_for(@page)
      @flowchart = record && RuntimeFlowchart.new(record)
      @entity = @page.entity
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

Related: [Page rendering](page-rendering), [Audience flows](audience-flows), [Flowchart builder](flowchart-builder), [Entity builder](entity-builder), [Shared resources](shared-resources), [Website builder](website-builder).
