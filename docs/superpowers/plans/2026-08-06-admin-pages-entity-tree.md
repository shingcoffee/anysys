# Admin Pages Entity Tree Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **Git:** Do NOT create commits unless the user explicitly asks. Skip all Commit steps.

**Goal:** Refactor `/:cid/admin/pages` so a left-side entity filter tree (shared with chrome sidebar URLs) categorizes/filters the page list.

**Architecture:** Single `Admin::PagesController#index` serves All / Entity / Uncategorized via path-based routes. `Admin::Pages::TreeBuilder` feeds both the in-page `FilterTreeComponent` and `PagesContributor`. Legacy `EntityPagesController` redirects to the unified entity path.

**Tech Stack:** Rails 8.1, ViewComponent, Stimulus, Tailwind, RSpec, Vitest, I18n en+zh-CN

**Spec:** `docs/superpowers/specs/2026-08-06-admin-pages-entity-tree-design.md`

## Global Constraints

- Admin URL auth: admin or owner only (existing)
- Multi-tenant: `Entity.for_customer` / `Page.for_customer` only; cross-tenant entity → 404
- No hard-coded user-facing strings; en + zh-CN parity
- Stimulus: English `default:` Values + server-passed `data-*-value`; 100% Vitest lines+branches
- Bridge entities never appear as tree parents
- Tree is entity filter nodes only (no page leaves)
- No Page.entity_id FK migration (metadata binding stays)
- Do not auto-commit

## File map

| File | Responsibility |
|------|----------------|
| `app/models/page.rb` | Add `uncategorized_for(customer_id)` scope |
| `app/services/admin/pages/tree_builder.rb` | Shared nav items for chrome + in-page tree |
| `app/services/pages_contributor.rb` | Emit SidebarNodes from TreeBuilder (unified paths) |
| `config/routes.rb` | Entity + uncategorized collection routes; keep legacy route for redirect |
| `app/controllers/admin/pages_controller.rb` | Resolve selection, build tree, drop entity dropdown filter |
| `app/controllers/admin/entity_pages_controller.rb` | Redirect to unified entity URL |
| `app/components/admin/pages/filter_tree_component.rb` (+ erb) | Left nav list UI |
| `app/javascript/controllers/pages_filter_panel_controller.js` | Mobile off-canvas open/close |
| `app/views/admin/pages/index.html.erb` | Split layout: tree + table |
| `config/locales/admin_misc.*.yml`, `chrome.*.yml` | New/updated copy |
| Specs mirroring each layer | RSpec + Vitest |

---

### Task 1: Page.uncategorized_for scope

**Files:**
- Modify: `app/models/page.rb` (near `for_entity`)
- Test: `spec/models/page_entity_grouping_spec.rb` (extend) or `spec/models/page_uncategorized_spec.rb`

**Interfaces:**
- Produces: `Page.uncategorized_for(customer_id)` → ActiveRecord::Relation of visible pages for that customer whose `metadata.entity_id` is blank OR not in `Entity.for_customer(customer_id).select(:id)`

- [ ] **Step 1: Write failing examples**

```ruby
describe ".uncategorized_for" do
  it "includes pages with nil entity_id" do
    orphan = create(:page, customer: customer) # force nil entity in metadata if factory sets one
    expect(Page.uncategorized_for(customer.id)).to include(orphan)
  end

  it "includes pages bound to a missing/stale entity id" do
    stale = create(:page, customer: customer, entity: entity_a)
    stale.entity_id = 9_999_999
    stale.save!
    expect(Page.uncategorized_for(customer.id)).to include(stale)
  end

  it "excludes pages bound to a live customer entity" do
    expect(Page.uncategorized_for(customer.id)).not_to include(a1)
  end

  it "never returns another tenant's pages" do
    expect(Page.uncategorized_for(customer.id)).not_to include(other_tenant_page)
  end
end
```

- [ ] **Step 2: Run to verify fail** — `bundle exec rspec spec/models/page_entity_grouping_spec.rb -e uncategorized`
- [ ] **Step 3: Implement scope** using `CONFIG_ENTITY_ID_SQL` + join on `current_version: :content`, scoped with `for_customer(customer_id)`
- [ ] **Step 4: Run to verify pass**
- [ ] **Step 5: Commit** — SKIP unless user asks

---

### Task 2: Admin::Pages::TreeBuilder

**Files:**
- Create: `app/services/admin/pages/tree_builder.rb`
- Test: `spec/services/admin/pages/tree_builder_spec.rb`

**Interfaces:**
- Consumes: `Page.for_entity`, `Page.uncategorized_for`, `Entity.for_customer(...).non_bridge.by_name`
- Produces: `Admin::Pages::TreeBuilder.call(customer_id:, selected_key:)` → array of item structs/hashes:
  - `key` — `"all"` | `"entity.<id>"` | `"uncategorized"`
  - `label` — I18n for all/uncategorized; `entity.display_label` for entities
  - `path` — unified admin pages paths
  - `count` — Integer
  - `selected` — Boolean

Item order: All Pages, entities by_name, Uncategorized (only if count > 0). Empty entities still included with count 0. Bridges excluded.

Path helpers (use string paths if helpers unavailable in service):
- all: `"/#{customer_id}/admin/pages"`
- entity: `"/#{customer_id}/admin/pages/entities/#{entity.id}"`
- uncategorized: `"/#{customer_id}/admin/pages/uncategorized"`

Counts: prefer one grouped query on entity_id from configuration JSON for entities + one count for uncategorized; avoid N+1.

- [ ] **Step 1: Failing spec** covering order, bridge exclusion, empty entity shown, uncategorized omitted when 0 / included when >0, selected flags, tenant isolation of labels
- [ ] **Step 2: Run fail**
- [ ] **Step 3: Implement TreeBuilder**
- [ ] **Step 4: Run pass**
- [ ] **Step 5: Commit** — SKIP

