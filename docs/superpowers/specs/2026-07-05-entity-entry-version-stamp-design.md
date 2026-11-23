# Entity Entry Version Stamp — Design

**Date:** 2026-07-05
**Status:** Approved
**Scope:** Backend only (model + migration + specs). No UI, controller, or route changes.

## Problem

`entity_entries` links to its entity via `entity_id` only. It carries no record of
*which entity definition version* was in effect when the entry was authored. Entities
are versioned (head pointer `current_version_id` → `EntityVersion`, definitions in a
content-addressed store), and the definition can change over time (fields added,
renamed, removed). Today every entry is always reinterpreted against the entity's
current head — there is no provenance for the schema an entry was created under.

## Goal

Record, per entry, the entity version it was authored under, for **provenance only**
(audit / potential future display). Rendering and validation continue to resolve
against the current head exactly as they do today — this change adds a stored fact and
nothing else.

## Decisions

- **Store the version _number_, not a foreign key.** Versions are pruned to the most
  recent `MAX_VERSIONS = 50` (`Versionable#prune_versions!` does `destroy_all` on older
  rows, and orphaned content is GC'd). A nullable FK would be nullified once its version
  is pruned, losing provenance after 50 newer versions. `version_number` is immutable
  and never reused, so `"authored under v7"` stays true forever. This suits a
  provenance-only need where durability matters more than joining to a (possibly gone)
  row.
- **Storage-only.** No index (not a hot query path), no index-backed filtering, no UI
  column. Adding display later is a separate, additive change.
- **Existing entries stay `NULL`.** Their authoring version is genuinely unknown; a
  `NULL` stamp reads as "pre-versioning / unknown." No backfill.

## Design

### 1. Migration

```ruby
add_column :entity_entries, :entity_version_number, :integer, null: true
```

Nullable integer. No index, no FK.

### 2. Stamping — a single `before_create` on the base `EntityEntry`

```ruby
before_create :stamp_entity_version

def stamp_entity_version
  self.entity_version_number = entity&.current_version&.version_number
end
```

- `before_create` is the one choke point every creation path flows through — the
  flowchart runtime (`new_model_generator`, `upsert_model_generator`,
  `bulk_import_generator`), console, imports. No code-generator changes required.
- Fires once, at insert, so the stamp is **frozen**: later edits to the entity (new
  versions) never mutate an existing entry's stamp.
- Sets to `NULL` when the entity has no current version yet.
- **Authoritative (not `||=`).** `entity_version_number` is a real column, so
  `EntityEntry#[]=` routes it to the AR setter (`super`), and the entity-params path
  (`FormParamsRouter#build_primary` → `PopulatePrimary`) does *not* whitelist keys to
  the schema. A crafted submission (`entity[entity_version_number]=…`) would otherwise
  forge the stamp. Low severity (no tenant/privilege boundary — only mislabels the
  user's own entry) but it defeats the feature's purpose, so `before_create`
  overwrites any incoming value from the true head. Nothing in scope legitimately
  pre-sets the stamp.

### 3. No other changes

`entity_version_number` is a real AR column, so `EntityEntry`'s hash-access,
`method_missing`, and `validate_data_keys` correctly treat it as a column (via
`has_attribute?`), not a `data` JSON key — no conflict with the dynamic-attribute
machinery. The `index` action (`@entries.map(&:data_json)`) is untouched.

## Testing (model specs)

- Creating an entry stamps `entity_version_number` from the entity's head
  `version_number`.
- The stamp is **frozen**: committing new entity versions after the entry is created
  does not change the entry's stamp.
- `NULL` when the entity has no current version.
- Authoritative: a client-supplied `entity_version_number` is overwritten by the head
  (anti-forge).
- Verified through the `EntityEntry.build_for(entity)` runtime creation path, not only
  the base class.

## Out of scope

- Rendering/validating entries against their stamped version (current head still used).
- Displaying the version in any entry list/table UI.
- Backfilling existing entries.
- Any FK / join to `entity_versions`.
