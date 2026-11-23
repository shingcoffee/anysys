# Phase 5: Power User Features Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add minimap navigation, auto-layout, connection routing options, version history, and bulk element viewing for power users.

**Architecture:** Canvas uses viewBox-based zoom/pan via ZoomPanManager. Connections rendered by ConnectionManagerMixin with path calculation. Configuration stored as JSON in flowcharts.configuration column. No version table exists yet — requires migration.

**Tech Stack:** StimulusJS, vanilla SVG, TailwindCSS, Rails, RSpec.

**Spec Reference:** Items #6, #7, #9, #33, #35

---

## Task 1: Minimap (#6)

**Files:**
- Create: `app/javascript/flowchart/minimap_manager.js`
- Modify: `app/views/flowcharts/_editor.html.erb` — minimap container
- Modify: `app/javascript/controllers/flowchart_canvas_controller.js` — initialize and update minimap

A small overview panel in the bottom-right showing all elements as dots with a viewport rectangle.

- [ ] **Step 1: Create MinimapManager**

Create `app/javascript/flowchart/minimap_manager.js` — renders a scaled-down representation of the canvas in a small container. Shows colored dots for elements and a blue rectangle for the current viewport. Click/drag on minimap to navigate.

Key methods: `render()`, `updateViewport()`, `_handleClick(e)`, `_handleDrag(e)`.

- [ ] **Step 2: Add minimap container to editor**

In `_editor.html.erb`, add a 200x150 container in the bottom-right of the canvas area with a toggle button.

- [ ] **Step 3: Wire minimap updates**

In canvas controller, initialize MinimapManager. Update minimap on: element add/move/delete, zoom/pan changes, connection changes.

- [ ] **Step 4: Verify and commit**

---

## Task 2: Auto-Layout (#7)

**Files:**
- Create: `app/javascript/flowchart/layout_manager.js`
- Modify: `app/views/flowcharts/_editor.html.erb` — auto-layout button
- Modify: `app/javascript/controllers/flowchart_canvas_controller.js` — wire layout
- Modify: `app/javascript/controllers/toolbar_controller.js` — layout action

Simple hierarchical top-to-bottom layout without external libraries. Uses BFS from start element to assign layers, then centers elements within each layer.

- [ ] **Step 1: Create LayoutManager**

Implements a basic Sugiyama-style layered layout:
1. BFS from start to assign layer numbers
2. Sort elements within each layer (minimize edge crossings heuristic)
3. Position elements: centered horizontally per layer, spaced vertically

- [ ] **Step 2: Add toolbar button and wire**

- [ ] **Step 3: Verify and commit**

---

## Task 3: Connection Routing Options (#9)

**Files:**
- Modify: `app/javascript/flowchart/connection_manager.js` — add routing modes
- Modify: `app/javascript/flowchart/canvas.js` — store routing preference in metadata
- Modify: `app/views/flowcharts/_editor.html.erb` — routing toggle in toolbar
- Modify: `app/javascript/controllers/toolbar_controller.js` — routing toggle action

Three modes: Bezier (current default for vertical), Orthogonal (right-angle), Straight (direct line).

- [ ] **Step 1: Add routing mode to canvas**

Store `this.connectionRouting` on canvas (default "bezier"). Save/load from metadata.

- [ ] **Step 2: Update path calculation**

In `_calculatePath()`, branch based on routing mode:
- bezier: current behavior
- straight: always 2-point direct line
- orthogonal: always use right-angle segments

- [ ] **Step 3: Add routing toggle UI and wire**

- [ ] **Step 4: Verify and commit**

---

## Task 4: Version History (#33)

**Files:**
- Create: `db/migrate/TIMESTAMP_create_flowchart_versions.rb`
- Create: `app/models/flowchart_version.rb`
- Modify: `app/models/flowchart.rb` — has_many :flowchart_versions, version creation on save
- Modify: `app/controllers/flowcharts_controller.rb` — versions action, restore action
- Create: `app/views/flowcharts/_version_panel.html.erb` — version list UI
- Modify: `app/views/flowcharts/_editor.html.erb` — history button
- Modify: `app/javascript/controllers/flowchart_canvas_controller.js` — version panel
- Create: `spec/models/flowchart_version_spec.rb`

- [ ] **Step 1: Create migration and model**

- [ ] **Step 2: Create version on save**

- [ ] **Step 3: Add version list UI and restore**

- [ ] **Step 4: Write specs and verify**

---

## Task 5: Bulk Element View / Elements Panel (#35)

**Files:**
- Modify: `app/views/flowcharts/_editor.html.erb` — elements panel
- Modify: `app/javascript/controllers/flowchart_canvas_controller.js` — elements panel logic

A bottom panel listing all elements in table form with type icon, label, connection count, and validation status. Click to select and zoom to element.

- [ ] **Step 1: Add elements panel UI**

- [ ] **Step 2: Wire panel with canvas data**

- [ ] **Step 3: Verify and commit**
