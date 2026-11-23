# Entity references, value display and form lifecycle — design

**Date:** 2026-10-23 · **Status:** DESIGN_APPROVED, revised after the student / course demo review (pending spec review)

**Revision:** The demo review added P11–P13 and their fixes (sections 3.7, 5.3, 5.4 and 5.5, and duplicate-label numbering in 3.1 and 3.2). It reworked the assistant's enrolment example (section 7) and corrected sections 3.5, 3.6, 3.9, 5.1, 6.1, 9 and 11.

**Goal:** Fix the confirmed defects of the entity → flowchart → page mechanism that do not need the larger structural redesign, so the later pieces (relationships, target records, business rules, permissions, live forms) start from a correct baseline. This is the first sub-project from the mechanism review that used the student / course / instructor example as evidence.

**Ground rules:** No backward compatibility and no data migration. Existing entities, flowcharts and pages will be deleted, so nothing here preserves or converts stored data. The usual project rules apply: three roles, three URL categories, I18n parity for `en` and `zh-CN`, developer docs updated in the same change, and 100% Vitest line and branch coverage for `app/javascript/**`.

## 1. Problems fixed

| # | Problem and evidence |
|---|---|
| P1 | `Entities::ComputedLoader` compares reference ids without casting (`json_extract(...) IN ('27')`). A link row whose parent id was stored as a JSON number is never counted. The Course list shows 0 enrolled, while sorting by the same column (which casts) counts 1. |
| P2 | `value_field` is honored by the builder preview and the page-level `query` source but ignored by the live form, which always saves the id. |
| P3 | A dropdown on an ordinary entity (Course → Instructor) accepts any submitted value. Nothing checks that the record exists or belongs to the tenant. |
| P4 | Admin Create Entry refuses any entity with a reference dropdown ("This form does not support these fields: 授课教师."), so a Course can't be created there. |
| P5 | The entity editor can't create reference dropdowns. Opening one created by the assistant and saving it replaces its `config` with `null`, which drops the binding. |
| P6 | The list shows referenced ids ("25") as badges. The CSV exports option codes and ids. The detail drawer shows raw values and "—" for every derived field. Calculated fields are never shown outside flowcharts. |
| P7 | Trashing an entity leaves its forms launched. They render only section headings and a Submit button. In the demo, Timesheet is trashed but its form 工时记录 is still live. |
| P8 | Nothing tells an admin that a form was generated from an older version of its entity. |
| P9 | The generator drops descriptions and puts calculated and computed fields on create forms, where they are always empty. It writes untranslated English into forms ("Additional", "Other Fields", "Linked: …", "Divider", "Spacer", "Heading"). Link-row fields land under "Additional", or under the link entity's machine name ("Linked: assoc_course_student"). Section headings render even when the viewer can see none of the section's fields. |
| P10 | The assistant is told entries can be updated and to choose a `value_field`. Its worked example counts withdrawn enrolments and makes grades visible and writable for every audience. |
| P11 | Changes on the referenced side break dropdowns without warning. The trash guard counts associations but not dropdowns, so Instructor can be trashed; Course's required 授课教师 dropdown is then empty, and no Course can be submitted. Deleting, retyping or hiding Instructor's 姓名 or Student's 学号 empties the same dropdowns, and nothing checks it. |
| P12 | Choices with the same label can't be told apart. Students #26 and #31 both have the code "001", so the enrolment step offers "001" twice. |
| P13 | A launched form can stop accepting submissions with no sign in the forms list. Launching never checks the form's flowchart. All 15 launched forms in the dev data submit through flowchart 27, so taking it offline or trashing it makes every one reply "This form is not available." A field that becomes required for one of the form's audiences after the form was generated is missing from it, so every submission fails. Widening a launched form's audiences is never re-checked either. |

## 2. Decisions

- A reference dropdown always saves the referenced record's id, as a string. Its options show a required display field (`label_field`) of the referenced entity. `value_field` is removed everywhere.
- Shared services own reference listing and value display, and every caller goes through them. Choices that share a label get their record number.
- References are protected from both sides. A referencing entity can't save a broken reference. A referenced entity can't be trashed while it is referenced, and can't delete, retype or hide a field that others display.
- Field visibility stays the only gate on what a dropdown reveals. A dropdown lists the display field of every record to everyone who can open the form, so the assistant hides personal fields from members and the public, and the editor and the docs say so.
- A form launches only when it can be submitted. On top of today's checks, its dropdowns must have visible labels, every field required for its audiences must be on it, and its flowchart must be launched. Changing a launched form's audiences re-runs the audience checks. A launched form that later lacks a required field, or whose flowchart goes offline, shows "Can't be submitted".
- Trashing an entity takes its live forms offline. Restoring the entity leaves them offline and lists them.
- A flowchart that launched forms use can't be trashed. Taking it offline stays allowed, and the notice says how many forms stop accepting submissions.
- The entity editor fully supports creating and editing reference dropdowns.

## 3. Reference dropdowns

Every reference lookup and check in this section reads the target's definition as the tenant sees it (`resolved_current_version`), so a tenant's override of a shared entity applies.

### 3.1 Display-field rule: `Entities::ReferenceLabels`

A small module owns the rule for which fields may label a reference, and the label text.

