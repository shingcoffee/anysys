# Phase 6: Premium Features Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add keyboard shortcuts for element creation, new element types (error handler, timer), annotations, property presets, advanced branch conditions, and documentation generation.

**Tech Stack:** StimulusJS, vanilla SVG, TailwindCSS, Rails, RSpec.

**Spec Reference:** Items #12, #23, #24, #25, #26, #27, #37

**Deferred:** #11 (grouping), #13 (multi-page), #36 (collaboration), #38 (BPMN import)

---

## Task 1: Keyboard Shortcuts for Adding Elements (#12)

When no element is selected and canvas is focused, press hotkey to create element at viewport center:
- S = Start, E = End, P = Process, D = Decision, L = Loop, F = Fork, J = Join

In `canvas.js` `_handleKeyDown`, add single-key handlers (only when no modifier and no selection):

```javascript
if (!isMod && this.selectedElements.length === 0 && !this.isResizing && !this.isDragging) {
  const keyMap = { s: "start", e: "end", p: "process", d: "decision", l: "loop", f: "fork", j: "join" }
  const type = keyMap[e.key.toLowerCase()]
  if (type) {
    e.preventDefault()
    const center = this.zoomPanManager.clientToSVG(
      this.svg.getBoundingClientRect().width / 2 + this.svg.getBoundingClientRect().left,
      this.svg.getBoundingClientRect().height / 2 + this.svg.getBoundingClientRect().top
    )
    this.addElement({ type, x: center.x, y: center.y })
    return
  }
}
```

**Files:** Modify `canvas.js` only.

---

## Task 2: Error/Catch Element Type (#23)

New element type: **error_handler** — attaches to Process elements to catch failures.
- Shape: Rounded rectangle with lightning bolt icon
- Color: Orange theme (fill: #fff7ed, stroke: #ea580c)
- Properties: error types to catch (text array), fallback action (select)
- ActivityGenerator: generates rescue block wrapping the connected process

**Files:**
- Create: `app/components/flowchart_elements/error_handler_element_component.rb`
- Modify: `constants/elements.js`, `constants/schemas.js`, `element_renderer.js`
- Modify: `_editor.html.erb` (palette), `base_element_component.rb` (icon)
- Modify: `validation_service.js`, `activity_generator.rb`

---

## Task 3: Delay/Timer Element Type (#24)

New element type: **timer** — pauses execution.
- Shape: Rounded rectangle with clock icon
- Color: Slate theme (fill: #f8fafc, stroke: #64748b)
- Properties: delayType (fixed/until_condition), duration (number+unit), condition
- ActivityGenerator: generates sleep or polling code

**Files:** Same pattern as error_handler — create component, add constants/schema/renderer, palette, generator.

---

## Task 4: Annotations/Comments on Elements (#25)

Add a `comments` array to element properties. Visual indicator (small dot) on elements that have comments. Click comment icon to open comment panel.

**Files:**
- Modify: `element_renderer.js` — render comment indicator dot
- Modify: `property_editor_controller.js` — comments section in property editor
- Modify: `schemas.js` — add comments field to common properties

---

## Task 5: Property Templates/Presets (#26)

"Apply Template" button in Process property editor. Presets pre-fill steps array:
- CRUD Create: new_model → build_contract → validate → save_model
- CRUD Read: find_model
- CRUD Delete: find_model → destroy_model

**Files:**
- Modify: `step_manager.js` — add presets dropdown
- Modify: `templates.js` — preset definitions and UI

---

## Task 6: Advanced Branch Condition Types (#27)

Add to BRANCH_OPERATORS: `matches_regex`, `in_range`, `is_type`, `is_nil`.
Update ActivityGenerator to compile these to Ruby.

**Files:**
- Modify: `constants/schemas.js` — add operators
- Modify: `activity_generator.rb` — handle new operators

---

## Task 7: Documentation Generation (#37)

"Generate Docs" button produces a Markdown document describing the flow.

**Files:**
- Create: `app/services/flowchart_documenter.rb`
- Modify: `flowcharts_controller.rb` — docs action
- Modify: `config/routes.rb` — docs route
- Modify: `_editor.html.erb` — button in toolbar
