# Core route source audit — 2026-10-11

## Evidence and scope

The original audit was read-only: `config/routes.rb` was read in full, every eligible controller action was traced through its scopes, concerns, activities/contracts, models and declared database invariants, and relevant specs were inspected. No requests, tests, application boot, database queries or subagents were executed. Git status was clean at the original audit's beginning and end. Source-confirmed findings are deductions from inspected code and stated triggers, not executed reproductions.

This report preserves that audit and records the subsequent security-engineer controller/helper implementation. Finding citations below refer to the **pre-remediation source line numbers**; the shared working tree now contains concurrent backend/domain changes. Re-read current source before applying these anchors. Runtime verification remains pending.

### Exact boundaries

* Include core admin entity definitions, entity/entry browse and deletion, index settings, entity-page redirects, runtime admin page browsing/batch operations, module catalog/generic entries/how-to/configuration, search, maintenance landing/customer profile, constants and entities at tenant and platform mounts, module lifecycle, platform customers/module settings/industry catalog/developer docs/customer contexts.
* Exclude **all tenant/platform maintenance flowchart and page controllers and nested routes**, builder-only template picker/standalone layout previews/field templates/code-generator I/O and execution APIs.
* Entity version `page` is excluded at both mounts: its sole purpose is builder-managed page creation. Version metadata listing remains included.
* Authentication, payments, email, SMS, website, AI, support and billing domain implementations belong to separate audits. Common authorization/tenant-context and generic module lifecycle interfaces were inspected as dependencies.
* Never read/search/execute `app/services/page_layout_templates/templates/**`. Only the registry facade/loader and catalog integration were inspected.

## Exhaustive controller/action coverage

Notation: A=`/:customer_id/admin`, T=`A/maintenance`, P=`T/platform`. The table covers **87 distinct eligible controller/action pairs**; remounts/aliases are listed separately rather than counted as new actions. REST reads are GET, create POST, update PATCH/PUT, destroy DELETE. JSON/HTML/CSV branches were inspected where present. `config/routes.rb` was not changed by the security-engineer lane.

| Controller | Eligible actions | Mounts / aliases |
| --- | --- | --- |
| `admin/entity_definitions` | index | A/entity_definitions, Bearer JSON API |
| `admin/entities` | index, show | A/entities; show HTML/CSV |
| `admin/entity_entries` | index, show, destroy, batch_destroy | index T/entities/:entity_id/entries; show A; destroy A/T; DELETE A/.../entries/batch |
| `admin/entity_index_settings` | update | A/entities/:entity_id/index_setting |
| `admin/entity_pages` | index | A/entities/:entity_id/pages, redirect |
| `admin/pages` | index, show, batch_update | A/pages; index aliases uncategorized and entities/:entity_id; PATCH batch |
| `admin/modules` | index | A/modules |
| `admin/module_entries` | show | A/modules/:module_key/entries/:key |
| `admin/module_howtos` | show | A/modules/:module_key/howto |
| `admin/settings` | show | A/settings |
| `admin/module_configs` | show, update | A/settings/modules/:key; show alias /:entry_key |
| `admin/search` | index | A/search |
| `admin/maintenances` | show | A/maintenance |
| `admin/maintenance/customer_profiles` | show, edit, update | T/customer_profile |
| `admin/maintenance/constants` | index, show, new, create, edit, update, destroy | T/P constants |
| `admin/maintenance/constant_copies` | show | T/P constants/:constant_id/copy; unsaved form |
| `admin/maintenance/shared_resource_overrides` | destroy | T constants/entity override branches only |
| `admin/maintenance/entities` | index, show, new, create, edit, update, destroy, trash, empty_trash, template_fields, base_model_fields | T/P entities |
| `admin/maintenance/entity_restorations` | update | T/P entities/:entity_id/restoration |
| `admin/maintenance/entity_copies` | show | T/P entities/:entity_id/copy |
| `admin/maintenance/entity_template_previews` | show | T/P finder/reference parser; preview renderer boundary |
| `admin/maintenance/entity_versions` | index, show, create, edit, destroy, default | T/P entity versions; PUT default; page excluded |
| `admin/maintenance/modules` | index | T/modules |
| `admin/maintenance/module_enablements` | create, destroy | T/modules/:module_id/enablement |
| `admin/maintenance/module_sub_toggles` | update | T/modules/:module_id/sub_toggle |
| `admin/maintenance/module_owner_configurations` | update | T/modules/:module_id/owner_configuration, extra owner guard |
| `admin/maintenance/platform/customers` | index, show, new, create, edit, update, destroy, trash, empty_trash | P/customers; edit is template-backed |
| `admin/maintenance/platform/customer_restorations` | update | P/customers/:customer_id/restoration; nested target parameter differs from outer path identity |
| `admin/maintenance/platform/module_settings` | index, show, update, configuration, developer | P/module_settings |
| `admin/maintenance/platform/industry_templates` | index, show, edit, update | P/industry_templates, business catalog only |
| `admin/maintenance/platform/industry_template_assignments` | create, destroy | nested template_assignments |
| `admin/maintenance/platform/industry_template_cards` | show | nested template_cards, membership/catalog only |
| `admin/maintenance/platform/industry_template_default_seeds` | create, destroy | collection default_seed; seed missing / reset all |
| `admin/maintenance/platform/industry_template_new_template_seeds` | create | collection new_template_seed |
| `admin/maintenance/platform/developer_docs` | index, show | allowlisted slug |
| `admin/maintenance/platform/customer_contexts` | update, destroy, search | singular customer_context + search GET |