- `LABEL_HTML_TYPES = %w[text search email tel url number date]`.
- `labelable?(attribute)` is true for an input attribute whose `type` is not `Calculated`, `Computed` or `EntityReference` and whose `html_type` is in `LABEL_HTML_TYPES`.
- `text(raw_label, id)` returns the label, or `common.references.untitled` ("Untitled (#%{id})") when the label is blank.
- `missing(id)` returns `common.references.missing` ("Missing record (#%{id})").
- `disambiguate(pairs)` takes `[label, id]` pairs and rewrites every label that occurs more than once as `common.references.duplicate` ("%{label} (#%{id})"). Labels are compared exactly, after trimming whitespace. Unique labels are left alone.

The same rule applies to an association's display field. Link entities use that field as the label of their reference to the associated entity, so a non-labelable display field would produce an empty dropdown.

### 3.2 Listing choices: `Entities::ReferenceOptions`

`Entities::ReferenceOptions.call(entity_id:, label_field:, customer_id:, audience:, limit: 200)` returns `Array<[label, id_string]>`.

- **Target:** `Entity.where(customer_id: [customer_id, nil]).active.non_bridge.find_by(id: entity_id)`. No target returns `[]`.
- **Label attribute:** it must exist on the target's definition for the tenant, be labelable, and be visible to `audience` (`EntityAttributeAudience.visible_to?`). Otherwise the service returns `[]`.
- **Entries:** `EntityEntry.where(customer_id:, entity_id: target.id)`, ordered by label (case-insensitive) and then id, limited to `limit`. The label is read with `json_extract` on the allowlisted slug, never through `send`.
- **Duplicates:** the labels go through `ReferenceLabels.disambiguate`, so the demo's two students show as "001 (#26)" and "001 (#31)". Only records in the returned list are compared.
- The service never raises on bad configuration; it returns `[]`.

Callers:

1. Generated form dropdowns: the ERB preamble from `PageContentGenerator::FormFields#build_dynamic_options_preamble` calls the service with the field's `dynamic_options` (`entity_id`, `label_field`) instead of embedding its own query.
2. Builder preview: `Admin::Maintenance::PageFieldOptionsController`.
3. Admin Create Entry: `Entities::EntryForm` (section 3.4).
4. Quick-add: `Admin::EntityEntriesController#quick_add_label` uses `ReferenceLabels.text`, so a newly added option is labelled like the others. It adds the record number when another record of the entity already has the same label. Options already in the open dropdown keep their text until the form reloads.

The page-level `query` source (`PageContentGenerator::DynamicOptionsResolver`) keeps its conditions, ordering and limit, but its option value is always the record id.

### 3.3 Validation on every write: `EntityEntryContract`

This rule applies to each attribute whose `config.options_source` is `"entity_entries"`, which covers ordinary-entity dropdowns and link-row target references.

- Every submitted value must be the id of an `EntityEntry` with the model's `customer_id` and `entity_id == config.entity_id`. For a multi-select, each element must be.
- If not, the contract adds `common.errors.dynamic.association_target_missing` ("%{field}: the selected record does not exist.").
- The rule ignores per-audience validator flags, because it protects integrity rather than being a configurable validator.
- It covers every write that goes through the contract: page submissions, admin Create Entry, link rows, and the flowchart Build Contract / Validate steps.

In `Pages::BridgeEntries`, `missing_target` is removed because the link row's contract now performs that check. The parent link is written as `@entry.id.to_s`.

### 3.4 Admin Create Entry: `Entities::EntryForm`

- `select`, `radio` and `multi-select` attributes with `options_source: "entity_entries"` and a labelable label field become supported. Their options come from `ReferenceOptions` with the admin audience.
- These fields skip the "value must be one of the listed options" check, because the list is capped at 200. The contract's existence check decides validity.
- Attributes of type `EntityReference` (link-entity internals) stay excluded.

### 3.5 Launch check: references

The check covers every input field whose `dynamic_options.options_source` is `"entity_entries"`. It reads them through `Page#input_fields` (section 5.3), so fields inside columns containers count. It runs for each audience the page is visible to (`Page::VISIBILITY_LEVELS.select { |audience| visible_to?(audience) }`).

- The target entity must exist and be active. Otherwise launch is blocked with `maint_core.errors.page_launch.reference_target_inactive`.
- The label field must be labelable and visible to that audience. Otherwise launch is blocked with `maint_core.errors.page_launch.reference_label_hidden`, which names the field, the display field and the audience. The audience name comes from `common.visibility.{admin,member,public}`.

### 3.6 Definition validation on the referencing side: `EntitySchemaValidation`

Saving an entity fails in these cases, whether the save comes from the editor or the assistant:

| Case | Error key |
|---|---|
| An `entity_entries` attribute's target entity doesn't exist for the tenant. A shared entity's global default must target a shared entity; a tenant's override may also target that tenant's entities. | `maint_core.errors.validations.reference_target_missing` |
| Its `label_field` is missing, or isn't labelable on the target. | `maint_core.errors.validations.reference_label_field_invalid` |
| An association's `display_field` isn't labelable. | `maint_core.errors.validations.association_display_field_invalid` |

Unlike the existing validations in `EntitySchemaValidation`, which run on every save, these checks run only when `property_schema` or `associations` change. Status-only saves such as trash and restore therefore never fail on them.

A target in any status counts as existing, including a trashed one, as `validate_association_target_exists` already does for associations. Section 3.7 stops a referenced entity from being trashed, so this only matters when an entity is restored after its target was trashed or permanently deleted. The restore succeeds, and section 3.5 blocks relaunching its forms until the reference is fixed.

### 3.7 Changes on the referenced side: `Entities::ReferenceDependents`

Section 3.6 checks a reference when the referencing entity is saved. This section protects it when the referenced entity changes. `Entities::ReferenceDependents` finds what depends on an entity. It reads only active entities and launched forms.

