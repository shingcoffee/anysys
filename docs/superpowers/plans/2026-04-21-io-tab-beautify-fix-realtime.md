# I/O Tab: Beautify, Fix Empty State, Real-time Updates — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Beautify the element I/O tab, fix the empty-tab race condition when two elements share step types, and re-render the I/O tab in real-time whenever element config changes.

**Architecture:** All changes are in JavaScript only — `element_io_manager.js`, a new `element_io/renderers.js` helper, and a one-line addition to `property_editor_controller.js`. The empty-state fix snapshots pin data before any await to eliminate a concurrent-write race. Real-time updates use a self-subscribed `flowchartStructureChanged` listener in `ElementIoManager` with a 150ms debounce.

**Tech Stack:** StimulusJS, vanilla JS (no frameworks), TailwindCSS for styling. RSpec for system-level specs (currently skipped pending JS driver).

---

## File Map

| File | Role |
|------|------|
| `app/javascript/controllers/property_editor/element_io/renderers.js` | **New** — pure HTML string helpers: `renderInputsSection`, `renderOutputsSection`, `renderInputRow`, `renderOutputRow` |
| `app/javascript/controllers/property_editor/element_io_manager.js` | Modified — use renderers, snapshot fix, listener lifecycle |
| `app/javascript/controllers/property_editor_controller.js` | Modified — call `elementIoManager.close()` in `_hideSidebar` |
| `spec/system/property_editor/element_io_tab_spec.rb` | Modified — add skipped examples for new behaviors |

---

### Task 1: Create `renderers.js` with styled HTML helpers

**Files:**
- Create: `app/javascript/controllers/property_editor/element_io/renderers.js`

- [ ] **Step 1: Create the file**

```js
import { escapeHtml } from "utils"

/**
 * Renders the full Inputs section HTML.
 * @param {Array} inputPins - Array of {pin, source} objects from IoExtractor
 * @param {Array} overrideList - Array of {pin, override_key} objects
 * @param {Function} renderRow - (pin, overrideList) => string
 * @returns {string}
 */
export function renderInputsSection(inputPins, overrideList, renderRow) {
  const count = inputPins.length
  const header = `<div class="flex items-center justify-between mb-2">
    <span class="text-xs font-semibold uppercase tracking-wide text-slate-500">Inputs</span>
    <span class="text-xs text-slate-400">${count}</span>
  </div>`
  const body = count === 0
    ? `<p class="text-xs text-slate-400 italic">No inputs detected.</p>`
    : inputPins.map((p) => renderRow(p, overrideList)).join("")
  return `<div data-element-io-inputs>${header}${body}</div>`
}

/**
 * Renders the full Outputs section HTML.
 * @param {Array} outputPins - Array of {pin} objects
 * @param {Array} overrideList - Array of {pin, renamed_to} objects
 * @returns {string}
 */
export function renderOutputsSection(outputPins, overrideList) {
  const count = outputPins.length
  const header = `<div class="flex items-center justify-between mb-2">
    <span class="text-xs font-semibold uppercase tracking-wide text-slate-500">Outputs</span>
    <span class="text-xs text-slate-400">${count}</span>
  </div>`
  const body = count === 0
    ? `<p class="text-xs text-slate-400 italic">No outputs detected.</p>`
    : outputPins.map((p) => renderOutputRow(p, overrideList)).join("")
  return `<div data-element-io-outputs class="border-t border-slate-100 pt-3 mt-1">${header}${body}</div>`
}

/**
 * Renders a single output pin row.
 * @param {{pin: string}} outputPin
 * @param {Array} overrideList - Array of {pin, renamed_to}
 * @returns {string}
 */
export function renderOutputRow(outputPin, overrideList) {
  const rename = overrideList.find((o) => o.pin === outputPin.pin)?.renamed_to
  const badge = rename
    ? `<span class="text-[11px] bg-amber-50 text-amber-700 px-1.5 py-0.5 rounded border border-amber-200 ml-1">⚠ renamed → ${escapeHtml(rename)}</span>`
    : ""
  return `
    <div class="flex items-center gap-2 py-1 min-h-[28px]" data-element-io-output data-pin="${escapeHtml(outputPin.pin)}">
      <span class="font-mono text-sm text-slate-700">${escapeHtml(outputPin.pin)}</span>${badge}
    </div>`
}

/**
 * Renders the source badge for an input pin.
 * @param {string|undefined} source - "config_expr" | "generator_literal" | undefined
 * @returns {string}
 */
export function renderSourceBadge(source) {
  if (source === "config_expr") {
    return `<span class="text-[10px] font-medium px-1.5 py-0.5 rounded bg-indigo-50 text-indigo-700 border border-indigo-100">config</span>`
  }
  if (source === "generator_literal") {
    return `<span class="text-[10px] font-medium px-1.5 py-0.5 rounded bg-slate-50 text-slate-500 border border-slate-200">auto</span>`
  }
  return ""
}

/**
 * Renders a read-only input pin row (0 or 1 real candidate).
 * @param {{pin: string, source?: string}} pin
 * @returns {string}
 */
export function renderReadOnlyInputRow(pin) {
  return `
    <div class="flex items-center gap-2 py-1 min-h-[28px]" data-element-io-input data-pin="${escapeHtml(pin.pin)}">
      <span class="font-mono text-sm text-slate-700">${escapeHtml(pin.pin)}</span>
      ${renderSourceBadge(pin.source)}
    </div>`
}

/**
 * Renders an editable input pin row with producer <select> (2+ real candidates).
 * @param {{pin: string, source?: string}} pin
 * @param {Array} externals - [{effective, label}]
 * @param {Array} selfs - [{effective, label}]
 * @param {string|null} selectedKey - currently selected override_key or null
 * @returns {string}
 */
export function renderEditableInputRow(pin, externals, selfs, selectedKey) {
  const options = [
    `<option value="__none__" ${selectedKey === "" ? "selected" : ""}>— no producer —</option>`
  ]
  for (const cand of externals) {
    const selected = selectedKey === cand.effective ? "selected" : ""
    options.push(
      `<option value="${escapeHtml(cand.effective)}" ${selected}>${escapeHtml(cand.label)} • ${escapeHtml(cand.effective)}</option>`
    )
  }
  for (const cand of selfs) {
    const selected = selectedKey === cand.effective ? "selected" : ""
    options.push(
      `<option value="${escapeHtml(cand.effective)}" ${selected}>${escapeHtml(cand.label)} • ${escapeHtml(cand.effective)} (self)</option>`
    )
  }
  return `
    <div class="flex items-center gap-2 py-1 min-h-[28px]" data-element-io-input data-pin="${escapeHtml(pin.pin)}">
      <span class="font-mono text-sm text-slate-700">${escapeHtml(pin.pin)}</span>
      ${renderSourceBadge(pin.source)}
      <select class="text-xs border border-slate-200 rounded-md px-2 py-0.5 bg-white focus:ring-1 focus:ring-indigo-400 focus:outline-none"
              data-element-io-producer-select>
        ${options.join("")}
      </select>
    </div>`
}
```

