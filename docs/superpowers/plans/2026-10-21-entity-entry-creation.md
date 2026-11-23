# Entity entry creation — implementation plan

**Date:** 2026-10-21 · **Status:** implementation, bilingual references, integrated QA and scoped release verification completed; ready for parallel review (pending)

**Goal:** Generalize Create Entry from Course (`/81721200/admin/entities/60`) to active, non-bridge entities. Add nested admin new/create routes, a primary-record form, and a small Trailblazer creation activity. **No migration.** [UX specification](../specs/2026-10-21-entity-entry-creation-ux.md).

## Findings that determine the implementation

- `app/views/admin/entities/show.html.erb` already passes Export CSV to `AdminPageComponent`. That component is the current dashboard header implementation; do not reference the retired `Dashboard::PageHeaderComponent` name.
- `Admin::EntityEntriesController` already serves browse show/destroy/batch and maintenance index/destroy. Add creation only to its browse mount. Its existing `find_entry` remains limited to show/destroy.
- `Entity#after_find` hydrates definition attributes from `resolved_current_version`; `grouped_property_schema`, `input_fields`, and `EntityAttributeAudience` provide existing schema/order/audience rules. `EntityEntry#before_create` stamps the effective version.
- Before implementation, `EntityEntry.build_for` provided read-only derived accessors while `EntityEntryContract.build_for` declared every property writable. An **unsaved** Course probe validated successfully, then `contract.sync` raised `NoMethodError: enrolled_count=`. The shared contract factory now disables derived writes/parsing without dropping readers or validators; no second validator engine was introduced.
- Course needs text/textarea/select/date/number, four groups, defaults `线下` and `筹备中`, and admin-only internal notes. Other practical supported controls are listed in the UX input table. Explicitly block unsupported visible input semantics.
- `PageFieldPopulator` also expands bridges/base fields, and `Pages::FormParams` depends on Page configuration/rules. Neither is the form's schema service. Reuse their established schema conventions without instantiating a Page or executing a flowchart.

## Implemented shared interfaces

### Form service (backend-owned)

```ruby
Entities::EntryForm.new(entity:, customer:, params: nil)
# params == nil: GET defaults; params == {}: a submitted empty data object

form.entity                  # authorized, effective-schema Entity
form.groups                  # ordered Group objects, filtered to writable fields
form.writable_slugs           # frozen Array<String>; only supported admin inputs
form.filtered_input           # string-keyed Hash passed to Reform; defaults + attempt
form.values                   # display values; raw attempted literals retained
form.errors                   # Hash<String, Array<String>>, with "base" for general errors
form.available?               # schema readiness, not an authorization decision
form.blockers                 # descriptors for unsupported visible writable fields
form.value_for(slug)
form.errors_for(slug)
form.add_errors!(errors)       # merge translated keyed errors without rebuilding values
```

Data objects, not ORM objects, inside groups:

```ruby
Group = { key:, label:, fields: } # label nil for ungrouped; view translates fallback
Field = { slug:, label:, help_text:, html_type:, required:, options:,
          constraints:, full_width:, invalid_literal: }
# options: [[label, value], ...]; normalized string values
# constraints: only server-derived min/max/step/minlength/maxlength when applicable
# invalid_literal: native number/date control cannot represent the attempted literal
```

Use readers with these names (Struct/Data or plain POROs); frontend never parses entity JSON or queries option sources. `label` resolves `display_label.presence || name`; `help_text` uses `description`; metadata stays escaped at render time. `required` reflects `EntityAttributeAudience.applying_audiences(field).include?("admin")` plus a presence validator.

Service rules:

