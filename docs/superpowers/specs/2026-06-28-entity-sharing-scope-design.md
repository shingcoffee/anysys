# Entity Sharing Scope — Customer Specific / Shared

**Date:** 2026-06-28
**Status:** Approved (design)
**Surface:** `/:cid/admin/maintenance/entities` (platform-owner customer `81721200`)

## Summary

Give the `Entity` model the same sharing-scope concept that `Flowchart`
already has: an entity is either **Customer Specific** (tenant-scoped, the
status quo) or **Shared** (`customer_id = NULL`, visible to every tenant,
mutable only by the platform owner). The platform owner sets the scope via a
**Type** selector when creating/editing an entity; ordinary admins never see
the selector and their entities are always Customer Specific.

This is achieved by **renaming the existing `entities.element_type` string
column to a `type` integer enum** that mirrors `Flowchart`'s enum exactly.

### Out of scope / non-goals

- **No flowchart change.** Flowchart already uses
  `enum :type, { customer_specific: 0, shared: 1 }` with labels
  "Customer Specific" / "Shared". It is left untouched.
- **No `Constant` change.** Only Entity is modified.
- **Shared entities cannot define associations / bridge entities** in v1
  (see "Associations" below). This keeps per-tenant bridge generation
  unambiguous and can be lifted later.

## Naming decision

Both Flowchart and Entity use the enum keys **`customer_specific`** and
**`shared`**, displayed as **"Customer Specific"** and **"Shared"**. We do
NOT rename to "custom". This matches the existing flowchart enum so the two
features are consistent and the ~130 existing `customer_specific` references
(flowchart, factories, specs, the sibling `Constant` model) are untouched.

## Data model

### Migration: `element_type` (string) → `type` (integer enum)

`entities.element_type` today is a `string` column, `null: false`,
`default: "custom"`, and in practice always `"custom"`. It is replaced by:

- `type` — `integer`, `null: false`, `default: 0`, indexed.
  Enum: `{ customer_specific: 0, shared: 1 }`.
- Data conversion: every existing row (all `element_type="custom"` with a
  `customer_id`) maps to `customer_specific (0)`.
- `customer_id` becomes **nullable** (shared entities have `customer_id NULL`).
  Tenant-required-ness is enforced in the model, not the DB, mirroring
  Flowchart.

The migration:
1. add `type` integer column (default 0, null false) + index,
2. backfill `type = 0` for all rows (already the default),
3. remove the `element_type` column,
4. change `customer_id` to nullable.

### `Entity` model changes

```ruby
self.inheritance_column = :_type_disabled   # `type` is an enum, not STI
enum :type, { customer_specific: 0, shared: 1 },
     default: :customer_specific, prefix: :type
```

- **Validations**
  - Remove `validates :element_type, presence: true`.
  - `validates :customer_id, presence: true` becomes conditional:
    required only `if: :type_customer_specific?`.
  - Name uniqueness becomes conditional (mirror flowchart):
    `uniqueness: { scope: :customer_id }, if: :type_customer_specific?`
    and `uniqueness: true, if: :type_shared?`.
  - **New:** a shared entity may not define associations —
    `validate :shared_entity_has_no_associations`
    (adds an error if `type_shared?` && `associations_list.any?`).
- **Callbacks**
  - `before_validation :clear_customer_for_shared` →
    `self.customer_id = nil if type_shared?`.
- **Scopes** (mirror flowchart / TenantScoped)
  - `scope :shared, -> { where(type: :shared) }`
  - `scope :customer_specific, -> { where(type: :customer_specific) }`
  - `scope :accessible` — current customer's own entities **OR** shared:
    `where(customer_id: Current.customer_id).or(where(type: :shared))`
    when `Current.customer?`, else `where(type: :shared)`.
- **Snapshot / versioning**
  - `definition_snapshot` / `apply_definition_snapshot!`: replace the
    `element_type` key with `type` (store/read the enum string).
  - `EntityVersion::VERSIONED_COLUMNS`: `element_type` → `type`.
  - `as_palette_item` keeps `element_type: "custom_#{id}"` — this is a
    **computed palette identity**, not the DB column, and JS palette
    consumers depend on it. Unchanged.

### Bridge entities

`BridgeEntityManagement` currently assigns `element_type: "custom"` when
materializing a bridge entity; this becomes `type: :customer_specific`.
Bridge-entity internals remain strictly `customer_id`-scoped — shared
entities do not participate in bridge generation (enforced by the
"no associations on shared" validation above).

## Cross-tenant visibility

