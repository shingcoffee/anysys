# Property Editor Refactor — Process Step / Loop Advanced / Decision Branches

**Date:** 2026-06-12
**Page:** `/:cid/admin/maintenance/flowcharts/:id/edit` (right-hand property sidebar)
**Goal:** Make the three heaviest editor surfaces guided instead of blank-slate: fewer entry paths, contextual auto-population, progressive disclosure, consistent styling.

## Scope

In scope: `step_manager.js` (process Step tab), `branch_manager.js` (decision Branches), loop fields in `schemas.js` + `form_builder.js` (loop Advanced tab), `templates.js`, supporting ViewComponents, and the loop-type change handler in `property_editor_controller.js`.

Out of scope: runtime (`flowchart_runtime/*.rb`), I/O tab, JoinManager, other element types beyond incidental shared-template impact, schema/DB changes, undo system, branch reordering. No backward compatibility burden (per AGENTS.md), but the saved config key names/shapes must stay exactly as the runtime reads them today.

## Decisions on open questions

1. **Process action picker placement:** Inline searchable picker (combobox) directly on the Step tab — no modal. Empty state = the picker is the hero. Committed step card gets a "Change" affordance that re-opens the picker. The step modal and the quick-add dual-dropdown row are both deleted.
2. **Branch condition requirement:** Optional. Condition-less branches are allowed (they act as "otherwise" routes) and show an amber "no condition" badge on the card instead of blocking submit.
3. **Loop type switch retention:** Values of hidden fields are preserved (CSS hide/show, never DOM removal), so switching While → For-Each → While round-trips losslessly.

## Design

### 1. Process — Step section

**Single entry path.** Replace the quick-add category/action dropdown pair *and* the cascading-dropdown modal with one inline searchable action picker built on the existing `searchActions()` / `getActionsByCategory()` registry helpers:

- A search input + grouped results list (category headings, leaf actions flattened with breadcrumb labels, e.g. "Validate › Format › Email"). Hierarchical `subOptions` trees are flattened to selectable leaves so one click commits a fully-resolved action — no cascading selects.
- Keyboard navigable (↑/↓/Enter), filters on label/description/category.
- `singleUse` actions already present render disabled with a "already added" hint.
- Selecting a leaf **immediately commits the step** — no separate confirm button.

**Config visible immediately.** On commit, the step card renders expanded with its `configSchema` fields inline:

- Fields with `default` pre-filled; `visibleWhen` evaluated against the defaulted config so dependent fields show correctly from the first paint.
- Path-typed fields get `ctx.` placeholder hints.
- On reload of a saved element, the card starts collapsed (summary view) — expanded-by-default applies only to a just-added step.

**Inline Advanced.** Retry count / backoff / timeout / guard condition move into a collapsible "Advanced" sub-section inside the expanded card (collapsed by default). The header shows an "N override(s)" badge when any value is non-default. `collectSteps()` reads them from the card, removing the modal-only fields.

### 2. Decision — Branches section

**One guided flow.** Remove the branch quick-add dropdown. "Add Branch" (modal, retained because branch creation also spawns a canvas element) is the only path, upgraded:

- **Preset chips** at the top of the modal: `Yes`, `No`, `Otherwise`, `Custom`. Picking a chip pre-fills the branch name and a sensible condition skeleton (Yes → main condition's left operand with `==`/`true`; No → negated; Otherwise → no condition). Custom leaves everything blank.
- **Left operand is a select**, seeded from upstream variables (`_getParentOutputOptions` + `canvas.entityAttributes`) with an "enter manually…" escape hatch that swaps to a text input.
- Choosing a left operand defaults the operator to `==` and focuses the right operand.
- Name required (inline validation); condition optional.

**Readable cards.** Branch cards summarize conditions in plain language using `BRANCH_OPERATORS` labels ("ctx.status equals active"; "Count of Users > 10"). Condition-less branches show an amber "no condition — always matches" badge. Summaries refresh immediately after edits.

**Canvas safety.** `onBeforeChange` snapshot, branch element creation, `_remapBranchConnections`, `_repositionAllBranchElements` are called in exactly today's order — the refactor changes the form layer only.

### 3. Loop — Advanced section

**Progressive disclosure by loop type** (segmented control stays):

- **For-Each:** show `collection` (required, `ctx.items` hint), `itemVariable`, `indexVariable`, `skipCondition`. On selecting For-Each, auto-fill `itemVariable` = "item" and `indexVariable` = "index" *iff currently empty*. A live hint under `itemVariable` reads "Available inside the loop body as `<value>`".
- **While / Do-While:** show the condition builder full-width at top, nothing else by default.
- **Options disclosure:** `iterations` (relabelled "Max iterations (safety guard)" with helper text), `breakCondition`, `accumulatorVariable` live in a collapsed "Options" group for all types (for For-Each, `skipCondition` stays top-level since it's the common case).
- Type switches show/hide via CSS only; all values survive round-trips. Visibility logic consolidated into the declarative `visibleWhen` mechanism in `form_builder.js` instead of the bespoke `handleLoopTypeChange` DOM walking — one visibility manager for all tabs.

### 4. Shared consistency

- One card template (`buildCompactItem` evolution) renders both step and branch cards: accent border, title, human-readable subtitle, badges, trailing actions.
- Section headers, empty states, and disclosure sub-sections use the same `templates.js` builders across the three surfaces; matching ViewComponents (`SectionHeaderComponent`, `EmptyStateComponent`, `CompactItemComponent`) updated to mirror them where server-rendered.
- New shared `buildDisclosureSection()` template (chevron header + collapsible body + optional badge) backs the step Advanced and the loop Options groups.

## Data contracts (unchanged)

- `properties.steps[]`: `{id, action, suboption, selectionLabels, keywordParams, description, retryCount, retryBackoff, timeout, guardCondition, config{}}`
- `properties.branches[]`: `{id, name, description, elementId, condition{type: field|query_count, …}}` + condition mirrored on the connection
- Loop: `loopType`, `condition{}`, `collection`, `itemVariable`, `indexVariable`, `iterations`, `breakCondition`, `accumulatorVariable`, `skipCondition`

## Error handling

- Entity API failure in Query Count panel: keep silent-fail, render disabled "Could not load entities" option.
- For-Each save with empty `collection`: inline field error, save blocked for that field only.
- Branch modal without name: inline error via existing `_highlightFieldError`.

## Testing

- Component specs for updated/new ViewComponents (disclosure section, compact item changes).
- Jest-less codebase → behavior verified via system/request specs where feasible plus the release-engineer smoke pass on the live page; existing `element_io_tab_spec.rb` untouched.
- QA focus: config JSON emitted by `collectSteps()` / `collectBranches()` / loop form matches the contracts above byte-for-byte for representative configs.
