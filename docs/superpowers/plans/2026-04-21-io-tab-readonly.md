# Element I/O Tab — Read-Only Rule & Self-As-Producer — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** On the flowchart edit I/O tab, show input pins read-only unless two or more real producer candidates exist; treat the element's own matching outputs as producer candidates.

**Architecture:** Two frontend files only. Extend `computeInputOverrides` in `element_io/override_computer.js` to treat self-outputs as a fallback producer for the auto-persisted default. Extend `_renderInputRow` in `element_io_manager.js` to enumerate real candidates (external + self) and branch: `≥ 2` → existing dropdown (with self options appended); `≤ 1` → pin-name-only row with no `<select>`. `io_overrides` JSON shape unchanged. No Ruby, controller, or route changes.

**Tech Stack:** StimulusJS (ESM classes), TailwindCSS. No JS test framework currently installed — manual browser verification plus extending the already-skipped system spec `spec/system/property_editor/element_io_tab_spec.rb` with codified intent.

**Spec:** `docs/superpowers/specs/2026-04-21-io-tab-readonly-design.md`

---

## File Structure

- **Modify:** `app/javascript/controllers/property_editor/element_io/override_computer.js`
  - `computeInputOverrides` gains a self-output fallback scan after the external-predecessor scan.
  - Existing helper `effectiveMatches` is reused; no new exports.
- **Modify:** `app/javascript/controllers/property_editor/element_io_manager.js`
  - `_renderInputRow` rewritten: enumerate external candidates + self candidates, count them, branch on `≥ 2` vs `≤ 1`.
  - Two tiny private helpers added inside the class: `_externalCandidates(element, pin)` and `_selfCandidates(element, pin)`. Kept inline (no new helper file — see spec "non-goals").
- **Modify:** `spec/system/property_editor/element_io_tab_spec.rb`
  - Add three new (still-skipped) examples documenting the new rules.

No new files. No routing, controller, model, schema, or Ruby service changes.

---

## Task 1: Extend `computeInputOverrides` with self-output fallback

**Files:**
- Modify: `app/javascript/controllers/property_editor/element_io/override_computer.js`

- [ ] **Step 1: Read the current `computeInputOverrides` implementation**

Open `app/javascript/controllers/property_editor/element_io/override_computer.js`. Confirm `computeInputOverrides(element, inputPins, reachability, emitted)` runs through `preds.reverse()` and sets `chosen` from the nearest predecessor. Also confirm `emitted` is a `Map<elementId, Map<pin, effectiveKey>>` already built by `collectEmittedKeys(canvas)` — this means the current element's own emitted map is already available under `emitted.get(element.id)`. We will use that.

- [ ] **Step 2: Replace the function with the self-fallback version**

Replace the entire `computeInputOverrides` function with:

```js
function computeInputOverrides(element, inputPins, reachability, emitted) {
  const overrides = []
  const preds = reachability.predecessors(element.id)
  const existing = (element.properties?.io_overrides?.inputs) || []
  const tombstoneSet = new Set(
    existing.filter((e) => e.override_key === "").map((e) => e.pin)
  )

  const selfPinMap = emitted.get(element.id) || new Map()

  for (const pin of inputPins.map((i) => i.pin)) {
    if (tombstoneSet.has(pin)) {
      overrides.push({ pin, override_key: "" })
      continue
    }

    let chosen = null
    for (let i = preds.length - 1; i >= 0 && !chosen; i--) {
      const pid = preds[i]
      const pinMap = emitted.get(pid)
      if (!pinMap) continue
      for (const [producerPin, effective] of pinMap) {
        if (producerPin === pin || effective === pin || effectiveMatches(pin, effective)) {
          chosen = { pid, effective }
          break
        }
      }
    }

    if (!chosen) {
      for (const [producerPin, effective] of selfPinMap) {
        if (producerPin === pin || effective === pin || effectiveMatches(pin, effective)) {
          chosen = { pid: element.id, effective }
          break
        }
      }
    }

    if (!chosen) continue
    if (chosen.effective === pin) continue
    overrides.push({ pin, override_key: chosen.effective })
  }
  return overrides
}
```

Only change vs current code: the second `if (!chosen)` block scanning `selfPinMap`. Everything else byte-identical.

- [ ] **Step 3: Sanity-check the file still parses**

Run: `node --check app/javascript/controllers/property_editor/element_io/override_computer.js`
Expected: no output (file parses cleanly).

- [ ] **Step 4: Commit**

```bash
git add app/javascript/controllers/property_editor/element_io/override_computer.js
git commit -m "feat(element_io/override_computer): self-output fallback for input producer"
```

---

## Task 2: Extend `_renderInputRow` with candidate-count branch and self options

