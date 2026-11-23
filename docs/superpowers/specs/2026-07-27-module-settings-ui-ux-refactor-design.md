# Module Settings UI/UX Refactor Design Spec

## Overview
Refactor the Platform Owner Module Settings page (`/:customer_id/admin/maintenance/platform/module_settings/:id`) to improve layout, readability, and interactivity. Key improvements include relocating toggle status labels to title headers, replacing the 'Data Type' column with descriptive attribute labels, converting Template Token toggles to AJAX checkboxes, and folding model attribute lists by default.

---

## Requirements & Scope

### 1. Module Controls Card Layout
- **No toggle-adjacent labels**: The text label next to the toggle button on the right is omitted (`show_label: false`).
- **Title-level status badges**: The active/inactive, required/optional, or enabled/disabled status is rendered as a status badge right next to the section title inside the `<h3>` header.

### 2. Technical Reference Tab — Model Attributes & Template Tokens
- **Attribute Descriptive Labels**: Replace the `Data Type` column with `Attribute Label` (`attribute_label`). Obtain the label dynamically via `klass.human_attribute_name(col.name)`.
- **AJAX Checkboxes for Template Tokens**: Replace the `ModuleToggleComponent` with an HTML checkbox backed by a Stimulus controller (`template_token_checkbox_controller.js`). Checking/unchecking triggers an asynchronous PATCH request to update the database record, displaying an inline status indicator upon success/failure without a page refresh.
- **Folded Model Attribute Lists**: Fold (collapse) each model's attribute list by default using a `<details>` / `<summary>` collapsible card structure.

---

## Architectural & Technical Design

### A. ViewComponent Update
- `Admin::Maintenance::Platform::ModuleToggleComponent`:
  - Add `show_label: true` parameter (defaults to `true`).
  - Render the label span `<span class="text-body-sm text-text-primary"><%= label %></span>` only if `show_label?` is true.

### B. Service Layer Update
- `ModuleModelDiscovery` (`app/services/module_model_discovery.rb`):
  - In `extract_columns(klass)`, include `label: klass.human_attribute_name(col.name)`.

### C. View & Template Updates
- `app/views/admin/maintenance/platform/module_settings/show.html.erb`:
  - Pass `show_label: false` to `ModuleToggleComponent` instances in Module Controls.
  - Add status `BadgeComponent` tags directly inside the `<h3>` headers for `Module Status`, `Required Module`, and `Handoff Target`.
  - In the `Model Attributes & Template Tokens` card:
    - Wrap each model block in a `<details class="group rounded-lg border border-border-subtle bg-surface mb-3 overflow-hidden">`.
    - Render a `<summary>` with model name, table name badge, attribute count, and fold chevron icon.
    - Replace `Data Type` column header with `Attribute Label` (`maint_platform.module_settings.show.tokens.attribute_label`).
    - Render `col[:label]` in place of `col[:type]`.
    - Replace `ModuleToggleComponent` in the tokens table with a Stimulus-driven checkbox.

### D. Stimulus Controller
- `app/javascript/controllers/template_token_checkbox_controller.js`:
  - Controller attached to the token checkbox.
  - Sends asynchronous `fetch` PATCH request with `token_model`, `token_attribute`, `token_enabled` (1/0), and `authenticity_token`.
  - Updates inline UI state (loading spinner / success indicator / error toast).

### E. Controller & Routing Layer
- `Admin::Maintenance::Platform::ModuleSettingsController` (`app/controllers/admin/maintenance/platform/module_settings_controller.rb`):
  - In `#update`, respond with JSON `{ success: true, enabled: ... }` when format is JSON or request is XHR/Fetch.

### F. I18n Locales
- Add `maint_platform.module_settings.show.tokens.attribute_label` in both `config/locales/maint_platform.en.yml` and `config/locales/maint_platform.zh-CN.yml`.

---

## Verification & Testing Strategy
- **RSpec**: Request specs for `Admin::Maintenance::Platform::ModuleSettingsController` testing both HTML and JSON/AJAX PATCH updates for token toggling.
- **Vitest**: Unit tests for `template_token_checkbox_controller.js` ensuring 100% JS line/branch coverage.
- **Manual Verification**: Smoke-test module settings page under customer `81721200` to verify toggle placement, folded model cards, attribute labels, and AJAX checkbox operations.
