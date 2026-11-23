---
title: "Entity builder"
summary: "How entity schemas, versions, associations, computed fields, and tenant entries are stored, edited, and created from the admin browser."
---

## Summary

An entity is the schema for a tenant's records. `Entity` keeps identity on the parent row (`name`, `display_label`, `status`, `category`, `extended_model`, `customer_id`) and keeps the definition body on a version. The body is `property_schema`, `default_properties`, `associations`, `attribute_groups`, plus `icon`, `color`, `description`, and `referenced_template`. After load, `reload_definition_from_head!` copies that body from `Versionable#resolved_current_version`, so a customer with an override sees their fork and everyone else sees the global default.

Records are `EntityEntry` rows. Each row belongs to one entity and one customer. Variable attributes live in the JSON `data` column. Calculated and computed fields are not stored there. There is no type named rollup: aggregates are property-schema fields with `type` `"Computed"`, compiled to SQL by `Entities::ComputedCompiler`.

The schema editor is the maintenance form at `/:customer_id/admin/maintenance/entities`, remounted for shared rows at `/:customer_id/admin/maintenance/platform/entities`. Entries stay on the tenant path. They are not remounted under Shared Resources.

## Flow

```text
Admin form (entity-form)
        |
        |  hidden JSON: property_schema, associations,
        |  attribute_groups, default_properties
        v
Admin::Maintenance::EntitiesController
        |  definition_scope + SharedResourceMode
        |  tenant override permits definition keys only
        v
Entity#save
        |  BridgeEntityManagement#sync_bridge_entities!
        |  Versionable after_save autocommit
        v
EntityDefinitionContent.store!   (SHA-256, content-addressed)
        |
        v
EntityVersion  -->  current_version_id
                 or entity_customer_heads (per-customer override)

Reads of the schema
        |
        v
resolved_current_version --> virtual attributes

Records
        |
        +-- page submit / flowchart activities
        |
        +-- Admin::EntityEntriesController  new / create / edit / update
                |
                v
            Entities::EntryForm (effective schema + allowlisted inputs)
                |
                v
            Entities::Activities::CreateEntry / UpdateEntry
                |
                v
            EntityEntryContract (admin audience + writable_slugs)
        |
        v
EntityEntry (customer_id + entity_id + data JSON)
        |
        v
Admin::EntityEntriesController  index / show / destroy / batch_destroy
```

A save on the tenant path of a shared entity writes that customer's override line, including when the URL customer is `81721200`. The platform prefix (`Current.shared_resources_mode`) writes the global row (`customer_id` NULL). `guard_shared_global_writes` rejects destroy of that shared row on the tenant path. Identity columns are omitted from the permitted keys on the same path. Tenant empty-trash uses `customer_id: current_customer_id`, so shared rows (`customer_id` NULL) are outside that scope; the platform prefix empties `only_deleted.shared`.

`Entity#create` and `#update` run inside a transaction and call `sync_bridge_entities!`. A bridge that fails to save rolls the entity back. `Versionable` then commits a version only when the snapshot hash changed. Identity-only edits do not add a version. History is pruned to `Versionable::MAX_VERSIONS` (50) per line.

## Implementation

### Model

`Entity` includes `SoftDeletable` (deleted status `:inactive`), `TenantScoped`, `SharedIdentity`, `BridgeEntityManagement`, `EntitySchemaValidation`, and `Versionable`. `acts_as_versionable` uses reflection `:entity_versions`, version class `EntityVersion`, content class `EntityDefinitionContent`, snapshot reader `:definition_snapshot_json`, and customer head reflection `:entity_customer_heads`.

`category` is `plain`, `bridge`, or `extension`. Selecting `extended_model` makes a non-bridge entity an extension; clearing it makes it plain. A bridge never extends a base model.

The form's **Extend Base Model** select lists `ExtendableModelRegistry.for_customer(current_customer_id)` on both prefixes and is omitted for bridges. On the tenant path it is optional (blank option `maint_core.entities.form.no_base_model`), so a tenant admin can create a customer-owned extension; on Shared Resources it is required. On a tenant override of a shared entity the select is shown disabled, because `extended_model` is identity. With no approved models, the tenant path shows `no_base_models_tenant` (pointing at Maintenance / Modules) and the platform prefix shows `no_base_models`. `Entity#extended_model_is_approved` re-checks the submitted class against the registry for the entity's `customer_id`. `name` is required (1..100 characters) and does not enforce uniqueness. A shared entity cannot carry associations (`shared_entity_has_no_associations`).

Approved `extended_model`/column catalogs are metadata only. Runtime page submissions currently persist EntityEntry; base-model writes, writable contracts and authenticated ownership adapters are not implemented. The one exception is a person entity (extending `Authentication::User`): an admin may link each of its entries to one same-tenant user through `entity_entries.user_id`, see [Person linking](person-linking). Base controls are omitted and nonempty/malformed base input is rejected before activity execution; see [Page rendering](page-rendering) and [Flowchart runtime](flowchart-runtime).

`property_schema` entries use `type` `"Calculated"` for formulas and `"Computed"` for bridge aggregates. `input_fields` excludes both. `grouped_property_schema` orders attributes by `attribute_groups`, with ungrouped attributes last. `EntitySchemaValidation` checks unique names and slugs, group shape, duplicate or self-referential associations, a real target entity, and each computed field's `config` (`function`, `precision`, `bridge_entity_id`, source field, filters). Computed fields are allowed only on customer-owned entities. Functions are `Entities::ComputedCompiler::FUNCTIONS`: `avg`, `sum`, `count`, `min`, `max`. Filter operators are `=`, `!=`, `>`, `>=`, `<`, `<=`. Numeric controls are `number` and `range`. Precision max is 6.

`BridgeEntityManagement#sync_bridge_entities!` creates or updates a junction entity (`category: :bridge`) for each association. Association hashes carry `target_entity_id`, `display_field`, and `bridge_entity_id`. Soft-deleting a source entity soft-deletes its bridges; `restore` restores them.

### Entity-record dropdowns

A select or radio attribute can list another entity's records: the editor's **Use Entity Records** mode saves `config: { options_source: "entity_entries", entity_id:, label_field: }`. An entry always stores the record **id**; `label_field` (the display field) only labels the choices. There is no `value_field`.

