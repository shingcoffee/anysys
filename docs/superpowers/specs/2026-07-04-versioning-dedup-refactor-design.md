# Versioning Dedup Refactor — Head-Pointer + Content-Addressed Storage

**Date:** 2026-07-04
**Status:** Design — awaiting review
**Scope:** `Entity`, `Flowchart`, `Page` and their version machinery (`Versionable`, `VersionRecord`, the three `*_versions` tables, the Versions panel controllers).

## Problem

The versioned definition of a resource is stored **twice over**:

- **(A) Live ↔ current-version duplication.** A parent's live columns and its `default_version` snapshot hold the *exact same* definition. Every `create_version_snapshot!` copies the live state into a new full-JSON version row, and `default_version_id` points at it — so the current state exists in two places.
- **(B) Cross-version redundancy.** Every version is a *full* snapshot. A one-field edit re-stores the entire definition; `restore_as_new!` writes two near-identical snapshots ("Before restore" + "Restored from vN"); no-op saves store another full copy.

Currently: `Entity` spreads its definition across many columns; `Flowchart`/`Page` keep theirs in a single `configuration` column. `Entity` versions `name`/`name_slug`/`type` inside the snapshot; `Flowchart`/`Page` keep `name`/`type` as separate un-versioned columns.

## Chosen approach

**Head-pointer / immutable revisions + content-addressed storage** (per-resource content tables).

