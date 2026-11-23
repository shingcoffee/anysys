# Audience Flows — Plan 2: Exact Audiences, Actions, Member Navigation

> **For agentic workers:** REQUIRED SUB-SKILL: use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to run this plan task by task. Steps use checkbox (`- [ ]`) syntax for tracking. Every task names its SDLC agent, the files it owns, the interfaces it consumes and produces, and its key test cases.

**Goal:** Each audience gets its own page and flowchart for the same business action. A page's audiences become an exact set (admin, member, public as independent switches). Pages that share an action key form one action, with at most one live page per audience; `/:cid/actions/:action_key` sends every viewer to the page for their audience. Bridge entities such as Enrollment can back member pages. Member pages appear in member navigation, and member lists and composite lists get row actions that open an action with prefilled values.

**Architecture:** `pages.visibility` (a hierarchical level) is replaced by three booleans and a nullable `action_key`. `PageVisibility` keeps its read API (`visible_to?`, `visible_audiences`) but becomes set membership, so most readers don't change. `Pages::ActionResolver` is the only lookup from action key to page. `Pages::ActionsController` (public URL category) redirects by audience. Prefill is display-only: `Pages::Prefill` filters query values to fields and options the viewer may use, and submission validation is unchanged.

**Tech Stack:** Rails 8.1.2, Ruby 3.2.8, Reform contracts, ViewComponent, Stimulus, Tailwind, RSpec, Vitest (100% lines + branches on `app/javascript/**`).

**Spec:** [`docs/2026-10-27-audience-flows-design.md`](2026-10-27-audience-flows-design.md) §3.1, §3.2, §3.7.1–§3.7.2, §3.8.5, §3.9, §5, §6, §7.

**Sibling plans:** Plan 1 [`docs/2026-10-27-audience-flows-plan-1-ownership.md`](2026-10-27-audience-flows-plan-1-ownership.md) must be complete and green first: this plan uses `People::Ownership`, `Pages::AudienceGuard`, `LaunchChecks#audience_errors` and `BuiltinSurface#default_enabled`. Plan 3 [`docs/2026-10-27-audience-flows-plan-3-registration.md`](2026-10-27-audience-flows-plan-3-registration.md) follows and uses the action router and `Pages::ActionLink`.

---

## Global Constraints

Same as Plan 1 (branch `main`, no commits, `model` omitted or `inherit`, I18n parity with the `locale_parity` helper, no `t()` in constants, 100% Vitest on touched JS, docs in both locales, fail closed, ignore `app/services/page_layout_templates/templates/`). Plan-specific additions:

- **Isolated test databases:** `TEST_ENV_NUMBER=4<task number>` (Task 3 → `43`, Task 10 → `410`). Load the schema per task after Task 1's migration: `RAILS_ENV=test TEST_ENV_NUMBER=4N bin/rails db:schema:load`.
- **Red between waves is expected.** Task 1 removes `pages.visibility`, so specs outside a task's ownership may fail until Task 5 (spec sweep) finishes. Each builder runs only its own specs. Task 11 runs the full suite.
- **No compatibility layer.** No `visibility` attribute alias, no transient factory attribute that maps old levels. Specs move to the factory traits from Task 1.
- **Mechanical spec migration** (Tasks 2–5): an old `visibility: "member"` becomes `:for_member` (admin + member), and `visibility: "public"` becomes `:for_member, :for_public` (all three), which keeps each old example's meaning. Examples that assert the new exact-set behavior are written fresh by Tasks 1 and 3.

---

## Waves and file ownership

