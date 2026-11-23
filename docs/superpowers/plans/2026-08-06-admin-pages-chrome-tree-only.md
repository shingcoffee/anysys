# Admin Pages Chrome Tree Only — Implementation Plan

> **For agentic workers:** Implement task-by-task. Do NOT commit unless the user asks.

**Goal:** Entity page filtering lives only in the chrome Pages sidebar (with counts); the admin pages index content is a clean table.

**Architecture:** `TreeBuilder` feeds `PagesContributor` badges. Strip in-page `FilterTreeComponent` and mobile filter Stimulus. Controller keeps path-based scoping without `@tree`.

**Tech Stack:** Rails 8.1, ViewComponent, Stimulus, Tailwind, RSpec, Vitest, I18n

**Spec:** `docs/superpowers/specs/2026-08-06-admin-pages-chrome-tree-only-design.md`

## Global Constraints

- Admin auth / tenant scoping unchanged
- No hard-coded UI strings; en + zh-CN parity
- Do not auto-commit

## File map

| File | Change |
|------|--------|
| `app/services/pages_contributor.rb` | Attach `badge: { label: count.to_s }` from TreeBuilder |
| `app/controllers/admin/pages_controller.rb` | Drop `@tree` |
| `app/views/admin/pages/index.html.erb` | Table-only body |
| `app/components/admin/pages/filter_tree_component.*` | Delete |
| `app/javascript/controllers/pages_filter_panel_controller.js` | Delete |
| Matching specs + locales | Update / delete |

### Task 1: PagesContributor badges + specs
### Task 2: Strip in-page tree UI + dead code
### Task 3: I18n + request assertions + verify Vitest/RSpec
