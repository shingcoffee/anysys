# I/O Tab: Beautify, Fix Empty State, Real-time Updates — Design

**Date:** 2026-04-21
**Topic:** Three improvements to the element I/O tab on the flowchart edit page:
  a) Beautification (minimal clean-up, source badges)
  b) Fix empty I/O tab when two elements share the same step type
  c) Real-time I/O tab updates when element config changes

## Problem

On `/:customer_id/flowcharts/:id/edit`, the property editor's **I/O** tab for elements has three issues:

1. **Visual noise / bare styling.** Pin rows are plain monospace text with unstyled `<select>` elements. No source context (where did this pin come from — user wired it or generator default?), no count headers, no visual hierarchy.

2. **Empty tab when two elements share the same step.** When two `process` elements contain steps with overlapping output pins, `computeOutputOverrides` renames outputs on both via the collision-rename logic. The Inputs section may render empty or stale because `_render` re-reads pin data from `canvas.elementPins[element.id]` at render time, which can be clobbered by a concurrent `refreshElementPins` call (triggered by the same `flowchartStructureChanged` event that fires on editor open). The snapshot is taken before `computeElementOverrides` awaits, but the render reads the cache again after the await — a window where an async cache overwrite can produce empty output.

3. **No real-time update.** Changing a config field on the General tab triggers `_performSync` → `flowchartStructureChanged` → `refreshElementPins` in the background, but the I/O tab HTML is not re-rendered unless the user switches away and back to the I/O tab. The tab badge count also stales.

## Scope

All changes are in JavaScript only. No Ruby, no routes, no ViewComponent changes.

## Solution

### a) Beautification

**New file:** `app/javascript/controllers/property_editor/element_io/renderers.js`

Owns all HTML string assembly for the I/O tab pane. `element_io_manager.js` calls renderer functions rather than building HTML strings inline. Keeps the manager file logic-focused.

**Visual changes:**

| Element | Before | After |
|---------|--------|-------|
| Section header | `<h4 class="text-sm font-semibold text-gray-700 mt-2 mb-1">Inputs</h4>` | `Inputs (N)` in `text-xs font-semibold uppercase tracking-wide text-slate-500 mb-2` |
| Section divider | `class="mt-4"` on outputs div | `border-t border-slate-100 pt-3 mt-1` |
| Pin row | `flex items-center gap-2 my-1` | `flex items-center gap-2 py-1 min-h-[28px]` |
| Source badge | none | `config` badge (indigo-50/indigo-700) for `config_expr`; `auto` badge (slate-50/slate-500) for `generator_literal`; `text-[10px] font-medium px-1.5 py-0.5 rounded` |
| Producer select | `text-sm border border-gray-300 rounded px-2 py-1` | `text-xs border border-slate-200 rounded-md px-2 py-0.5 bg-white focus:ring-1 focus:ring-indigo-400` |
| Rename badge | `text-xs text-amber-700` inline | `text-[11px] bg-amber-50 text-amber-700 px-1.5 rounded border border-amber-200` |
| Empty state | `text-xs text-gray-500` | `text-xs text-slate-400 italic` — "No inputs detected." / "No outputs detected." |

Source badges use the `source` field already present on input pin objects (`config_expr` or `generator_literal`). No data-model change.

### b) Empty state fix — pin snapshot

**Root cause:** `_render` reads `canvas.getElementPins(element.id)` at line 88 — *after* `computeElementOverrides` has awaited. The `flowchartStructureChanged` listener in `flowchart_canvas_controller.js` calls `refreshElementPins` concurrently. If that async write lands between the `computeElementOverrides` await and the `_render` call, `_render` sees a fresh-but-empty intermediate cache entry.

**Fix:** Snapshot pins immediately after the fetch/cache-prime in `openForElement`, and pass the snapshot as a parameter to `_render`.

```js
// openForElement — after cache prime:
const pins = canvas.getElementPins(element.id)   // snapshot before any await
const computed = await computeElementOverrides(canvas, element.id)
element.properties.io_overrides = this._merge(element.properties.io_overrides, computed)
this._render(element, paneElement, pins)          // pass snapshot

// _render signature change:
_render(element, pane, pins) {   // pins is now a parameter, not re-read from cache
  const overrides = element.properties.io_overrides || { inputs: [], outputs: [] }
  // ...
}
```

The snapshot is taken synchronously before the first `await`, so it cannot be overwritten by the concurrent `refreshElementPins`.

### c) Real-time updates — self-subscribed listener

`ElementIoManager` subscribes to `flowchartStructureChanged` on the canvas SVG element when it opens for an element. It debounces by 150ms to let `refreshElementPins` (triggered by the same event in `flowchart_canvas_controller.js`) complete first before re-calling `openForElement`.

A new `close()` method cleans up the listener and internal state. `property_editor_controller._hideSidebar` calls `this.elementIoManager.close()` before clearing `currentElement`.

**Filtering:** The listener checks `event.detail?.elementId`. If the event is scoped to a specific element id and that id does not match the currently-open element, the re-render is skipped. Global structural changes (no elementId in detail) always trigger a re-render.

**Debounce:** 150ms — matches the `_syncChangesToCanvas` debounce in the property editor controller, ensuring the structural change is fully settled before re-render.

**Listener lifecycle:**

```
openForElement(element, pane)
  → store _currentElement, _currentPane
  → _subscribeToStructureChanges()   (no-op if already subscribed)

close()
  → removeEventListener on canvas svg
  → clear _structureListener, _reRenderTimer
  → clear _currentElement, _currentPane

property_editor_controller._hideSidebar()
  → elementIoManager.close()   ← NEW call
  → (existing teardown)
```

## Files changed

| File | Change |
|------|--------|
| `app/javascript/controllers/property_editor/element_io_manager.js` | Snapshot fix (b); listener lifecycle — `_subscribeToStructureChanges`, `close` (c); delegate HTML to renderers (a) |
| `app/javascript/controllers/property_editor/element_io/renderers.js` | **New** — exports `renderInputRow`, `renderOutputRow`, `renderSection` helpers |
| `app/javascript/controllers/property_editor_controller.js` | Call `elementIoManager.close()` in `_hideSidebar` |
| `spec/system/property_editor/element_io_tab_spec.rb` | New skipped examples documenting intent for all three improvements |

## Edge cases

| Case | Behavior |
|------|----------|
| `refreshElementPins` races with render | Snapshot taken pre-await; race window eliminated |
| Element editor closed before debounce fires | `close()` calls `clearTimeout(_reRenderTimer)`; re-render never fires |
| User switches to I/O tab after config change | `onTabActivated` still calls `openForElement` — snapshot path runs, fresh pins used |
| Element with no `source` field on input pin | Source badge not rendered (backwards compat with any cached pin missing the field) |
| Same `flowchartStructureChanged` fires multiple times rapidly | Debounce collapses into one re-render |
| Two elements share same step — outputs collision-renamed | Outputs show amber rename badges; inputs show correct pins from snapshot |
| Canvas svg not yet present when `openForElement` called | `_subscribeToStructureChanges` returns early; no listener added (tab still renders, just no auto-refresh) |

## Out of scope

- Per-step I/O pane in the Steps tab (`step_io_manager.js`) — unchanged
- Output section interaction (already read-only)
- Ruby / server-side changes
- Full JS unit test suite (no test framework configured)