| Wave | Task | Agent | Owns |
|---|---|---|---|
| 0 | 0 — UX spec | anysys-ux-designer | `docs/2026-10-27-audience-flows-ux.md` |
| 1 | 1 — Audiences, action key, resolver | anysys-backend-developer | migration, `db/schema.rb`, `app/models/page.rb`, `app/models/concerns/{page_visibility,page_launch_lifecycle}.rb`, `app/contracts/pages/visibility_contract.rb`, `app/services/pages/{action_resolver,action_link,launch_checks}.rb`, `config/locales/maint_core.{en,zh-CN}.yml`, `spec/factories/pages.rb`, their specs |
| 2 | 2 — Distribution card | anysys-frontend-developer | `app/components/pages/distribution_card_component.{rb,html.erb}`, `app/javascript/controllers/page_visibility_controller.js`, `spec/javascript/controllers/page_visibility_controller.test.js`, `config/locales/comp_misc.{en,zh-CN}.yml`, `spec/components/pages/**`, `spec/components/admin/pages/**` |
| 2 | 3 — Page surfaces and action router | anysys-security-engineer | `app/controllers/public_pages_controller.rb`, `app/controllers/member/pages_controller.rb`, `app/controllers/admin/page_forms_controller.rb`, `app/controllers/admin/maintenance/{page_renders,page_visibilities}_controller.rb`, `app/controllers/pages/actions_controller.rb`, `config/routes.rb`, `config/locales/public_views.{en,zh-CN}.yml`, `spec/requests/public_pages_*_spec.rb`, `spec/requests/member/pages_spec.rb`, `spec/requests/admin/page_forms_spec.rb`, `spec/requests/admin/maintenance/{page_renders,page_visibilities}_spec.rb`, `spec/requests/pages/actions_spec.rb` |
| 2 | 4 — Other readers and the bridge picker | anysys-security-engineer | `app/services/captcha/throttle_registry.rb`, `app/controllers/admin/settings/modules/captcha/{pages,status}_controller.rb`, `app/controllers/admin/maintenance/platform/captcha/pages_controller.rb`, `app/services/page_shortcuts/{target_eligibility,lookup}.rb`, `app/services/ai_assistant/assistant/generate_page.rb`, `app/services/ai_assistant/assistant/tools/generate_page_tool.rb`, `app/controllers/admin/maintenance/pages_controller.rb`, `app/helpers/application_helper.rb`, their specs (`spec/services/captcha/**`, `spec/services/page_shortcuts/**`, `spec/services/ai_assistant/**` generate-page specs, `spec/requests/admin/maintenance/pages_spec.rb`, captcha request specs, `spec/helpers/application_helper_spec.rb`) |
| 2 | 7 — Prefill and row-action services | anysys-backend-developer | `app/services/pages/prefill.rb`, `app/models/member/surface_setting.rb`, `app/concepts/member/settings/**`, `app/services/member/effective_surface.rb`, `app/services/composite_page_renderer.rb`, `app/services/page_content_generator/form_fields.rb`, `config/locales/admin_settings.{en,zh-CN}.yml`, their specs |
| 3 | 5 — Spec sweep | anysys-qa-engineer | every remaining spec that sets page `visibility:` and is not owned by Tasks 1–4, 6–9 |
| 3 | 6 — Member page links | anysys-backend-developer | `app/services/member/sources/{pages,builtin_surface}.rb`, `config/initializers/member_surface_sources.rb`, `config/locales/admin_settings.{en,zh-CN}.yml`, `spec/services/member/sources/{pages,builtin_surface}_spec.rb`, `spec/services/member/navigation_spec.rb` |
| 3 | 8 — Row-action and prefill UI | anysys-frontend-developer | `app/components/member/{surface_index,index_table}_component.{rb,html.erb}`, `app/components/admin/settings/member_surface_form_component.{rb,html.erb}`, `app/helpers/page_prefill_helper.rb`, `app/services/page_content_generator/composite_renderer.rb` (list HTML), `app/javascript/controllers/list_module_controller.js` and its test (only if the link needs a click guard), `config/locales/{comp_admin,settings_people,member,public_views}.{en,zh-CN}.yml`, their component, helper and renderer specs |
| 3 | 9 — Prefill and row-action wiring | anysys-security-engineer | `app/controllers/concerns/page_rendering.rb`, `app/controllers/public_pages_controller.rb`, `app/controllers/member/pages_controller.rb`, `app/controllers/admin/page_forms_controller.rb`, `app/controllers/admin/settings/member_surfaces_controller.rb`, `spec/requests/public_pages_prefill_spec.rb`, `spec/requests/admin/settings/member_surfaces_spec.rb` |
| 4 | 10 — Docs | anysys-tech-lead (writes docs only) | `doc/reference/{en,zh-CN}/**` page-visibility mentions, new `audience-flows.md`, `app/services/developer_docs/catalog.rb` |
| 5 | 11 — Verification and review | anysys-release-engineer, then anysys-tech-lead + anysys-code-reviewer in parallel | none (read-only) |

Files shared across waves (never within one): `admin_settings.*.yml` (Task 7, then Task 6), `public_views.*.yml` (Task 3, then Task 8), and `public_pages_controller.rb`, `member/pages_controller.rb`, `admin/page_forms_controller.rb` (Task 3, then Task 9).

## Spec coverage