1. Read/reload the effective definition under `Current.set(customer:, shared_resources_mode: false)` before building descriptors. Keep that context around contract construction and save too. Never resolve shared schemas with the global `current_version` or another tenant's head.
2. Filter by admin visibility; exclude Calculated/Computed, computed storage, readonly fields, `EntityReference`, and internal columns. The new endpoint additionally refuses bridge entity targets.
3. Apply the explicit UX control map. Unsupported **visible writable** fields block submission even if optional; no arbitrary text fallback. Treat an empty writable form as unavailable. Hidden/derived unsupported fields do not create blockers.
4. Support static `config.options` (including already-materialized constant options), scalar selects/radios, scalar text/numbers/dates, array multi-selects and optionless booleans. Dynamic option bindings are blockers. Do not implement live lookup, relationship selection, uploads, or related-record writes.
5. Defaults: filter `default_properties_json` through the same write set and value-shape rules; fall back to options marked `default: true` only when no explicit default key exists. Overlay submitted keys by **key presence**, preserving false/zero/empty; default selection for radio/single select must be unambiguous.
6. Submitted wrapper is `entry[data]`. Accept JSON-safe scalars only for scalar fields and arrays of choice scalars only for multi-selects; reject objects/nested arrays/uploads with keyed 422 errors. Unknown/internal/hidden/derived keys are discarded, including defaults. Do not use an unrestricted mass-assignment hash.
7. Normalize recognized boolean literals to `"0"`/`"1"`, with hidden false sent by the UI; reject other literals rather than turning them into false. Send a blank hidden sentinel for multi-selects; remove that sentinel to preserve a submitted empty array. Validate nonblank choice values against the effective static option values independently of optional schema inclusion validators. Preserve a rejected scalar choice in the failed select as an escaped, selected error option; a rejected radio value is echoed in its inline error. It is not added to the allowed choices.
8. Preserve scalar literals for numeric validators (never `to_i`/`to_f` invalid input into zero); check finite numeric syntax and strict real ISO dates with Ruby's standard parsers. Leave ranges, lengths and other configured rules to Reform. Empty values retain their configured validator semantics. On failure flag unrepresentable numeric/date literals for the text rerender.
9. Keep `values` distinct from normalized `filtered_input` where necessary. A failed POST reuses its form object; it must not restart the GET-default path. Filtered-out keys never reappear in HTML. Nonrendered contract errors remain visible in the summary.

### Contract and creation activity (backend-owned)

```ruby
EntityEntryContract.build_for(entity, audience: "admin", writable_slugs: form.writable_slugs)
# New optional writable_slugs keyword; nil retains ordinary input syncing for other callers.

Entities::Activities::CreateEntry.call(customer:, actor:, entity:, params:)
# params is the object-shaped entry[data] Hash or ActionController::Parameters,
# never a whole controller params object; the service owns per-field shape filtering.
# Returns [signal, ctx] using the standard Trailblazer Activity calling convention.
# ctx[:form] => EntryForm; ctx[:model] => unsaved/persisted EntityEntry
# ctx[:contract] => EntityEntryContract; ctx[:errors] => keyed translated errors
# signal.to_h[:semantic] => :success, :failure or :forbidden
```

`CreateEntry` is a `Trailblazer::Activity::Railway`. Its keyword adapter wraps the installed `[input, {}]` Activity API and returns `[signal, ctx]`, retaining `Current.set(customer:, shared_resources_mode: false)` around the complete call. The controller branches on the terminal semantic, not internal step names.

Pipeline: establish customer context → authorize actor/entity → reload effective schema/build form and runtime model → reject unavailable/invalid shapes/literals → build admin contract → validate → `contract.save` (sync allowed properties and save) → collect errors on failure. The model binds `customer_id` and `entity` from trusted arguments. Save runs in `EntityEntry.transaction(requires_new: true)`, rolling back a false contract save and handling `RecordInvalid`/`RecordNotSaved`. This path persists one primary model, with no `ActivitySteps::SaveAll`, page submission or generated flowchart execution.

**Implemented derived contract fix:** `EntityEntryContract.schema_property_options` returns Reform 2.6's exact `{ writeable: false, parse: false }` for Calculated/Computed types, `storage: "computed"`, and properties outside a non-nil `writable_slugs` set. Readers and existing audience-scoped validations remain declared. `property_accessor(name, validates: nil, **property_options)` forwards the options, and `ContractGenerator.new(entity, writable_slugs: nil)` emits the same flags. A hidden ordinary property outside the admin form's write set is not synced as nil; with `writable_slugs: nil`, ordinary properties keep their normal write behavior. Regression specs exercise readers/validators plus `sync` **and** `save` with real `EntityEntry.build_for` objects.

