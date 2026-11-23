# Add Attribute Modal — Visual Polish + Grouping Bug Fixes

**Date:** 2026-06-03
**Surface:** Entity create/new + edit page (`/:cid/admin/maintenance/entities/new` and `/edit`)
**Files:** `app/views/admin/maintenance/entities/_attribute_modal.html.erb`,
`app/javascript/controllers/entity_form/{group_manager,attribute_manager,type_manager,template_builder}.js`

## Goal

Two things on the entity builder's "Add Attribute" experience:

1. **Re-design (visual polish only)** the Add Attribute modal — keep the existing
   single-modal layout and field order, but tighten spacing, hierarchy, and styling.
   Special attention to the **selection HTML type** configuration (the options editor for
   `select` / `radio` / `checkbox`): a layout/style refactor of that block, no new features.
2. **Fix the attribute grouping / ungroup functionality**, which is currently broken, plus
   the other defects found in the add-attribute flow.

Out of scope (explicitly declined by user): tabbed/stepped/wizard modal, drag-reorder of
options, bulk-paste options, any structural reorganization, any backend/model/route change.

## Bugs to fix

### B1 — Grouping is completely non-functional (critical)
`GroupManager.showFloater()` appends its dropdown/menu/inline-form markup to
`document.body`, which is **outside the `entity-form` Stimulus controller element**.
Stimulus only binds `data-action` (and registers `data-*-target`) for elements inside the
controller's subtree, so every floater interaction silently never fires:
`chooseGroup`, `startNewGroupInline`, `commitNewGroupInline`, `openGroupMenu` →
`editGroup` / `deleteGroup`, and the inline `newGroupInlineName` target.

**Fix:** append the floater to the controller element (`this.c.element`) instead of
`document.body`, and switch positioning from `position:absolute` + page-scroll coordinates
to `position:fixed` + viewport coordinates (`rect.bottom` / `rect.left`, no scroll offset),
so placement is unaffected by where the node lives in the DOM. The existing outside-click
dismiss handler is unaffected.

### B2 — Editing an attribute silently removes it from its group
`AttributeManager.collectModalData()` hardcodes `group_id: null`. On edit,
`SchemaManager.updateAttributeRow` then resets the row's `data-attr-group-id` to `""`,
so editing any grouped attribute ejects it from its group.

**Fix:** preserve the editing row's existing `group_id` when collecting modal data
(read it from `this.c.editingRow`'s `group_id` hidden input / `data-attr-group-id` when
editing; keep `null` for brand-new attributes). The modal does not edit group membership,
so it must round-trip the current value rather than clobber it.

### B3 — Malformed `<button>` markup in the modal
In `_attribute_modal.html.erb`, the "Use Constant" toggle and the "Add Option" button are
missing the closing `>` on their opening tag, so the button's label/child markup is absorbed
into the tag and the buttons render broken.

**Fix:** close both tags correctly (covered naturally by the restyle).

### B4 — Dead references / stale copy
`ModalManager.resetModalFields` references `configMin/Max/Step/Rows` targets that do not
exist in the modal or the controller's `static targets`; the config section comment says
"selection and numeric types" though only selection + file configs exist.

**Fix:** remove the dead target resets and correct the comment during the polish pass.

### B5 — JS-built group header styling drift (consistency)
`TemplateBuilder.buildAttributeGroupHeaderHtml` (used when regrouping after a client-side
change) renders headers with hardcoded gray utility classes, while the server-rendered
header in `_attributes_table.html.erb` uses the themed tokens
(`bg-accent-subtle`, `text-text-muted`, `attribute_group_color_classes`). After a regroup the
header restyles inconsistently.

**Fix:** align the JS-built header markup with the server-rendered, themed version so a row
moved into/out of a group keeps consistent styling. (Color bar map already mirrors the
helper's bar colors.)

## Re-design (visual polish) of the modal

Keep the same fields, order, and single-scroll modal. Polish only:

- Consistent vertical rhythm and section grouping using the existing design tokens
  (`form-label`, `input-field`, `text-caption`, `bg-canvas-elevated`, `border-border-subtle`).
- **Selection options editor**: restyle the Manual/Constant segmented toggle so the active
  state is unambiguous; give each option row a clean, aligned layout (default control +
  label input + value input + remove), and make the "Add Option" affordance a clear,
  full-width-or-leading secondary button. Tidy the constant preview card. No behavior change.
- Fix all malformed markup as part of this pass.
- Tailwind-only, Stimulus-only — no custom CSS/JS. Keep all existing `data-action` /
  `data-entity-form-target` hooks intact (renaming/removing a target would break the
  controller).

## Testing

- Stimulus/system coverage (or controller-level JS behavior tests where the suite has them)
  for: grouping a selection of attributes via "Move to group", creating a group inline,
  the group kebab (edit/delete), and that editing a grouped attribute keeps its group.
- Verify the modal renders without malformed markup (request/view spec or system spec).
- Scope: moderate change confined to the entity builder; run the entity-builder-related
  specs (model/helper + any request/system specs covering the entities form), not the full suite.

## Success criteria

- Selecting attributes → "Move to group" → choosing/creating a group actually moves them and
  the table regroups; ungrouping (choose "Ungrouped") works; group edit/delete work.
- Editing a grouped attribute preserves its group.
- Modal renders cleanly; selection-options editor looks polished and aligned.
- No regressions in add/edit/copy/remove attribute, validators, visibility, constant options.
