# Decision Multi-Branch (Case/When) + Merge Element Design

**Date:** 2026-04-10
**Approach:** Dynamic Output Ports on Decision + Merge Element

## Overview

Redesign the Decision element to support case/when-style multi-branching with dynamic output ports on the canvas, and introduce a new Merge element for selective branch convergence. The backend infrastructure (topology analyzer, code generator) already supports 3+ branches — this design focuses on the UI/canvas layer and the new Merge element across the full stack.

## 1. Decision Element — Dynamic Output Ports

### Canvas Rendering

- The **top handle** is always the input (incoming connection).
- Output ports are dynamically created based on configured branches, distributed along the **lower half** of the diamond perimeter (left vertex → bottom vertex → right vertex).
- Port placement algorithm: divide the lower-half perimeter arc into `N+1` segments, place ports at segment boundaries (evenly spaced).
- Each output port is rendered as a green circle labeled with the branch name (font-size ~9px, offset outward from diamond edge).
- The **default/else** port is rendered in amber.
- Port placement by branch count:
  - 2 branches: bottom-left, bottom-right
  - 3 branches: bottom-left, bottom, bottom-right
  - 4 branches: bottom-left, bottom, bottom-right, right
  - 5+: evenly distributed along bottom-left → right → top-right edges

### Property Editor — Case/When Branch List

- **Element Name** field (text input).
- **Switch On** field (optional) — the common operand expression, e.g. `ctx[:order_status]`.
- **Branches** list — each branch displays:
  - Branch name (e.g. "Active")
  - Condition preview as inline code (e.g. `== "active"`)
  - Edit and delete controls
  - Drag handle for reordering
- **"+ Add Branch"** button opens a modal with:
  - Branch name (free text, not a yes/no dropdown)
  - Condition configuration (field condition or query_count condition — existing condition types)
  - Description (optional)
- The last branch without a condition automatically becomes the **default (else)** branch, displayed with amber styling.
- Branch names must be unique within the same Decision.

### Code Generation (unchanged pattern)

Decision steps generate `if/elsif/else` chains setting `ctx[:_route_N]`:

```ruby
def check_order_status(ctx, **)
  status = ctx[:order_status]

  if status == "active"
    ctx[:_route_0] = :branch_0
  elsif status == "pending"
    ctx[:_route_0] = :branch_1
  elsif status == "rejected"
    ctx[:_route_0] = :branch_2
  else
    ctx[:_route_0] = :branch_3
  end
  true
end
```

## 2. Merge Element — Selective Branch Convergence

### Purpose

A pure flow-control element with no business logic. It marks where selected branches from a Decision converge back to a single track.

### Canvas Rendering

- **Shape:** Rounded rectangle bar (wider than tall, ~140x36).
- **Color:** Purple theme — `#ede9fe` fill, `#8b5cf6` stroke.
- **Dynamic input ports** along the top edge — one per merged branch, labeled with branch name.
- **Single output port** at bottom center — continues as a single track.
- Displays subtitle text inside the bar showing merged branch names, e.g. "(Active + Pending)".

### Property Editor

- **Element Name** field.
- **Source Decision** — auto-detected from incoming connections. Displayed as a read-only reference with the Decision's name.
- **Branches to Merge** — checkbox list of all branches from the source Decision. User checks which branches converge at this Merge. Unchecked branches continue independently.

### Data Structure

```json
{
  "id": "el_merge_a1b2",
  "type": "merge",
  "x": 300, "y": 400,
  "width": 140, "height": 36,
  "properties": {
    "name": "Merge Active & Pending",
    "sourceDecisionId": "el_decision_x1y2",
    "mergedBranches": ["branch_0", "branch_1"]
  }
}
```

### Multiple Merges per Decision

Fully supported. Each Merge element selects its own subset of branches. Example:

- Decision has 4 branches: Active, Pending, Rejected, Default
- Merge A joins Active + Pending → downstream Process X
- Merge B joins Rejected + Default → downstream Process Y
- Optional Merge C joins outputs of Merge A + Merge B (nested merge)

### Nested Merge (Merge of Merges)

When Merge C receives incoming connections from Merge A and Merge B (not directly from a Decision), `sourceDecisionId` traces back to the original Decision through the upstream Merges. The `mergedBranches` is the union of all upstream merged branches. The topology analyzer resolves this by following the merge chain: Merge C's `mergedBranches` = Merge A's `[:branch_0, :branch_1]` + Merge B's `[:branch_2, :branch_3]` = `[:branch_0, :branch_1, :branch_2, :branch_3]`. If the union covers all branches, the guard optimization kicks in and the guard is omitted entirely.

### Validation Rules

- Must have `sourceDecisionId` set (auto-detected from incoming connections).
- `mergedBranches` must contain at least 2 branches.
- All listed branches must exist on the source Decision.
- A branch cannot appear in two different Merge elements for the same Decision.
- Must have at least one incoming connection and one outgoing connection.

## 3. Canvas Infrastructure — Dynamic Ports & Connection Routing

### Element Renderer Changes (`element_renderer.js`)