**Files:**
- Modify: `app/javascript/controllers/property_editor/element_io_manager.js`

- [ ] **Step 1: Replace `_renderInputRow`**

In `app/javascript/controllers/property_editor/element_io_manager.js`, locate `_renderInputRow(element, pin, overrideList, reachability)` (currently around line 115). Replace the whole method with:

```js
  _renderInputRow(element, pin, overrideList, reachability) {
    const existing = overrideList.find((e) => e.pin === pin.pin)
    const selectedKey = existing ? existing.override_key : null

    const externals = this._externalCandidates(element, pin, reachability)
    const selfs = this._selfCandidates(element, pin)
    const candidates = externals.concat(selfs)

    if (candidates.length < 2) {
      return `
        <div class="flex items-center gap-2 my-1" data-element-io-input data-pin="${escapeHtml(pin.pin)}">
          <span class="font-mono text-sm">${escapeHtml(pin.pin)}</span>
        </div>
      `
    }

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
      <div class="flex items-center gap-2 my-1" data-element-io-input data-pin="${escapeHtml(pin.pin)}">
        <span class="font-mono text-sm">${escapeHtml(pin.pin)}</span>
        <select class="text-sm border border-gray-300 rounded px-2 py-1"
                data-element-io-producer-select>
          ${options.join("")}
        </select>
      </div>
    `
  }
```

- [ ] **Step 2: Add the two helpers below `_renderInputRow`**

Insert immediately after `_renderInputRow` and before `_renderOutputs`:

```js
  _externalCandidates(element, pin, reachability) {
    const canvas = this.controller.canvas
    const preds = reachability.predecessors(element.id)
    const out = []
    for (const pid of [...preds].reverse()) {
      const producer = canvas.elements.find((e) => e.id === pid)
      if (!producer) continue
      const pinMap = (canvas.getElementPins(pid).outputs || [])
      const overrideOuts = producer.properties?.io_overrides?.outputs || []
      for (const p of pinMap) {
        const renamed = overrideOuts.find((o) => o.pin === p.pin)?.renamed_to
        const effective = renamed || p.pin
        if (effective !== pin.pin && !effective.startsWith(`${pin.pin}_`)) continue
        out.push({ effective, label: producer.label || producer.type })
      }
    }
    return out
  }

  _selfCandidates(element, pin) {
    const canvas = this.controller.canvas
    const pinMap = (canvas.getElementPins(element.id).outputs || [])
    const overrideOuts = element.properties?.io_overrides?.outputs || []
    const out = []
    for (const p of pinMap) {
      const renamed = overrideOuts.find((o) => o.pin === p.pin)?.renamed_to
      const effective = renamed || p.pin
      if (effective !== pin.pin && !effective.startsWith(`${pin.pin}_`)) continue
      out.push({ effective, label: element.label || element.type })
    }
    return out
  }
```

Behavior notes:
- `_externalCandidates` preserves the existing `[...preds].reverse()` iteration so the farthest-first dropdown ordering stays identical.
- `_selfCandidates` uses the same `pin_<suffix>` matching rule as externals (`effective.startsWith(pin.pin + "_")` or exact match).
- Label: self options reuse `element.label || element.type` so the user sees the same name they saw in the canvas.

- [ ] **Step 3: Sanity-check the file still parses**

Run: `node --check app/javascript/controllers/property_editor/element_io_manager.js`
Expected: no output.

- [ ] **Step 4: Commit**

```bash
git add app/javascript/controllers/property_editor/element_io_manager.js
git commit -m "feat(element_io_manager): read-only inputs below 2 candidates, self outputs as producer"
```

---

## Task 3: Extend the (skipped) system spec with the new rules

**Files:**
- Modify: `spec/system/property_editor/element_io_tab_spec.rb`

- [ ] **Step 1: Append three new examples**

Open `spec/system/property_editor/element_io_tab_spec.rb`. Inside the existing `RSpec.describe "Element I/O tab"` block, after the two existing `it` examples, add:

```ruby
  it "renders an input row as plain text when it has fewer than 2 real producer candidates" do
    visit "/#{customer.id}/flowcharts/#{flowchart.id}/edit"

    # L1 has one input pin `items` with only `Start` upstream; `Start` does not
    # emit `items`, so there are 0 real candidates. Under the new rule the row
    # must render without a <select>.
    find("[data-element-id='l1']").click
    find("[data-tab='io']").click

    within "[data-element-io-inputs]" do
      row = find("[data-element-io-input][data-pin='items']")
      expect(row).to have_no_css("select")
    end
  end

  it "renders a <select> when 2+ real candidates exist (including self-output)" do
    visit "/#{customer.id}/flowcharts/#{flowchart.id}/edit"

    # L2 reads `item` and also writes `item` (self), AND L1 is a reachable
    # upstream producer of `item`. Two real candidates → dropdown renders
    # with a `(self)` option for L2's own output.
    find("[data-element-id='l2']").click
    find("[data-tab='io']").click

    within "[data-element-io-inputs]" do
      row = find("[data-element-io-input][data-pin='item']")
      expect(row).to have_css("select[data-element-io-producer-select]")
      expect(row).to have_content("(self)")
    end
  end

  it "keeps the Outputs section unchanged (still shows renamed badge)" do
    visit "/#{customer.id}/flowcharts/#{flowchart.id}/edit"

    find("[data-element-id='l2']").click
    find("[data-tab='io']").click

    within "[data-element-io-outputs]" do
      expect(page).to have_content("⚠ renamed")
    end
  end