- `references(entity)` returns one `{ entity:, field_label:, label_field: }` row per reference:
  - an attribute, or an association's extra attribute, with `config.options_source: "entity_entries"` and `config.entity_id` equal to the entity;
  - an association whose `target_entity_id` is the entity, with its `display_field` as the label field.
- `forms(entity, label_field)` returns one `{ page:, field_label:, audiences: }` row per launched page that has an input field whose `dynamic_options` targets the entity and shows `label_field`. `audiences` lists the audiences the page is visible to.
- The entity itself is skipped, so a self-reference such as an employee's manager never blocks it.
- **Scope:**
  - Trashing affects every tenant that can see the entity.
  - A save affects the tenants that read the definition being saved. A customer-owned entity or a tenant's override affects that tenant. A shared entity's global default affects every tenant without an override of it.
  - The service reads the affected tenants' entities (including their overrides of shared entities), shared entities, and the launched forms those tenants see.

**Trash guard.** `Entity#soft_delete` (in `BridgeEntityManagement`) refuses while `references` returns anything. This check runs after the existing association check.

- The error `maint_core.errors.validations.entity_referenced` lists each reference as `common.references.field_path` ("Course › 授课教师"), joined with `to_sentence`.
- Because the association check runs first, in practice the message lists dropdowns.
- `Admin::Maintenance::EntitiesController#destroy` already shows the model's errors as an alert.

**Save guard.** When `property_schema` changes, saving fails if the new definition breaks a reference to the entity:

| Case | Editor error (`EntitySchemaValidation`) | Assistant violation (`update_entity`) |
|---|---|---|
| A field that `references` lists as a label field is deleted, or its type changes so it isn't labelable. Changing its slug counts as deleting it. | `maint_core.errors.validations.display_field_in_use` | `attribute.display_field_in_use` |
| That field becomes hidden from one of the `audiences` of a form that `forms` returns. | `maint_core.errors.validations.display_field_hidden_from_form` | `attribute.display_field_hidden` |

- Changing the field's name (its label) is always allowed, because the slug stays the same.
- The assistant check runs in `EntityDefinitions::Api::SemanticValidator`, so the model sees the violation before a plan is parked. Without it, the save would fail only after the admin approved the plan, as a generic `domain.invalid`.

### 3.8 Entity editor

These changes go in `Admin::Maintenance::Entities::AttributeModalComponent` and the `entity_form` Stimulus managers.

- **New mode:** the options-source toggle ("Manual Entry" / "Use Constant") gets a third choice, "Use Entity Records" (`comp_admin.attribute_modal.use_entity_records`), for select, radio and multi-select.
- **What the mode shows:**
  - a "Target Entity" select, reusing `maint_core.entities.assoc.target_entity`;
  - a "Display field" select (`comp_admin.attribute_modal.display_field`) that lists only labelable attributes;
  - the hint `comp_admin.attribute_modal.entity_records_hint`, which says that the record id is saved and that the dropdown lists the display field of every record to everyone who can open the form.
- **Data source:** `/:cid/admin/maintenance/entities.json`, which the association dialog already uses.
  - Each attribute gets a `labelable` flag, computed server-side with `ReferenceLabels.labelable?`.
  - Bridge entities are not offered as reference targets.
  - The entity being edited is included once it is saved, so self-references such as an employee's manager work.
- **Saving:** the mode produces `config: { options_source: "entity_entries", entity_id: "<id>", label_field: "<slug>" }`. A missing choice uses the existing alerts `maint_core.entities.assoc_modal.select_target_entity_alert` and `select_display_field_alert`.
- **Opening an existing reference:** the dialog opens in this mode with its entity and display field selected, so saving keeps the binding.
- **Association dialog:** its display-field select also lists only labelable attributes.
- **UI and tests:** consult the shadcn/ui plugin before building the new controls, and deliver them through the existing ViewComponent, Tailwind and Stimulus patterns. Every Stimulus file touched stays at 100% Vitest line and branch coverage.

### 3.9 Assistant contract

- **`entity.defs.json`, `options` and `optionsLite`:**
  - Remove `value_field`.
  - `label_field` gets the description "Slug of a human-readable attribute of that entity (text, search, email, tel, url, number or date) shown as the choice label. The stored value is always the record id."
  - The `entity_entries` conditional requires `["entity", "label_field"]`.
- **`entity.defs.json`, `association` and `associationPatch`:** `display_field` drops "(or id)".
  - In `association` it becomes "Slug of a human-readable attribute of the related entity (text, search, email, tel, url, number or date) used as the label of each linked record."
  - In `associationPatch` it becomes "Replacement display-field slug. The same type rule applies."
- **`update_entity.json`:** drop `value_field?` from the options description.
- **`Operations::CreateEntity` and `Operations::UpdateEntity`:** `version 2`.
- **`EntityDefinitions::Api::SemanticValidator`:**
  - Checks `label_field` only.
  - Adds four violation codes:
    - `options.label_field_not_labelable` and `association.display_field_not_labelable`, with the variables `field` and `entity`;
    - section 3.7's `attribute.display_field_in_use`, with `slug` and `fields`;
    - section 3.7's `attribute.display_field_hidden`, with `slug`, `audience` and `form`.
  - Their messages go under `operations.violations.*` in `operations_entity.{en,zh-CN}.yml`.
