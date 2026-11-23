# Subflow Configuration Refactor Design

## Overview

Refactor the flowchart configuration structure to keep subflows as compact references rather than expanding them inline during save. The activity generators will look up referenced flowcharts at generation time.

## Goals

1. Save subflow elements as compact references with `flowchartId`
2. Never expand subflows into inline elements when saving
3. Generators detect subflow elements and look up referenced flowcharts
4. Runtime expansion (for UI visualization) remains unchanged

## Configuration Structure

Subflow elements are stored as compact references:

```json
{
  "elements": [
    { "id": "start_1", "type": "start", ... },
    {
      "id": "process_1",
      "type": "process",
      "label": "Invoke: Validate User",
      "properties": {
        "steps": [{ "action": "invoke_activity" }]
      }
    },
    {
      "id": "subflow_1",
      "type": "subflow",
      "label": "Sub-flow: Validate User",
      "properties": {
        "flowchartId": 123,
        "inputs": [{ "value": "ctx" }],
        "outputs": [{ "value": "signal" }, { "value": "ctx" }]
      }
    },
    { "id": "end_1", "type": "end", ... }
  ],
  "connections": [
    { "from": "start_1", "to": "process_1" },
    { "from": "process_1", "to": "subflow_1" },
    { "from": "subflow_1", "to": "end_1" }
  ]
}
```

## Save Process

- Save configuration as-is without expanding subflows
- Filter out runtime-only `_expandedFromSubflow` elements
- Keep original subflow elements with `flowchartId` reference

## Generator Logic

During DFS traversal:
1. Detect `type: "subflow"` elements
2. Look up referenced flowchart by `flowchartId`
3. Generate `step Subprocess(SubflowActivity)` declaration
4. Continue traversal to next connected element

## Files to Modify

1. `app/javascript/controllers/flowchart_canvas_controller.js` - Remove expand-before-save
2. `app/javascript/flowchart/canvas.js` - Filter expanded elements in getConfiguration()
3. `app/services/activity_generator.rb` - Handle subflow elements directly
4. `spec/services/activity_generator_spec.rb` - Update tests

## Runtime Behavior

- Users can still double-click to expand/collapse subflows for visualization
- Expansion state is UI-only, not persisted
- Load restores subflows in collapsed form