| Design section | Tasks |
|---|---|
| §3.1 Exact audiences (columns, migration, reads, writes, identity, card) | 1, 2, 3, 4, 5 |
| §3.2 Actions (key, collisions, resolver, router, prefill passthrough, counterpart redirect) | 1, 3 |
| §3.7.1–§3.7.2 Bridge-bound pages, member only | 1, 4 |
| §3.8.5 Member page links | 6 |
| §3.9 Row actions and prefill | 7, 8, 9 |
| §5 Strings | 1, 2, 3, 6, 7, 8 |
| §6 Documentation (including the new Audience flows page) | 10 |
| §7 Test matrix (audience and action rows) | 1, 3, 4, 6, 9, 11 |

---

## Task 0 — UX spec

**Agent:** anysys-ux-designer. Consult the `shadcn` skill and MCP registry (switch, input, select, badge, alert) before specifying; the result is delivered with ViewComponent + Tailwind + Stimulus.

**Files:** create `docs/2026-10-27-audience-flows-ux.md`.

- [ ] Distribution card: three independent audience switches with the URL row for each enabled audience; the last enabled switch is disabled with a tooltip; an action key input with format help; a read-only "Other pages in this action" list (page name + audiences) from `Pages::ActionResolver.siblings`; where `action_audience_taken` and `page_audiences_blank` errors render.
- [ ] Settings / Member: the Pages source row list (one toggle per launched member page) and, on an entity surface form, a "Row action" group: action (select of action keys that have a launched member page), target field (text, slug format), button label (optional, placeholder = default label).
- [ ] Member index: row action button placement on desktop table rows and on the stacked mobile cards. Composite list: trailing link column.
- [ ] Copy table with every new UI key, en and zh-CN, assigned to its locale file (`comp_misc` for the card, `comp_admin` / `settings_people` for Settings / Member, `member` for the index). Flash copy is already fixed in design §5.
- [ ] Mobile, tablet and desktop layouts for each surface.

---

## Task 1 — Audiences, action key, resolver

**Agent:** anysys-backend-developer

**Files:**
- Create `db/migrate/<timestamp>_replace_page_visibility_with_audiences.rb`; regenerate `db/schema.rb`
- Modify `app/models/concerns/page_visibility.rb`, `app/models/page.rb`, `app/models/concerns/page_launch_lifecycle.rb`
- Modify `app/contracts/pages/visibility_contract.rb`
- Create `app/services/pages/action_resolver.rb`, `app/services/pages/action_link.rb`
- Modify `app/services/pages/launch_checks.rb`
- Modify `config/locales/maint_core.en.yml`, `config/locales/maint_core.zh-CN.yml`
- Modify `spec/factories/pages.rb`
- Specs: `spec/models/page_spec.rb`, create `spec/models/concerns/page_visibility_spec.rb`, `spec/contracts/pages/visibility_contract_spec.rb`, `spec/services/pages/launch_checks_spec.rb`, create `spec/services/pages/{action_resolver,action_link}_spec.rb`, `spec/models/page_size_and_uniqueness_spec.rb` (sweep only)

**Interfaces:**
- Produces:
  - Columns `audience_admin` (boolean, not null, default true), `audience_member` and `audience_public` (boolean, not null, default false), `action_key` (string, null), index `[:customer_id, :action_key]`.
  - `PageVisibility::AUDIENCES = %w[admin member public]`; `Page#visible_to?(audience)` (membership; unknown → false); `Page#visible_audiences` (ordered list); `Page#visible_audiences=(list)`; `Page.for_audience(audience)` (SQL scope).
  - `Pages::ActionResolver.page_for(customer_id:, action_key:, audience:) → Page | nil` (active, launched, accessible to the customer, tenant page before shared page); `.counterpart(page:, audience:)` (same action key, nil when the page has none or the counterpart is the page itself); `.siblings(page)` (other active pages in the same action and owner, launched or not, for the card).
  - `Pages::ActionLink.path(customer_id:, action_key:, prefill: {}) → String` (`/:cid/actions/:key?prefill[slug]=value`; drops keys and values that fail §3.2.5).
  - `LaunchChecks#action_errors(audiences)` → `action_audience_taken` (`%{audience}`, `%{action}`); `LaunchChecks#audience_errors` gains `bridge_page_member_only` (no variables).
  - Keys `maint_core.errors.validations.page_audiences_blank`, `page_action_key_invalid`, `maint_core.errors.page_launch.action_audience_taken`, `bridge_page_member_only` (text from design §5).
  - Factory traits `:for_member` (adds member), `:for_public` (adds public), `:member_only`, `:public_only`, `:launched`.

