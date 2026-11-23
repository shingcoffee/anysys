# Admin Entity Entry List — Redesign

**Date:** 2026-08-06
**Surface:** `GET /:cid/admin/entities/:id` (`Admin::EntitiesController#show`)
**Status:** Approved design, ready for implementation planning

## Problem

The admin entity entry list is the primary way an administrator browses the records
of a dynamic entity. Today it is a thin wrapper around `AdminTableComponent` and
falls short in four ways:

1. **No actions.** The page is entirely read-only. There is no way to open a record,
   delete one, or select several. A `batch_destroy` endpoint already exists at
   `DELETE /:cid/admin/entities/:entity_id/entries/batch` but has **no UI whatsoever**.
2. **Search and sort do not work on the entity's own data.** `ColumnsBuilder` emits
   attribute columns with `sortable: false, searchable: false`, so the search box
   in the toolbar matches nothing and attribute headers are not clickable.
3. **No result ordering.** `Admin::EntitiesController#show` builds its scope with no
   `ORDER BY`. SQLite is then free to return rows in any order, which means paging
   through a list can repeat or skip records. This is a correctness bug, not just polish.
4. **Layout problems.** The Columns dropdown floats in a detached `div` above the card;
   system columns (ID / Created / Updated) render *after* the data columns; labels are
   raw field names (`first name`); blank values render as empty cells.

## Goals

- Make the page actionable: open, delete, and bulk-delete entries.
- Make search, sort, and filtering work against the entity's own attribute values.
- Make the presentation type-aware and consistent with every other admin list.
- Fix the missing default ordering.

## Non-Goals

- **No create or edit forms.** Entry authoring stays out of scope; the detail view is
  read-only. (`EntityEntryContract` exists but is not wired up here.)
- No changes to the legacy `Maintenance › Entities › Entries` page.
- No changes to the member-facing entity surfaces.
- No general rollout of the new features to the other 24 `AdminTableComponent` callers.

## Constraints

- **Database is SQLite.** `entity_entries.data` is a `text` column holding a JSON
  document. Any query against attribute values must go through `json_extract`.
- **`ModuleEntriesResolver` is shared by 25 admin list pages.** Changes to it must be
  strictly additive and preserve current behaviour for every existing caller.
- **Pagination must use the `pagy` gem**, as every other list page does. No hand-rolled
  offset/limit arithmetic.
- All user-facing strings must be I18n with parity between `en` and `zh-CN`.
- All JavaScript under `app/javascript/**` must stay at 100% Vitest line *and* branch coverage.

## Approach

A bespoke `Admin::Entities::EntriesTableComponent` owns this page's markup, rather than
adding entity-specific behaviour to the shared `AdminTableComponent`. This keeps the
other 24 admin lists completely untouched at the UI layer.

To avoid visual drift — which AGENTS.md forbids ("All backend admin pages should have
consistent layout and styling") — the bespoke component is *composed from shared
primitives*: the same `card`, `table-header`, `table-row`, and `input-field` classes,
the same `BadgeComponent` and `ButtonComponent`, and the same pagy-driven pager markup
that `AdminTableComponent` renders. It is a new arrangement of existing parts, not a
new visual language.

The **data** layer is a different matter and stays shared: `ModuleEntriesResolver` gains
`sql:` expression support. This is a two-line additive change that no existing caller
can observe, and duplicating the resolver would be exactly the redundancy AGENTS.md
warns against.

## Layout

```
Entities / student
student                                    [Export CSV] [Columns ▾]
Browse and manage student entries

┌─ card ─────────────────────────────────────────────────────────┐
│ [🔍 Search entries…]   [Grade ▾] [Active ▾]      1–10 of 42     │
│ Grade: A ✕    Active: Yes ✕    Clear all                        │
├────────────────────────────────────────────────────────────────┤  ← bulk bar replaces
│ ☑ 3 selected                          [Delete selected] [Clear] │    the row above when
├────────────────────────────────────────────────────────────────┤    ≥1 row is selected
│ ☐ │ ID↑ │ First name │ Age │ Created   │ Updated   │            │
│ ☐ │  1  │ Alice      │  12 │ 2 days ago│ 2 days ago│   [🗑]     │
├────────────────────────────────────────────────────────────────┤
│ Rows: [10 ▾]   [⇕ Compact]                        ‹ 1 2 3 ›     │
└────────────────────────────────────────────────────────────────┘
```

Specific changes from today:

1. The **Columns** dropdown moves out of its detached floating `div` and into the page
   header action row, beside **Export CSV**.
2. **Column order** becomes: selection checkbox → **ID** → attribute columns →
   Created → Updated → row actions. Today ID and the timestamps come last.
3. **Labels are titleized** — `First name`, not `first name`.
4. **Row click opens a read-only slide-over drawer** showing *every* field of the entry,
   grouped by the entity's own attribute groups, not merely the visible columns.
   Browsing therefore never leaves the list.
5. The **bulk bar** swaps in for the search row when at least one row is selected. The
   header checkbox selects the current page and shows an indeterminate state on a
   partial selection.
6. **Mobile** keeps the existing `sm:hidden` stacked card list, with a checkbox and
   tap-to-open drawer.
7. **Two distinct empty states**: "No entries yet" versus "No entries match your search",
   the latter offering a *Clear search* action.

## Data Layer

### Type-aware columns

`Admin::Entities::ColumnsBuilder` reads each field's `html_type` (per
`HtmlTypeOptions::GROUPED_HTML_TYPES`) and maps it to a column type:

| `html_type` | column type | rendering |
|---|---|---|
| `number`, `range` | `:number` | right-aligned, `tabular-nums` |
| `date`, `month`, `week` | `:date` | formatted date, exact value on hover |
| `datetime-local`, `time` | `:datetime` | relative time, exact value on hover |
| `checkbox` | `:boolean` | Yes / No |
| `select`, `radio` | `:badge` | badge derived from the field's configured options |
| `textarea` | `:truncate` | truncated at 60 characters |
| anything else | `:text` | plain text |

A blank or nil value renders as an em-dash (`—`), never an empty cell.

### Search and sort

Each attribute column carries an SQL expression alongside its key:

```ruby
{
  key:        :first_name,
  label:      "First name",
  type:       :text,
  sortable:   true,
  searchable: true,
  sql:        "json_extract(entity_entries.data, '$.first_name')",
  cell:       ->(row) { row["first_name"] }
}
```

`ModuleEntriesResolver` resolves `col[:sql]` in place of the bare column reference:

```ruby
expr = col[:sql] || "#{rel.table_name}.#{col[:key]}"
```

- `apply_search` builds `LOWER(#{expr}) LIKE :q` for every searchable column.
- `apply_sort` builds `rel.reorder(Arel.sql("#{expr} #{direction}"))`.

**Injection safety.** Expressions are constructed solely by our own builder from the
entity schema; nothing from `params` is ever interpolated into them. The incoming
`sort` param continues to be matched against the column whitelist before the column's
expression is used, and `dir` is still normalised to `asc`/`desc`.

**Numeric sorting.** `:number` columns wrap the expression in `CAST(… AS REAL)`, because
`json_extract` returns text for values stored as strings and a lexical sort would place
`10` before `9`.

### Default ordering

The scope in `Admin::EntitiesController#show` gains `.order(created_at: :desc)` so that,
absent an explicit sort, results are stable across pages. This fixes the repeat/skip
paging bug described above.

### Filters

`Admin::Entities::FiltersBuilder` produces one filter per `select` / `radio` / `checkbox`
field, taking its options from the field's `config`. Each filter supplies a scope lambda:

```ruby
->(rel, value) { rel.where("json_extract(entity_entries.data, '$.#{slug}') = ?", value) }
```

Active filters render as removable chips, and removing one resets `page` so the user
cannot land on a page that no longer exists.

### CSV export

`Admin::Entities::EntriesCsv` renders the **filtered, unpaginated** result set using the
currently visible columns, so the export always matches what is on screen. Served via
`format.csv` on `#show`, filename `<entity-slug>-entries-YYYYMMDD.csv`.

### Pagination

Pagination stays on `ModuleEntriesResolver.paginate`, which already builds a `Pagy` and
returns `{ page:, per_page:, total:, total_pages: }`. The **Rows: [10 ▾]** selector is
merely the `per_page` query param, which the resolver already accepts and feeds to
`Pagy#limit`. No new pagination code is written.

### Preference persistence

`per_page` and `density` are query params, and are also written into the existing
`EntityIndexSetting#config` JSON overlay — the same per-customer, per-entity record that
already stores `visible_column_keys` — so a user's choice persists across visits.