```

These examples are intentionally inside the `skip "System specs need Capybara JS driver configuration"` guard at the top of the describe block, so they will be skipped by the current CI but exercised once a JS driver is configured.

- [ ] **Step 2: Run the file to verify it still loads (skipped, no errors)**

Run: `bundle exec rspec spec/system/property_editor/element_io_tab_spec.rb`
Expected: `5 examples, 0 failures, 5 pending` (or equivalent "skipped" wording for this Rspec version). No parse or load errors.

- [ ] **Step 3: Commit**

```bash
git add spec/system/property_editor/element_io_tab_spec.rb
git commit -m "test(element_io_tab): codify read-only rule and self-output dropdown option"
```

---

## Task 4: Manual verification in the browser

**Files:** none (verification only)

- [ ] **Step 1: Restart the Rails server if needed**

Run: `ls tmp/pids/server.pid` — if present, server is running. Otherwise: `bundle exec rails server -b 0.0.0.0 -p 3000` in a background process.

- [ ] **Step 2: Precompile assets so the JS changes take effect in the browser**

Run: `rm -f public/assets/.manifest.json && RAILS_ENV=development bundle exec rails assets:precompile`
Expected: finishes without errors.

- [ ] **Step 3: Verify "0 or 1 candidate → read-only" in the browser**

Open `/96546124/flowcharts/49/edit`. Pick an element whose input pin has fewer than 2 producer candidates (e.g., an early element where only the Start precedes it).

Click the element → open the **I/O** tab.

Expected: Input rows show only the pin name (monospace text). No `<select>` element, no "— no producer —" text.

- [ ] **Step 4: Verify "≥ 2 candidates → dropdown" including self**

Find (or create) an element that both reads and writes the same ctx key AND has an external predecessor that also emits that key. A process element with raw-union I/O is a likely fit. If needed, add two loop elements back-to-back, both using the same `itemVariable`.

Open the I/O tab for the downstream element.

Expected: The input row for that pin renders a `<select>` with:
1. `— no producer —` first,
2. at least one external option in the form `<label> • <effective>`,
3. at least one self option in the form `<label> • <effective> (self)`.

Selecting any option still persists to `element.properties.io_overrides.inputs` — confirm by saving and reloading, the selection sticks.

- [ ] **Step 5: Verify outputs are unchanged**

On an element whose output pin collides with another emitter, confirm the amber `⚠ renamed → <key>` badge still appears next to the output pin name.

- [ ] **Step 6: Run backend regression spec surface**

Run: `bundle exec rspec spec/services/code_generators/ spec/controllers/code_generators/`
Expected: 0 failures. This is a safety check — none of these specs touch the element I/O tab logic, but it verifies no accidental asset pipeline breakage.

- [ ] **Step 7: No commit for this task**

This task is verification only. Any tweaks surfaced during manual testing belong to a follow-up task; don't bundle fixes with verification.

---

## Verification Checklist

- [ ] `node --check app/javascript/controllers/property_editor/element_io/override_computer.js` passes.
- [ ] `node --check app/javascript/controllers/property_editor/element_io_manager.js` passes.
- [ ] `bundle exec rspec spec/system/property_editor/element_io_tab_spec.rb` reports 5 examples, 0 failures, all pending/skipped.
- [ ] `bundle exec rspec spec/services/code_generators/ spec/controllers/code_generators/` passes.
- [ ] Manual browser check: input with ≤1 real candidate renders plain text, no `<select>`.
- [ ] Manual browser check: input with ≥2 real candidates (including a self-output) renders `<select>` with the external option, the `(self)` option, and `— no producer —`.
- [ ] Manual browser check: outputs still show the `⚠ renamed → <key>` badge when collision-renamed.
- [ ] `element.properties.io_overrides` JSON shape unchanged — still `{inputs: [{pin, override_key}], outputs: [{pin, renamed_to}]}`.