**Implemented runtime factory guard:** `EntityEntry.build_for` skips schema slugs in `column_names + %w[entity customer]`, preserving authoritative AR columns/associations. Anonymous subclasses return `EntityEntry.model_name`, so Rails/I18n errors and `RecordInvalid` can use the parent model identity. This guard is factory-specific; it does not change `ModelGenerator` or the general `attribute_accessor` DSL.

The activity additionally checks `actor.admin_or_owner?`, same-customer actor or pinned `platform_owner?`, and active/non-bridge entity ownership/shared accessibility. Role/audience/customer are server-controlled. This makes direct service calls respect the same boundary as HTTP. Each POST uses a freshly resolved schema; no submitted schema, audience or provenance token is authoritative.

### HTTP boundary (security-owned)

Routes at the existing browse nesting:

```text
GET  /:cid/admin/entities/:entity_id/entries/new  → Admin::EntityEntriesController#new
POST /:cid/admin/entities/:entity_id/entries      → Admin::EntityEntriesController#create
new_admin_entity_entry_path(cid, entity)
admin_entity_entries_path(cid, entity)
```

Browse `entries` now uses `only: %i[new create show destroy]` and retains the batch collection route. Creation is not mounted in maintenance/platform. The route comment describes browse-and-entry actions. `find_entity` and existing-record `find_entry` both use path parameters, so body/query IDs do not replace the routed entity or entry.

- Inherit `ApplicationController`'s `TenantContext`, `RouteAuthorization`, CanCan and MFA guards. These centrally guard both new verbs at the controller layer; do not duplicate or bypass role filters.
- Resolve the entity using `request.path_parameters[:entity_id]` and `Entity.where(customer_id: current_customer.id).or(Entity.shared)`. For new/create additionally require active, non-bridge. The path-derived current customer controls writes, even for a cross-tenant owner; body/query IDs never replace it.
- GET: `@entry_form = Entities::EntryForm.new(entity: @entity, customer: current_customer)`; render `new`, explicitly `layout: "dashboard"` for full-page behavior.
- POST: require object-shaped `entry` and `entry[data]`; malformed/missing wrappers return 400 (an empty data object is valid wrapper shape). Pass the inner Hash/Parameters object plus trusted actor/customer/entity to the activity without `permit!` or unrestricted conversion. EntryForm reads only its allowlisted keys, reports malformed field shapes, and exposes a plain filtered hash to Reform.
- Success: 303 to `admin_entity_path(current_customer.id, @entity)` with translated flash. Failure: `@entry_form = ctx[:form]`; render `new`, status 422, explicit dashboard layout. `:forbidden` uses existing access-denied handling. Other requested response formats use existing Rails negotiation; no new JSON-create API is required.
- New and POST use full-page HTML, not the existing `entity-entry-detail` Turbo frame. Header link targets `_top`; form uses `data-turbo-frame="_top"`.

### Components (frontend-owned)

```ruby
Admin::Entities::EntryFormComponent.new(form:, create_path:, cancel_path:)
Admin::Entities::EntryFieldComponent.new(field:, value:, errors:)
```

The thin `app/views/admin/entity_entries/new.html.erb` mounts the existing admin shell and form component. Header integration in `app/views/admin/entities/show.html.erb` adds primary Create Entry before Export CSV. Both URL helpers come from the security contract above.

`EntryFieldComponent` uses a fixed class map, sets names `entry[data][slug]` (arrays add `[]`), consumes descriptors, and never constantizes a schema value. The implemented adapter owns labels/help/errors and ARIA; supported `FormFields` controls use `input_only: true` and explicit IDs, with matching radio/toggle templates and checkbox checked state. The form composes responsive cards, a linked summary, raw-literal fallback and footer. It reuses `ButtonComponent` with a real submit and `name: nil`. The browser header opts into `AdminPageComponent(wrap_title: true, wrap_actions: true)`; the new form uses `width: :narrow, wrap_title: true`. No new Stimulus controller was added.

### Platform copy (frontend-owned, backend consumes error keys)

The following suffixes are present under `admin_misc.entities.entry_form` in both area locale files. The UI reuses `common.actions.cancel` and `comp_form_fields.select.blank_option`. Schema-authored metadata is escaped data; all new platform wording is translated at call/render time.