- The parent becomes a **head**: it points at its `current_version_id`. The definition **body** lives only in version rows.
- Version payloads are extracted into a per-resource **content-addressed** table. A payload is stored **once**, keyed by the SHA-256 of its canonical JSON; identical payloads across the history share one content row.
- The current definition is therefore stored in exactly one place (the head version's content), and redundant snapshots collapse to shared references → **(A)** and **(B)** both eliminated.

### Decisions locked during brainstorming

1. Eliminate **both** (A) and (B).
2. Apply to **all three** resources via the shared concerns.
3. **Un-version** entity `name` / `name_slug` / `type` — they become plain queryable identity columns on the parent, exactly how `Flowchart`/`Page` already treat their `name`/`type`. Renames/type changes no longer create a version. Icon/color/description **stay** versioned (they are body, not identity). This keeps uniqueness, slugs, `accessible`/`shared` scopes, and `search_by_name` at the SQL level.
4. **One content table per resource** (`entity_definition_contents`, `flowchart_configuration_contents`, `page_configuration_contents`), with the dedup/GC behavior factored into a shared `ContentAddressable` concern so the three tables don't duplicate logic.

## Data model

### New per-resource content tables (immutable, content-addressed)

Each of `entity_definition_contents`, `flowchart_configuration_contents`, `page_configuration_contents`:

| column | type | notes |
|---|---|---|
| `id` | pk | |
| `customer_id` | integer, **nullable** | NULL for `shared` resources; dedup is scoped per-tenant |
| `content_hash` | string, not null | SHA-256 hex of the payload's **canonical** JSON (recursively sorted keys) |
| `payload` | text, not null | the definition/configuration JSON — stored **once** |
| `created_at` | datetime | immutable; rows are never updated |

- Unique index on `(customer_id, content_hash)` → dedup within a tenant, no cross-tenant payload sharing (preserves multi-tenant isolation and keeps GC per-tenant).
- Index on `customer_id`.
- Rows are **immutable**: never updated, only created (find-or-create) and garbage-collected when unreferenced.

### Version rows (`entity_versions`, `flowchart_versions`, `page_versions`)

- **Drop** the payload column (`snapshot` on entity; `configuration` on flowchart/page).
- **Add** `content_id` (FK → the resource's content table, `null: false`), indexed.
- **Keep** `version_number`, `description`, `based_on_version_id`, `customer_id`, the parent FK, timestamps.
- `VersionRecord#payload` now reads through `content.payload` — the controller JSON contract is byte-for-byte unchanged.

### Parent rows

- Rename `default_version_id → current_version_id` (the head pointer) on all three parents.
- **Flowchart / Page:** drop the `configuration` column. The body lives only in `current_version → content`.
- **Entity:** drop the definition-**body** columns: `property_schema`, `default_properties`, `associations`, `attribute_groups`, `extendable_models`, `icon`, `color`, `description`, `referenced_template`. **Keep** identity/classification/lifecycle: `customer_id`, `name`, `name_slug`, `type`, `status`, `is_bridge_entity`.

## Components

### `ContentAddressable` concern (new) — shared by the three content models

- `self.canonical_json(hash)` — deterministic serialization (recursively sorted keys) so equal definitions hash equally regardless of key order.
- `self.digest(payload)` — SHA-256 hex of the canonical form.
- `self.store!(customer_id:, payload:)` — find-or-create by `(customer_id, content_hash)`; returns the content row. Idempotent; retries the narrow `RecordNotUnique` race (as `Versionable` already does).
- `self.sweep_orphans!(customer_id:)` — delete content rows of this table not referenced by any version row (called after prune/destroy, inside the same transaction).

Each content model: `include ContentAddressable`, `include TenantScoped` (customer scoping), and declares its owning version relation for the orphan sweep.

### `VersionRecord` concern (parent-side of a version) — modified

- `acts_as_version parent:, content_class:` (replaces `payload:`).
- Adds `belongs_to :content, class_name: content_class`.
- `#payload` delegates to `content.payload`. `validates :content, presence: true` (replaces the payload-presence validation).
- `version_number` uniqueness scope unchanged.

### `Versionable` concern (head-side) — modified

- Rename everything `default_*` → `current_*` (`current_version` association, `current_version_id`, `display_current_version`, `nullify_current_version_id_before_destroy`).
- `create_version_snapshot!` → **`commit_version!(description:, based_on_version_id:)`**:
  1. Build the payload via `current_snapshot` (unchanged reader hook).
  2. **No-op short-circuit:** if the payload's hash equals the current head's content hash, return the head unchanged (no new version, no new content).
  3. `content = <ContentClass>.store!(customer_id:, payload:)` — dedups automatically.
  4. Create the version row with `content_id`, next `version_number`, lineage.
  5. Advance `current_version_id` in the same transaction (head can never point at a stale version).
  6. `prune_versions!` to `MAX_VERSIONS`, then `content_class.sweep_orphans!` for this tenant.
- **`restore_as_new!(version)`** collapses to **one** commit: create a new head version whose `content_id` = the chosen version's *existing* content row (zero payload copy), `based_on_version_id = version.id`. No "Before restore" snapshot — the outgoing head is already an immutable version in the history.
- Prune still nullifies inbound FK pointers first (SQLite RESTRICT quirk, unchanged).

### Definition read delegation (Entity)

To contain blast radius, the parent **keeps its public accessor API**. Only the backing store changes: `property_schema_json`, `default_properties_json`, `associations_json`, `attribute_groups_json`, `extendable_models_json`, and the derived readers (`grouped_property_schema`, `data_fields`, `calculated_fields`, `searchable_field_keys`, `as_palette_item`, contract factory, association graph, palette, member surface, page bindings) all keep calling the same methods.

- Implement a memoized `definition` reader that parses `current_version.content.payload` once.
- Re-back each `*_json` accessor to pull its slice from `definition` (replacing the column-backed `json_attribute` reads for body fields).
- Memo invalidated on `reload` and after `commit_version!`.
- `icon` / `color` / `description` / `referenced_template` readers likewise delegate to `definition`.

`Flowchart`/`Page` already read their body through a single `configuration` accessor; re-back that accessor from the head content the same way (their `configuration_json` memo already exists on `Page`).

### Write flow (admin edit)

The controller's update action applies the contract/Reform changes to an in-memory working definition, then calls `commit_version!(description: "Manual save")`. Entity's current `saved_changes.keys.intersect?(VERSIONED_COLUMNS)` gate is replaced by the `commit_version!` no-op short-circuit (hash unchanged ⇒ no version). Identity-only edits (rename/type/status) are ordinary column writes on the parent and never touch versions.

### Versions-panel controllers

- `base_versions_controller`, `entities_controller`, `flowcharts_controller`, `pages_controller`: rename `default_version`/`default_version_id` references to `current_version`/`current_version_id`; the "Default Version v#" column label becomes "Current Version v#". The JSON list/restore/set-current contract is otherwise unchanged (`payload` still resolves via `content`).

## Migration & backfill

Single migration (dev DB is SQLite; note the RESTRICT-FK handling the concern already documents):

1. Create the three content tables.
2. For each existing version row: canonicalize its `snapshot`/`configuration` → `store!` (find-or-create content) → set `content_id`.
3. For each parent: point `current_version_id` at the existing `default_version` row (the live state already equals that snapshot — duplication A — so content dedup makes them coincide; no new head row needed).
4. Create a `v1` head (content + version) for parents that have **no** versions — notably **bridge entities**, which are currently excluded from versioning but whose body must now live in a version.
5. Make `content_id` `null: false`; drop the payload columns (`snapshot`, `configuration`); drop the entity body columns; rename `default_version_id → current_version_id`.
6. Sweep orphan contents per tenant.

The backfill runs in Ruby (like the existing `CreateEntityVersions` backfill) so payloads are canonicalized exactly as the app does, not double-encoded.

## Testing

- **Content model:** canonical JSON is key-order-independent; equal payloads ⇒ equal hash ⇒ one row; different payloads ⇒ distinct rows; `store!` is idempotent under the unique-index race.
- **Commit:** head advances; version_number increments; no-op short-circuit creates no version when the hash is unchanged.
- **Restore:** references the chosen version's *existing* content row (assert no new content row created); lineage `based_on_version_id` set; head advanced.
- **GC:** pruning past `MAX_VERSIONS` deletes now-orphaned content; content still referenced by another version is retained.
- **Multi-tenant:** content dedup scoped by `customer_id`; two tenants with identical payloads get separate rows; `shared` resources (customer_id NULL) store/retrieve correctly and never dedup against a tenant's rows.
- **Read delegation:** `entity.property_schema_json` et al. reflect the head content; reflect the new head after commit and after restore; survive `reload`.
- **Identity un-versioning:** entity rename/type change writes the parent column, creates **no** version; uniqueness/slug/scope/search still work.
- **Migration:** every parent ends with a non-null `current_version_id`; bridge entities get a v1; payload/body columns are gone; no orphan content; round-trip of a sampled definition is byte-identical.
- **Blast-radius regression:** existing contract-factory, association-graph, palette, member-surface, and page-binding specs pass unchanged (proves the accessor delegation is transparent).

## Out of scope

- Near-duplicate (delta) compression — content-addressing dedups *exact* duplicates only; that is the dominant redundancy here (restore pairs, no-op saves, revert-to-previous). Delta chains were considered and rejected (fragile JSON diffs, chain-walking reads).
- Any change to the Versions-panel UX beyond the "Current Version" label rename.
- Cross-resource content sharing (each resource has its own content table by decision 4).