- [ ] **Step 1: Migration.**

  ```ruby
  class ReplacePageVisibilityWithAudiences < ActiveRecord::Migration[8.1]
    def up
      add_column :pages, :audience_admin, :boolean, null: false, default: true
      add_column :pages, :audience_member, :boolean, null: false, default: false
      add_column :pages, :audience_public, :boolean, null: false, default: false
      add_column :pages, :action_key, :string
      execute <<~SQL
        UPDATE pages
        SET audience_member = (visibility IN ('member', 'public')),
            audience_public = (visibility = 'public')
      SQL
      remove_column :pages, :visibility
      add_index :pages, %i[customer_id action_key]
    end

    def down
      add_column :pages, :visibility, :string, null: false, default: "admin"
      execute <<~SQL
        UPDATE pages
        SET visibility = CASE WHEN audience_public THEN 'public' WHEN audience_member THEN 'member' ELSE 'admin' END
      SQL
      remove_index :pages, %i[customer_id action_key]
      remove_column :pages, :action_key
      remove_column :pages, :audience_public
      remove_column :pages, :audience_member
      remove_column :pages, :audience_admin
    end
  end
  ```

  Migration spec cases (run against a scratch table or a dev DB copy, then delete the scratch spec): `admin` → admin only; `member` → admin + member; `public` → all three.
- [ ] **Step 2: Failing model and concern specs.** Membership (`visible_to?("member")` is false on a public-only page); `visible_audiences` order; at least one audience (`page_audiences_blank`); action key format (`page_action_key_invalid`; blank stores nil); `for_audience` SQL scope; unknown audience → false and `for_audience` returns none.
- [ ] **Step 3: Failing resolver, link and launch-check specs.**
  - `page_for`: tenant page wins over a shared page with the same key and audience; offline, trashed and other-tenant pages are ignored; nil key → nil.
  - `counterpart`: finds the member page of a public page's action; nil when the page has no key.
  - `action_errors`: launching a second live member page with key `enroll` in the same tenant fails `action_audience_taken`; the same key in another tenant, or on a shared page, passes; adding the member audience to a live page that would collide fails through the contract; a page taken offline frees the slot.
  - `bridge_page_member_only`: a page bound to an owned bridge launches only when its audiences are exactly `[member]`.
  - `ActionLink.path`: encodes prefill; drops an 11th key, a key that isn't a slug, and a value over 200 characters.
- [ ] **Step 4: Implement.** `launch!` and the visibility contract's save run the collision check inside a transaction holding the owning customer's row lock (`Customer.lock.find(page.customer_id || Authentication::User::PLATFORM_CUSTOMER_ID)`; shared pages lock the platform customer), so two concurrent launches can't both pass. The contract takes `visible_audiences: []` and `action_key`, maps them to the booleans, and re-runs `reference_errors`, `required_field_errors`, `audience_errors` and `action_errors` for audiences it adds to a live page.
- [ ] **Step 5:** `bin/rails db:migrate`; `locale_parity maint_core`; run `TEST_ENV_NUMBER=41 bundle exec rspec spec/models/page_spec.rb spec/models/concerns/page_visibility_spec.rb spec/models/page_size_and_uniqueness_spec.rb spec/contracts/pages spec/services/pages/launch_checks_spec.rb spec/services/pages/action_resolver_spec.rb spec/services/pages/action_link_spec.rb`.

---

## Task 2 — Distribution card

**Agent:** anysys-frontend-developer