| Key suffix | English | 简体中文 |
|---|---|---|
| `create` | Create Entry | 创建条目 |
| `title` | Create Entry — %{name} | 创建条目 — %{name} |
| `description` | Add a new record to %{name}. | 为%{name}添加一条记录。 |
| `submitting` | Creating… | 正在创建… |
| `other_fields` | Other fields | 其他字段 |
| `errors_heading` | Please correct the errors below. | 请修正以下错误。 |
| `unsupported_fields` | This form does not support these fields: %{fields}. | 此表单暂不支持以下字段：%{fields}。 |
| `no_fields` | No editable fields are available for this entity. | 此实体没有可编辑的字段。 |
| `created` | Entry created successfully. | 条目创建成功。 |
| `errors.invalid_shape` | Enter a value in the expected format. | 请按要求的格式输入。 |
| `errors.invalid_choice` | Select an available option. | 请选择有效选项。 |
| `errors.invalid_number` | Enter a valid number. | 请输入有效数字。 |
| `errors.invalid_date` | Enter a valid date in YYYY-MM-DD format. | 请输入 YYYY-MM-DD 格式的有效日期。 |
| `errors.invalid_boolean` | Choose a valid checkbox value. | 请选择有效的勾选值。 |
| `errors.rejected_value` | Submitted value: %{value} | 本次提交值：%{value} |
| `errors.save_failed` | The entry could not be created. Please try again. | 条目创建失败，请重试。 |

Reform's standard validation messages use existing Rails locale keys, with the summary resolving visible attribute names from descriptors rather than humanized slugs. Backend and frontend share these error keys; both translations are present.

## Parallel build ownership and sequence

The source/spec delivery items below are present in the working tree. Checked delivery items record file implementation, not successful execution of application tests or browser journeys. Pre-existing uncommitted developer-reference changes, including the entity-builder assistant-generated-page discussion, are preserved.

1. **Interface checkpoint:** builders agree on the exact readers, keyword call, context keys, field names and route helpers above. Frontend uses form/descriptor doubles; security can wire the controller against the documented activity result.
2. **Parallel lanes:**
   - [x] **Backend implementation/spec delivery:** `app/services/entities/entry_form.rb`, `app/services/entities/activities/create_entry.rb`, shared contract/generator flags and `EntityEntry` factory guards; service/activity/contract/generator/model regression specs added.
   - [x] **Frontend implementation/spec delivery:** entry form/field component pairs and new view; entity-show action and wrapping header; scoped `FormFields` adapter support; both `config/locales/admin_misc.{en,zh-CN}.yml`; component/DOM/localization and header-view specs added.
   - [x] **Security implementation/spec delivery:** browse routes, controller new/create and path-based lookup; `spec/requests/admin/entity_entry_creation_spec.rb` covers authorization, wrappers, tenant isolation and shared heads; routing specs added.
3. [x] **Integrated QA:** rerun after the rooted `::Entities::ComputedLoader` fix passed **105 examples, 0 failures**. The integrated specs exercise schema/default/input boundaries, primary persistence, authorization and shared overrides; results were supplied by the QA owner.
4. [x] **Integration/docs delivery:** inspected fresh implementation/reference diffs; updated `doc/reference/{en,zh-CN}/{entity-builder,flowchart-runtime,dashboard,page-rendering}.md` against actual behavior through additive/current-text patches, preserving user-authored additions. Exact sections are listed below.
5. [x] **Scoped release verification:** **29 spec files, 541 examples, 0 failures**; RuboCop inspected **26 files, no offenses**; Tailwind build passed. Development GET smoke and Course's bilingual Chromium matrix passed as recorded below. Shared-entity browser smoke was unavailable because development has no eligible active, non-bridge shared entity; shared behavior is covered by request specs. Browser smoke used `SKIP_AUTH=1`; authorization is verified by the request specs, not that bypassed browser session.
6. [ ] **Parallel review — pending:** anysys-tech-lead checks conventions/I18n/docs; anysys-code-reviewer checks allowlists, derived-property flags, hidden defaults, owner tenant binding and primary-only atomic persistence. No review completion evidence has been provided.

## Verification results and readiness

