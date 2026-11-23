# Email Template Tabbed Workspace UX Redesign

## Goal
Make email template create (`/new`) and edit (`/edit` → Composer) easier to use: less chrome, clearer primary task (write), searchable variable insert, and dedicated Preview / Test panes.

## Direction
**Single-pane tabbed workspace (Compose · Preview · Test)** on both create and edit Composer.

## Decisions

### Layout
- Replace the split-column layout + “Workspace Layout” toolbar with three workspace tabs:
  - **Compose** (default): name, subject, Rich text / HTML control, searchable Insert variable, body editor; plain-text fallback collapsed (`<details>`); create-only “Activate immediately”.
  - **Preview**: full-width live preview (auto-refresh, HTML/plain tabs, open in new tab, manual refresh).
  - **Test**: send-test email panel (mock vars, unsaved draft supported).
- Page header keeps Cancel + primary submit always visible (new/edit wrappers + form footer).
- **Edit** keeps outer tabs: Composer · Settings · Versions (emoji removed from labels). Composer hosts the shared workspace.

### Variables
- Replace native “Insert variable” `<select>` with existing `SearchableSelectComponent` (type-to-filter).
- On select → insert `{{field}}` into the active editor (Lexxy / HTML textarea) → clear the picker.
- Keep `{{` autocomplete on subject / HTML / plain text.

### Dedup
- Extract shared workspace into `app/views/admin/modules/emails/templates/_workspace.html.erb`.
- `_form.html.erb` renders it once for create and once inside edit Composer.

### Out of scope
- Figma token pass (MCP auth unavailable; reuse existing admin Tailwind / component patterns).
- Changing preview/test backend endpoints.
- Removing Settings / Versions on edit.

## Verification
- Request specs: new/edit render workspace tabs + searchable select; omit `template-workspace-layout`; create still omits advanced settings.
- Vitest: `template-variable-picker` supports searchable-select change + clear.
- Manual smoke: compose → preview updates → test send.