- **Display fields.** `Entities::ReferenceLabels.labelable?` allows text, search, email, tel, url, number and date input attributes; never calculated, computed or reference fields, and never `id`. The same rule applies to an association's `display_field`. `GET /:cid/admin/maintenance/entities.json` marks each attribute `labelable`, and the editor offers only those.
- **Choices.** `Entities::ReferenceOptions` lists the target's records in the viewing tenant, ordered by label then id, at most 200. A record without a label reads `Untitled (#id)`; repeated labels are numbered `label (#id)`. The list is empty when the target is trashed, a bridge, foreign, or when the display field is hidden from the viewer's audience.
- **Definition rules.** Saving a definition rejects a dropdown whose target doesn't exist (`reference_target_missing`) or whose display field isn't labelable (`reference_label_field_invalid`), and an association whose display field isn't (`association_display_field_invalid`). Status-only saves (trash, restore) skip these checks.
- **Trash.** `soft_delete` refuses an entity that other entities still reference and names them (`entity_referenced`). `Entities::ReferenceDependents` finds referrers in customer-owned definitions, shared defaults and every tenant override.
- **Display field changes.** Deleting or retyping a field other entities display is refused (`display_field_in_use`), as is hiding it from an audience of a launched form that lists it (`display_field_hidden_from_form`).
- **Visibility.** A dropdown lists the display field of every record to everyone who can open the form, so a person's name or ID used as a display field should be hidden from members and the public unless the form includes only the admin audience.
- **Owner switch.** A reference whose target is a person entity may carry `"owner": true`. The attribute modal renders an **Owner** switch (`comp_admin.attribute_modal.owner_label` / `owner_help`: "Members see and submit only records they own through this field.") in the Use Entity Records block. `data-entity-form-person-entity-ids-value` lists person-entity ids (including trashed, so a restored Student still qualifies). `ReferenceManager` shows the switch only when the selected target is in that list; it stays hidden for non-person targets, person entities, bridges, and association extras. `AttributeManager` writes `"owner": true` only when the switch is on; the key is omitted otherwise. `ModalManager#prefillModalWithAttribute` restores on and off.
- **Owner flag rules.** `EntitySchemaValidation#validate_owner_reference` runs when `property_schema` or `associations` changed. `"owner": true` is valid only on a reference to a person entity, and at most once. `"owner": false` and a missing key are equivalent. Violations: `maint_core.errors.validations.entity_owner_reference_invalid` (`%{field}`: "%{field} can mark the record's owner only when it references a person entity.") and `entity_owner_reference_multiple` ("Only one field can mark the record's owner."). The flag is refused on a non-reference, a non-person target, any attribute of a person or bridge entity, and association `additional_attributes` (bridges infer). Named targets from the assistant (`config` carries the entity name) are skipped on the first `EntityDefinitions::Persist` save and checked on the second save once the id is resolved. See [Person linking](person-linking) for kinds and [Operations API](operations-api) for `owner` on the public vocabulary.

`EntityDefinitions::Persist` writes a set of customer-owned definitions under the customer lock: normalize, then identities, option sources, associations and computed fields. It is not the form's save path; the [Operations API](operations-api) calls it. `EntityDefinitions::Capabilities` is the registry inventory that `Normalizer` and the assistant prompt's capability matrix read.

### Authoring through operations

Outside the form, entities are authored through the [Operations API](operations-api): `create_entity` applies at once, `update_entity` always waits for an administrator's approval, and `get_entity` is read-only. They take a public vocabulary (`slug`, `kind`, `rules`, `access`, `options`, `extends`) that `EntityDefinitions::Api::Mapper` translates to and from the stored definition on this page. `EntityDefinitions::Api::SemanticValidator` applies the cross-field rules, and `Persist` writes. Only customer-owned, active, non-bridge entities are in scope; shared entities, bridges and names in the trash are refused.

Attribute definitions may be partial, such as `{"name":"Notes","html_type":"textarea"}`. An omitted `kind` is `input`, and the mapper derives an omitted slug from the name with `parameterize(separator: "_")`, producing `notes`. The same rule applies to input, Calculated, Computed and bridge fields, and the slug never changes afterwards. An explicit slug must match `^[A-Za-z0-9_]+$`, and `id` is reserved. A name that parameterizes to nothing, such as a Chinese label, needs an explicit slug; otherwise validation reports `attribute.reserved_slug`.

An update is a typed change set of editor actions (`add_attribute`, `update_attribute`, `move_attribute`, `remove_group` and so on) addressed by slug, group key or related entity name. `update_entity` parks an `OperationInvocation` with a reviewable `ChangePlan` and each entity's `current_line_head_version_id`. Approval runs `Operations::Activities::Confirm`: it revalidates, checks those heads under the customer lock and applies the change set to a freshly read catalog document, so the write lands on the latest head. A stale `expected_version` is refused with `conflict.version_changed` when the change is proposed; at approval a moved head returns `conflict` and the administrator is asked to request the change again. A patch carries only the keys sent, so omitted settings keep their stored values. The model cannot approve its own proposal; only the administrator can. See [AI assistant](ai-assistant).

Entity and generated-page capacity comes from [Billing](billing) entitlements. An active subscription uses its accepted `plan_snapshot["limits"]`; later catalog increases or decreases do not rewrite that allowance. With no configured default, the finite built-in Starter fallback provides 50 pages, 25 entities and 5 members without seeding catalog rows on a read. An explicitly configured finite zero limit remains authoritative.

Entities created by the assistant are active immediately: `Entity` defaults to `status: :active`, association bridges are explicitly active, and there is no separate entity launch flag. The assistant's successful follow-on form generation launches a tenant-owned `Page` with the column defaults (admin on, member and public off); a form-generation/launch failure leaves the entity operation applied and reports the form failure. Reused pages retain their existing launch state and audiences. Entity update approvals are unchanged. See [Page builder](page-builder) and [AI assistant](ai-assistant).

### Versions

`EntityVersionsController` lists `current_line_versions`. Historical edit hydrates the selected scoped snapshot/reference and carries `based_on_version_id`. Set-default/restore use `Entities::PromoteVersion.call(entity:, version:, restore:)`: validate candidate, reconcile bridges, fully validate, then move the head atomically. Repaired bridge identities produce a new accurate version; rejection leaves head/bridges intact. `POST .../versions/:id/page` remains the page-creation boundary. Equal payloads share content.

### Domains

A domain groups the entities of one business area, for example Course, Student, Semester and their bridges in one domain, Customer and Order in another. Only the platform owner manages domains (`EntityDomainVisibility.allowed?`, gated through `OwnerOnlySurfaces`). Domains are stored per customer: the owner organizes each tenant's list on that tenant's URL. Tenant admins get `403` on every domain-management route and see the flat maintenance table, but they browse their entities grouped by domain, read-only, at `/:cid/admin/domains`.