Route source ranges: core `258–370`; tenant definitions/modules `374–408`; platform shared definitions `483–504`; customers `547–553`; module settings `585–590`; industry catalog `653–665`; developer docs/context `689–699`.

**Absent mounts are intentional facts, not audited actions:** platform constants/entities have no override-reset route; entity entries are not remounted as shared platform records. Customer-specific reset stays on the tenant prefix.

## Backend chains

### Common request pipeline

`PlatformPathHelper` mode setup → `TenantContext` path-derived customer/request metadata → enabled registration `before_request` hooks → `RouteAuthorization` authentication/role/route-subject checks → MFA boundary → action-specific finder. `TenantScoped` does not install a tenant default scope. `SharedIdentity.accessible` explicitly selects the current tenant plus shared NULL-owned rows.

The original `TenantContext` rejected signed-in foreign users on public paths too. The follow-up fixes that: cross-tenant checks apply to protected admin/member paths; public visitors remain allowed. `current_tenant_user` provides same-tenant-only attribution, distinct from privileged actor authorization. Domain callers must use this helper or an equivalent backend check for tenant-owned card/member attribution.

### Entity definition API

`EntityDefinitionsController#index` → prepended Bearer concern → `EntityDefinitions::List` Railway → `Entity.accessible.by_name` → `Serializer` → hydrated fields and `resolved_current_version` → JSON. No entry-data lookup. Token internals are an authentication-audit boundary. Unpaginated/N+1 scaling was noted, not ranked as a confirmed correctness defect.

### Entity browse, entry deletion and index preference

Entity index → `EntityAssociationGraph` → primary redirect/empty state. Show → own/shared entity finder → `EntityIndexSetting` → columns/filters → customer+entity entry relation → `ModuleEntriesResolver` → computed compiler/loader → HTML or CSV. Index preference update → operation → Reform contract (allowed slugs, system exclusions, 50-key cap) → unique customer/entity row. Entry show/index/delete/batch all scope by both current customer and entity. Resolver caps ordinary pagination at 200; CSV explicitly caps at 100,000. Sort SQL uses declared columns, computed functions/operators/slugs are allowlisted and tenant-predicated, and search/filter values are bound/quoted.

### Runtime page browse

Entity pages → scoped entity → unified filter redirect. Pages index → path selection → accessible/for-entity/uncategorized relation → columns/launch filter/resolver → ops table and sidebar counts. Show → accessible page → publishing panel links. Original bulk mutation used `update_all`; follow-up uses validated lifecycle methods and one transaction. Page hydration resolves overrides, but original grouping/count SQL joins global `current_version`; override-rebinding reachability remains a builder-write boundary.

