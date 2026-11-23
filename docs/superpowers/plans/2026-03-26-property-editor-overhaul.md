# Property Editor Overhaul Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Redesign the property editor sidebar with a color-coded header, pinned footer, section separators, and consistent field styling.

**Architecture:** ERB template restructure for header/footer, then JS changes in form_builder for separators and styling. Input styling consistency pass across property editor JS files.

**Tech Stack:** TailwindCSS, StimulusJS, ERB

**Spec:** `docs/superpowers/specs/2026-03-26-property-editor-overhaul-design.md`

---

## File Map

| File | Tasks | Purpose |
|------|-------|---------|
| `app/views/flowcharts/_editor.html.erb` | 1 | Header rewrite + footer pinning |
| `app/javascript/controllers/property_editor/form_builder.js` | 2, 3 | Title update, separators, input styling |
| `app/javascript/controllers/property_editor/templates.js` | 3 | Input styling (blue→indigo) |
| `app/javascript/controllers/property_editor/step_manager.js` | 3 | Input styling (blue→indigo) |
| `app/javascript/controllers/property_editor/branch_manager.js` | 3 | Input styling (blue→indigo, if applicable) |
| `app/javascript/controllers/property_editor/io_manager/input_operations.js` | 3 | Border/bg update (keep green focus) |
| `app/javascript/controllers/property_editor/io_manager/output_operations.js` | 3 | Border/bg update (keep purple focus) |

---

### Task 1: Header + footer restructure in ERB

Rewrite the property editor sidebar HTML for color-coded header and pinned footer.

### Task 2: Form builder — title, separators, input class

Update form_builder.js: _updateTitle() sets dot color, _buildFormFields() injects section separators, inputClass updated.

### Task 3: Input styling consistency across JS files

Update focus rings (blue→indigo) in templates.js, step_manager.js, branch_manager.js. Update border/bg in io_manager files.

### Task 4: Verify and precompile