**Files:**
- Modify `app/components/pages/distribution_card_component.{rb,html.erb}`
- Modify `app/javascript/controllers/page_visibility_controller.js`, `spec/javascript/controllers/page_visibility_controller.test.js`
- Modify `config/locales/comp_misc.en.yml`, `config/locales/comp_misc.zh-CN.yml` (remove `admin_always_visible_aria` and `always_on`; add Task 0's card keys)
- Specs: `spec/components/pages/distribution_card_component_spec.rb`, sweep `spec/components/admin/pages/**`

**Interfaces:**
- Consumes: Task 0 layout; Task 1 `visible_audiences`, `siblings`, `action_key`.
- Produces: the card posts `page[visible_audiences][]` and `page[action_key]` to the existing visibility endpoint.

- [ ] **Step 1: JS.** Replace the member↔public cascade with independent switches; when one switch remains on, disable it and expose the reason through the server-passed `data-page-visibility-last-audience-value` text. No literal UI text in JS.
- [ ] **Step 2: Vitest** cases: toggling each switch independently; the last switch locks and unlocks; the hidden inputs match the checked switches; missing value falls back to the English `default:`. Run `npx vitest run --coverage --config config/javascript/vitest.config.js spec/javascript/controllers/page_visibility_controller.test.js` → 100% lines and branches.
- [ ] **Step 3: Component.** Admin is a normal switch. Render the action key input, the siblings list, and the URL row per enabled audience. Mobile layout stacks the switches.
- [ ] **Step 4: Component specs** — three switches reflect the exact set; siblings list shows other pages' audiences; no admin lock text. `locale_parity comp_misc`. Run `TEST_ENV_NUMBER=42 bundle exec rspec spec/components/pages spec/components/admin/pages`.

---

## Task 3 — Page surfaces and action router

**Agent:** anysys-security-engineer

**Files:**
- Modify `app/controllers/public_pages_controller.rb`, `app/controllers/member/pages_controller.rb`, `app/controllers/admin/page_forms_controller.rb`, `app/controllers/admin/maintenance/page_renders_controller.rb`, `app/controllers/admin/maintenance/page_visibilities_controller.rb` (permit `action_key`)
- Create `app/controllers/pages/actions_controller.rb`
- Modify `config/routes.rb` (next to the public page routes: `get "actions/:action_key", to: "pages/actions#show", as: :page_action, constraints: { action_key: /[a-z][a-z0-9_]{1,62}/ }`)
- Modify `config/locales/public_views.en.yml`, `config/locales/public_views.zh-CN.yml` (`public_views.actions.continue_here`, `not_for_your_account`)
- Specs: all `spec/requests/public_pages_*_spec.rb`, `spec/requests/member/pages_spec.rb`, `spec/requests/admin/page_forms_spec.rb`, `spec/requests/admin/maintenance/page_renders_spec.rb`; create `spec/requests/admin/maintenance/page_visibilities_spec.rb`, `spec/requests/pages/actions_spec.rb`

**Interfaces:**
- Consumes: Task 1; Plan 1's `Pages::AudienceGuard` (unchanged).
- Produces: route helper `page_action_path(customer_id:, action_key:)`; viewer audience = `page_runtime_audience` everywhere.

- [ ] **Step 1: Failing request specs** — one example per rule in design §3.1.4–§3.1.5 and §3.2.4–§3.2.6:
  - GET public URL: public-only page renders for anonymous, member and admin viewers; a member-only page 404s; a signed-in member is redirected (303) to the member counterpart with `prefill` kept; an admin is redirected (303) to the admin counterpart's form when the action has one.
  - POST as member to a public-only page with a member counterpart → redirect to the counterpart with `continue_here`; without a counterpart → back to the page with `not_for_your_account`; nothing written in either case.
  - POST as admin to a public-only page → `not_for_your_account`, nothing written.
  - POST anonymous to a member page → sign-in with the member page stored; to an admin-only page → sign-in with the admin render stored (an expired admin session lands back on the form); to a page with neither member nor admin and no public → 404.
  - Another tenant's admin and another tenant's member are treated as public (today's foreign-session rule): GET renders only when public is in the set, POST is refused unless public is in the set, and the action router sends them to the public page or 404s.
  - Member page GET requires member; the admin GET preview (`allow_admin_member_preview!`) still works; member POST through the preview is refused.
  - Admin form and maintenance render require admin in the set.
  - Action router: each audience lands on its page; anonymous with only a member page → sign-in with the member page and prefill stored; no page for the audience → 404; unknown key → 404; a key from another tenant → 404; `prefill` over the limits is dropped.
  - Visibility endpoint: tenant path on a shared page → refused (`shared_page_readonly`); invalid action key → alert with `page_action_key_invalid`; collision → alert with `action_audience_taken`.
- [ ] **Step 2: Implement.** `page_visible_to_current_viewer?(page)` becomes `page.visible_to?(page_runtime_audience)`. `authorize_submission!` applies the refusal rules in design order. `stored_submission_return_path` and `post_submit_path` choose the surface of the viewer's audience. `Pages::ActionsController` has no auth guard (public URL category) and only redirects; the targets enforce their own guards.
- [ ] **Step 3:** `locale_parity public_views`; run `TEST_ENV_NUMBER=43 bundle exec rspec spec/requests/public_pages_*_spec.rb spec/requests/member/pages_spec.rb spec/requests/admin/page_forms_spec.rb spec/requests/admin/maintenance/page_renders_spec.rb spec/requests/admin/maintenance/page_visibilities_spec.rb spec/requests/pages/actions_spec.rb`.

---

## Task 4 — Other readers and the bridge picker

**Agent:** anysys-security-engineer

**Files:**
- Modify `app/services/captcha/throttle_registry.rb` (`Page.for_audience("public")`)
- Modify `app/controllers/admin/settings/modules/captcha/{pages,status}_controller.rb`, `app/controllers/admin/maintenance/platform/captcha/pages_controller.rb` (`page.visible_to?("public")` / `for_audience`)
- Modify `app/services/page_shortcuts/{target_eligibility,lookup}.rb` (shortcuts target pages with public in the set)
- Modify `app/services/ai_assistant/assistant/generate_page.rb` (drop the `visibility = "admin"` assignment; the column default is admin-only) and the description in `tools/generate_page_tool.rb` if it names visibility
- Modify `app/controllers/admin/maintenance/pages_controller.rb` (the entity picker adds tenant bridges whose `People::Ownership.kind` is `:owned`) and `app/helpers/application_helper.rb` (`grouped_entity_options` keeps flowcharts bound to owned bridges)
- Specs: `spec/services/captcha/**`, `spec/services/page_shortcuts/**`, the generate-page specs under `spec/services/ai_assistant/**`, captcha settings request specs, `spec/requests/admin/maintenance/pages_spec.rb`, `spec/helpers/application_helper_spec.rb`

- [ ] **Step 1: Failing specs.** Captcha lists and throttles pages with public in the set, including a page that is public-only (no admin); a shortcut can't target a member-only page; the generated assistant page is admin-only; the picker lists an owned bridge and its flowcharts, never a non-owned or trashed bridge, and never in shared-resources mode (shared entities can't carry associations).
- [ ] **Step 2: Implement.**
- [ ] **Step 3: Run** `TEST_ENV_NUMBER=44 bundle exec rspec spec/services/captcha spec/services/page_shortcuts spec/services/ai_assistant spec/requests/admin/maintenance/pages_spec.rb spec/requests/admin/settings spec/requests/admin/maintenance/platform spec/helpers`.

---

## Task 5 — Spec sweep

**Agent:** anysys-qa-engineer

**Files:** every spec file still matching the search below after Tasks 1–4 and 7, excluding files owned by Tasks 6, 8 and 9.

- [ ] **Step 1: Find them.** `rg -l "visibility: [\"':](admin|member|public)|VISIBILITY_LEVELS|\.visibility\b" spec | xargs rg -l -i page`. Leave attribute-level `visibility` hashes (`"visibility" => { "member" => false }`) alone.
- [ ] **Step 2: Migrate** each match with the traits from Task 1 (see Global Constraints for the mapping). Where an example asserted hierarchical behavior (for example "a public page is visible to members"), rewrite it to assert the exact-set rule.
- [ ] **Step 3: Verify** the search returns nothing, then run the swept files: `TEST_ENV_NUMBER=45 bundle exec rspec <swept files>`.

---

## Task 6 — Member page links

**Agent:** anysys-backend-developer

**Files:**
- Create `app/services/member/sources/pages.rb`; modify `app/services/member/sources/builtin_surface.rb` (comment: link descriptors for builtin and page entries)
- Modify `config/initializers/member_surface_sources.rb` (load `Member::Sources::Pages`)
- Modify `config/locales/admin_settings.{en,zh-CN}.yml`: `admin_settings.member.sources.pages.name` "Pages" / 「页面」, `description` "Launched pages members can open." / 「会员可打开的已上线页面。」
- Specs: create `spec/services/member/sources/pages_spec.rb`; `spec/services/member/sources/builtin_surface_spec.rb`, `spec/services/member/navigation_spec.rb`

**Interfaces:**
- Consumes: Task 1 (`for_audience`, `ActionResolver`); Plan 1 `BuiltinSurface#default_enabled`.
- Produces: source key `:pages`, editable, position after entities; one `BuiltinSurface` per page: key `page_<id>`, label = page name, `path_seg` `pages/<id>`, `default_enabled: false`.

- [ ] **Step 1: Failing specs.** Lists launched, active tenant and shared pages with member in the set; skips offline, trashed, admin-only and public-only pages; when a tenant page and a shared page share an action key and the member audience, lists only the resolver's choice; links are off until an admin enables them; navigation builds `/:cid/member/pages/<id>`; `Member::SurfacesController` 404s `surfaces/page_<id>`; a member of another tenant never sees the link.
- [ ] **Step 2: Implement**; `locale_parity admin_settings`. Inside `Member::Sources::Pages` a bare `Pages::ActionResolver` resolves to the source class itself, so write `::Pages::ActionResolver` and `::Page`.
- [ ] **Step 3: Run** `TEST_ENV_NUMBER=46 bundle exec rspec spec/services/member spec/requests/member/surfaces_spec.rb`.

---

## Task 7 — Prefill and row-action services

**Agent:** anysys-backend-developer

**Files:**
- Create `app/services/pages/prefill.rb`, `spec/services/pages/prefill_spec.rb`
- Modify `app/models/member/surface_setting.rb` (overlay keys `row_action_key`, `row_action_field`, `row_action_label`; `row_action_or(default_label)`)
- Modify `app/concepts/member/settings/{contract,operation}/update.rb` (`OVERLAY_KEYS` and contract properties; validation: action key and field slug formats, label ≤ 60 characters)
- Modify `app/services/member/effective_surface.rb` (`#row_action` → `{ action_key:, field:, label: }` or nil)
- Modify `app/services/composite_page_renderer.rb` (list tiles read `config.row_action`; each record's data gains `row_action_path` from `Pages::ActionLink.path`; Task 8 renders it)
- Modify `app/services/page_content_generator/form_fields.rb` (input fields render `value: page_prefill_value(<slug>)`)
- Modify `config/locales/admin_settings.en.yml`, `config/locales/admin_settings.zh-CN.yml` (`admin_settings.errors.validations.row_action_invalid` "The row action needs an action key and a target field." / 「行操作须填写操作标识和目标字段。」)
- Specs: `spec/services/pages/prefill_spec.rb`, `spec/models/member/surface_setting_spec.rb`, `spec/concepts/member/settings/operation/update_spec.rb`, `spec/services/member/effective_surface_spec.rb`, `spec/services/composite_page_renderer_spec.rb`, `spec/services/page_content_generator_safety_spec.rb`

**Interfaces:**
- Consumes: Task 1 (`ActionLink`); Plan 1 (`People::Ownership.reachable_ids`, `owner_reference`).
- Produces: `Pages::Prefill.values(page:, params:, audience:, viewer:) → { "<slug>" => "<value>" }`; the generated ERB calls `page_prefill_value(slug)` (helper from Task 8).

- [ ] **Step 1: Failing specs.** Prefill keeps a visible text field; drops a field hidden from the audience, an unknown slug, the owner reference, and a reference id outside the viewer's options (another member's Student, another tenant's Course); keeps an in-scope reference; never raises on malformed params. Settings save and reload the three overlay keys; a row action without a field fails `row_action_invalid`; `row_action` uses the default label when none is set. Composite list rows carry the action link only when `row_action` is configured. The generator's ERB stays injection-safe with a hostile slug (existing safety spec pattern).
- [ ] **Step 2: Implement**; `locale_parity admin_settings`.
- [ ] **Step 3: Run** `TEST_ENV_NUMBER=47 bundle exec rspec spec/services/pages/prefill_spec.rb spec/models/member spec/concepts/member spec/services/member/effective_surface_spec.rb spec/services/composite_page_renderer_spec.rb spec/services/page_content_generator_safety_spec.rb`.

---

## Task 8 — Row-action and prefill UI

**Agent:** anysys-frontend-developer

**Files:**
- Modify `app/components/member/{surface_index,index_table}_component.{rb,html.erb}` (row action button on table rows and mobile cards)
- Modify `app/components/admin/settings/member_surface_form_component.{rb,html.erb}` (row action group, entity surfaces only)
- Modify `app/services/page_content_generator/composite_renderer.rb` (`render_list_module_html` adds a trailing link column when records carry `row_action_path`; escape with `ERB::Util.html_escape` like the surrounding markup). The link must not trigger `list-module#selectRow`; if it does, guard it in `app/javascript/controllers/list_module_controller.js` and cover the guard in Vitest.
- Create `app/helpers/page_prefill_helper.rb` (`page_prefill_value(slug)` reads `@page_prefill`; nil when unset)
- Modify `config/locales/{comp_admin,settings_people,member,public_views}.{en,zh-CN}.yml` (Task 0 copy; `member.entity_surfaces.row_action_default` and `public_views.composite.row_action_default` "Open" / 「打开」)
- Specs: `spec/components/member/{surface_index,index_table}_component_spec.rb`, `spec/components/admin/settings/member_surface_form_component_spec.rb`, create `spec/helpers/page_prefill_helper_spec.rb`, `spec/services/page_content_generator_composite_spec.rb`

- [ ] **Step 1: Failing specs** — the button renders with the overlay or default label and links to `ActionLink.path` with `prefill[<field>]=<row id>`; no button without a row action; the settings group shows only for entity surfaces and lists action keys with a launched member page; helper returns nil for missing slugs.
- [ ] **Step 2: Implement** (Tailwind only; responsive per Task 0); `locale_parity` for each touched file.
- [ ] **Step 3: Run** `TEST_ENV_NUMBER=48 bundle exec rspec spec/components/member spec/components/admin/settings spec/helpers/page_prefill_helper_spec.rb spec/services/page_content_generator_composite_spec.rb`; if `list_module_controller.js` changed, `npx vitest run --coverage --config config/javascript/vitest.config.js spec/javascript/controllers/list_module_controller.test.js` → 100% lines and branches.

---

## Task 9 — Prefill and row-action wiring

**Agent:** anysys-security-engineer

**Files:**
- Modify `app/controllers/concerns/page_rendering.rb` (`prepare_page_render(page, return_to:, quick_add:, prefill: {})` sets `@page_prefill`)
- Modify `app/controllers/public_pages_controller.rb`, `app/controllers/member/pages_controller.rb`, `app/controllers/admin/page_forms_controller.rb` (pass `Pages::Prefill.values(page:, params:, audience: page_runtime_audience, viewer: page_runtime_user)`)
- Modify `app/controllers/admin/settings/member_surfaces_controller.rb` (permit the three row action params)
- Specs: create `spec/requests/public_pages_prefill_spec.rb`; `spec/requests/admin/settings/member_surfaces_spec.rb`

- [ ] **Step 1: Failing request specs** — `?prefill[course]=<id>` preselects the course on the member enroll page; another tenant's course id is ignored; a prefilled hidden field never renders; submitting without the prefilled value still validates normally (prefill grants nothing); the admin saves a row action and the member index shows the button; a member can't post Settings / Member params.
- [ ] **Step 2: Implement.**
- [ ] **Step 3: Run** `TEST_ENV_NUMBER=49 bundle exec rspec spec/requests/public_pages_prefill_spec.rb spec/requests/admin/settings/member_surfaces_spec.rb spec/requests/member`.

---

## Task 10 — Docs

**Agent:** anysys-tech-lead (docs only)

- [ ] `rg -n "visibility|Visibility|admin only|members and admins" doc/reference/` and rewrite every page-visibility mention in both locales to exact audiences (attribute-level `visibility` stays). Expected pages: page-builder, page-rendering, member-and-public, tenancy-and-roles, shared-resources, page-shortcuts, captcha, ai-assistant, overview, customer-documentation, dashboard, website-builder.
- [ ] page-rendering: the refusal rules, the counterpart redirect, prefill, and a callout that a signed-in admin can't submit a public-only page (test it signed out, or add the admin audience).
- [ ] page-builder: action key, audience switches, bridge-bound pages, row actions.
- [ ] member-and-public: the Pages source and row actions.
- [ ] Create `doc/reference/{en,zh-CN}/audience-flows.md` with front-matter `title` / `summary` and the five headings `DeveloperDocs::Catalog::REQUIRED_HEADINGS` requires (en: Summary, Flow, Implementation, Where to pay attention, Key code; zh-CN: 概要, 流程, 实现, 需要特别注意, 关键代码). Content: the enrollment example from design §1, per-audience flowcharts and the shared "Enroll core" subflow (design §4), the ownership table, actions and the router, and what Plan 3 adds (registration, continuation, claim).
- [ ] Register `audience-flows` in the `access` group of `DeveloperDocs::Catalog` (after `person-linking`); cross-link from member-and-public, page-builder and person-linking.
- [ ] `bundle exec rspec spec/services/developer_docs` is green.

---

## Task 11 — Verification and review

**Agent:** anysys-release-engineer, then anysys-tech-lead and anysys-code-reviewer in parallel.

- [ ] `rg -n "\bvisibility\b" app lib config | rg -iv "attribute|visibility\.(member|public|admin)|content-visibility|\"visibility\" =>"` lists no page-visibility reads.
- [ ] `bin/rails parallel:prepare && bin/rails parallel:spec` passes (paste the summary line).
- [ ] `npx vitest run --coverage --config config/javascript/vitest.config.js` — 100% lines and branches.
- [ ] `locale_parity` for `maint_core`, `comp_misc`, `public_views`, `admin_settings`, `comp_admin`, `settings_people`, `member` prints nothing.
- [ ] Admin screens (distribution card, Settings / Member) smoke with the standard `rm -f public/assets/.manifest.json && SKIP_AUTH=1 bin/rails server -b 0.0.0.0 -p 3000`. Audience paths need real sessions, because `SKIP_AUTH` signs every request in as the tenant's first user: restart without `SKIP_AUTH`, then give a public Student page and a member Enrollment page the action key `enroll`; `/:cid/actions/enroll` signed out shows the Student page; signed in as a member it shows the Enroll page; a Courses surface row action opens it with the course preselected.
- [ ] Reviews: tech-lead (three URL categories, the action router is public and redirect-only, I18n, docs) and code-reviewer (open redirects in the router and prefill, IDOR through prefill, collision race, every former hierarchical check converted). Fix findings in the owning task's files and re-run its specs.