- **Remove `value_field` from:**
  - `Api::Mapper`;
  - `ChoiceList`, where `Source` becomes `options_source` plus entity name;
  - `Persist`, where `label_field` has no default because it is required;
  - `Normalizer` and `Assistant::ChangePlan`;
  - `AiAssistant::ProposedChangesComponent`, together with `ai_assistant.assistant.plan.config_fields.value_field` in both locales;
  - `BridgeEntityManagement` (link references);
  - `PageFieldPopulator` and `admin/maintenance/pages/_field_sidebar_item.html.erb`.

## 4. Showing values

### 4.1 One set of derived expressions: `Entities::DerivedExpressions`

`Entities::DerivedExpressions.for(entity, customer_id:)` returns `[{ name:, sql:, kind: }]`, where `kind` is `:computed` or `:calculated`.

- Computed subqueries come from `ComputedCompiler.compile_all`.
- Calculated expressions come from `FormulaCompiler.compile_all(schema, resolved: computed)`, with the same `FormulaError` rescue and alias check that `FlowchartRuntime::QueryBuilder#inject_calculated_fields` uses today.
- `QueryBuilder`, the sort SQL in `Admin::Entities::ColumnsBuilder`, and `DerivedValues` all use it, so display, sorting and filtering compute values the same way.

### 4.2 Loading derived values: `Entities::DerivedValues` (replaces `Entities::ComputedLoader`)

- `call(entity:, customer_id:, entry_ids:)` returns `{ Integer id => { slug => value } }`. It runs one query that selects `entity_entries.id` plus every expression from section 4.1 for the given ids, scoped by customer and entity.
- Computed values keep today's coercion: count becomes an integer, other functions become floats, and an empty result uses the definition's empty default. Calculated values are returned as SQLite returns them.
- `prime!(entries, customer_id:)` replaces `ComputedLoader.prime!`. `EntityEntry#computed_values` and `prime_computed_values!` become `derived_values` and `prime_derived_values!`, and they include calculated fields.
- `ComputedLoader` and its spec are deleted, and `ComputedDefinition#loader_sql` is removed.
- Large CSV exports pay the same per-row cost that sorting by a computed column already pays.

### 4.3 Display text: `Entities::EntryDisplay`

`Entities::EntryDisplay.new(entity:, entries:, customer_id:, audience:)` preloads everything it needs for the given entries: one `DerivedValues` query, plus one query per referenced entity. Then `#text(entry, slug)` returns a String:

| Stored value | Text |
|---|---|
| blank | `common.labels.em_dash` |
| static option (select, radio, multi-select) | the option label; a multi-select joins its labels with ", " |
| reference (`entity_entries`) | the referenced record's label via `ReferenceLabels.text`; `ReferenceLabels.missing(id)` when the record no longer exists; the raw id when the display field isn't visible to `audience` |
| calculated or computed | the value from `DerivedValues` |
| boolean (checkbox, switch) | `common.labels.yes` / `common.labels.no` |
| anything else, including dates | the stored value as text (components keep formatting dates and datetimes as today) |

It never raises. An unknown slug returns its raw value as text. Display text never adds record numbers to duplicate labels; only dropdowns do (section 3.2).

### 4.4 Callers and visible effects

- **`Admin::EntitiesController#show`:** builds an `EntryDisplay` for the page of rows (HTML) and for the export rows (CSV), and passes it to `ColumnsBuilder` in place of computed values.
- **`Admin::Entities::ColumnsBuilder`:**
  - Attribute cells and badge labels come from `EntryDisplay#text`.
  - Calculated fields join computed fields as selectable, sortable columns, with their sort SQL from section 4.1.
- **`Admin::Entities::EntriesCsv`:** the code is unchanged. Because cells now return display text, the export contains option labels and record names.
- **`Admin::Entities::EntryDetailComponent#attribute_value`:** uses `EntryDisplay#text` with the admin audience, derived fields included.
- **Member surfaces** (`Member::SurfacesController`, `Member::EntitySurfaceBuilder`, `Member::SurfaceTemplateApplier`): use `DerivedValues.prime!` and `EntryDisplay` with the member audience.

## 5. Form lifecycle

### 5.1 Trash cascade

Only entities that nothing else depends on get this far. The existing guard refuses an entity with associations or one that is an association's target, and section 3.7 refuses one that another entity's dropdown references. Timesheet is the demo's example (P7).

- `Entity#soft_delete` (in `BridgeEntityManagement`) gains a step inside its existing transaction, after the status change. It takes every launched page bound to the entity offline (`Page.for_entity(id).launched`) by calling `take_offline!` on each.
- `Page.for_entity` compares `CAST(json_extract(...) AS TEXT)` with the id as a string, so a binding stored as a JSON number or as a string matches. Today it compares with an integer, the same trap as P1.
- For a shared entity this covers every tenant's forms.
- The method records how many it took offline in `forms_taken_offline`. If any step fails, the trash is rolled back.
- `Admin::Maintenance::EntitiesController#destroy`, which serves both the tenant and platform prefixes, appends `maint_core.flash.entities.forms_taken_offline` to its existing notice when the count is positive.

### 5.2 Restore

- `BaseRestorationsController` gains an overridable `restored_notice(record)` that returns today's message by default.
- `EntityRestorationsController` overrides it. When pages bound to the entity are offline, it appends `maint_core.flash.entity_restorations.offline_forms` with their names.
- Pages are not relaunched automatically.

### 5.3 Launch checks: every submission must be able to succeed

`Page#input_fields` is a new helper. It returns every non-layout field on every step, including fields inside columns containers, which `Page#fields` doesn't reach. Section 3.5 and the checks below use it.

`Page#submission_blockers` returns the messages from the two checks below. `PageLaunchLifecycle#launch_errors` adds them to today's checks and section 3.5's, and section 5.5 reuses them for the badge.

