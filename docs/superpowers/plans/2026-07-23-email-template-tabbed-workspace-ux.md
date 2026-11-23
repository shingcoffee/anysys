# Email Template Tabbed Workspace UX Implementation Plan

> **For agentic workers:** Implement task-by-task. Steps use checkbox syntax.

**Goal:** Replace the crowded split email-template workspace with Compose / Preview / Test tabs and a searchable Insert variable control on create + edit.

**Architecture:** Shared `_workspace.html.erb` partial; `_form.html.erb` deduped; reuse `SearchableSelectComponent` + updated `template-variable-picker` Stimulus controller.

**Tech Stack:** Rails ERB, ViewComponent, Stimulus, Tailwind, RSpec, Vitest

## Global Constraints
- Scope: create + edit Composer only; Settings/Versions unchanged in behavior
- No new JS frameworks; Stimulus only
- Keep preview/test-send endpoints as-is

### Task 1: Searchable variable insert
- Modify picker controller + SearchableSelect expand_all
- Tests in vitest + request specs

### Task 2: Tabbed workspace partial + form rewrite
- Create `_workspace.html.erb`, slim `_form.html.erb`
- Locales en + zh-CN

### Task 3: Verify
- `bundle exec rspec spec/requests/admin/modules/emails/templates_spec.rb`
- `npx vitest run spec/javascript/controllers/template_variable_picker_controller.test.js`
