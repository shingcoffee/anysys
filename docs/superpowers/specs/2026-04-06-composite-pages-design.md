# Composite Pages / Inter-Module Events Design

**Date:** 2026-04-06
**Gap Reference:** Gap #4 from gap-analysis-anysys-vs-fw.md
**Status:** Draft

---

## Overview

Extend the Page model to support a `"layout": "composite"` mode where multiple modules (list + form) are rendered simultaneously on one page with inter-module event communication via Stimulus custom events. List modules provide server-side rendered data grids with sorting, pagination, and row actions via Turbo Frames. Module visibility can be conditional on events.

---

## 1. Composite Page Configuration

A Page with `"layout": "composite"` in its configuration. The `"modules"` array defines each module:

```json
{
  "layout": "composite",
  "modules": [
    {
      "id": "mod_1",
      "module_type": "list",
      "title": "Orders",
      "entity_id": 45,
      "width": "half",
      "config": {
        "columns": ["name", "status", "amount"],
        "sortable": true,
        "paginate": true,
        "pageSize": 25,
        "defaultSort": "created_at",
        "defaultDirection": "desc",
        "conditions": { "operator": "AND", "rules": [] },
        "row_actions": ["view", "edit", "delete"]
      },
      "visibility": null,
      "events": {
        "emit": ["row:selected"],
        "listen": []
      }
    },
    {
      "id": "mod_2",
      "module_type": "form",
      "title": "Order Details",
      "entity_id": 45,
      "width": "half",
      "config": {
        "fields": []
      },
      "visibility": { "on_event": "row:selected" },
      "events": {
        "emit": ["record:saved"],
        "listen": ["row:selected"]
      }
    }
  ],
  "metadata": { "entity_id": 45 }
}
```

### Module types

- `"form"` — existing page field rendering
- `"list"` — new table/data grid display

### Width options

`"full"`, `"half"`, `"third"`, `"two_thirds"` — maps to TailwindCSS grid columns.

---

## 2. List Module — Server-Side Rendering

New `CompositeModules::ListComponent` ViewComponent:
- Takes entity, columns config, and pagination params
- Queries data via QueryBuilder (with calculated fields auto-injected)
- Renders a table with TailwindCSS styling
- Sorting via Turbo Frame requests (column header links)
- Pagination via Turbo Frame (page links)
- Row click dispatches custom event with record ID

---

## 3. Inter-Module Events

Stimulus `composite-page` controller on the wrapper div:
- Child modules dispatch events: `this.dispatch("row-selected", { detail: { recordId: 123, moduleId: "mod_1" } })`
- Other modules listen: `data-action="composite-page:row-selected->form-module#loadRecord"`
- Events defined in module config, wired up at render time

---

## 4. Module Visibility

A module with `"visibility": { "on_event": "row:selected" }` starts hidden and becomes visible when the event fires. Implemented via Stimulus toggling `hidden` class.

---

## 5. File Changes

### New files

| File | Purpose |
|---|---|
| `app/components/composite_modules/list_component.rb` | List/table ViewComponent with sorting, pagination |
| `app/components/composite_modules/list_component.html.erb` | List template |
| `app/components/composite_modules/module_wrapper_component.rb` | Wrapper with width, visibility, event wiring |
| `app/components/composite_modules/module_wrapper_component.html.erb` | Wrapper template |
| `app/javascript/controllers/composite_page_controller.js` | Event dispatch/listen, visibility toggling |
| `app/javascript/controllers/list_module_controller.js` | Sort, paginate, row selection |
| `app/services/composite_page_renderer.rb` | Orchestrates rendering of composite page modules |
| `spec/services/composite_page_renderer_spec.rb` | Unit tests |
| `spec/components/composite_modules/list_component_spec.rb` | Component tests |
| `spec/integration/composite_page_integration_spec.rb` | End-to-end test |

### Modified files

| File | Change |
|---|---|
| `app/services/page_content_generator.rb` | Detect `layout: "composite"` and delegate to CompositePageRenderer |
| `app/controllers/pages_controller.rb` | Add `module_data` action for Turbo Frame list requests |
| `config/routes.rb` | Add `module_data` route |

### No database migration needed

---

## 6. Testing Strategy

- **CompositePageRenderer specs:** Renders composite layout with list + form modules. Handles missing entities gracefully. Generates correct grid layout.
- **ListComponent specs:** Renders table with columns from entity schema. Handles empty data. Generates sort links and pagination.
- **ModuleWrapperComponent specs:** Applies correct width classes. Handles visibility config. Wires event data attributes.
- **Integration specs:** Full composite page with list module querying real data, verifying HTML output contains table with correct records.