- **Required fields.** For each audience the page is visible to, every attribute required for that audience must have a field on the form.
  - An attribute is required for an audience when it has a validator in `ValidatorRegistry::REQUIRING_VALIDATIONS` (presence, acceptance) and `EntityAttributeAudience.applying_audiences` includes the audience. This is the rule the contract applies.
  - The check reads the entity's current definition for the tenant, because that is what submissions are validated against.
  - Calculated and computed attributes never count. A default value doesn't satisfy the check, because submissions don't apply defaults.
  - The entity's own attributes match fields with `source: "entity"` and the same `property_slug`. A missing one gives `maint_core.errors.page_launch.required_field_missing`.
  - Each link entity with at least one field on the form is checked the same way, against fields with `source: "bridge"` and that link's `source_section`. The reference back to the entity is skipped, because `Pages::BridgeEntries` fills it in. A missing one gives `maint_core.errors.page_launch.required_link_field_missing`.
- **Submission process.** When `form_settings.flowchart_id` is set, two conditions apply:
  - The flowchart must be found the way `Pages::PublicSubmission` finds it (`Flowchart.accessible.launched`).
  - A customer-specific flowchart must be bound to the page's entity, under the same entity-mismatch rule.

  The lookup and the rule move into one method that both callers use, so they can't drift. If either condition fails, the check gives `maint_core.errors.page_launch.submission_process_offline`. Tenant admins see this message, so it never says "flowchart".

**Audience changes.** When a launched page's audiences change, `Pages::VisibilityContract` runs section 3.5's check and the required-field check for the new audiences. It refuses the change if either fails. `PageVisibilitiesController` already shows the contract's errors in its `maint_core.flash.page_visibilities.update_failed` flash.

**Assistant-generated forms.** `AiAssistant::Assistant::GeneratePage` launches each generated admin-only form and rolls it back if launch fails. A generated form that fails these checks is therefore reported as skipped, with the reason.

### 5.4 Flowchart guards

`Page.bound_to_flowchart(flowchart_id)` returns the pages whose configuration names the flowchart in `form_settings.flowchart_id`, through the global head or any tenant's override head.

- It compares ids as text, like `Page.for_entity`.
- For a shared flowchart it covers shared pages and every tenant's pages. For a customer-owned flowchart it covers shared pages and the owning tenant's pages.

The guards:

- **Trash.** `Flowchart#soft_delete` refuses while `Page.bound_to_flowchart(id).launched` exists, whether the flowchart is launched or a draft.
  - The error `maint_core.errors.validations.flowchart_in_use` lists the forms, joined with `to_sentence`.
  - `Admin::Maintenance::FlowchartsController#destroy` ignores the result today and always reports success. It now redirects with the error as an alert when the trash is refused.
- **Take offline.** `FlowchartLaunchesController#destroy` still takes the flowchart offline, because that is the only way to edit a launched global default (`launched_edit_locked?`).
  - When launched forms use the flowchart, the notice (`maint_core.flash.flowchart_launches.taken_offline`) appends `maint_core.flash.flowchart_launches.forms_stopped` with their count.
  - Those forms show "Can't be submitted" (section 5.5) until it is launched again.
- Both actions are owner-only (`FlowchartVisibility`), so these two messages may say "flowchart".

### 5.5 Status badges

A page shows at most one of these badges. They appear in `Admin::Pages::OpsTableComponent`, on both the mobile card and the desktop row, and next to the launch badge in `admin/maintenance/pages/show.html.erb`.

1. **Can't be submitted:** the page is launched and `submission_blockers` isn't empty.
   - It uses `BadgeComponent` with `variant: :danger` and the label `admin_misc.pages.cannot_submit`.
   - The tooltip `admin_misc.pages.cannot_submit_hint` lists the blockers, joined the way `launch!` joins its errors.
   - This is how a tenant admin learns that a required field was added after the form was built, or that its submission process went offline.
2. **Out of date:** shown otherwise, when `Page#entity_out_of_date?` is true.
   - That is the case when `entity_version_id` is present and differs from `entity.resolved_current_version&.id`, resolved per tenant through `Current.customer`.
   - Hand-built pages without an `entity_version_id` are never flagged.
   - It uses `variant: :warning`, the label `admin_misc.pages.out_of_date` and the tooltip `admin_misc.pages.out_of_date_hint`.

The list computes both badges for the rows it shows. It preloads the rows' entities and link entities, their versions, and the bound flowcharts to avoid N+1 queries.

## 6. Generator and rendering

### 6.1 Generator

- `EntityFieldOrganizer` leaves `Calculated` and `Computed` attributes out of the entity's own fields. Generated forms and the builder palette both read it, so derived fields disappear from both.
- `PageFieldPopulator#build_field` sets `help_text` to the attribute's `description`.
- `PageTemplateApplier::FieldGrouper` and `LayoutElementBuilder` translate every label they write, using `maint_core.pages.generator.*` at generation time.
- Link-row fields always get their own section in both grouping modes. Its heading is `maint_core.pages.generator.sections.linked` with the related entity's display label ("关联：学生" / "Linked: Student").
  - `PageFieldPopulator` passes the related entity's display label as `source_section_label`, instead of the link entity's machine name (`assoc_course_student`).
  - `FieldGrouper#reorganize_by_attribute_groups` gives each link section its own heading, instead of putting its fields under "Additional".
- `LayoutElementBuilder.element_defaults` raises `ArgumentError` for any type other than divider, spacer or heading, instead of titleizing the type.