### Module catalog/configuration/search

Module hub → `Dashboard::ModuleCards` → available-for-customer modules → known links or registration contributions. Generic entries → key/singular alias → enabled assignment gate → registration entry relation → resolver. Payment logs, email templates/send activities/lists, SMS messages and website pages use current-tenant relations; other registrations have no generic entries. How-to/settings use contribution permission projection. Generic module config uses key whitelists, owner-managed-key exclusion, handoff exit gate and locked assignment merge. Search uses scoped Pages/Entities/Modules sources, escaped LIKE, minimum two-character query, maximum five items/group.

### Constants

Path-specific scope/forced create identity → options normalization → Constant validation → tenant shared callbacks restore identity, stash incoming options, restore global options before parent save, persist customer override afterward. Matching global defaults do not create a new pinned override. Copies are unsaved forms with path-checked sources. Reset resolves an accessible shared parent and deletes the current customer's override.

### Entity maintenance/versioning

Path-specific identity/body whitelist → create identity → quota boundary → name/label/slug/category/schema/group/association/computed validation → Versionable content hash, per-line version number, head promotion, pruning/GC → transactional bridge sync. Destroy uses shared-global-write guard plus association protection/soft deletion. Trash/restoration distinguish owned tenant rows from platform shared rows. Versions scope to the current line; shared global snapshots are read fallback only, not tenant default/delete targets. Original promotion bypassed entity validation/bridge sync; follow-up delegates to `Entities::PromoteVersion`. Historical editor uses `VersionHydrator` plus selected reference and scoped lineage. Template fields use the registry/extractor; base-model fields require enabled owner-approved registry entries and AR ancestry. Entity show generates display-only source, not evaluated code.

### Module lifecycle

Active catalog/current assignments → enable transaction/provision → disable transaction/deprovision with required protection. Boolean sub-toggle requires declared key and boolean schema type. Owner configuration requires owner, active module/enabled assignment, owner-key whitelist and bounded integer strings. Payment revoke disables tenant accounts; email/SMS hooks are no-ops; captcha strips config on owned pages; website delegates provision/unpublishes; authentication delegates; AI hooks are no-ops. Provider/domain internals remain separately owned. Follow-up commits activation only after provisioning succeeds.

### Customers/context

Profile uses current customer, descriptive whitelist, owner-only tier. Platform customer CRUD uses owner guard, path identity, unscoped show and active edit/update/destroy. Create delegates reserved-role seed, required module provision and billing onboarding. Soft-delete/trash/purge/restoration are separate lifecycle operations. Follow-up purge calls `Customers::Purge` for the full deleted selection and reports its result. Context update redirects to an active target; later requests derive context from URL. Domain normalization/ownership/bounded DNS checks were inspected but not executed.

### Platform module settings

Key-or-ID module finder → model discovery/workspace. Updates cover status/required/handoff, lifecycle hooks, discovered extension metadata, schema defaults, platform template-token mutation and signup boundary. Mandatory status/required stay fixed; inactive required/handoff invariants have model checks. Follow-up prevalidates before mutation, locks the module and wraps mutations/required rollout in one transaction. Token sensitive-column check is early; token resolution is an email boundary. Default persistence across registration is backend-owned.

### Industry catalog/developer docs

Validated taxonomy → mapping queries and registry metadata → catalog membership; bulk replacement is transactional; assignment save checks registry keys; seeds use category-to-industry mapping and insert/model creation. Renderer/card implementations and template contents are excluded. Developer docs use Catalog allowlist → Repository locale fallback, safe YAML, bounded search, mtime cache → Kramdown/Rouge → link rewrite/Loofah sanitation. No original confirmed renderer/path-traversal defect. Follow-up preserves document locale through links and search without changing the user's global preference.

## Ranked original source-confirmed findings

### P1

