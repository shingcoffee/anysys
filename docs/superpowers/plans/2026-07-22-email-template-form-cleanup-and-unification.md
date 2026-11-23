# Email Template Form Cleanup & Workspace Unification Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the redundant "Variables Board" card from the email template form and unify the composer/preview workspace layout between template creation (`/new`) and editing (`/edit`) to ensure consistent autocomplete and live preview behavior.

**Architecture:** Remove duplicated HTML cards from `_form.html.erb`, ensure Subject input on `edit` has autocomplete data actions (`input->editor-variable-autocomplete#onInput keydown->editor-variable-autocomplete#onKeydown`), remove unused i18n keys, and update tests.

**Tech Stack:** Rails v8.1.2, ViewComponent, TailwindCSS, StimulusJS, Vitest, Playwright, RSpec.

## Global Constraints
- Only use TailwindCSS for styling.
- Ensure 100% Vitest line/branch coverage for JS.
- All user-facing copy MUST be in both `en` and `zh-CN` locales.

---

### Task 1: Unify Form Partial and Remove Variables Board

**Files:**
- Modify: `app/views/admin/modules/emails/templates/_form.html.erb`

**Interfaces:**
- Consumes: `Emails::Template` model, `editor-variable-autocomplete` controller
- Produces: Cleaned up form template without Variables Board and with unified Subject autocomplete actions on edit

- [ ] **Step 1: Edit `_form.html.erb` to remove Variables Board and unify Subject field actions**

Remove the `<%# --- Click-to-Copy Variables Board Card --- %>` block from both `new` (unpersisted) and `edit` (persisted) branches in `app/views/admin/modules/emails/templates/_form.html.erb`. Ensure the Subject input on `edit` has `data: { action: "input->editor-variable-autocomplete#onInput keydown->editor-variable-autocomplete#onKeydown input->remote-template-preview#debouncedLoadPreview" }`.

- [ ] **Step 2: Commit changes**

```bash
git add app/views/admin/modules/emails/templates/_form.html.erb
git commit -m "refactor(emails): remove Variables Board and unify autocomplete actions on edit form"
```

---

### Task 2: Clean Up Unused Locale Keys

**Files:**
- Modify: `config/locales/admin_modules.en.yml`
- Modify: `config/locales/admin_modules.zh-CN.yml`

**Interfaces:**
- Consumes: YAML locale files
- Produces: Updated locale files without `variables_board_title` and `variables_board_hint`

- [ ] **Step 1: Remove unused i18n keys from locale files**

Remove `variables_board_title` and `variables_board_hint` under `admin_modules.emails.templates.form.workspace` from `config/locales/admin_modules.en.yml` and `config/locales/admin_modules.zh-CN.yml`.

- [ ] **Step 2: Commit changes**

```bash
git add config/locales/admin_modules.en.yml config/locales/admin_modules.zh-CN.yml
git commit -m "chore(emails): remove unused variables_board locale keys"
```

---

### Task 3: Update Specs and Verify Full Suite

**Files:**
- Modify: `spec/requests/admin/modules/emails/templates_spec.rb`

**Interfaces:**
- Consumes: RSpec request spec suite
- Produces: Verified test coverage confirming form unification and absence of Variables Board

- [ ] **Step 1: Update `templates_spec.rb` to assert absence of Variables Board**

In `spec/requests/admin/modules/emails/templates_spec.rb`, update specs to assert that `variables_board_title` is no longer present in the response body.

- [ ] **Step 2: Run test suite**

Run:
`bundle exec rspec spec/requests/admin/modules/emails/templates_spec.rb`
`npx vitest run spec/javascript/controllers/editor_variable_autocomplete_controller.test.js --config config/javascript/vitest.config.js`
`npx playwright test spec/e2e/email_template_autocomplete.app.spec.js`

Expected: All tests pass.

- [ ] **Step 3: Commit changes, clobber assets, and restart server**

```bash
git add spec/requests/admin/modules/emails/templates_spec.rb
git commit -m "test(emails): update request specs for form unification and absence of Variables Board"
rm -f public/assets/.manifest.json && bin/rails assets:clobber && bin/rails tailwindcss:build
```

Restart Rails server with `SKIP_AUTH=1`.
