# Email Template Creation Live Preview & Variable Autocomplete Design

## 1. Overview & Goals
Enhance the Email Template workspace with two key capabilities:
1. **Creation Live Preview & Test-Send**: Enable the side-by-side workspace (Split / Compose / Preview modes, real-time preview iframe, and instant dry-run test-send) on the template creation page (`!template.persisted?`), giving creators instant feedback before saving.
2. **Inline `{{` Variable Autocomplete**: Provide an intuitive, inline searchable autocomplete dropdown when typing `{{` inside any template editor field (Subject input, HTML code textarea, Plain Text fallback textarea, or Rich Text editor).

## 2. Architecture & Component Boundaries

### A. Shared Form Workspace (`app/views/admin/modules/emails/templates/_form.html.erb`)
- Harmonize the workspace layout across Creation and Edit modes:
  - **Creation Mode (`!template.persisted?`)**:
    - **Section 1: Basic Information**: Name and Subject fields.
    - **Section 2: Interactive Workspace**:
      - Layout toggles: Split View, Write Focus, Preview Focus (`template-workspace-layout` controller).
      - Left column: Editor (Rich Text / HTML Code, inline `{{` autocomplete, plain text fallback).
      - Right column: Real-time Preview iframe & Test-Send email card (`remote-template-preview` controller).
    - **Section 3: Simple Status Checkbox**: "Activate template immediately" toggle.
    - **Form Actions**: Cancel & Create buttons.
  - **Edit Mode (`template.persisted?`)**:
    - Retains the 3-tab workspace (`tabs` controller: Composer & Preview, Settings & Delivery, Version History).

### B. Stimulus Autocomplete Controller (`app/javascript/controllers/editor_variable_autocomplete_controller.js`)
- **Target Fields**: Attaches to inputs and textareas (Subject, `body_html`, `body_text`) and ActionText/Trix editor elements.
- **Variables Catalog**: Consumes a JSON array value `variablesValue` containing variables from `Emails::Campaigns::FieldCatalog` and `template.variables`.
- **Trigger Detection**:
  - Monitors `input` and `keydown` events.
  - Matches pattern `\{\{([a-zA-Z0-9_]*)$` behind current caret position.
- **Dropdown Menu**:
  - Dynamically attaches a floating Tailwind container (`bg-white border border-gray-200 rounded-lg shadow-xl z-50 max-h-56 overflow-y-auto`).
  - Positioned relatively beneath the active field/caret.
  - Renders filtered variable matches with monospace token badges and human-readable field labels.
- **Keyboard & Mouse Interaction**:
  - `ArrowDown` / `ArrowUp`: Navigate list items.
  - `Enter` / `Tab`: Insert selected variable `{{variable_name}}` and advance cursor past `}}`.
  - `Escape` or Blur: Close dropdown.

## 3. UI/UX Specifications

### Variable Dropdown Styling
- **Container**: `absolute z-50 w-72 bg-white rounded-lg shadow-lg border border-gray-200 py-1 overflow-hidden font-sans text-sm`.
- **Search Header / Hint**: `px-3 py-1.5 text-xs text-gray-400 bg-gray-50 border-b border-gray-100 flex justify-between items-center`.
- **Option Item**: `px-3 py-2 cursor-pointer flex items-center justify-between text-xs hover:bg-indigo-50 hover:text-indigo-900 transition-colors`.
- **Variable Badge**: `font-mono bg-gray-100 text-gray-700 px-1.5 py-0.5 rounded border border-gray-200 text-xs`.
- **Active Selection**: `bg-indigo-50 border-l-2 border-indigo-600 text-indigo-900 font-medium`.

## 4. Internationalization (I18n)
New translation keys in `config/locales/admin_modules.en.yml` and `config/locales/admin_modules.zh-CN.yml`:
- `admin_modules.emails.templates.form.autocomplete.hint`: "Type to filter variables" / "输入以筛选变量"
- `admin_modules.emails.templates.form.autocomplete.empty`: "No matching variables" / "未找到匹配变量"

## 5. Testing Strategy
- **Vitest JS Unit Tests**: `spec/javascript/controllers/editor_variable_autocomplete_controller.test.js` achieving 100% line and branch test coverage.
- **RSpec Request Specs**: `spec/requests/admin/modules/emails/templates_spec.rb` verifying preview and test-send calls succeed on new/unpersisted template payload.