- [ ] **Step 2: Verify file exists**

```bash
ls app/javascript/controllers/property_editor/element_io/renderers.js
```

Expected: file listed with no error.

---

### Task 2: Update `element_io_manager.js` — use renderers + snapshot fix

**Files:**
- Modify: `app/javascript/controllers/property_editor/element_io_manager.js`

- [ ] **Step 1: Replace the import block at the top of the file**

Replace lines 24–27 (the four import lines) with:

```js
import { escapeHtml } from "utils"
import { fetchElementPins } from "controllers/property_editor/element_io/io_params_client"
import { computeElementOverrides } from "controllers/property_editor/element_io/override_computer"
import { ElementReachability } from "controllers/property_editor/element_io/reachability"
import {
  renderInputsSection,
  renderOutputsSection,
  renderReadOnlyInputRow,
  renderEditableInputRow
} from "controllers/property_editor/element_io/renderers"
```

- [ ] **Step 2: Update `openForElement` to snapshot pins and store element/pane references**

Replace the existing `openForElement` method (lines 34–52) with:

```js
async openForElement(element, paneElement) {
  if (!element || !paneElement) return
  const canvas = this.controller.canvas
  if (!canvas) return

  this._currentElement = element
  this._currentPane = paneElement
  this._subscribeToStructureChanges()

  const cached = canvas.getElementPins(element.id)
  const needsFetch =
    !cached || ((cached.inputs?.length || 0) + (cached.outputs?.length || 0) === 0)
  if (needsFetch) {
    const pins = await fetchElementPins(element.type, element.properties || {})
    canvas.setElementPins(element.id, pins)
  }

  // Snapshot before any subsequent awaits to avoid race with refreshElementPins
  const pins = canvas.getElementPins(element.id)

  element.properties = element.properties || {}
  const computed = await computeElementOverrides(canvas, element.id)
  element.properties.io_overrides = this._merge(element.properties.io_overrides, computed)

  this._render(element, paneElement, pins)
}
```

- [ ] **Step 3: Add `close()` method after `updateProducer`**

Add this new method after the closing `}` of `updateProducer` (after line 71):