**F1 — association cycles break tenant-wide dashboard HTML.** `app/services/entities_contributor.rb:20` recurses without a path/visited set; `sidebar_builder.rb:6–8` constructs contributors before menu filtering. `entity_association_graph.rb:8–17` has no cycle handling; schema validation only rejects self-reference (`app/models/concerns/entity_schema_validation.rb:174–180`). Trigger: Root→A→B→A. Result: stack exhaustion for dashboard layouts, including repair pages. Rootless A↔B also reports a false empty index. Fix: cycle-safe traversal plus explicit graph policy. Specs: `spec/services/entity_association_graph_spec.rb`, `spec/services/entities_contributor_spec.rb`, `spec/requests/admin/entities_spec.rb`.

**F2 — bulk publication bypasses preflight.** `app/controllers/admin/pages_controller.rb:39` directly launches; `app/models/concerns/page_launch_lifecycle.rb:22–28,43–49` requires active entity, fields and valid references. Trigger: batch launch a no-field/orphan page. Fix: shared validated lifecycle and truthful atomic/per-record results. Spec: `spec/requests/admin/pages_spec.rb:197` only checked flags.

### P2

**F3 — customer purge omits dependents and can partially purge.** `app/controllers/admin/maintenance/platform/customers_controller.rb:48–49`; `app/models/customer.rb:44–52` omits pages/constants/override rows/settings/logs and default-scoped children hide trashed entities. Restrictive FKs: `db/schema.rb:1394,1398,1400,1415`. Trigger: deleted customer with a page or archived entity. Fix: complete ownership-aware atomic purge. Spec: `spec/requests/admin/maintenance/platform/customers_spec.rb:254` uses a fresh customer.

**F4 — formatted platform collections leave shared mode.** `app/helpers/admin/maintenance/platform_path_helper.rb:10,52` excludes the dot boundary; `SharedResourceMode:32–36,47–53` chooses scope/identity from that mode. POST platform constants/entities `.json` creates tenant-owned records; GET includes tenant scope/overrides. Fix: anchored format-aware path identity. Specs: `spec/requests/admin/maintenance/platform/shared_resources_spec.rb:125,154`.

**F5 — shared global CUD accepts the wrong outer CID.** `config/routes.rb:188,479`; `app/controllers/concerns/route_authorization.rb:135–138`; `platform_path_helper.rb:10,52`. Owner on another customer's platform prefix can mutate global rows. Fix: actual outer PATH_INFO CID must be 81721200, independent of nested/body/query customer IDs. Owner-only path-lock violation, not tenant-admin escalation. Specs: shared resources path-lock examples; customers prefix tests.

**F6 — entity promotion bypasses validation/bridge reconciliation.** `app/controllers/admin/maintenance/base_versions_controller.rb:38–48`; `app/models/concerns/versionable.rb:275–289`; contrast ordinary controller sync at `entities_controller.rb:117–120`. Trigger: remove an association/bridge, then promote its historical version. Fix: entity-specific transactional promotion. Specs: `spec/requests/maintenance/entity_versions_spec.rb`, bridge lifecycle specs.

**F7 — historical edit ignores the selected snapshot and lineage.** `entity_versions_controller.rb:23–24` redirects with version; `entities_controller.rb:72–73` ignores it; existing form uses current fields and no lineage ID. Fix: scoped historical hydration and carry based-on ID on save without widening version-line access. Specs: entity version edit auth coverage; VersionHydrator specs.

**F8 — shared target deletion misses tenant referencers.** `app/models/concerns/entity_schema_validation.rb:216–219` permits shared targets; `bridge_entity_management.rb:133–142` restricted reverse lookup to shared parent's NULL CID. Trigger: delete shared target with live tenant associations. Fix: platform-only global referencer check. Specs: same-tenant association deletion tests and platform shared delete.

**F9 — malformed definition/reference shapes crash or silently save empty data.** `json_serializable.rb:60–69`; `entity_schema_validation.rb:50,98–105`; `model_generator.rb:83`; `entity_template_previews_controller.rb:18–20`. Triggers: `[null]`, scalar JSON, missing slug, non-object reference, invalid syntax. Fix: syntax/container/item/required-key validation and controlled responses before invalid form/renderer usage. Specs: entity CRUD/schema/preview requests.