---

### Task 3: Routes + PagesController + EntityPages redirect

**Files:**
- Modify: `config/routes.rb` (admin pages block ~166)
- Modify: `app/controllers/admin/pages_controller.rb`
- Modify: `app/controllers/admin/entity_pages_controller.rb`
- Test: `spec/requests/admin/pages_spec.rb`, `spec/requests/admin/entity_pages_spec.rb`

**Routes to add** (inside `resources :pages, only: :index`):

```ruby
collection do
  patch :batch, action: :batch_update
  get :uncategorized, action: :index, as: :uncategorized
  get "entities/:entity_id", action: :index, as: :entity
end
```

Expected helpers: `uncategorized_admin_pages_path`, `entity_admin_pages_path(customer_id, entity_id)` (confirm with `bin/rails routes -g admin/pages`).

**Controller selection:**
- If `params[:entity_id]` present (entity collection route) → find `Entity.for_customer(...).find(params[:entity_id])`, scope `for_entity`, `selected_key = "entity.#{id}"`, title may use entity name
- Elsif path/uncategorized (`params[:action]` still index — detect via `request.path` end_with `/uncategorized` OR a route default) → scope `uncategorized_for`, `selected_key = "uncategorized"`
- Else → all pages, `selected_key = "all"`

Remove entity dropdown from `@filters` (keep launch). Set `@tree = Admin::Pages::TreeBuilder.call(...)`. Pass `base_path` into AdminTableComponent if needed so turbo search stays on current selection URL.

**EntityPagesController:**

```ruby
def index
  entity = Entity.for_customer(current_customer.id).find(params[:entity_id])
  redirect_to entity_admin_pages_path(current_customer.id, entity.id, request.query_parameters.except(:entity_id, :customer_id))
end
```

- [ ] **Step 1: Update/add request specs** for entity path 200+filter, uncategorized, legacy redirect 302, cross-tenant entity 404, member forbid
- [ ] **Step 2: Run fail**
- [ ] **Step 3: Implement routes + controllers**
- [ ] **Step 4: Run pass**
- [ ] **Step 5: Commit** — SKIP

---

### Task 4: FilterTreeComponent + mobile Stimulus + index layout + I18n

**Files:**
- Create: `app/components/admin/pages/filter_tree_component.rb`
- Create: `app/components/admin/pages/filter_tree_component.html.erb`
- Create: `app/javascript/controllers/pages_filter_panel_controller.js`
- Create: `spec/components/admin/pages/filter_tree_component_spec.rb`
- Create: `spec/javascript/controllers/pages_filter_panel_controller.test.js`
- Modify: `app/views/admin/pages/index.html.erb`
- Modify: `config/locales/admin_misc.en.yml`, `admin_misc.zh-CN.yml` (tree labels, mobile toggle, description update, uncategorized title/empty)
- Modify: `config/locales/chrome.en.yml`, `chrome.zh-CN.yml` if uncategorized chrome label needed (`chrome.sidebar.pages.uncategorized`)

**UI:**
- Desktop: `hidden md:flex` aside ~224px with FilterTreeComponent
- Mobile: toggle button + off-canvas panel (backdrop + translate) via Stimulus; tree inside
- Active row: `bg-accent-subtle text-accent font-medium` (align SidebarNodeComponent)
- Show count as muted badge
- AdminTable without entity filter; `params` permit list drops entity_id filter key if unused

**Stimulus values:** e.g. `openLabel` / `closeLabel` defaults in English; server sets translated via data attributes.

- [ ] **Step 1: Component + JS tests (fail)**
- [ ] **Step 2: Implement component, JS, view, locales**
- [ ] **Step 3: `bundle exec rspec spec/components/admin/pages/filter_tree_component_spec.rb`**
- [ ] **Step 4: `npx vitest run --coverage` — touched controller at 100% lines/branches**
- [ ] **Step 5: Commit** — SKIP

---

### Task 5: PagesContributor unification

**Files:**
- Modify: `app/services/pages_contributor.rb`
- Modify: `spec/services/pages_contributor_spec.rb`

Map TreeBuilder items → `SidebarNode` (reuse ICONS). Entity paths must be unified `/admin/pages/entities/:id`. Include Uncategorized node when TreeBuilder emits it. Update spec that currently expects `/admin/entities/#{id}/pages`.

- [ ] **Step 1: Update contributor spec expectations (fail)**
- [ ] **Step 2: Implement contributor via TreeBuilder**
- [ ] **Step 3: Run `bundle exec rspec spec/services/pages_contributor_spec.rb`**
- [ ] **Step 4: Commit** — SKIP

---

### Task 6: Verification suite

**Files:** none (run only)

- [ ] Run: `bundle exec rspec spec/models/page_entity_grouping_spec.rb spec/services/admin/pages/tree_builder_spec.rb spec/services/pages_contributor_spec.rb spec/components/admin/pages/filter_tree_component_spec.rb spec/requests/admin/pages_spec.rb spec/requests/admin/entity_pages_spec.rb spec/requests/pages_spec.rb`
- [ ] Run: `npx vitest run --coverage` (confirm pages_filter_panel_controller 100%)
- [ ] Fix any failures
- [ ] Optional smoke: restart dev server with `SKIP_AUTH=1` and hit `/81721200/admin/pages`

---

## Spec coverage checklist

- [x] Entity-only tree (no page leaves)
- [x] Unified chrome + in-page URLs
- [x] Empty entities shown
- [x] Uncategorized when orphans exist
- [x] Mobile off-canvas
- [x] Legacy entity_pages redirect
- [x] Auth + tenant isolation
- [x] I18n both locales