```js
close() {
  const svg = this.controller.canvas?.svg
  if (svg && this._structureListener) {
    svg.removeEventListener("flowchartStructureChanged", this._structureListener)
  }
  this._structureListener = null
  clearTimeout(this._reRenderTimer)
  this._currentElement = null
  this._currentPane = null
}
```

- [ ] **Step 4: Add `_subscribeToStructureChanges()` private method**

Add this method before the `_merge` method:

```js
_subscribeToStructureChanges() {
  if (this._structureListener) return
  const svg = this.controller.canvas?.svg
  if (!svg) return
  this._structureListener = async (event) => {
    const changedId = event.detail?.elementId || null
    if (changedId && changedId !== this._currentElement?.id) return
    clearTimeout(this._reRenderTimer)
    this._reRenderTimer = setTimeout(() => {
      if (this._currentElement && this._currentPane) {
        this.openForElement(this._currentElement, this._currentPane).catch(() => {})
      }
    }, 150)
  }
  svg.addEventListener("flowchartStructureChanged", this._structureListener)
}
```

- [ ] **Step 5: Update `_render` to accept `pins` parameter and use renderers**

Replace the existing `_render` method (lines 87–104) with:

```js
_render(element, pane, pins) {
  const overrides = element.properties.io_overrides || { inputs: [], outputs: [] }
  const reachability = new ElementReachability(this.controller.canvas)

  const inputsHtml = renderInputsSection(
    pins.inputs || [],
    overrides.inputs || [],
    (pin, overrideList) => this._renderInputRow(element, pin, overrideList, reachability)
  )
  const outputsHtml = renderOutputsSection(pins.outputs || [], overrides.outputs || [])

  pane.innerHTML = inputsHtml + outputsHtml

  this._wireInputHandlers(element, pane)
}
```

- [ ] **Step 6: Update `_renderInputRow` to use renderer helpers**

Replace the existing `_renderInputRow` method (lines 115–156) with:

```js
_renderInputRow(element, pin, overrideList, reachability) {
  const existing = overrideList.find((e) => e.pin === pin.pin)
  const selectedKey = existing ? existing.override_key : null

  const externals = this._externalCandidates(element, pin, reachability)
  const selfs = this._selfCandidates(element, pin)
  const candidates = externals.concat(selfs)

  if (candidates.length < 2) {
    return renderReadOnlyInputRow(pin)
  }

  return renderEditableInputRow(pin, externals, selfs, selectedKey)
}
```

- [ ] **Step 7: Remove `_renderInputs` and `_renderOutputs` methods**

Delete the old `_renderInputs` method (lines 106–113) and the old `_renderOutputs` method (lines 189–206) — these are now handled by `renderers.js`.

- [ ] **Step 8: Verify the full file compiles without errors by checking for syntax**

```bash
node --input-type=module < app/javascript/controllers/property_editor/element_io_manager.js 2>&1 | head -5
```

Expected: blank output (no syntax errors). If there are import errors about missing modules, that's expected in Node — look only for syntax errors.

---

### Task 3: Update `property_editor_controller.js` — call `elementIoManager.close()`

**Files:**
- Modify: `app/javascript/controllers/property_editor_controller.js:1024-1037`

- [ ] **Step 1: Add `elementIoManager.close()` call in `_hideSidebar`**

In `_hideSidebar` (around line 1024), find this code:

```js
_hideSidebar() {
  // Remove form change listeners
  this._removeFormChangeListeners()
```

Replace it with:

```js
_hideSidebar() {
  // Remove form change listeners
  this._removeFormChangeListeners()

  // Close element I/O manager to remove structure-change listener
  if (this.elementIoManager) this.elementIoManager.close()
```

- [ ] **Step 2: Verify change is correct**

```bash
grep -n "elementIoManager.close" app/javascript/controllers/property_editor_controller.js
```

Expected output: one line showing `this.elementIoManager.close()` inside `_hideSidebar`.

---

### Task 4: Add skipped system spec examples for the three new behaviors

**Files:**
- Modify: `spec/system/property_editor/element_io_tab_spec.rb`

- [ ] **Step 1: Add new skipped examples to the spec file**

Append these examples inside the outer `RSpec.describe` block, after the last existing `it` block (after line 128, before the final `end`):