### 6.2 Hidden sections

- `PageContentGenerator#generate_fields` splits a page's fields into runs, each starting at a `section` layout element.
- A run is dropped entirely (its section element, the divider right before it, and the layout elements inside it) when it contains at least one input field and `field_boundary.visible_field?` is false for all of them. Fields inside a columns container count as inputs of the run.
- Runs without input fields render as today.
- This happens per request, for the viewer's audience.

## 7. Assistant instructions

- **`entity_platform.md`:**
  - Admins create, view and delete entries under Entities; editing entries isn't available yet.
  - Descriptions become help text on generated forms and on Create Entry.
- **`entity_authoring.md`:**
  - An `entity_entries` dropdown always saves the record id. Always set `label_field`, and an association's `display_field`, to a human-readable attribute of an allowed type, such as a name, title or code. Never set it to `id`.
  - Visibility applies to every record of an entity, and a dropdown lists its display field for every record to everyone who can open the form. Unless the admin asks otherwise:
    - hide fields that identify or describe a person (names, ID numbers, birth dates, contact details, addresses) from members and the public;
    - keep grades, scores and staff notes admin-only.
  - A field that other entities display can't be deleted, retyped, or hidden from a launched form that shows it. Change the display field on the referencing entity first.
- **`entity_examples.md`:**
  - **Student:** `student_id`, `first_name`, `last_name`, `date_of_birth`, `email`, `phone`, `street`, `city`, `postal_code` and `country` get `"access": {"visible_to": {"member": false, "public": false}}`. The assumptions add that personal details are visible to admins only.
  - **Course enrolment, link row:** it carries three fields:
    - `enrolled_on` (date);
    - `status` (select: Enrolled, Waitlisted, Dropped, Completed; required), which replaces `result`;
    - `grade` (number, 0–100), which is admin-only.
  - **Course enrolment, `enrolled_students`:** it counts only enrolled rows, with `"filter": {"attribute": "status", "operator": "=", "value": "Enrolled"}`. A filter holds a single comparison, so `!=` on one status would still count the others, such as waitlisted rows.
  - **Course enrolment, `seats_remaining`:** a calculated number field (`"formula": "seats - enrolled_students"`) joins the Capacity group.
  - **Course enrolment, reply:** it describes the status, the seats-remaining field and the admin-only grade.
  - **Application:** the example drops `value_field` and keeps `"label_field": "title"`.
- **Validation:** `tool_examples_contract_spec` validates every example against the version 2 schemas.

## 8. Translations

New keys. Each goes into the matching `en` and `zh-CN` area file.

