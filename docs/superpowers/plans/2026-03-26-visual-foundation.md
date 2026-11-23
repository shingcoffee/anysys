# Visual Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Migrate the flowchart editor from ad-hoc gray Tailwind classes to a deliberate slate-based design system with consistent surfaces, typography, and depth.

**Architecture:** Two-phase approach: (1) mechanical gray→slate replacement across all files using replace_all, then (2) targeted changes for surface hierarchy, typography, and depth that go beyond simple color swap. Phase 1 is safe because `gray-` only appears in Tailwind CSS class strings across all affected files.

**Tech Stack:** TailwindCSS (slate palette), ERB templates, StimulusJS

**Spec:** `docs/superpowers/specs/2026-03-26-visual-foundation-design.md`

---

## File Map

| File | Task | Occurrences |
|------|------|-------------|
| `app/views/flowcharts/_editor.html.erb` | 1, 3 | ~106 gray refs + targeted changes |
| `app/components/flowchart_elements/base_element_component.rb` | 1 | ~3 gray refs |
| `app/javascript/controllers/flowchart_canvas_controller.js` | 1, 3 | ~15 gray refs + shadow changes |
| `app/javascript/controllers/property_editor/templates.js` | 2 | ~85 gray refs |
| `app/javascript/controllers/property_editor/step_manager.js` | 2 | ~10 gray refs |
| `app/javascript/controllers/property_editor/branch_manager.js` | 2 | ~13 gray refs |
| `app/javascript/controllers/property_editor/form_builder.js` | 2 | ~3 gray refs |
| `app/javascript/controllers/property_editor/io_manager/output_operations.js` | 2 | ~31 gray refs |
| `app/javascript/controllers/property_editor/io_manager/input_operations.js` | 2 | ~4 gray refs |

---

### Task 1: gray→slate migration — template + component + canvas controller

Mechanical replacement of all `gray-` with `slate-` in the three most visible files.

**Files:**
- Modify: `app/views/flowcharts/_editor.html.erb`
- Modify: `app/components/flowchart_elements/base_element_component.rb`
- Modify: `app/javascript/controllers/flowchart_canvas_controller.js`

- [ ] **Step 1: Replace gray→slate in _editor.html.erb**

Use Edit with `replace_all=true`, `old_string="gray-"`, `new_string="slate-"`.

- [ ] **Step 2: Replace gray→slate in base_element_component.rb**

Use Edit with `replace_all=true`, `old_string="gray-"`, `new_string="slate-"`.

This changes `base_classes` from:
```ruby
"flowchart-element bg-white border border-gray-200 rounded px-2 py-1.5 text-sm font-medium text-gray-700 cursor-pointer hover:border-blue-400 hover:shadow-sm transition-all duration-200 select-none"
```
To:
```ruby
"flowchart-element bg-white border border-slate-200 rounded px-2 py-1.5 text-sm font-medium text-slate-700 cursor-pointer hover:border-blue-400 hover:shadow-sm transition-all duration-200 select-none"
```

- [ ] **Step 3: Replace gray→slate in flowchart_canvas_controller.js**

Use Edit with `replace_all=true`, `old_string="gray-"`, `new_string="slate-"`.

- [ ] **Step 4: Verify no remaining gray references**

Run: `grep -c "gray-" app/views/flowcharts/_editor.html.erb app/components/flowchart_elements/base_element_component.rb app/javascript/controllers/flowchart_canvas_controller.js`

Expected: 0 for all files.

---

### Task 2: gray→slate migration — property editor JS files

Same mechanical replacement across all property editor files that contain gray references.

**Files:**
- Modify: `app/javascript/controllers/property_editor/templates.js`
- Modify: `app/javascript/controllers/property_editor/step_manager.js`
- Modify: `app/javascript/controllers/property_editor/branch_manager.js`
- Modify: `app/javascript/controllers/property_editor/form_builder.js`
- Modify: `app/javascript/controllers/property_editor/io_manager/output_operations.js`
- Modify: `app/javascript/controllers/property_editor/io_manager/input_operations.js`

- [ ] **Step 1: Replace gray→slate in all 6 files**

For each file, use Edit with `replace_all=true`, `old_string="gray-"`, `new_string="slate-"`.