```ruby
  it "shows source badges on input pins — config badge for config_expr, auto badge for generator_literal" do
    skip "System specs need Capybara JS driver configuration"
    visit "/#{customer.id}/flowcharts/#{flowchart.id}/edit"

    find("[data-element-id='l1']").click
    find("[data-tab='io']").click

    # L1's `items` input comes from a config expression ctx[:items] in the
    # collection field — the source badge should read "config".
    # (Requires Capybara JS driver to inspect rendered DOM)
    within "[data-element-io-inputs]" do
      row = find("[data-element-io-input][data-pin='items']", wait: 3)
      # If source is config_expr, the "config" badge span is present
      expect(row).to have_css("span", text: "config").or have_css("span", text: "auto")
    end
  end

  it "shows section headers with pin counts" do
    skip "System specs need Capybara JS driver configuration"
    visit "/#{customer.id}/flowcharts/#{flowchart.id}/edit"

    find("[data-element-id='l1']").click
    find("[data-tab='io']").click

    within "[data-element-io-inputs]" do
      # Header row contains "Inputs" label
      expect(page).to have_css("span", text: /\AInputs\z/i)
    end

    within "[data-element-io-outputs]" do
      expect(page).to have_css("span", text: /\AOutputs\z/i)
    end
  end

  it "re-renders the I/O tab in real-time after a config field change on the General tab" do
    skip "System specs need Capybara JS driver configuration"
    visit "/#{customer.id}/flowcharts/#{flowchart.id}/edit"

    find("[data-element-id='l1']").click
    find("[data-tab='io']").click

    # Record initial output count shown in Outputs header badge
    initial_count = find("[data-element-io-outputs] span", text: /\d+/).text.to_i

    # Switch to General tab and change a config field that affects I/O pins
    find("[data-tab='general']").click
    fill_in "indexVariable", with: "new_idx"

    # Switch back to I/O tab — pins should have updated (new_idx instead of idx)
    find("[data-tab='io']").click
    within "[data-element-io-outputs]" do
      expect(page).to have_content("new_idx")
    end
  end

  it "I/O tab is not empty when two loop elements share the same step type (item/idx outputs)" do
    skip "System specs need Capybara JS driver configuration"
    visit "/#{customer.id}/flowcharts/#{flowchart.id}/edit"

    # L2 shares item/idx output pins with L1. Before the snapshot fix this
    # could render an empty I/O tab due to a race on the pin cache.
    find("[data-element-id='l2']").click
    find("[data-tab='io']").click

    within "[data-element-io-outputs]" do
      expect(page).to have_css("[data-element-io-output]")
    end
    within "[data-element-io-inputs]" do
      expect(page).to have_css("[data-element-io-input]")
    end
  end
```

- [ ] **Step 2: Run the spec file to confirm all skipped (none fail at parse/syntax level)**

```bash
bundle exec rspec spec/system/property_editor/element_io_tab_spec.rb --format documentation 2>&1 | head -30
```

Expected: all examples listed as "pending" / "skipped". No failures. No syntax errors.

---

### Task 5: Run existing Ruby specs as a regression check

**Files:** (none changed)

- [ ] **Step 1: Run the io_extractor and controller specs**

```bash
bundle exec rspec spec/services/code_generators/io_extractor_spec.rb spec/controllers/code_generators/element_type_io_params_controller_spec.rb --format progress 2>&1 | tail -10
```

Expected: all green, 0 failures.

- [ ] **Step 2: Run the full system spec file**

```bash
bundle exec rspec spec/system/property_editor/element_io_tab_spec.rb --format documentation 2>&1 | tail -15
```

Expected: all pending/skipped, 0 failures.

---

## Self-Review Checklist

**Spec coverage:**

| Spec requirement | Task |
|-----------------|------|
| a) Beautification — source badges, section headers with count, styled rows, better selects, better rename badge | Task 1 (renderers.js) + Task 2 Step 5/6 |
| b) Empty state fix — snapshot pins before await | Task 2 Step 2 |
| c) Real-time re-render — self-subscribed listener, 150ms debounce | Task 2 Steps 3/4 |
| c) Close listener on editor close | Task 2 Step 3, Task 3 Step 1 |
| System spec coverage for new behaviors | Task 4 |
| Regression check | Task 5 |

**Placeholder scan:** No TBDs, no "implement later", all steps have complete code. ✓

**Type consistency:**
- `renderInputsSection` exported in Task 1, imported in Task 2 Step 1 ✓
- `renderOutputsSection` same ✓
- `renderReadOnlyInputRow` same ✓
- `renderEditableInputRow` same ✓
- `close()` defined in Task 2 Step 3, called in Task 3 Step 1 ✓
- `_subscribeToStructureChanges()` defined in Task 2 Step 4, called in Task 2 Step 2 ✓
- `_render(element, pane, pins)` — three-param signature defined in Task 2 Step 5, called with three args in Task 2 Step 2 ✓
- `_currentElement` / `_currentPane` set in Task 2 Step 2, read in Task 2 Step 4 (listener), cleared in Task 2 Step 3 (close) ✓
- `_renderInputRow` still called as `this._renderInputRow(element, pin, overrideList, reachability)` in Task 2 Step 5, and the updated signature in Step 6 matches ✓