| Key | en | zh-CN |
|---|---|---|
| `common.references.untitled` | `Untitled (#%{id})` | `未命名（#%{id}）` |
| `common.references.missing` | `Missing record (#%{id})` | `记录不存在（#%{id}）` |
| `common.references.duplicate` | `%{label} (#%{id})` | `%{label}（#%{id}）` |
| `common.references.field_path` | `%{entity} › %{field}` | `%{entity} › %{field}` |
| `maint_core.errors.page_launch.reference_label_hidden` | `%{field}: display field %{label} isn't visible to %{audience}, so the dropdown would be empty` | `%{field}：显示字段“%{label}”对%{audience}不可见，下拉列表将为空` |
| `maint_core.errors.page_launch.reference_target_inactive` | `%{field}: the referenced entity is missing or in the trash, so the dropdown would be empty` | `%{field}：引用的实体不存在或已在回收站中，下拉列表将为空` |
| `maint_core.errors.page_launch.required_field_missing` | `%{field} is required for %{audience} but isn't on the form` | `“%{field}”对%{audience}为必填，但表单中没有该字段` |
| `maint_core.errors.page_launch.required_link_field_missing` | `%{field} on the link to %{target} is required for %{audience} but isn't on the form` | `与%{target}关联中的“%{field}”对%{audience}为必填，但表单中没有该字段` |
| `maint_core.errors.page_launch.submission_process_offline` | `This form's submission process is offline, so it can't accept submissions` | `该表单的提交流程已下线，无法接收提交` |
| `maint_core.errors.validations.reference_target_missing` | `%{field}: the referenced entity doesn't exist` | `%{field}：引用的实体不存在` |
| `maint_core.errors.validations.reference_label_field_invalid` | `%{field}: display field %{label} must be a text, search, email, phone, URL, number or date field of %{entity}` | `%{field}：显示字段“%{label}”须为%{entity}的文本、搜索、邮箱、电话、网址、数字或日期字段` |
| `maint_core.errors.validations.association_display_field_invalid` | `association with %{target_name}: display field %{label} must be a text, search, email, phone, URL, number or date field` | `与%{target_name}的关联：显示字段“%{label}”须为文本、搜索、邮箱、电话、网址、数字或日期字段` |
| `maint_core.errors.validations.entity_referenced` | `Cannot delete an entity that other entities reference: %{fields}. Remove those fields or point them at another entity first.` | `无法删除仍被其他实体引用的实体：%{fields}。请先移除这些字段，或改为引用其他实体。` |
| `maint_core.errors.validations.display_field_in_use` | `%{label} is the display field of %{fields}. Keep it as a text, search, email, phone, URL, number or date field, or choose another display field there first.` | `“%{label}”是%{fields}的显示字段。请保留为文本、搜索、邮箱、电话、网址、数字或日期字段，或先在那里改用其他显示字段。` |
| `maint_core.errors.validations.display_field_hidden_from_form` | `%{label} must stay visible to %{audience}: the launched form %{form} shows it in %{field}.` | `“%{label}”须对%{audience}保持可见：已上线的表单“%{form}”在“%{field}”中显示该字段。` |
| `maint_core.errors.validations.flowchart_in_use` | `Cannot delete a flowchart that launched forms use: %{names}. Take those forms offline first.` | `无法删除已上线表单正在使用的流程图：%{names}。请先将这些表单下线。` |
| `maint_core.flash.entities.forms_taken_offline` | `%{count} form(s) taken offline.` | `已将 %{count} 个表单下线。` |
| `maint_core.flash.entity_restorations.offline_forms` | `These forms are still offline: %{names}. Relaunch them under Forms.` | `以下表单仍处于下线状态：%{names}。请在“表单”中重新上线。` |
| `maint_core.flash.flowchart_launches.forms_stopped` | `%{count} launched form(s) can't accept submissions until it is launched again.` | `%{count} 个已上线表单在流程图重新上线前无法接收提交。` |
| `admin_misc.pages.cannot_submit` | `Can't be submitted` | `无法提交` |
| `admin_misc.pages.cannot_submit_hint` | `Every submission fails: %{problems}` | `所有提交都会失败：%{problems}` |
| `admin_misc.pages.out_of_date` | `Out of date` | `版本过旧` |
| `admin_misc.pages.out_of_date_hint` | `Built from version %{built}; %{entity} is now on version %{current}.` | `基于第 %{built} 版生成；%{entity}当前为第 %{current} 版。` |
| `maint_core.pages.generator.sections.additional` | `Additional` | `其他信息` |
| `maint_core.pages.generator.sections.other_fields` | `Other Fields` | `其他字段` |
| `maint_core.pages.generator.sections.linked` | `Linked: %{name}` | `关联：%{name}` |
| `maint_core.pages.generator.layout.divider` | `Divider` | `分隔线` |
| `maint_core.pages.generator.layout.spacer` | `Spacer` | `间距` |
| `maint_core.pages.generator.layout.heading` | `Heading` | `标题` |
| `comp_admin.attribute_modal.use_entity_records` | `Use Entity Records` | `使用实体记录` |
| `comp_admin.attribute_modal.display_field` | `Display field` | `显示字段` |
| `comp_admin.attribute_modal.entity_records_hint` | `Saves the record's id. The dropdown lists the display field of every record to everyone who can open the form.` | `保存记录 ID。下拉列表会向所有能打开表单的人列出每条记录的显示字段。` |
| `operations.violations.options.label_field_not_labelable` | `The field %{field} on entity %{entity} can't label a choice. Use a text, search, email, tel, url, number or date field.` | `实体 %{entity} 上的字段 %{field} 不能作为选项标签，请使用文本、搜索、邮箱、电话、网址、数字或日期字段。` |
| `operations.violations.association.display_field_not_labelable` | `The display field %{field} on entity %{entity} must be a text, search, email, tel, url, number or date field.` | `实体 %{entity} 上的显示字段 %{field} 须为文本、搜索、邮箱、电话、网址、数字或日期字段。` |
| `operations.violations.attribute.display_field_in_use` | `The attribute %{slug} is the display field of %{fields}. Keep it as a text, search, email, tel, url, number or date field, or change the display field there first.` | `属性 %{slug} 是%{fields}的显示字段。请保留为文本、搜索、邮箱、电话、网址、数字或日期字段，或先在那里更换显示字段。` |
| `operations.violations.attribute.display_field_hidden` | `The attribute %{slug} must stay visible to %{audience} because the launched form %{form} lists it.` | `属性 %{slug} 须对 %{audience} 保持可见，因为已上线的表单 %{form} 使用了该字段。` |

In the `maint_core` messages, `%{audience}` is the translated `common.visibility.*` name. In the `operations.violations` messages it is the audience key (`admin`, `member` or `public`), as passed in the violation's `details`. Lists of names and fields are joined with `to_sentence`, which follows the locale.

Reused keys:

- `common.errors.dynamic.association_target_missing`
- `common.visibility.{admin,member,public}`
- `common.labels.{em_dash,yes,no}`
- `maint_core.entities.assoc.target_entity`
- `maint_core.entities.assoc_modal.select_target_entity_alert`
- `maint_core.entities.assoc_modal.select_display_field_alert`
- `maint_core.flash.page_visibilities.update_failed`
- `maint_core.flash.flowchart_launches.taken_offline`

Removed key: `ai_assistant.assistant.plan.config_fields.value_field`, in both locales.

## 9. Developer docs

The following pages are updated in both `doc/reference/en/` and `doc/reference/zh-CN/`, in the same change:

| Page | What changes |
|---|---|
| `entity-builder` | the "Use Entity Records" source and the display-field rule; reference validation on the referencing side and the referenced side (trash guard, save guard); duplicate-label numbering; a callout that a dropdown lists the display field of every record to everyone who can open the form, so field visibility decides what a public form reveals; Create Entry support; list, CSV and detail display; calculated columns; the trash cascade |
| `page-builder` | generator changes (help text, no derived fields, translated and link-row headings), the palette, the launch checks (references, required fields, submission process), the re-check on audience changes, the "Can't be submitted" and "Out of date" badges |
| `page-rendering` | how dropdown options and labels are built, including duplicate numbering; the same public-exposure callout; hidden sections |
| `flowchart-runtime` | `EntityEntryContract`'s existence check on reference values; `Pages::BridgeEntries` writing the parent id as a string and leaving target checks to the contract |
| `flowchart-builder` | trash refused while launched forms use a flowchart; the take-offline notice; launching a form requires its flowchart to be launched |
| `operations-api` | `value_field` removed, `label_field` required, the `display_field` descriptions, the four new violation codes, version 2 of `create_entity` and `update_entity` |

