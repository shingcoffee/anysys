# Email templates list — balanced UX redesign

**Date:** 2026-07-30  
**Status:** Approved for planning  
**Surface:** `/:cid/admin/modules/emails/templates` (index) + related show header actions

## Goal

Balanced table redesign: keep scanability of the current list, fix row-action UX bugs (kebab overflow, unclear Archive vs Delete, status transitions only on the list), and move lifecycle / destructive / secondary actions to the detail page.

## Decisions (from brainstorming)

| Topic | Choice |
|-------|--------|
| Primary outcome | UX redesign + bug fixes |
| Optimize for | Balanced table (not cards, not radical layout) |
| Must-fix focus | Row-action UX |
| Action model | Drop kebab; compact Edit + Preview on list; status / Duplicate / Versions / Delete elsewhere |

**Approach:** Compact actions + detail-page lifecycle (Approach 1).

## Page structure & columns

Remain on `AdminTableComponent` (same pattern as Audience / Lists).

| Column | Behavior |
|--------|----------|
| Template | Name + subject subtitle (token labels via shared `TokenCatalog`), editor-type leading icon |
| Status | Lifecycle badge (`draft` / `active` / `retired` shown as Archived in UI copy) |
| Messages | Per-template message usage count (existing correlated subquery) |
| Updated | Relative datetime |
| Actions | Compact group only — **no kebab** |

Keep: search (`q`), status filter, breadcrumbs, title, “New Template”, empty state (tighten copy only if inconsistent).

No Content sub-tabs (templates-only entry stays). No card/list hybrid layout.

## Row actions & lifecycle

### List (per row)

- **Edit** → edit page (inline / `row_actions`)
- **Preview** → edit page with `Emails::TemplateEditorComponent::PREVIEW_ANCHOR`
- No `row_menu_actions`, no `menu-placement` on this table
- Row click → show (detail) unchanged

### Show (header)

- Keep: Edit, Preview, Duplicate, Delete (confirm-gated)
- **Add:** lifecycle actions from existing `status_actions_for` (Set active / Archive / etc.) wired to the existing `status` PATCH endpoint
- Versions remains reachable via the existing versions count/link on show (not a list kebab item)

### Removed from list

Duplicate, Versions modal trigger, status transitions, Delete.

## Bugs fixed

1. **Kebab overflow / clipping** — list menus inside `overflow` table wrappers become invisible on last rows; removing the kebab eliminates the class of bug for this surface.
2. **Unclear Archive vs Delete on the list** — both leave the list; Delete stays confirm-gated on show; Archive is an explicit status action on show.
3. **Status transitions missing on show** — today they exist only in the list kebab; move them to the show header.

## Out of scope

- Orphan subject tokens rendering as `{{Token}}` (unknown UUID)
- Unnormalized literal `{{first_name}}` subjects
- Reworking `menu_placement_controller` globally (other tables may still use kebabs)
- Stale `templates_entry_config` in feature-module registration (dead alternate config; optional cleanup only if touched)

## Implementation shape

1. **`TemplatesController#index`:** keep column/filter/resolver setup; `@row_actions` = Edit + Preview only; remove `@row_menu_actions` (and versions Stimulus wrapper on index if it exists only for the kebab Versions item).
2. **`templates/show`:** append `status_actions_for(@template)` (or equivalent) to `AdminPageComponent` `actions`, with appropriate variants (secondary for lifecycle; danger stays on Delete).
3. **Index view:** drop `row_menu_actions:` and versions controller mount if unused after kebab removal.
4. **I18n:** reuse existing keys (`set_active`, `set_retired` / Archive, etc.); add `en` + `zh-CN` only if new copy is required.
5. **No new Stimulus** for this pass.

## Testing

Targeted request specs (not full suite):

- Index renders Edit + Preview per row; does **not** render kebab / `menu-placement`, Duplicate, Versions open action, Delete, or status transitions on the list
- Index search, status filter, messages count, token-labeled subject subtitle still work
- Show header includes lifecycle actions for the current status; Delete still confirm-gated; Duplicate still present
- Status PATCH still redirects to index with flash; in-use guard unchanged
- Tenant isolation 404 cases unchanged

No new Vitest (no JS change on this path).

## Success criteria

- List actions are Edit + Preview only; no clipped/hidden menus
- Lifecycle and Delete are discoverable on show with clear labeling
- Existing list scan columns and filters still work
- Specs above pass with real command output