## Components and Files

| File | Change |
|---|---|
| `app/components/admin/entities/entries_table_component.{rb,html.erb}` | **new** — bespoke table composed from shared primitives |
| `app/components/admin/entities/entry_detail_component.{rb,html.erb}` | **new** — slide-over body, fields grouped by attribute group |
| `app/components/admin/entities/column_picker_component.html.erb` | relocated into the page-header action row |
| `app/services/admin/entities/columns_builder.rb` | type awareness, `sql:` expressions, ID-first ordering |
| `app/services/admin/entities/filters_builder.rb` | **new** |
| `app/services/admin/entities/entries_csv.rb` | **new** |
| `app/services/module_entries_resolver.rb` | honour `col[:sql]` in `apply_search` and `apply_sort` |
| `app/controllers/admin/entities_controller.rb` | default order, filters, `per_page`/`density`, `format.csv` |
| `app/controllers/admin/entity_entries_controller.rb` | add `#show` for the drawer |
| `config/routes.rb` | admin `entries` gains `only: :show` |
| `app/javascript/controllers/batch_select_controller.js` | add indeterminate state and a selected-count readout |

`app/views/admin/entities/show.html.erb` becomes a thin caller of the new component.

## JavaScript

The only JavaScript touched is the existing `batch_select_controller.js`, which already
handles select-all plus row checkboxes plus an enable/disable submit button. Two additions:

- An **indeterminate** state on the header checkbox when the selection is partial.
- A **selected-count** readout for the bulk bar.

The count string is a Stimulus Value with an ICU-style English default,
`countTemplateValue = "{count} selected"`, populated by the server through
`data-batch-select-count-template-value="<%= t("comp_admin.batch_select.selected") %>"`
and rendered with `.replace("{count}", n)`. No literal user-facing text appears in the
JavaScript source, and the spec asserts against the default rather than a data attribute.

## Authorization and Tenancy

No new authorization model — the existing guarantees are re-verified at each new entry point:

- `/:cid/admin/*` is already behind `require_admin_or_owner!`.
- The entity is loaded via `Entity.for_customer(current_customer.id)`.
- Every entry query is scoped by **both** `customer_id` and `entity_id`. This covers the
  existing `batch_destroy`, the new `#show`, the CSV export, and the list itself.
- A cross-tenant entity or entry id yields `RecordNotFound`, not a leak.

## Testing

| Spec | Covers |
|---|---|
| `spec/services/admin/entities/columns_builder_spec.rb` | type mapping, `sql:` output, ID-first order, numeric `CAST` |
| `spec/services/admin/entities/filters_builder_spec.rb` | filter derivation from select/radio/checkbox config |
| `spec/services/admin/entities/entries_csv_spec.rb` | export honours filters and visible columns |
| `spec/services/module_entries_resolver_spec.rb` | `sql:` search and sort; existing callers unchanged |
| `spec/components/admin/entities/entries_table_component_spec.rb` | column order, blank em-dash, badges, bulk bar, both empty states |
| `spec/components/admin/entities/entry_detail_component_spec.rb` | grouped fields, read-only |
| `spec/requests/admin/entities_spec.rb` | HTML and CSV responses, default ordering, filters, cross-tenant 404 |
| `spec/requests/admin/entity_entries_spec.rb` | drawer `#show`, bulk delete, tenant scoping |
| `spec/javascript/controllers/batch_select_controller.test.js` | indeterminate state and count; 100% lines and branches |

Because `ModuleEntriesResolver` is shared by 25 admin list pages, the change qualifies as
cross-cutting under AGENTS.md. Validation therefore ends with a **full** `bundle exec rspec`
run (or `bin/rails parallel:spec`), not merely targeted specs, plus
`npx vitest run --coverage`.

## Risks

- **Resolver regression.** Mitigated by making `sql:` purely additive — absent the key,
  the generated SQL is byte-identical to today's — and by the full-suite run.
- **`json_extract` availability.** Confirmed present: the project runs SQLite **3.51.1**,
  where JSON1 is compiled in by default, and `SELECT json_extract(data, '$.first_name')
  FROM entity_entries` executes successfully against the development database. No fallback
  path is required.
- **Sort performance.** `json_extract` sorting cannot use an index. Acceptable at current
  entry volumes; if it becomes a problem the remedy is a generated column plus index,
  which is out of scope here.