**F10 — copy drops association display fields.** `entity_copies_controller.rb:12–14` omits display_field/display_field_label required by `entity_schema_validation.rb:192–197`. Fix: preserve display config, omit bridge identity. Spec: `spec/requests/admin/maintenance/entity_copies_spec.rb:24` lacks associated source.

**F11 — extension writes bypass approved registry.** `entities_controller.rb:189–203`; `app/models/entity.rb:256–267`; field read API gates registry/AR ancestry at controller `168–170`. Trigger: persist `extended_model=String` or unapproved class. Fix: backend approval/ancestry validation. No arbitrary execution or IDOR was established. Specs: entity extension update and base_model_fields guards.

**F12 — owner defaults reset on boot.** Module settings controller `146–150` saves schema defaults; `app/services/feature_modules/base_module.rb:107` overwrites schema; initializer `config/initializers/feature_modules.rb:29` registers all modules. Fix: preserve owner defaults independently from declaration metadata. Specs: module_settings defaults and BaseModule register preservation.

**F13 — platform updates partially commit; failed required provisioning is skipped on retry.** Module settings controller `50–56,117–128`, active-assignment skip at `124`. Trigger: availability update plus rejected sensitive token, or provisioning exception after activation. Fix: prevalidation/atomic mutations and activation after successful provisioning. Specs: module settings required/sensitive-token cases and tenant enablement failure.

**F14 — log FK blocks entry deletion.** `admin/entity_entries_controller.rb:33,51–53`; `app/models/feature_modules/log.rb:17`; restrictive FK `db/schema.rb:1401`; original EntityEntry lacks nullification. Trigger: referenced entry deletion. Fix: backend nullify/restrict policy plus atomic truthful controller result. Spec: entry delete/batch examples lack log.

**F15 — entry deletion leaves bridge records/phantom computed counts.** Entry controller direct destroy; `entity_entry.rb:223–229` validates keys only; bridge participant IDs are JSON (`bridge_entity_management.rb:188–211`); computed loader counts rows (`computed_definition.rb:147–157`). Fix: tenant-scoped reference cleanup/restriction. Specs: entry deletion plus computed-loader relations.

**F16 — restoration flashes success on false return.** `base_restorations_controller.rb:23–25` ignores validating `SoftDeletable#restore` at `soft_deletable.rb:56`. Trigger: trash A B, create A-B with same active slug, restore A B. Fix: surface failure, preserve dependent atomicity. Specs: entity/customer restoration happy paths.

**F17 — activation excludes inactive pages; submitted IDs fabricate counts.** `admin/pages_controller.rb:37,42`; active default scope `app/models/page.rb:154`. Trigger: deactivate then activate, duplicates/foreign/nonexistent IDs. Fix: owned with-deleted activation and actual successful matched-row count. Spec: `admin/pages_spec.rb:185,226` starts active.

**F18 — invalid customer enums raise before validation branches.** `customer.rb:19,25–26`; profile update and platform customer create/update. Trigger: invalid industry/tier. Fix: backend validating enums/contract. Specs: profile/customer invalid cases mostly blank name.

**F19 — CSV formula output.** `app/services/admin/entities/entries_csv.rb:19–21,28–36`; entity CSV controller `46–48`. Trigger: formula-leading text or heading exported unchanged. Fix: spreadsheet-safe text policy; CSV quoting alone is insufficient. Actual evaluation is client-dependent. Specs: EntriesCsv and entity CSV requests.

**F20 — malformed industry container clears catalog.** Industry controller `28–31` filters objects to empty; mapping model `22–25` deletes before recreate. Trigger: template_keys object rather than list. Fix: reject malformed shape before replacement; valid empty remains allowed. Spec: industry_templates malformed/clear cases.

**F21 — unknown module HTML update raises again in rescue redirect.** Module settings controller `41,62–65,189–196`: missing finder gets broad rescue then member helper with nil module. Fix: preserve 404 outside mutation rescue. Spec: failure tests stub existing module updates.

### P3

**F22 — uncategorized.html selects all.** Pages controller `69` exact suffix check. Fix: format-aware selection. Spec: admin pages uncategorized request.