Files:
1. `app/javascript/controllers/property_editor/templates.js`
2. `app/javascript/controllers/property_editor/step_manager.js`
3. `app/javascript/controllers/property_editor/branch_manager.js`
4. `app/javascript/controllers/property_editor/form_builder.js`
5. `app/javascript/controllers/property_editor/io_manager/output_operations.js`
6. `app/javascript/controllers/property_editor/io_manager/input_operations.js`

- [ ] **Step 2: Verify no remaining gray references**

Run: `grep -rn "gray-" app/javascript/controllers/property_editor/ --include="*.js" | wc -l`

Expected: 0

---

### Task 3: Targeted changes — surface hierarchy, typography, depth

Apply the specific changes that go beyond the gray→slate swap.

**Files:**
- Modify: `app/views/flowcharts/_editor.html.erb`
- Modify: `app/javascript/controllers/flowchart_canvas_controller.js`

- [ ] **Step 1: Canvas background — darken from slate-50 to slate-100**

In `app/views/flowcharts/_editor.html.erb`, find the canvas container div (has `data-flowchart-canvas-target="canvasContainer"`). Change `bg-slate-50` to `bg-slate-100`:

Find: `class="flex-1 min-w-0 bg-slate-50 overflow-hidden relative"`
Replace: `class="flex-1 min-w-0 bg-slate-100 overflow-hidden relative"`

- [ ] **Step 2: Left sidebar — change from slate-50 to white**

In `_editor.html.erb`, find the left sidebar div. Change `bg-slate-50` to `bg-white`:

Find: `class="w-[140px] bg-slate-50 border-r border-slate-200 flex flex-col flex-shrink-0 overflow-hidden"`
Replace: `class="w-[140px] bg-white border-r border-slate-200 flex flex-col flex-shrink-0 overflow-hidden"`

- [ ] **Step 3: Property editor title — downsize from text-lg to text-sm font-semibold**

In `_editor.html.erb`, find the property editor title h3:

Find: `class="text-lg font-medium text-slate-900"`
Replace: `class="text-sm font-semibold text-slate-900"`

- [ ] **Step 4: Bottom panel — add shadow-sm for depth**

In `_editor.html.erb`, find the bottom panel container:

Find: `class="absolute bottom-0 left-0 right-0 bg-white border-t border-slate-200 shadow-lg z-20 hidden"`
Replace: `class="absolute bottom-0 left-0 right-0 bg-white border-t border-slate-200 shadow-sm z-20 hidden"`

Note: Change `shadow-lg` to `shadow-sm` — the bottom panel is Level 1 chrome, not a floating overlay.

- [ ] **Step 5: Overlay consistency — standardize ring classes**

In `_editor.html.erb`, update floating overlays to use consistent `ring-1 ring-slate-200`:

Find the overflow menu: `ring-1 ring-black/5` → `ring-1 ring-slate-200`
Find the context menu: check its classes and ensure `ring-1 ring-slate-200`
Find the shortcut panel: add `ring-1 ring-slate-200` if missing
Find the search bar: add `ring-1 ring-slate-200` if missing

- [ ] **Step 6: Canvas controller — update context menu ring class in dynamic HTML**

In `flowchart_canvas_controller.js`, if the context menu HTML generation uses `ring-black/5`, replace with `ring-slate-200`.

- [ ] **Step 7: Verify and precompile**

Run: `bundle exec rails assets:precompile`

Confirm no errors.

---

### Task 4: Final verification

- [ ] **Step 1: Verify zero gray references remain in editor files**

```bash
grep -rn "gray-" app/views/flowcharts/_editor.html.erb app/components/flowchart_elements/base_element_component.rb app/javascript/controllers/flowchart_canvas_controller.js app/javascript/controllers/property_editor/ --include="*.js" --include="*.rb" --include="*.erb"
```

Expected: No output (zero matches).

- [ ] **Step 2: Precompile and restart server**

```bash
bundle exec rails assets:precompile
```

- [ ] **Step 3: Manual verification**

Open `/96546124/flowcharts/48/edit` and confirm:
1. Canvas background is slightly darker (slate-100) than sidebar panels
2. Left sidebar is white (matches toolbar and right sidebar)
3. All text uses slate tones (cooler blue-gray, not warm gray)
4. Bottom panel has subtle shadow
5. Overflow menu and context menu have consistent ring borders
6. Property editor title is smaller (`text-sm font-semibold`)
7. Open property editor, verify form fields all use slate colors
8. No visual inconsistencies between static HTML and dynamic JS-rendered content