Before finishing, run `rg "value_field|ComputedLoader|computed_values" doc/reference/` and expect no matches.

## 10. Testing

RSpec:

- **Services:**
  - `ReferenceLabels`, `ReferenceOptions`:
    - tenant scoping, label visibility per audience, and a tenant's override of a shared target;
    - ordering and the untitled fallback;
    - duplicate numbering ("001 (#26)" and "001 (#31)", with unique labels untouched);
    - bad configuration returns `[]`.
  - `ReferenceDependents`:
    - dropdowns, dropdowns on link rows, and association display fields;
    - a self-reference is skipped, and trashed entities are ignored;
    - tenant scope, and a shared entity's global default skipping tenants that override it.
  - `DerivedExpressions`, `DerivedValues`: includes a regression for P1, where a parent id stored as a JSON number counts as 1. Also a calculated field that depends on a computed one, and a broken formula giving blank values.
  - `EntryDisplay`: every row of the table in section 4.3.
- **Contract:** a valid id; another tenant's id; a nonexistent id; a multi-select with one bad element; a link row with a bad target.
- **`EntryForm` and the admin Create Entry request:**
  - an entity with a reference dropdown can be created;
  - the "This form does not support these fields" message no longer appears for references.
- **Entity definitions:**
  - `EntitySchemaValidation` covers all three cases in section 3.6, and a trashed target still allows saving.
  - Trash guard:
    - Instructor can't be trashed while Course's dropdown references it, and the message names "Course › 授课教师";
    - it can be trashed once the dropdown is removed;
    - a shared entity that another tenant's entity references can't be trashed.
  - Save guard:
    - saving Instructor fails when 姓名 is deleted, retyped to a non-labelable type, or hidden from an audience of a launched form that shows it;
    - changing the field's name from 姓名 to 全名 succeeds.
  - Operations specs cover:
    - `value_field` rejected and `label_field` required;
    - the four new violation codes;
    - version 2 in `Operations::Activities::Execute` / `Confirm`.
  - `tool_examples_contract_spec` passes.
- **Generator and renderer:**
  - help text is copied;
  - derived fields are left out of generated forms and the palette;
  - translated headings appear in both locales, and link-row fields get "Linked: <related entity>" in both grouping modes;
  - `ArgumentError` is raised for unknown element types;
  - a section is hidden for an audience that can see none of its fields, and a content-only section stays.
- **Lifecycle:**
  - Trash and restore:
    - trashing an entity takes its live forms offline, including other tenants' forms for a shared entity, and produces the flash message;
    - a failure rolls the trash back;
    - restoring lists the offline forms.
  - `Page.for_entity` and `Page.bound_to_flowchart` match ids stored as JSON numbers and as strings, and `bound_to_flowchart` finds tenant override heads.
  - The launch check blocks:
    - a dropdown whose label is hidden from an audience, or whose target is missing or trashed;
    - a missing required field, own or on a link row, for each audience, even when the field has a default value;
    - an offline, trashed or missing flowchart, and a customer flowchart bound to another entity.
  - The launch check doesn't require derived fields or fields hidden from an audience, and it finds fields inside columns containers.
  - Restoring an entity whose reference target was permanently deleted succeeds.
  - `Pages::VisibilityContract` refuses widening a launched form to an audience that fails those checks, and doesn't check offline pages.
  - Flowchart guards:
    - trash is refused while launched forms use the flowchart, including through an override head and when the flowchart is a draft;
    - the controller shows the alert;
    - taking it offline reports the count.
  - `GeneratePage` reports a skipped page when its flowchart is offline.
  - The tenant-facing launch messages contain neither "flowchart" nor "流程图" in either locale.
- **Components:**
  - the detail drawer and entries table show labels, names and derived values;
  - "Can't be submitted" appears for a launched form with a blocker and takes precedence over "Out of date";
  - "Out of date" appears otherwise, in the forms list and on the page show header.

Vitest: the `entity_form` managers (modal, type, association) and any new manager at 100% lines and branches (`npx vitest run --coverage`).

Final run: the contract change touches every write path, so run the full suite in parallel (`bin/rails parallel:prepare && bin/rails parallel:spec`).

## 11. Out of scope (later sub-projects)

- **References and dropdowns:**
  - What happens to references when a referenced record is deleted or its label changes. Today the display shows "Missing record (#id)".
  - Lists of related records on the detail drawer, and searching the entries list by a referenced record's name.
  - Dropdown search beyond 200 records.
  - Filtering a dropdown's choices, for example leaving out former instructors.
  - A second display field ("001 · Jenny"), and uniqueness rules for codes.
  - Sorting reference and option columns by their labels.
- **Link rows and business rules:**
  - A submission writes at most one row per link entity. Nothing enrols a student in an existing course, and link rows can't be listed or edited.
  - Enforcing capacity; seats remaining can go below zero.
  - Running the form's flowchart from admin Create Entry, so business rules added to the flowchart later won't apply there.
- **Forms:**
  - Required base-model fields in the launch check.
  - Re-checking a launched form when it is edited in the builder belongs to the live-forms sub-project. Until then, the "Can't be submitted" badge reports missing required fields.
  - Syncing a form with its entity, or regenerating it.
  - Wizard steps that end up with nothing visible.
  - Base-model section headings, which still use the model's humanized name.
- **Permissions:** per-audience editability, entry ownership, record-level visibility and member self-service.