**F23 — bridge-bound uncategorized count/list mismatch.** `admin/pages/tree_builder.rb:21,67–83` excludes bridge entities from known IDs; `page.rb:146` listing includes them. Fix: one backend classification relation. Specs: TreeBuilder and page entity grouping.

**F24 — Chinese catalog edit shows English categories.** `app/views/admin/maintenance/platform/industry_templates/edit.html.erb:39` emits meta label rather than `PageLayoutTemplates.category_label` (`page_layout_templates.rb:160–164`). Fix belongs catalog presentation owner, not this controller lane. Spec: industry Chinese wording currently only checks industry labels.

**F25 — parent purge leaves content orphans.** `soft_deletable_controller.rb:49`; `versionable.rb:42,317–319` destroys versions/pointers without parent-destroy content sweep. Fix: ownership-aware post-destroy GC preserving other references. Specs: entity empty-trash and Versionable prune GC.

## Shared-resource locks and database invariants

Tenant creates force owned identity; platform creates force NULL identity. Tenant shared saves modify customer body only (including owner on tenant URL), not global name/display label/extension/association identity. Tenant destroy/restore/empty-trash never selects a shared global row. Platform finders select shared rows only. Tenant copies of shared rows are rejected. Reset targets only current-customer override storage. Version mutations use the current tenant/global line; shared global read fallback never admits another tenant's override.

Original database review: constants have NULL-safe owned/shared unique name indexes; override pairs are unique but lack parent/customer FKs. Entities have owned name uniqueness, customer/head FKs, but lacked NULL-safe shared name/slug backstops. Entries have separate customer/entity FKs, not a composite tenant invariant or JSON relation FKs. Index settings have unique pair and separate FKs. Versions have NULL-safe per-line numbering, but schema lacked entity/content/lineage FKs; heads lacked relational line consistency. Content `(customer_id,hash)` uniqueness lacked NULL-safe global dedup. Modules/assignments have unique key/pair and FKs but model-only status/schema invariants. Industry pairs are unique/non-null but registry/taxonomy membership is model-only and seed bulk insertion bypasses validation. Missing DB constraints alone did not establish eligible-route IDOR. Concurrent backend migrations may now replace these original facts; no live-schema comparison was performed.

## Excluded boundary calls

| Eligible caller | Boundary not followed as a route/implementation audit |
| --- | --- |
| Entity version page, T/P | Entire builder page-creation action excluded; `Pages::Activities::CreateFromEntityVersion` |
| Entity template preview | Transient orchestrator inspected; PageFieldPopulator/PageTemplateApplier/PageContentGenerator/maintenance preview renderer excluded |
| Entity form | TemplatePickerComponent and picker-card URL excluded; historical lineage carried through a controller helper, no entity builder partial changed |
| Industry cards | Catalog membership included; TemplateCardComponent preview/zoom excluded |
| Runtime admin pages | Maintenance preview/launch/distribution destination controllers excluded |
| Search pages | Returned maintenance-page destination excluded; source query/link audited |
| Shared overrides | Constant/Entity branches only; Flowchart/Page branches excluded |
| Module developer metadata | Contract declarations included; builder consumers/execution excluded |
| Module/customer hooks | Integration lifecycle included; auth/payment/email/SMS/website/AI/billing implementation lanes separate |

## Follow-up controller/helper changes