Shared entities (`customer_id NULL`) must surface in the **entity catalog
read paths** the same way shared flowcharts do, but NOT in bridge internals.

- **Switch to `Entity.accessible`** for the catalog/picker reads where a
  tenant should be able to *see and select* shared entities:
  - `Admin::Maintenance::EntitiesController#find_entity` and the index
    (index: own + shared-only-under-platform-owner, see Controller below).
  - Entity pickers used by flowchart/page/entity-copy forms
    (`Entity.for_current_customer.by_name` → `Entity.accessible.by_name`)
    so shared entities are selectable.
- **Leave `customer_id`-scoped (unchanged):** all of
  `BridgeEntityManagement`, `EntitySchemaValidation`, page-binding bridge
  lookups, and code generators that resolve bridge entities. These operate
  on per-tenant materialized records and must not leak across tenants.

Each switched call site is enumerated in the implementation plan so the
blast radius is explicit and reviewable.

## Controller & authorization

`Admin::Maintenance::EntitiesController` (only reachable under
`/:cid/admin/maintenance/entities`; admin/owner guard already in place):

- `platform_owner_customer?` / `current_user.platform_owner?` helpers
  (reuse `Authentication::User::PLATFORM_CUSTOMER_ID` /
  `User#platform_owner?`), mirroring `FlowchartsController`.
- `new`: `Entity.new(type: :customer_specific, customer: current_customer)`.
- `entity_params`: permit `:type` (replacing `:element_type`), but
  **force `type = "customer_specific"` unless `current_user.platform_owner?`**
  — only the platform owner can create shared entities.
- `create`: quota guard (`Billing::Quota::Guard`) applies only to
  `customer_specific` creates; shared creates skip tenant quota.
- `edit`/`update`: add `before_action :guard_shared_write!` —
  a non-platform-owner attempting to edit/update/destroy a shared entity
  gets a redirect (HTML) / 403 `shared_entity_readonly` (JSON).
- `find_entity`: `Entity.accessible.find(params[:id])` so the owner can open
  shared entities; the write guard still blocks non-owner mutation.
- `index`: `flowchart_index_scope`-style — own entities, plus `shared`
  **only under the platform-owner customer**. The "Type" column renders
  `type.titleize` ("Customer Specific" / "Shared").

## View

`app/views/admin/maintenance/entities/_form.html.erb`:

- Replace the hidden `element_type` field with a **Type `<select>`**
  (`[["Customer Specific", "customer_specific"], ["Shared", "shared"]]`),
  Tailwind-only, styled like the flowchart form's Type field.
- The selector is rendered **only for the platform owner**. For ordinary
  admins the field is omitted (their entities are always customer_specific;
  `entity_params` enforces this server-side regardless).
- Help caption: "Shared entities are visible to every customer and can only
  be edited by the platform owner."

## Testing

- **Model spec** (`spec/models/entity_spec.rb`, updated): enum present;
  `customer_id` required only when customer_specific; `clear_customer_for_shared`
  nulls customer on shared; conditional name uniqueness (same name allowed in
  two tenants for customer_specific, globally unique for shared);
  shared-entity-with-associations is invalid; `accessible`/`shared` scopes;
  `element_type` references removed.
- **Request spec** (`spec/requests/admin/maintenance/entities_spec.rb`, updated +
  new): platform owner can create & edit a shared entity; non-owner admin's
  `type` param is forced to customer_specific; non-owner cannot edit/destroy a
  shared entity (403/redirect); a shared entity created by the owner is visible
  in another tenant's entity picker but not in their index unless platform
  owner; existing `element_type: "custom"` params replaced with `type`.
- **Factory** (`spec/factories/entities.rb`): `element_type { "custom" }` →
  `type { :customer_specific }`; add a `:shared` trait (customer nil).
- **Migration**: verified by running it on the dev DB and confirming
  existing rows become `customer_specific`.

## Files touched (anticipated)

- `db/migrate/<ts>_replace_entity_element_type_with_type.rb` (new)
- `db/schema.rb`
- `app/models/entity.rb`
- `app/models/entity_version.rb` (VERSIONED_COLUMNS)
- `app/models/concerns/bridge_entity_management.rb`
- `app/controllers/admin/maintenance/entities_controller.rb`
- Entity-picker call sites (enumerated in plan): flowcharts, pages,
  entity_copies, flowchart_copies, page_field_options, etc. — switched to
  `Entity.accessible` where cross-tenant selection is intended.
- `app/views/admin/maintenance/entities/_form.html.erb`
- `app/views/admin/maintenance/entities/index` cell (Type column label)
- Specs + factory as above.
