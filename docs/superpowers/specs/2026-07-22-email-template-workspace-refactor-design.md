# Specification: Email Template Workspace UI/UX Refactor

## 1. Introduction / Background
The email template creation and edit workflow features a side-by-side workspace: Composer (left) and Live Preview (right). 
To make live previewing and test-sending significantly easier and more comfortable ("at ease"), we are introducing:
1. **Real-time Live Sync (Auto-Refresh):** Debounced auto-updates of the preview as the user types (Subject, Rich Text, HTML source, and plain text fallback) with a toggle to disable.
2. **Instant Page-Load Preview:** Automatically rendering the preview upon page mount.
3. **Responsive Workspace Layout Toggles (Focus Modes):** Smooth layout switching between 👥 Split View, ✍️ Write Focus, and 👁️ Preview Focus.
4. **Click-to-Copy Variables Board:** A board displaying available variables that can be copied with a single click and pasted anywhere.
5. **Polished Test-Send UX:** Beautiful loading states and high-fidelity dismissible inline alert cards for delivery results.

---

## 2. Architecture & Components

We will introduce/refactor the following layers:

### A. Frontend Views (`app/views/admin/modules/emails/templates/_form.html.erb`)
- Wrap the workspace in a layout controller: `data-controller="template-workspace-layout"`.
- Add a visual Button Group at the top of the workspace to toggle Focus Modes.
- Embed a click-to-copy variables board under the Composer, allowing users to copy template variables instantly.
- Show the Settings & Delivery Card on both `new` and `edit` views (hidden inside a collapsible details element or styled nicely so it's clean and accessible).
- Place an "Auto-refresh" toggle (checkbox) in the Live Preview header.

### B. JavaScript Controllers (`app/javascript/controllers/`)
1. **`remote_template_preview_controller.js` (Refactored):**
   - Implements `connect()` to load the preview immediately.
   - Implements `debouncedLoadPreview()` utilizing a 1000ms timer to prevent server spamming while typing.
   - Monitors form changes via actions (`input->`, `change->`, `trix-change->`).
   - Renders spinner indicators during fetching/sending.
   - Renders polished alerts for test-send status.
2. **`template_workspace_layout_controller.js` (New):**
   - Manages Focus Modes by toggling CSS classes on the composer and preview containers (`hidden` and responsive grid classes).
3. **`click_to_copy_controller.js` (New):**
   - Copies text value to clipboard.
   - Displays temporary visual feedback ("Copied!" in green) on the badge button itself.

---

## 3. UI/UX Specifications (Tailwind Classes)
- **Focus Modes Button Group:** Rounded-lg button group using a flex row, with slate borders and primary accent highlighting.
- **Variables Board:** A card styled with a light slate background and small, interactive badge buttons (`hover:bg-slate-100 transition`).
- **Test-Send Alerts:**
  - Success: `bg-green-50 border-green-200 text-green-800`
  - Error: `bg-red-50 border-red-200 text-red-800`

---

## 4. Internationalization (I18n)
All labels, button text, tooltips, and feedback messages will use Rails I18n translations under `admin_modules.emails.templates.form` for both English (`en`) and Simplified Chinese (`zh-CN`). No user-facing hardcoded text will be used.

---

## 5. Verification & Testing Plan
1. **Vitest Unit Tests (`spec/javascript/controllers/`):**
   - Ensure `remote_template_preview_controller.test.js` is fully updated and retains 100% line/branch coverage.
   - Create unit tests for `template_workspace_layout_controller.test.js` with 100% line/branch coverage.
   - Create unit tests for `click_to_copy_controller.test.js` with 100% line/branch coverage.
2. **RSpec Request Tests (`spec/requests/admin/modules/emails/`):**
   - Ensure existing tests for templates, previews, and test-sends continue to pass.