* Shared mode uses an anchored 81721200 format-aware PATH_INFO pattern. RouteAuthorization requires that actual outer CID for every protected platform namespace, not the nested target/body/query parameter.
* Public foreign visitors are allowed. Protected tenant checks remain, and member preview admits same-tenant admin/owner only. `current_tenant_user` is available for same-tenant card/member attribution.
* Runtime page batches validate selection/action, use validated launch/take-offline, activate owned inactive records, validate reactivation of launched records, transact the selection and return actual unique matched counts; JSON failure is 422, HTML failure is an alert.
* Entity promotion delegates the backend `Entities::PromoteVersion.call(entity:, version:, restore: false)` result (`success?`, `version`, `errors`). Create uses restore=true. Controller scope rejects other entities/tenants and tenant attempts to promote a shared global snapshot.
* Entry deletion delegates `Entities::DeleteEntry.call(entry:)` result (`success?`, `entry`, `errors`) after customer+entity scoping. Controller wraps all selected helper calls in one transaction and rolls back on a failed result.
* Customer purge delegates `Customers::Purge.call(customers: Customer.only_deleted)` result (`success?`, `deleted_count`) and never claims success on failure. Customer soft deletion and generic restoration check real outcomes.
* Historical entity edit hydrates a scoped snapshot/reference and carries based_on_version_id via a local route helper. No entity/page/flowchart builder render was edited.
* Copy preserves display fields. Definition/request/reference containers receive controlled shape checks. Industry malformed containers/items are rejected before replacement.
* Module updates prevalidate, lock and transact mutations. Required/tenant activation follows successful provisioning. Missing module preserves 404. Durable owner defaults remain the backend lane.
* Developer-document links/search preserve the active locale using existing ReaderComponent locale input and controller URL/repository options; global user preference is unchanged. The only view change is passing that existing locale property in the developer-doc reader, not a builder rendering change.
* New wording is confined to `config/locales/routes_audit.en.yml` and `routes_audit.zh-CN.yml`, with matching key sets.

## Request verification authored, not executed

New request coverage: `spec/requests/core_route_audit_spec.rb`, `spec/requests/admin/pages_route_audit_spec.rb`, `spec/requests/admin/maintenance/entities_route_audit_spec.rb`, `spec/requests/admin/maintenance/entity_lifecycle_route_audit_spec.rb`, `spec/requests/admin/maintenance/platform/core_mutations_route_audit_spec.rb`. Existing page batch, customer platform-prefix, module-settings invalid-input, entity-version fixture and developer-doc locale expectations were updated. TenantContext's context controller specs now exercise protected paths for the protected cross-tenant invariant.

Tests deliberately cover actual path spoofing/nested target/mount prefix, public foreign visitor and same-tenant attribution, protected preview scoping, atomic batch invalid launch/reactivation, malformed definitions and selections, historical version isolation/lineage, bridge-aware promotion, log/bridge-aware deletion and rollback, module prevalidation/rollout rollback and retry, industry preservation, purge failure reporting, and locale navigation/search.

**No tests were run by this lane, as instructed.** Syntax/whitespace checks do not establish behavior, integration success or test-suite passage.

## Remaining dependencies and honest gaps

* The backend helpers above appeared during controller implementation and are integrated under their actual interfaces. Their validation, bridge/log cleanup, transactional behavior, customer-purge plan and migrations require backend/QA verification; their source was read but not edited here.
* Durable module defaults, cycle-safe graph/navigation, entity/model approval and enum validation, shared-target deletion checks, override/GC/DB invariants, CSV policy and page classification remain backend/presentation owners' changes. The catalog category view was not changed here.
* Public card/record attribution consumers in excluded payment/domain controllers must call `current_tenant_user` or perform equivalent same-tenant filtering. The core helper is supplied; those caller integrations were not edited or runtime-verified by this lane. A foreign logged-in actor must not cause a foreign user_id/payment method to be attached to the visited tenant.
* There are no provider calls, live DB inspection, browser smoke tests, migrations or server restart evidence. Token/MFA/credential/role and vendor execution remain other audit lanes.
* Shared page grouping joins global content, but changing override binding depends on excluded builder writes; no extra confirmed exploit was asserted.
* Nullable dedup/head/GC concurrency concerns were not demonstrated by a concurrency run.
* Per the dispatch, no reference docs or other existing locale files were edited. Reference synchronization must be completed by the coordinating documentation owner.

## Remaining-route follow-up — RC-01, RC-17, RC-18

These fixes are source-remediated and runtime-unverified. The expanded route matrix/manifest and paired reference documentation remain coordinator-owned.

### RC-01: visited-tenant runtime audience

`EntityAttributeAudience.for_user(user, customer_id:)` now grants a role audience only for the explicitly identified tenant or the fixed `Authentication::User#platform_owner?` exception. Missing tenant identity and foreign admin/member actors resolve to public. The original authenticated actor remains intact for Warden/session checks, page-level authorization, protected member guards and request audit metadata; it is not globally replaced with an anonymous user.