These checkboxes record verification backed by the QA/release results supplied on 2026-10-21 and the inspected browser artifacts, independently of source/spec delivery. The scoped evidence supports readiness for parallel review; that review remains pending.

**Integration verification status (2026-10-21):** the post-fix integrated QA rerun and scoped release checks passed. Course browser smoke is complete for both pages in both locales at all three recorded widths. Shared-entity browser smoke was not exercised; its request-spec coverage passed in the targeted verification.

- [x] **Form service:** admin visibility versus `validator_apply`; group/field order; inherited missing `html_type`; defaults including false/zero; explicit blanks and empty array; excluded provenance/IDs; wrong shapes; invalid numeric/date raw rerender; choice label/value distinctions; unsupported/empty schema; shared head versus global default.
- [x] **Activity/contract:** valid primary-only save; validation rollback; contract-save failure; derived read/validation retention plus no derived setter calls; hidden fields never synced; direct service forbidden for members/foreign admins; pinned owner writes to the path customer; effective version stamp.
- [x] **Requests/components:** nested GET/POST helpers; header action; 303/422/400; member/anonymous/foreign guards; foreign entity and bridge target 404; forged body/query IDs; shared overrides; no bridge/Enrollment/base-model writes; both locales; accessible labels/help/errors and linked summary; no frame-only new response.
- [x] **Course GET browser smoke:** Chromium, `en`/`zh-CN`, **375/768/1280px**, entries browser and new-entry form (**12 checks**) plus Create/Cancel footer visibility/layout (**6 checks**), all passed.
- [x] **Read-only development smoke:** no non-GET requests; development record counts were **0 before and 0 after**. The browser did not submit a create or validation-failure POST.

### Recorded verification evidence

| Check | Result | Scope / evidence |
|---|---|---|
| Integrated QA after the loader namespace fix | **105 examples, 0 failures** | QA-owner supplied result; rooted `::Entities::ComputedLoader` in place |
| Release targeted RSpec | **29 spec files, 541 examples, 0 failures** | Release-owner supplied result; targeted feature/shared-consumer scope |
| RuboCop | **26 files, no offenses** | Release-owner supplied result |
| `bin/rails tailwindcss:build` | **Passed** | Generated tracked `app/assets/builds/tailwind.css` changed; browser-served and built stylesheet hashes match |
| Development GET smoke | **All 200** | `/up`, `/81721200/admin/entities/60`, `/81721200/admin/entities/60/entries/new`, with `SKIP_AUTH=1` |
| Chromium page matrix | **12 checks passed** | Two pages × two locales × three widths; `/tmp/opencode/entity-entry-release-browser-evidence.json` |
| Chromium footer matrix | **6 checks passed** | New form × two locales × three widths; `/tmp/opencode/entity-entry-release-footer-evidence.json` |
| Development record preservation | **0 before / 0 after** | Release-owner supplied counts; browser artifacts record no non-GET requests |

The page matrix reports no horizontal overflow, missing translations, page errors, failing local/external resources or non-GET requests. Each new form exposes **14 labeled controls** in **four groups**, with defaults `delivery_mode = "线下"` and `status = "筹备中"`, admin-only notes visible and computed controls omitted. Footer checks confirm both Create and Cancel remain visible at each width/locale.

No eligible active, non-bridge shared entity exists in development for browser smoke. Shared global-default/override behavior remains covered by request specs; a shared browser journey is not claimed. The development browser used the authentication bypass, so it is read-only presentation evidence rather than real-session authorization evidence or a live successful-create/422 journey.

Verification was targeted: no full-suite result is claimed. JavaScript is unchanged for this slice; no Vitest run is claimed. Parallel tech-lead/code review is the remaining recorded readiness step.

### Feature and shared-consumer spec inventory

Reference inventory for this slice; the release result above is scoped to the reported 29-file selection:

```text
spec/services/entities/entry_form_spec.rb (new)
spec/services/entities/activities/create_entry_spec.rb (new)
spec/contracts/entity_entry_contract_spec.rb
spec/services/contract_generator_spec.rb
spec/models/entity_entry_spec.rb
spec/models/entity_entry_calculated_fields_spec.rb
spec/services/dynamic_class_loader_spec.rb
spec/services/activity_steps/save_all_spec.rb
spec/services/activity_steps/populate_primary_spec.rb
spec/services/flowchart_runtime/entries_spec.rb
spec/requests/admin/entity_entries_spec.rb
spec/requests/admin/entity_entry_creation_spec.rb (new)
spec/requests/admin/entities_spec.rb
spec/routing/admin_entity_entries_routing_spec.rb (new)
spec/views/admin/entities/show.html.erb_spec.rb (new)
spec/views/admin/entity_entries/new.html.erb_spec.rb (new)
spec/components/admin/entities/entry_form_component_spec.rb (new)
spec/components/admin/entities/entry_field_component_spec.rb (new)
spec/components/admin_page_component_spec.rb
spec/components/form_fields/ — touched controls only
```

The component/localization checks cover matching `entry_form` key sets and interpolation variables in both area files. The results above are recorded from the supplied QA/release evidence and inspected artifacts; this final plan update does not represent a new application-test, asset-build or browser execution.

## Completed bilingual developer reference integration

The paired reference pages now describe the implemented working-tree behavior. English/Simplified Chinese sections, examples and callouts are kept in lockstep. Existing assistant/page/flowchart-builder reference additions were retained.

### Entity builder — Entries / 记录

- [x] **Summary front matter and Flow / 流程:** entry creation is discoverable in the summary; Records includes `EntryForm` → `CreateEntry` → `EntityEntryContract` → primary save.
- [x] **Entries / 记录:** replace the obsolete no-create claim; retain maintenance index/destroy, browse show/destroy/batch and no update route; document exact runtime factory guards and contract/generator flags.
- [x] **Entries / 记录:** document the rooted `::Entities::ComputedLoader` call, result-row/tenant scoping, empty-result skip and aggregate reads on the browser GET after creation.
- [x] **Admin Create Entry / 管理端创建条目:** GET/POST URLs/helpers, full-page navigation, object wrappers and 303/422/400/406 responses.
- [x] **Effective schema, groups and defaults / 生效结构、分组与默认值:** effective shared head/global fallback, admin visibility/write exclusions, descriptor order, explicit defaults and submitted key-presence semantics.
- [x] **Supported inputs and validation / 支持的输入与校验:** explicit control map, static choices, boolean normalization, shape/literal validation, unsupported-field blockers and retained contract validators.
- [x] **Primary persistence and presentation / 主记录保存与展示:** primary-only savepoint, no derived/bridge/base writes, component adapter, attempted-value/error handling, I18n and responsive composition.
- [x] **Controllers and authorization / 控制器与授权; Key code / 关键代码:** controller/direct-activity authorization, path tenant/IDs/provenance, plus the actual admin contract construction excerpt.

### Flowchart runtime — Records / 记录

- [x] **Shared model and contract write boundaries / 共用模型与契约的写入边界:** real-column/association accessor collision guard, parent `model_name`, exact `writeable: false, parse: false` behavior including computed storage, non-nil write-set versus nil semantics, retained readers/validators, generator parity and direct primary creation outside flowchart/SaveAll execution.
- [x] **Key code / 关键代码:** identical actual `schema_property_options` excerpt in both locales.

### Dashboard — Shared admin page header / 共用管理页页头

- [x] Document the implemented optional `wrap_actions` default/breakpoints and entity-browser use, with a cross-link to the primary-entry form reference.

### Page rendering — Reusable field component API / 可复用字段组件 API

- [x] Document `BaseFieldComponent`'s `input_only` default, explicit ID precedence, wrapper/theme behavior and caller-owned labels/help/errors/ARIA; checkbox/radio/toggle adapter details and form-owned hidden sentinels. Cross-link from the entry form reference.

### Completed documentation verification

- [x] Automated parity checks for all four English/Simplified Chinese page pairs: heading hierarchy, paired added sections, technical tokens, table rows, code examples, inline commands and callouts.
- [x] New Ruby excerpts match the actual `CreateEntry` and `EntityEntryContract` source.
- [x] Plan spec paths exist; pre-existing assistant/page/flowchart-builder edits match their initial working-tree hashes, and both entity-builder assistant-generated-page paragraphs are retained.
- [x] `git diff --check` succeeds.