- **Storage.** `EntityDomain` (`customer_id`, `name` unique case-insensitively per customer, `description`, `color` from `EntityDomain::COLORS`) and `EntityDomainMembership` (`customer_id`, `entity_domain_id`, `entity_id`, unique on `customer_id` + `entity_id`). An entity is in at most one domain per customer. Membership is a join row, so placing a shared entity never touches the shared row; deleting a domain or an entity cascades its memberships only.
- **Bridges.** A bridge without its own membership follows its two ends (`EntityDomains::Catalog.bridge_ends`, the first two `entity_id`s in the bridge's `property_schema`) when both sit in the same domain, and is labelled **Auto**. An explicit membership wins; clearing it makes the bridge follow its ends again.
- **Writes.** `EntityDomains::Activities::Save` validates with `EntityDomains::Contracts::EntityDomain` and replaces the member list in one transaction (`EntityDomains::Memberships.replace!` moves an entity out of its previous domain). `Assign` moves one entity and `Destroy` deletes a domain; its entities become ungrouped. Entity ids must be customer-owned or shared entities visible to that customer.
- **Index.** On a tenant entities URL the owner gets the **Domains** view by default; `?view=table` keeps the paginated flat table. `EntityDomains::Layout` arranges sections (domains by name, ungrouped last) and `Admin::Maintenance::Entities::DomainIndexComponent` renders a domain navigator, a search box, a kind filter (`?kind=entity|bridge`) and one table with a row group per domain. `?domain_id=<id|ungrouped>` narrows to one domain. Empty domains stay listed unless a search or kind filter is active. The Shared Resources prefix and the JSON catalog are unaffected.
- **Browse by domain.** `GET /:cid/admin/domains` (`Admin::DomainsController#index`, admin or owner) is the landing page of the **Domains** menu (menu key `:entities`) and shows the first domain. `GET /:cid/admin/domains/:id` (`#show`) shows one domain, where `:id` is a domain id or `ungrouped` (`Admin::Domains::Directory::Section#key`); a key that is not one of the customer's browsable sections returns `404`. There is no entities index route; `/:cid/admin/entities/:id` stays the entries list. `Admin::Domains::Directory` builds one card per browsable (non-bridge) entity from `EntityAssociationGraph#all_entities`, with tenant entry count and last activity, and groups the cards with `EntityDomains::Layout`. Domains come by name with ungrouped entities last, and a domain with no browsable entity is left out. `?sort=name|recent|entries` orders the cards. `?layout=grid|list` switches between cards and rows; both links stay on the shown domain's URL. `Admin::Domains::DirectoryComponent` renders an overview card for the selected domain: a colour accent bar, a tinted layers tile, its name and description, and its total entries and last activity (`Section#entry_count` / `#last_entry_at`). Below it, a toolbar shows the record-type count with the sort and layout switches, followed by the domain's cards; in the list layout the rows sit under a **Name / Entries / Last updated** header. The page has no search box of its own; the sidebar search filters domains and record types. `Admin::Domains::EntityCardComponent` renders each entity. Without domains the entities render as one section without the overview card. Customer-facing wording on this page, the Domains menu and its sidebar avoids the word *entity*: the menu reads **Domains** and record pages say **record type**. The page is read-only for everyone, the owner included: it shows no cross-domain summary line and no domain controls, because domains are managed only from the owner's maintenance screens. The owner alone also gets **Create Entity** in the header and in the empty state. The sidebar (`EntitiesContributor`) has no overview link: it lists only domains under a **Business areas** heading. Each domain is a collapsible node whose label links to `/:cid/admin/domains/:key`, with a layers tile tinted by the domain colour (`SidebarTone.domain`), holding its entities flat and by label; ungrouped entities sit under an **Other** node with a neutral tray tile. The first domain also matches the bare `/:cid/admin/domains` (`match_paths`), so on the landing page it is the selected and only expanded node; clicking another domain opens that domain's page, which expands it alone. On a record page the domain holding that record type is the one expanded. Without domains the entities are listed flat under **Record types**. Every entity row carries a small tile that matches its domain page card: the colour, icon and initials come from `EntityGlyph`, shared with `Admin::Domains::EntityCardComponent`, and the open entity's tile lifts onto a white chip inside the accent highlight.

| Route | Purpose |
| --- | --- |
| `GET .../entity_domains/new`, `POST .../entity_domains` | Create a domain (name, colour, description, members) |
| `GET .../entity_domains/:id/edit`, `PATCH`/`DELETE .../entity_domains/:id` | Edit or delete a domain |
| `GET .../entities/:entity_id/domain_membership/edit`, `PATCH .../entities/:entity_id/domain_membership` | Move one entity to a domain, to **No domain**, or (bridges) back to **Automatic** |

`...` is `/:cid/admin/maintenance`.

### Entries

`EntityEntry` stores an object-shaped `data` JSON and rejects malformed/scalar data and non-input keys, including Calculated/Computed fields. `stamp_entity_version` overwrites client provenance with `entity.resolved_current_version.version_number`, so shared-entity entries record the effective customer head.

`EntityEntry.build_for(entity)` builds a runtime subclass with schema accessors for Trailblazer activities. It skips slugs in `EntityEntry.column_names + %w[entity customer]`, so JSON accessors cannot shadow real columns or those associations. Calculated/Computed accessors have readers but no generated writers. The anonymous subclass returns `EntityEntry.model_name` for Rails/I18n error handling, uses the parent's table and STI identity, and binds the entity after initialization. `ModelGenerator` emits `EntityEntry.class_eval` plus `attribute_accessor`; the factory's collision guard is specific to `build_for`. `[]` / `[]=` and `method_missing` are the other access paths. `Admin::Maintenance::EntitiesController#show` renders both `ModelGenerator` and `ContractGenerator` for inspection. Those two classes are not `CodeGenerators::GeneratorRegistry`.

`EntityEntryContract.build_for(entity, audience: nil, writable_slugs: nil)` declares every schema property with a slug. Calculated/Computed properties and any property with `storage: "computed"` get Reform 2.6's exact options `writeable: false, parse: false`: submitted values are not deserialized and `sync`/`save` never calls their model setters. A non-nil `writable_slugs` applies the same flags to every property outside the write set, without removing readers, existing model values or audience-scoped validators. `nil` leaves ordinary properties writable, including hidden ordinary properties; visibility alone is not a global write allowlist. `ContractGenerator.new(entity, writable_slugs: nil)` emits the same flags through `schema_property_options`, and `property_accessor(name, validates: nil, **property_options)` forwards them. Only `presence` and `acceptance` reject a blank value: `build_validation_options` adds `allow_blank: true` to every other validator and `ContractGenerator` emits the same source (e.g. `numericality: { allow_blank: true }`), so a field without a required rule may stay empty and is checked only when filled. See [Flowchart runtime](flowchart-runtime).

HTML lists and CSV exports build `::Entities::EntryDisplay` for their result rows once those are known (`Admin::EntitiesController#columns_for`) and pass it to `Admin::Entities::ColumnsBuilder`, whose cells and badges read `EntryDisplay#text`; sorting, search and filters read each column's `sql:` only. Derived values come from `Entities::DerivedValues`: one query selecting `entity_entries.id` plus every `Entities::DerivedExpressions` expression — the same SQL the list sorts by and `FlowchartRuntime::QueryBuilder` selects, so a link stored with a numeric parent id counts the same everywhere. The leading `::` resolves the top-level service namespace rather than `Admin::Entities`. The browser GET after Create Entry's 303 uses this same read path. Derived values are loaded for display, never written into the new entry's `data` or created as related records.

Maintenance routes remain `index` and `destroy` at `/:customer_id/admin/maintenance/entities/:entity_id/entries`. Browse nesting at `/:customer_id/admin/entities/:entity_id/entries` provides `new`, `create`, `show`, `edit`, `update`, `destroy`, and collection `DELETE .../entries/batch` (`batch_destroy`); see **Edit Entry** under Admin Create Entry. Both mounts use `Admin::EntityEntriesController`, which loads the path entity from the current customer or shared entities, then scopes existing entries by both `customer_id: current_customer.id` and `entity_id`. Entity and entry IDs come from `request.path_parameters`, not body/query overrides. Page submission and flowchart activities remain creation paths too; see [Page rendering](page-rendering) and [Flowchart runtime](flowchart-runtime).

`PATCH /:customer_id/admin/entities/:entity_id/index_setting` updates `EntityIndexSetting`. The platform entities routes do not nest entries.

### Admin entries list

`/:cid/admin/entities/:id` renders `Admin::Entities::EntriesTableComponent` inside the `entity-entries-table` Turbo frame. The page header carries the entity's palette icon (`attribute_group_icon_path`). The shared `Admin::ListToolbarComponent` provides debounced search (`admin-table` controller, which restores focus and typed text after the frame re-renders), one select per `Admin::Entities::FiltersBuilder` filter, and **Reset** while a search or filter is active. The toolbar's actions slot holds the **Columns** picker (`Admin::Entities::ColumnPickerComponent`, submitted with `data-turbo-frame="_top"` so its flash shows) and a Comfortable / Compact density toggle. Sortable headers use `Admin::SortableHeaderComponent` and set `aria-sort`; changing the sort returns to page 1.

Clicking anywhere on a row opens the entry's full detail page (`/:cid/admin/entities/:entity_id/entries/:id`, a `_top` link) through the `row-link` controller; checkboxes, buttons and text selection are left alone. Checked rows are highlighted and swap the toolbar for the bulk bar (**Clear**, **Delete selected**). The per-row edit and delete icons stay muted until hovered. On mobile, cards lead with the first non-ID column and show up to three more fields. `Admin::PaginationComponent` (with `summary: true`) always shows the result count and adds numbered pages plus a rows-per-page menu (`10 / 25 / 50 / 100`). `per_page` and `density` query params are saved per customer and entity in `EntityIndexSetting`.

**Display text.** `Entities::EntryDisplay.new(entity:, entries:, customer_id:, audience:, viewer:)` turns stored values into text for the list, the CSV export, the entry detail page (admin audience) and member surfaces (the member's audience): blank → `—`; select, radio and checkbox options → their labels, several joined with ", "; an `entity_entries` reference → the referenced record's display field (`Untitled (#id)` when blank, `Missing record (#id)` when the record is gone, the raw id when the display field is hidden from the audience or the row is outside the viewer's `People::Ownership.scope`); calculated and computed fields → their value; a checkbox or switch without options → Yes / No; anything else, including dates, as stored. Duplicate labels are numbered only in dropdowns, never here. Calculated fields can be picked as columns next to computed ones and sort by the same expression they display. Member surfaces attach the display with `EntryDisplay.prime!`, and descriptor lambdas read `EntityEntry#display_text(slug)`; dates and money keep their stored value for `Member::Formatters`.

### Admin Create Entry

The browser at `/:cid/admin/entities/:id` places primary **Create Entry** before **Export CSV** for active, non-bridge entities, including when the table or current search is empty. It opens a full dashboard page.

| Method | URL | Action / helper |
|---|---|---|
| `GET` | `/:cid/admin/entities/:entity_id/entries/new` | `Admin::EntityEntriesController#new` / `new_admin_entity_entry_path(cid, entity)` |
| `POST` | `/:cid/admin/entities/:entity_id/entries` | `Admin::EntityEntriesController#create` / `admin_entity_entries_path(cid, entity)` |

POST requires object-shaped `entry` and `entry[data]`. Missing, scalar, null or array wrappers return **400**; an empty data object is valid and applies allowed defaults. The controller passes only the inner Hash/Parameters to the activity; the form service reads its allowlisted keys without `permit!` or unrestricted mass assignment. Success redirects **303** to `admin_entity_path(cid, entity)` with a translated notice. Boundary, contract or save failure renders `new` with **422**, the same form object, attempted values and keyed errors. GET and failure renders use the dashboard layout, except for requests whose `Turbo-Frame` is a quick-add frame `entity-quick-add-frame-<depth>` (see below). The actions serve HTML; an authorized request negotiating an unsupported JSON response gets **406** before the writer runs.

#### Effective schema, groups and defaults

`Entities::EntryForm.new(entity:, customer:, params: nil)` reloads the entity inside `Current.set(customer: customer, shared_resources_mode: false)`. Every POST resolves the definition afresh; a shared entity uses that customer's `resolved_current_version` override, or the global default when there is no override. Schema, groups, defaults, validation and the creation-time version stamp follow this effective definition, including when the pinned owner visits another customer's URL.

Descriptors preserve `grouped_property_schema` group order and field order; empty groups are omitted and ungrouped fields come last under translated **Other fields**. Labels use `display_label.presence || name`, help uses `description`, and schema-authored text is escaped rather than translated automatically. Only admin-visible fields are considered. Calculated, Computed, `storage: "computed"`, `readonly: true`, `EntityReference`, real entry columns and `entity`/`customer` are excluded from controls, defaults and input. Excluded unsupported fields do not block readiness. `available?` means the schema has supported writable fields and no blockers; it is not an authorization check.

Only the write set receives `default_properties_json`. An explicit default key wins over static options marked `default: true`; otherwise those flags supply single-choice or multi-select defaults. Multiple flagged defaults block a select/radio unless an explicit default key exists. Submitted keys override defaults by **key presence**, preserving false, zero, null, blank strings and empty arrays. Omitted submitted keys still use defaults; `params: nil` is GET/defaults mode, while `{}` is a submitted empty object. Defaults undergo the same shape/literal checks as submitted values. Unknown, hidden, internal, readonly, reference and derived keys are discarded and do not reappear in the form.

#### Supported inputs and validation

| Schema `html_type` | Input boundary |
|---|---|
| `text`, `search`, `tel`, `url`, `email`, `textarea` | JSON-safe scalar; omitted `html_type` falls back to `text` |
| `number` | Scalar with finite decimal/exponent syntax when nonblank; invalid input is never coerced to zero |
| `date` | Blank/null or a real positive-year date string in strict `YYYY-MM-DD` format |
| `datetime-local` | Blank/null or the naive wall-clock string a `datetime-local` input posts: `YYYY-MM-DDTHH:MM`, optionally `:SS` and up to 3 fractional digits, with a real date and in-range time; no zone suffix. Stored as submitted |
| `select`, `radio` | Scalar choice from static `config.options`, or a record id from an `entity_entries` source |
| `multi-select` | Array of scalar choices (static or `entity_entries`); a hidden blank sentinel is removed to retain an explicit empty selection |
| `checkbox`, `switch` | Optionless boolean; hidden `"0"` plus checked `"1"` |

Scalars are null, strings, booleans, integers or finite floats. Objects, uploads, arrays on scalar controls and nested arrays are keyed shape errors. Choices accept scalar options or `{ "label", "value" }` objects and normalize values to strings; nonblank values must match allowed option **values**, independently of any inclusion validator. Select, radio and multi-select attributes with an `entity_entries` source are supported: their choices come from `Entities::ReferenceOptions` for the admin audience, and the entry contract checks that each submitted id is a record of the target entity in this customer (`common.errors.dynamic.association_target_missing`). The attribute is a blocker when the target is trashed or its display field can't label a reference for admins; a checkbox reference is always a blocker. Already-materialized constant options work, but the form performs no live constant lookup. Other entity bindings, non-`entity_entries` dynamic option sources, option-list checkboxes and unsupported controls (including files, rich text, range, time, month and week) block creation when visible and otherwise writable, even if optional. Supported fields still render beside the blocker notice; Create is disabled, and POST makes no write. A schema with no writable controls is also unavailable.

Boolean true literals are `true`, `1`, `"1"`, `"true"`, `"on"`; false literals are `false`, `0`, `"0"`, `"false"`, `"off"`. They normalize to `"1"`/`"0"`; other literals, including blank/null, are errors. Numeric/date checks preserve raw attempted scalars. Reform owns configured presence, range, length and other validation, applying `visibility` ∩ `validator_apply` for the fixed admin audience; missing audience flags default to enabled. Required markers and HTML constraints use only admin-applicable validators. A property excluded from writing can still fail an applicable contract validator; its nonrendered error remains in the summary.

#### Primary persistence and presentation

`Entities::Activities::CreateEntry.call(customer:, actor:, entity:, params:)` returns `[signal, ctx]` with semantic `:success`, `:failure` or `:forbidden`; context carries `:form`, `:model`, `:contract` when built, and keyed `:errors`. It reauthorizes the target, builds the effective form and `EntityEntry.build_for` model, rejects readiness/shape/literal errors, builds the admin contract with `writable_slugs: form.writable_slugs`, validates, and calls `contract.save` in `EntityEntry.transaction(requires_new: true)`. False saves roll back, and `RecordInvalid`/`RecordNotSaved` join the keyed error path. Missing error details use the translated save-failed fallback. Customer and entity are bound from trusted arguments; `before_create` stamps the effective version. This saves exactly one primary tenant entry, with no computed/derived writes, bridge/Enrollment rows or extended-base-model records. It does not execute a Page, flowchart or `ActivitySteps::SaveAll`.

`Admin::Entities::EntryFormComponent` and `EntryFieldComponent` consume descriptors through a fixed `FormFields` class map. The adapter owns labels, help/errors and ARIA using `input_only: true` and explicit control IDs; shared base, radio and toggle templates forward input attributes in that mode. Groups render as borderless fieldsets with a left-accent legend, separated by dividers (no card per group), matching admin page-form sections; fields use one column on phones and two from `md`, with textarea/radio/multi-select spanning both. Inputs are `text-sm` and `rounded-lg`, 44px tall on phones and 40px from `sm`. The linked alert summary points to visible fields; invalid numeric/date/datetime literals rerender as text, rejected select values remain escaped selected error options, and rejected radio values appear in inline errors without becoming allowed choices. Create/Cancel are full-width on phones and inline from `sm`. Header, form and Cancel target `_top`; Cancel returns to the browser. Platform copy uses both `admin_misc` locales. See [Dashboard](dashboard) for the wrapping header.

#### Quick add from a reference dropdown

A single-select reference field (`config.options_source: "entity_entries"`) on the Create Entry form ends with a **+ Add New** option, and so do entity-backed dropdowns on admin page renders (see [Page rendering](page-rendering)). Choosing it opens `Admin::Entities::QuickAddDialogComponent` on the referenced entity's Create Entry form. Multi-select and radio references do not get the option.

Each `EntryForm::Field` for a reference carries `reference`, an `EntryForm::Reference` with the referenced `entity` (nil when the reference cannot label its choices) and the `label_field` slug. `EntryForm#customer` is the URL tenant. `EntryFormComponent.new(..., quick_add_depth:)` gives each single-select reference with an entity the opener from `QuickAddDialogComponent.opener(entity:, customer_id:, label_field:, depth:)`, which returns `{ url:, label:, title:, dialog: }`. `url` is `new_admin_entity_entry_path(cid, entity, label_field:)` and `dialog` is the `#entity-quick-add-dialog-<depth>` outlet selector. The component renders that level's dialog after its `<form>`, never inside it, because the dialog hosts another form. `new.html.erb` passes `quick_add_depth: 0`. A nil depth adds no option and no dialog.

Dialogs nest one level per referenced entity. A dialog at depth N has the ids `entity-quick-add-dialog-N`, `entity-quick-add-title-N` and `entity-quick-add-frame-N`. `QuickAddDialogComponent.depth_of(turbo_frame_request_id)` reads N from the frame id and returns nil for any other frame, for the unsuffixed id, and past `MAX_DEPTH` (10). For a quick-add frame, `new` and a failed `create` render `quick_add` without a layout, inside `turbo-frame#entity-quick-add-frame-N`. That view renders the same `EntryFormComponent` with `frame: true`, `quick_add_depth: N + 1` and `id_prefix: "entry_quick_add_N"`, so the referenced form's own reference dropdowns open the next dialog. The prefix replaces `entry` in every control, label, help, error and summary-heading id (`EntryFieldComponent.field_id(slug, prefix)`), so nested forms never repeat an id already on the page. The form stays inside its frame, and Cancel is a button that closes that level (`entity-quick-add-dialog#close`). `opener` returns nil past `MAX_DEPTH`, so the deepest level offers no option. The create URL keeps `label_field`. A successful frame `create` skips the redirect and renders `quick_add_created` in the same level's frame: a `role="status"` marker with `data-entry-id` and `data-entry-label`. That level's dialog controller reacts to the marker, closes, and hands the entry to the dropdown one level up. The label follows `Entities::ReferenceLabels`: the display field when it can label a reference for admins, numbered `label (#id)` when another record already shows the same text, and `Untitled (#id)` otherwise. Authorization, tenant scoping, `CreateEntry` and validation are the same as the full page.

#### Edit Entry

Every row of the entries list ends with an **Edit** icon before Delete, and the entry detail page header offers **Delete** (a `turbo_method: :delete` link with the same confirmation as the row icon) and primary **Edit**. Edit is offered only for active, non-bridge entities: `admin/entities/show.html.erb` passes `edit_path:` to `EntriesTableComponent` only then, and `admin/entity_entries/show.html.erb` adds the Edit header action only then, so a bridge entry's detail page shows Delete alone.

**Entry detail page.** `GET /:cid/admin/entities/:entity_id/entries/:id` renders a full dashboard page (no drawer or Turbo frame): `AdminPageComponent` with breadcrumbs **Domains › entity › Entry #id**, the entity's icon and color tile, and the Delete / Edit actions above. The body is `Admin::Entities::EntryDetailComponent.new(entity:, entry:, display:, associations:, writable:)`, laid out as a main column plus a sidebar (`lg:` 18rem, `xl:` 20rem; stacked below `lg`). The main column has one card per attribute group, followed by one card per association (see **Associated records** below), in `grouped_property_schema` order with ungrouped attributes last under **Other fields**; groups without attributes are skipped. Each card header shows the group's icon on its color, the group name and a field count; its body is a two-column description list (one column on mobile) whose `textarea` and `multi-select` values span both columns and keep line breaks. Values come from `Entities::EntryDisplay` (admin audience), with blanks shown as a muted `—`. The sidebar (sticky from `lg`) holds **Record details** (ID, entity, created and updated times) and, when there are two or more cards (groups plus associations), a **Sections** index of in-page anchor links (`lg` and up). An entity without attributes shows an empty-state card.

| Method | URL | Action / helper |
|---|---|---|
| `GET` | `/:cid/admin/entities/:entity_id/entries/:id/edit` | `Admin::EntityEntriesController#edit` / `edit_admin_entity_entry_path(cid, entity, entry)` |
| `PATCH` | `/:cid/admin/entities/:entity_id/entries/:id` | `Admin::EntityEntriesController#update` / `admin_entity_entry_path(cid, entity, entry)` |

`edit.html.erb` uses the same dashboard shell and `EntryFormComponent` as `new`, with `http_method: :patch` (the component's default is `:post`), which switches the submit copy to **Save Changes** / **Saving…**. Body shape rules match POST (**400** for a missing or non-object `entry[data]`; **406** for JSON). Success redirects **303** to `admin_entity_path(cid, entity)` with a translated notice; any failure renders `edit` with **422**, the attempted values and keyed errors. Edit lookup requires the same active, non-bridge entity as creation, and the entry is scoped by `customer_id: current_customer.id` and the path `entity_id`, so another tenant's or another entity's entry returns **404**.

`Entities::EntryForm.new(entity:, customer:, entry:, params: nil)` edits an existing record (`persisted?` is true). The entry's stored `data`, without nil values, replaces `default_properties_json` and option defaults. The GET prefill normalizes stored values for display (booleans to `"1"`/`"0"`, invalid numeric/date literals as text) but drops their field errors, keeping only readiness errors: a stored value is judged when the admin submits it, and a stored choice that is no longer an option shows as blank. On PATCH, a key the submission omits keeps its stored value, not a default.

`Entities::Activities::UpdateEntry.call(customer:, actor:, entity:, entry:, params:)` returns the same `[signal, ctx]` shape as `CreateEntry`. It shares the authorize, validate, persist and error-collection steps through `Entities::Activities::EntryWriter`, adds `find_entry` (the entry must belong to the URL customer and the entity, otherwise `:forbidden`), and saves the `EntityEntry.build_for` record through the admin contract with `writable_slugs: form.writable_slugs`. Hidden, readonly and derived fields are outside the write set, so their stored values stay; `entity_version_number` is the creation stamp and does not change. The fallback error is `errors.update_failed`. Model errors, such as stored keys that are no longer in the schema (`validate_data_keys`), appear in the summary.

#### Associated records

Each association the entry's entity declares (`associations_list`, the source side only) gets its own card on the entry detail page, below the attribute groups. A card lists the bridge rows that link this entry, for example a student's course enrollments with their status and grade. `Entities::EntryAssociations.new(entity:, customer:)` resolves the associations: `#all` returns one `Association` per declared association whose bridge (`category: :bridge`, active, this customer or shared) and target entity (active, non-bridge) both exist. Each `Association` carries `bridge`, `target`, `source_slug` (the bridge's `EntityReference` back to this entity) and `columns` (the bridge's other attributes visible to the admin audience, target reference first). `#find(bridge_id)` looks one up. `#rows(association, entry)` scopes bridge entries to the current customer whose `source_slug` value equals the entry id as text, oldest first. `#sections(entry)` adds an `EntryDisplay` for those rows and the ids of target records that still exist.

`Admin::Entities::AssociationSectionComponent` renders a card headed by the target entity's icon, color and label, with an entry count. Rows are a table from `sm` and stacked cards on mobile, and the first column is the linked record. A reference to a record that still exists links to that record's detail page; a missing one reads `Missing record (#id)`. Its anchor is `entry-association-<bridge_id>`, which also appears in the **Sections** index. When the entity is writable (active, non-bridge), the card offers **Add** in its header and per-row **Edit** and **Delete** (with a confirmation). The associated entity's own entries show no card for the reverse side.

| Method | URL | Action / helper |
|---|---|---|
| `GET` | `/:cid/admin/entities/:entity_id/entries/:entry_id/associations/:association_id/entries/new` | `Admin::EntityAssociationEntriesController#new` / `new_admin_entity_entry_association_entry_path(cid, entity, entry, bridge_id)` |
| `POST` | `/:cid/admin/entities/:entity_id/entries/:entry_id/associations/:association_id/entries` | `#create` / `admin_entity_entry_association_entries_path(...)` |
| `GET` | `…/associations/:association_id/entries/:id/edit` | `#edit` / `edit_admin_entity_entry_association_entry_path(..., row)` |
| `PATCH` | `…/associations/:association_id/entries/:id` | `#update` / `admin_entity_entry_association_entry_path(..., row)` |
| `DELETE` | `…/associations/:association_id/entries/:id` | `#destroy` |

`:association_id` is the bridge entity id. Every action looks up an active, non-bridge entity of the current customer (or shared), an entry of that entity in the current customer, and an association the entity declares. A bridge row must also be one of `#rows(association, entry)`. Anything else returns **404**, and the path is admin-guarded by `RouteAuthorization`.

**Add one or many.** `new` renders `Admin::Entities::AssociationEntriesFormComponent`: a list of row cards (`AssociationEntryRowComponent`), each a bridge `EntryForm` whose fields post as `rows[<index>][<slug>]`. A blank row template (`rows[__ROW__]…`) lets the `association-rows` Stimulus controller add rows (**Add another**) and remove them (always keeping one), renumbering the row headings (`row_heading` template passed as a value). The target reference is a dropdown with **+ Add New** (a quick-add dialog one level above the form: depth 0 on the full page, depth 1 inside the entry page dialog). `create` calls `Entities::Activities::CreateAssociationEntries.call(customer:, actor:, entity:, entry:, association_id:, rows:)`. It accepts 1 to `MAX_ROWS` (50) rows. Each row goes through the form boundary, then the admin contract; every row is checked so all errors show at once, and the rows save in one transaction or not at all. Success redirects **303** to the entry detail page at the association's anchor with `association_entries.created` (pluralized). Failure re-renders with **422**, base errors in the summary and each row's errors in place. A `rows` value that is not an object returns **400**.

**Bridge row forms.** `Entities::EntryForm.new(..., links: { slug => id })` builds a bridge row form. The linked participant references are never shown and are always written as given, so a forged back-reference in the submission is ignored. The bridge's other `EntityReference` attributes with an `entity_entries` source become reference dropdowns. Without `links`, participant references stay excluded as before. `links` count toward `writable_slugs` but not toward `available?`.

**Edit / delete.** `edit` and `update` reuse `EntryFormComponent` (PATCH, `entry[data]`) with `Entities::Activities::UpdateAssociationEntry.call(customer:, actor:, entity:, entry:, association_id:, row:, params:)`, which shares `EntryWriter`'s validate/persist/error steps through `Entities::Activities::AssociationEntryWriter`. Hidden bridge fields keep their stored values. `destroy` calls `Entities::DeleteEntry`. Both return to the association's anchor with a translated notice.

**In a dialog.** When the entity is writable and has associations, `EntryDetailComponent` renders `QuickAddDialogComponent.new(depth: 0)`, and each card is an `association-dialog` Stimulus controller with that dialog as its outlet. **Add** and **Edit** open their form in the dialog instead of navigating, titled `association_entries.new_title` / `edit_title`. The links keep the full page `href`, so opening one in a new tab, or a page without the dialog, still shows the full page. They carry `data-turbo-prefetch="false"`: Turbo serves a hover-prefetched response to any later GET of the same URL, so a prefetched full page would replace the dialog's frame request and leave the dialog blank. A request whose `Turbo-Frame` header is `entity-quick-add-frame-<depth>` gets the `new_dialog` / `edit_dialog` view without the layout: the form inside that frame, submitting into it, with Cancel closing the dialog. A failed save re-renders there with **422**. A successful save sets the flash notice and renders `saved_dialog`, whose `created` marker tells the dialog to close; the opener then reloads the entry page with `Turbo.visit(..., { action: "replace" })` and scrolls back to the card. `destroy` is not in the dialog and redirects as before.

The reusable control API and adapter responsibilities are documented on [Page rendering](page-rendering).

### Controllers and authorization

`Admin::Maintenance::EntitiesController` includes `SharedResourceMode`. `definition_scope` is `Entity.shared` on the platform prefix and `Entity.accessible` on the tenant path (with customer heads preloaded). Create calls `apply_create_identity!` (`customer_id` NULL on the platform prefix, current customer otherwise) and `Billing::Quota::Guard` with item key `"entity"`, skipped for a shared create.

Permitted keys:

- Definition body, always: `icon`, `color`, `description`, `default_properties`, `property_schema`, `attribute_groups`, `referenced_template`.
- Identity, only when the save is not a tenant override: `name`, `display_label`, `extended_model`, `associations`.

`template_fields` runs `TemplateFieldExtractor` on `PageLayoutTemplates.find`. `base_model_fields` returns `EntityDefinitions::Capabilities.base_model_fields(customer_id, class_name)`: the column names, only when `ExtendableModelRegistry.for_customer` allows the class and it is an `ApplicationRecord`. `create_entity` reserves the same columns (`attribute.reserved_by_base_model`). Collection routes also include trash and empty-trash.

Trashing an entity also takes its launched forms offline, inside the same transaction and before the status change: `soft_delete` calls `take_offline!` on every `Page.for_entity(id).launched`, which for a shared entity means every tenant's forms. `Page.for_entity` compares the stored binding as text, so a JSON number or string matches. `forms_taken_offline` holds the count, and `destroy` appends `maint_core.flash.entities.forms_taken_offline` to its notice when it is positive. If a form can't be taken offline, the trash rolls back. Restoring doesn't relaunch forms: `EntityRestorationsController#restored_notice` appends `maint_core.flash.entity_restorations.offline_forms` with the names of the tenant's offline forms bound to the entity.

Tenant maintenance entities require admin/owner. The platform prefix additionally requires pinned owner eligibility and actual outer CID `81721200`; members cannot open either surface.

Browse new/create/edit/update inherit `ApplicationController`'s `TenantContext`, `RouteAuthorization`, CanCan and MFA guards. GET checks route read access; POST checks create access and PATCH checks update access. Anonymous users must sign in; members and foreign admins are denied through the existing handlers. Creation entity lookup requires current-customer or shared ownership plus active/non-bridge status; missing, foreign, inactive and bridge targets return **404**. Direct `CreateEntry` calls separately require a persisted customer, `actor.admin_or_owner?`, and either same-customer membership or pinned `actor.platform_owner?`; inaccessible/inactive/bridge entities return `:forbidden`. The URL customer controls all writes even for the cross-tenant owner. Body/query customer IDs, entity IDs, audience and provenance cannot replace those trusted bindings. Creation and editing are mounted only in browse nesting, not maintenance or platform nesting.

### Stimulus

`entity_form_controller.js` (`entity-form`) is the orchestrator on `app/views/admin/maintenance/entities/_form.html.erb`. It delegates to `TypeManager`, `ValidatorManager`, `TemplateBuilder`, `SchemaManager`, `ModalManager`, `ConstantsManager`, `ReferenceManager`, `AttributeManager`, `AssociationManager`, `GroupManager`, `DndManager`, and `ComputedManager` under `app/javascript/controllers/entity_form/`. `ReferenceManager` — the Use Entity Records mode: loads `entities.json` once, offers labelable display fields only, validates both selects, shows the Owner switch only for a person-entity target, and returns `{ options_source, entity_id, label_field }` plus `owner: true` when that switch is on. Submit runs `collectAttributes`, which fills the hidden JSON fields the controller permits.

The base-model select's `required` attribute is server-rendered. On change, `entity-form#extendedModelChanged` fetches `base_model_fields` and reserves those column names in the attribute editor.

`association_rows_controller.js` (`association-rows`) adds and removes bridge rows on the association **Add** form (see **Associated records**). `add` clones the row template under the next `rows[<index>]` key (the `__ROW__` token is replaced in attributes only, so option labels stay as written) and focuses its first field; `remove` keeps at least one row; `refresh` renumbers headings from the `heading` value (default `Entry {number}`) and shows remove buttons only while there are several rows.

`association_dialog_controller.js` (`association-dialog`) sits on each writable association card. `open` loads the clicked link's `href` into the `entity-quick-add-dialog` outlet with the `title` action param; without the outlet it does nothing and the link navigates. When the dialog reports the save, `reload` revisits the current path and query with `Turbo.visit(..., { action: "replace" })` and, on the next `turbo:load`, scrolls the card into view. Without Turbo it falls back to `location.reload()`.

`entity_selector_controller.js` looks up a sibling `page-canvas` controller. The live page editor is `page-builder`; see [Page builder](page-builder).

## Where to pay attention

### Route audit: definition, promotion and deletion invariants

Definition JSON validates syntax, array/object containers, object items, required slugs and config/reference shapes before generators/forms use it. Extension writes require the owner-approved registry and a concrete ActiveRecord subclass, not just a constant name. Copy preserves association display fields while omitting bridge identity. Shared-target deletion checks tenant referencers; source/bridge soft-delete and restore are atomic and surface failures.

`Entities::DeleteEntry.call(entry:)` returns success/entry/errors. Controllers scope customer plus entity and transact batch deletion; the model nullifies module-log links and deletes only same-tenant bridge rows referencing the participant, with cycle-bounded cascading. It does not delete other participants. CSV headings/text guard formula-leading values while numeric cells stay numeric. Association navigation is cycle-safe; see [Dashboard](dashboard), [Shared resources](shared-resources), [Page rendering](page-rendering).

:::note
On 2026-10-11 the targeted AI/entity-definition/STT/LLM slice passed 1,666 examples with zero failures using `storage/ai_verify.sqlite3` and schema version `20261011190000`. It includes partial-field normalization, strict invalid-slug rollback, version lineage, confirmation snapshots and immutable quota regressions. Core promotion/deletion, CSV and unrelated lifecycle requests were outside that run. Exact scope and commands are recorded in `docs/audits/2026-10-11-ai-stt-targeted-verification.md`.
:::

:::attention
Read definitions and entry provenance through `resolved_current_version`. `current_version` remains the global head. Existing customer forks stay pinned until `reset_customer_override!`.
:::

:::attention
`Admin::Maintenance::EntitiesController` treats `associations` as identity. A tenant-path save of a shared entity cannot change associations, name, display label, or `extended_model`. `Entity#shared_entity_has_no_associations` also rejects associations on a shared row. Bridges and `Computed` fields exist on customer-owned entities. `EntitySchemaValidation` refuses a computed field unless `customer_owned?`.
:::

:::attention
`Entities::ComputedCompiler.compile` returns a subquery string or `nil`. It does not raise. The schema type is `"Computed"`, not a rollup. `EntityEntry#validate_data_keys` rejects persistence when those fields occur in `data`; callers that need the aggregate use the compiled SQL (`compile_all`).
:::

:::attention
Do not look for entries under `/admin/maintenance/platform/entities`. The route comment and the controller mount keep `EntityEntry` on the tenant. `find_entry` always adds `customer_id: current_customer.id`. Destroying a shared entity is `guard_shared_global_writes` on `:destroy` only; the tenant path may still edit the definition body.
:::

## Key code

```ruby
# app/models/entity.rb
  def reload_definition_from_head!
    payload = resolved_current_version&.content&.payload
    snap = payload.present? ? JSON.parse(payload) : {}
    self.icon                = snap.fetch("icon", "custom")
    self.color               = snap.fetch("color", "#6366f1")
    self.description         = snap["description"]
    self.referenced_template = snap["referenced_template"]
    # Use the *_json= setters so json_attribute's memoized parse is cleared.
    self.property_schema_json    = snap["property_schema"]    || []
    self.default_properties_json = snap["default_properties"] || {}
    self.associations_json       = snap["associations"]       || []
    self.attribute_groups_json   = snap["attribute_groups"]   || []
    # The loaded state is the baseline for Dirty tracking, so a subsequent edit
    # is diffed against the head content (BridgeEntityManagement relies on this).
    clear_changes_information if persisted?
    self
  end
```

```ruby
# app/controllers/admin/maintenance/entities_controller.rb
    DEFINITION_KEYS = %i[icon color description default_properties property_schema
                         attribute_groups referenced_template].freeze
    IDENTITY_KEYS = %i[name display_label extended_model associations].freeze

    def permitted_entity_keys
      return DEFINITION_KEYS if tenant_override?(@entity)

      DEFINITION_KEYS + IDENTITY_KEYS
    end
```

```ruby
# app/models/entity_entry.rb
  def stamp_entity_version
    self.entity_version_number = entity&.resolved_current_version&.version_number
  end
```

```ruby
# app/services/entities/activities/create_entry.rb
        contract = ctx[:contract] = EntityEntryContract.build_for(
          form.entity, audience: "admin", writable_slugs: form.writable_slugs
        ).new(model)
        contract.validate(form.filtered_input)
```

```ruby
# app/services/entities/computed_compiler.rb
    FUNCTIONS = %w[avg sum count min max].freeze
    FILTER_OPS = %w[= != > >= < <=].freeze
    NUMERIC_HTML_TYPES = %w[number range].freeze
    MAX_PRECISION = 6
```

```ruby
# app/models/concerns/versionable.rb
  def resolved_current_version(cid = Current.customer_id)
    line_cid = override_customer_id(cid)
    return current_version if line_cid.nil?
    customer_head_for(line_cid)&.current_version || current_version
  end
```

Related: [Shared resources](shared-resources), [Page builder](page-builder), [Flowchart builder](flowchart-builder), [Constants](constants), [Operations API](operations-api).