- `_getHandlePositions(element)` becomes port-aware: for **decision** and **merge** elements, reads branch configuration to compute dynamic port positions.
- Other element types (process, start, end, subflow) retain the standard 4 fixed handles — no changes.
- Each dynamic port stores: `{ position: "port_0", x, y, branchKey: "branch_0", label: "Active" }`.
- Port labels rendered as small text next to each port, offset outward from the shape edge.

### Connection Manager Changes (`connection_manager.js`)

- New fields on connection objects: `fromPort` and `toPort` for dynamic port elements.
- Standard elements continue using `fromPosition`/`toPosition` — backward compatible within the connection system.
- When dragging from a Decision's output port, connection stores `fromPort: "port_0"`.
- When dragging to a Merge's input port, stores `toPort: "port_0"`.
- Orthogonal routing reads port coordinates when `fromPort`/`toPort` is present.

Updated connection data structure:

```json
{
  "id": "conn_abc123",
  "from": "el_decision_x1y2",
  "to": "el_process_a1b2",
  "fromPort": "port_0",
  "fromPosition": "bottom",
  "toPort": null,
  "toPosition": "top",
  "label": "Active",
  "properties": { "description": "", "priority": 0 }
}
```

### Port Sync — When Branches Change

When branches are added/removed/reordered in the property editor:

1. Recalculate port positions — redistribute ports along the diamond perimeter.
2. Update existing connections — remap `fromPort` values to match new port indices. If a branch is removed, its connection is deleted.
3. Re-render the element with updated ports and labels.
4. Update downstream Merge elements — if a merged branch is removed, remove it from `mergedBranches` and remove the corresponding input port.

All sync operations go through the undo/redo manager for full reversibility.

## 4. Topology Analyzer Changes (`flowchart_topology_analyzer.rb`)

### New `merge_groups` Structure

```ruby
Result = Struct.new(
  :branch_groups,
  :merge_groups,
  :node_guards,
  :decision_indices,
  keyword_init: true
)

# merge_groups:
{
  "el_merge_a1b2" => {
    source_decision_id: "el_decision_x1y2",
    merged_branches: [:branch_0, :branch_1],
    route_index: 0
  }
}
```

### Guard Assignment

- **Before merge:** nodes guarded by single branch — `ctx[:_route_0] == :branch_0`
- **The merge element itself:** guarded by compound — `[:branch_0, :branch_1].include?(ctx[:_route_0])`
- **After merge:** all downstream nodes inherit the merge's compound guard

### Convergence Detection

- Explicit Merge elements are recognized as convergence points — BFS stops at them.
- Unmerged branches that later converge implicitly still use the existing BFS intersection logic.

## 5. Activity Generator Changes (`activity_generator.rb`)

### Merge Element Handler

Generates a no-op method:

```ruby
def merge_active_and_pending(ctx, **)
  true
end
```

### Compound Guard Generation

When `node_guards` contains an array of branches (from merge), emit:

```ruby
return true unless [:branch_0, :branch_1].include?(ctx[:_route_0])
```

### Guard Optimization

If all branches of a decision are included in the compound guard, omit the guard entirely — the step runs unconditionally.

### Step Ordering

Topological sort places merge elements after all their upstream branch steps and before downstream steps.

## 6. Element Palette & ViewComponent

### Sidebar

Merge appears in the "Basic Elements" section alongside Start, Process, Decision, and End. Purple theme, horizontal bar icon.

### MergeElementComponent

- File: `app/components/flowchart_elements/merge_element_component.rb`
- Extends `BaseElementComponent` (same pattern as `DecisionElementComponent`)
- Shape: rounded rectangle bar
- Colors: `#ede9fe` fill, `#8b5cf6` stroke
- Label: "Merge"

## 7. Decision Element Validation

- Must have at least 2 branches configured.
- Each branch (except default) must have a condition.
- Branch names must be unique within the same Decision.
- Each configured branch must have at least one outgoing connection.

## 8. Test Coverage

### ViewComponent Specs

- `MergeElementComponent` renders with correct shape, colors, label.
- `DecisionElementComponent` updated rendering if changed.

### FlowchartTopologyAnalyzer Specs

- 2-branch decision with no merge — existing behavior preserved.
- 3-branch decision — correct `branch_groups` with `branch_0`/`branch_1`/`branch_2`.
- 4-branch decision with 1 selective merge (2 of 4) — correct `merge_groups`, correct guards.
- 4-branch decision with 2 merges — each merge has correct branch subset.
- Nested merge (merge of merges) — compound guard is union of all branches.
- All-branches-merged optimization — guard omitted.
- Validation: branch appearing in two merges raises error.

### ActivityGenerator Specs

- Decision with 3+ branches generates correct `if/elsif/else` chain.
- Merge element generates no-op method.
- Post-merge step generates compound guard with `.include?`.
- All-branches-merged generates no guard.
- Multiple merges for same decision — each downstream track has correct guard.

### JavaScript Specs

- Dynamic port calculation: 2, 3, 4, 5 branches produce correct positions on diamond.
- Port sync: add branch → port appears; remove branch → connection cleaned up.
- Merge property editor: auto-detects source decision, checkbox selection works.
- Connection creation: drag from dynamic port stores `fromPort` correctly.
