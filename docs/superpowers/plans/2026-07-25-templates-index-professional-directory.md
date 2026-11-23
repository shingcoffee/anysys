# Templates Index Professional Directory — Plan

**Goal:** Filters + More menu + Lists-calm directory on email templates index.

## Tasks

### Task 1 — AdminTable `row_menu_actions` + filter-aware empty state
- Add `row_menu_actions:` optional lambda
- Actions column if `row_actions` or `row_menu_actions` present
- Render More via `<details>` / `<summary>`
- `empty_after_search?` → also true when any filter param present (rename helper or broaden)
- Specs in `spec/components/admin_table_component_spec.rb`
- Vitest: none (no JS)

### Task 2 — Templates controller + index view + locales + request specs
- Scope filters for status + editor_type
- Pass filters to AdminTable; permit params
- `row_actions: nil`; `row_menu_actions:` Preview, Versions, status_*
- Locales: filter labels, More
- Request specs for filters + More markup + no long inline Edit/Preview strip

### Task 3 — Verify
- `bundle exec rspec spec/components/admin_table_component_spec.rb spec/requests/admin/modules/emails/templates_spec.rb`
