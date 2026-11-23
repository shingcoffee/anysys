# Email Template Form Cleanup & Workspace Unification Design

## Overview
This design document addresses the removal of the redundant "Variables Board" and the unification of the workspace layout between email template creation (`/new`) and editing (`/edit`).

## Problems Addressed
1. **Redundant Variables Board:** The "Variables Board" card with click-to-copy buttons is no longer needed now that the `{{` autocomplete menu and "Insert variable" picker provide direct inline insertion.
2. **Duplicated Workspace Layout:** `_form.html.erb` previously duplicated the entire composer & preview workspace between `new` (`unless template.persisted?`) and `edit` (`else`).
3. **Missing Autocomplete Handlers on Edit:** On the `edit` page, the Subject input field was missing the `editor-variable-autocomplete#onInput` and `onKeydown` data-action bindings, making `{{` autocomplete unavailable in the Subject field on template edits.

## Proposed Changes

### 1. View Refactoring (`app/views/admin/modules/emails/templates/_form.html.erb`)
- Remove the "Click-to-Copy Variables Board Card" HTML block.
- Standardize data actions for Subject field on both `new` and `edit` pages:
  `data: { action: "input->editor-variable-autocomplete#onInput keydown->editor-variable-autocomplete#onKeydown input->remote-template-preview#debouncedLoadPreview" }`
- Refactor `_form.html.erb` so that common workspace sections (Details/Basic Info, Focus Modes, 2-Column Composer & Preview Grid, and Fallback Plain Text) use shared structure, eliminating code duplication between `new` and `edit`.

### 2. Locale Cleanup (`config/locales/admin_modules.en.yml` & `config/locales/admin_modules.zh-CN.yml`)
- Remove unused keys:
  `admin_modules.emails.templates.form.workspace.variables_board_title`
  `admin_modules.emails.templates.form.workspace.variables_board_hint`

### 3. Test Updates
- Update `spec/requests/admin/modules/emails/templates_spec.rb` to:
  - Assert that `variables_board_title` is not rendered.
  - Verify that Subject field on `edit` has autocomplete data-action attributes.
- Run Vitest (`npx vitest run`), Playwright (`npx playwright test`), and RSpec request specs (`bundle exec rspec`).

## Verification Criteria
- `Variables Board` card is nowhere on `/new` or `/edit`.
- Typing `{{` in Subject field on `/edit` triggers autocomplete dropdown.
- All RSpec, Vitest, and Playwright tests pass cleanly.