The policy is installed at every inspected runtime role-to-audience boundary: normal/nested form generation, both query and generated-ERB entity-entry option labels, default composite list projection, public submission parameter/validator context, and retained entry data exported by InputMapper. These callers pass the visited/resource tenant explicitly, rather than inferring privilege from `Current.user.primary_role_key`. PublicPagesController passes only the permitted runtime viewer into submission metadata and uses the same audience for the handoff parameter map. PublicSubmission also filters a directly supplied foreign viewer defensively. Form action identity uses the resolved current customer, including clean aliases.

No maintenance page/flowchart editor controller or builder route was changed. PageVisibility's existing ordered audience predicate and public/member whole-page guards remain unchanged.

### Runtime BrowseScope caller completion

The sidebar tree already used `Admin::Pages::BrowseScope`; Admin::PagesController's entity and uncategorized lists still used global-head Page scopes. All index selections now delegate to BrowseScope with the explicit URL customer's ID. HTTP lists and tree badges therefore use the same customer override binding and the same stale/bridge/headless classification. Global defaults and other tenants' bindings remain independent.

### RC-17: existing catalog wording

Industry catalog category buttons and card badges now call the existing `PageLayoutTemplates.category_label` locale accessor. Layout, components and catalog membership behavior are unchanged; no new translations or template definitions were added or inspected.

### RC-18: optional-format webhook providers

Only the payment and email provider constraint bodies in `config/routes.rb` were changed. Each extracts the provider from its anchored PATH_INFO route grammar and excludes the optional format suffix before checking the request-time registry. It does not trust query/body provider values or an ambient parameter map from another route candidate. Journey continues to supply the formatless provider and separate format to the existing webhook controllers; provider verification/dispatch, SMS routing, billing additions and shortcut aliases are unchanged.

### Authored verification and handoff

* `spec/requests/public_pages_tenant_audience_spec.rb`: foreign admin/member GET and POST filtering; spoofed role/audience hints; clean aliases; preservation of the real session actor; narrower-page and protected-member rejection; same-tenant and fixed-owner positive cases; private dropdown labels; composite stored values; retained secret omission from module handoff.
* `spec/requests/formatted_webhook_routes_spec.rb`: bare/json/xml payment and email dispatch, actual provider/format metadata, payment acknowledgement parity, invalid-signature boundaries, mounted application/query spoofing, and unregistered-provider rejection.
* `spec/requests/admin/pages_route_audit_spec.rb`: effective shared override list/tree parity, another tenant's global fallback, and stale/bridge/headless uncategorized parity.
* Existing audience-policy, direct public-submission and InputMapper specs were updated for tenant identity. The existing industry request spec now checks Chinese category buttons and badges.

No tests, application requests, route expansion, migrations, provider calls or subagents were executed by this follow-up. Ruby syntax and scoped whitespace checks are static evidence only. Authentication recovery headers, Bearer tracking and other manifest findings remain with their assigned owners. The coordinator must reconcile the matrix and paired reference text against these source changes; this report does not claim runtime acceptance.

## Targeted core failure repair and execution

The later authorized repair of full-suite groups 20, 21, 23 and 24 is recorded in `2026-10-11-rspec-verification.md` under “Core follow-up,” including the exact schema-load and final passing commands. `Entities::Contracts::Definition` now owns structural normalization/checks shared by the explicitly whitelisted controller bags and entity promotion; semantic validators remain in the backend. Top-level Help namespace calls are qualified. Security 404 checks, truthful restoration, current navigation/locale/disclosure behavior, public foreign audience openness and cleaned member sentinels retain meaningful assertions.

**Actual targeted result: 554 examples, 0 failures across 23 files**, including the Chrome entity-group save/reload journey and the public-audience/formatted-provider regressions, using `TEST_DATABASE=storage/core_verify.sqlite3` with authentication enabled. This supersedes the earlier no-execution limitation only for that named cohort; it is not a full-suite or all-route acceptance claim. No builder source, unrelated backend-policy changes, full-suite rerun or subagents were used.
