# Audience Flows — Plan 1: Ownership and Row Scope

> **For agentic workers:** REQUIRED SUB-SKILL: use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to run this plan task by task. Steps use checkbox (`- [ ]`) syntax for tracking. Every task names its SDLC agent, the files it owns, the interfaces it consumes and produces, and its key test cases.

**Goal:** Members see and choose only the rows they own. A reference attribute can be flagged as the owner; every entity gets an ownership kind (person, owned, private, open); member and public reads are row-scoped; member submissions get the owner reference set by the server; flowcharts can find the member's own person entry; owned entities, including Enrollment-style bridges, get member surfaces. Pages bound to a bridge need exact audiences and land in Plan 2.

**Architecture:** One service, `People::Ownership`, answers "what kind is this entity" and "which rows may this viewer reach". Output code (reference dropdowns, entry labels, composite lists, query lists, member surfaces) calls it. The submit boundary calls it through a new `Pages::AudienceGuard`. Flowchart runtime never calls it: flowcharts are trusted and must see every row (counting seats, checking duplicates). Flowcharts get the member's linked entries as trusted context instead (`ctx[:current_person_ids]`, `find_model findBy: current_person`).

**Tech Stack:** Rails 8.1.2, Ruby 3.2.8, Trailblazer activities, ViewComponent, Stimulus, Tailwind, RSpec, Vitest (100% lines + branches on `app/javascript/**`), SQLite `json_extract`.

**Spec:** [`docs/2026-10-27-audience-flows-design.md`](2026-10-27-audience-flows-design.md) §3.3–§3.8, §5, §6, §7.

**Sibling plans:** Plan 2 [`docs/2026-10-27-audience-flows-plan-2-audiences.md`](2026-10-27-audience-flows-plan-2-audiences.md) (exact audiences, action keys, member nav, row actions) and Plan 3 [`docs/2026-10-27-audience-flows-plan-3-registration.md`](2026-10-27-audience-flows-plan-3-registration.md) (public registration, continuation, claim). Order: **Plan 1 → Plan 2 → Plan 3.** Plan 1 runs on today's hierarchical `pages.visibility`: everything here reads audiences through `Page#visible_audiences` and `EntityAttributeAudience`, which Plan 2 keeps.

---

## Global Constraints

Apply to every task. The task checklists do not repeat them.

- **Branch:** work directly on `main` (the checked-out branch). **Do not commit** — the reviewer commits. `git add` is allowed; `git commit` is not.
- **Subagents:** launch with `model` omitted or `inherit` (project default model). Never pass another model slug.
- **I18n:** no hard-coded user-facing strings. Every new key exists in `en` and `zh-CN` with identical key paths and `%{...}` variables. The English value is the exact text from design §5. zh-CN is terse and uses full-width punctuation. Never put `t()` / `I18n.t()` in a Ruby constant.
- **Locale parity check** (run after any locale edit; prints nothing when in parity):

  ```bash
  locale_parity() {
    ruby -ryaml -e '
      def leaves(h, p = []) = h.flat_map { |k, v| v.is_a?(Hash) ? leaves(v, p + [k]) : [[(p + [k]).join("."), v.to_s.scan(/%\{(\w+)\}/).flatten.sort]] }
      en = leaves(YAML.load_file(ARGV[0])["en"]).to_h
      zh = leaves(YAML.load_file(ARGV[1])["zh-CN"]).to_h
      (en.keys - zh.keys).each { |k| puts "missing zh-CN: #{k}" }
      (zh.keys - en.keys).each { |k| puts "missing en: #{k}" }
      (en.keys & zh.keys).each { |k| puts "vars differ: #{k}" if en[k] != zh[k] }
    ' "config/locales/$1.en.yml" "config/locales/$1.zh-CN.yml"
  }
  ```

- **Isolated test databases:** parallel builders must not share the test DB. Each task uses its own `TEST_ENV_NUMBER` (`3<task number>`, e.g. Task 4 → `34`, Task 10 → `310`). Load the schema once per task before the first run: `RAILS_ENV=test TEST_ENV_NUMBER=3N bin/rails db:schema:load`. Run specs as `TEST_ENV_NUMBER=3N bundle exec rspec <paths>`. Re-load after a migration lands.
- **Run scope:** builders run only their task's specs. Task 11 runs the full suite (`bin/rails parallel:prepare && bin/rails parallel:spec`) because this plan changes tenant row scoping.
- **JS coverage:** any change under `app/javascript/**` ships its Vitest update in the same task. Verify with `npx vitest run --coverage --config config/javascript/vitest.config.js <spec paths>` and confirm 100% lines and branches on the touched files. No `/* v8 ignore */` on testable logic.
- **Docs:** code and `doc/reference/{en,zh-CN}` change together (Task 10). zh-CN pages mirror the en sections and examples.
- **Spec style:** describe behavior, not implementation. Prefer request specs for authorization and tenant isolation. Every row-scope rule has a cross-tenant example and a cross-member example.
- **Fail closed:** when ownership can't be resolved (no viewer, viewer from another tenant, unknown audience, missing owner link), member and public scopes return no rows.
- **Ignore** `app/services/page_layout_templates/templates/`.

---

## Waves and file ownership

A file belongs to one task. Tasks in the same wave run in parallel; a wave starts when the previous wave's tasks are done and green.

| Wave | Task | Agent | Owns |
|---|---|---|---|
| 1 | 1 — `People::Ownership` | anysys-backend-developer | `app/services/people/ownership.rb`, `spec/services/people/ownership_spec.rb` |
| 1 | 2 — Owner flag rules | anysys-backend-developer | `app/models/concerns/entity_schema_validation.rb`, `spec/models/concerns/entity_schema_validation_spec.rb`, `config/locales/maint_core.{en,zh-CN}.yml` |
| 1 | 3 — Editor owner toggle | anysys-frontend-developer | `app/components/admin/maintenance/entities/attribute_modal_component.{rb,html.erb}`, `app/javascript/controllers/entity_form/{attribute_manager,modal_manager,reference_manager}.js`, matching `spec/javascript/controllers/entity_form/*.test.js`, `spec/components/admin/maintenance/entities/attribute_modal_component_spec.rb`, `config/locales/comp_admin.{en,zh-CN}.yml` |
| 1 | 4 — Operations API `owner` | anysys-backend-developer | `app/services/entity_definitions/{normalizer,serializer}.rb`, `app/services/entity_definitions/api/**`, `app/services/operations/schemas/entity.defs.json`, `app/services/ai_assistant/assistant/prompt/` entity documents, `config/locales/operations_entity.{en,zh-CN}.yml`, their specs |
| 2 | 5 — Member entity surfaces | anysys-backend-developer | `app/services/member/{entity_surface_builder,surface,effective_surface,null_surface_setting}.rb`, `app/services/member/sources/{entities,builtin_surface}.rb`, `app/models/member/surface_setting.rb`, `app/services/people/link.rb`, new migration, their specs, `spec/requests/member/surfaces_spec.rb` |
| 2 | 6 — Output row scope | anysys-backend-developer | `app/services/entities/{reference_options,entry_display}.rb`, `app/services/page_content_generator/{form_fields,dynamic_options_resolver}.rb`, `app/services/composite_page_renderer.rb`, `app/services/flowchart_runtime/query_builder.rb`, their specs, `spec/requests/member/page_reference_scope_spec.rb` |
| 2 | 7 — Input boundary | anysys-security-engineer | `app/services/pages/{audience_guard,public_submission,form_params}.rb`, `app/controllers/public_pages_controller.rb`, `config/locales/common.{en,zh-CN}.yml`, their specs, `spec/requests/public_pages_ownership_spec.rb` |
| 2 | 8 — Trusted flowchart context | anysys-backend-developer | `app/services/flowchart_runtime/{current_user,entries}.rb`, `app/services/code_generators/element_types/process/model_operations/{find_model,load_current_user}_generator.rb`, `app/services/flowchart_definitions/structure_schema.palette.json`, `spec/javascript/fixtures/action_catalog.sample.json`, `config/locales/flowchart_actions_model_records.{en,zh-CN}.yml`, their specs |
| 3 | 9 — Ownership launch checks | anysys-security-engineer | `app/services/pages/launch_checks.rb`, `app/models/concerns/page_launch_lifecycle.rb`, `app/contracts/pages/visibility_contract.rb`, `config/locales/maint_core.{en,zh-CN}.yml`, `spec/services/pages/launch_checks_spec.rb`, `spec/contracts/pages/visibility_contract_spec.rb`, `spec/models/page_spec.rb` (launch examples only) |
| 4 | 10 — Docs | anysys-tech-lead (writes docs only) | `doc/reference/{en,zh-CN}/{person-linking,entity-builder,member-and-public,page-rendering,page-builder,flowchart-runtime,flowchart-step-actions,operations-api}.md` |
| 5 | 11 — Verification and review | anysys-release-engineer, then anysys-tech-lead + anysys-code-reviewer in parallel | none (read-only) |

Wave 1 Task 2 and Wave 3 Task 9 both edit `maint_core.*.yml`; they are in different waves, so there is no conflict. Task 5 removes `People::Link.member_scope` because it owns its only caller.

## Spec coverage

| Design section | Tasks |
|---|---|
| §3.3 Ownership kinds and the owner flag | 1, 2, 3, 4 |
| §3.4 Row scope on outputs | 1, 5, 6 |
| §3.5 Input boundary (owner binding, reference guard, public rejection) | 7 |
| §3.6 Trusted context for flowcharts | 7, 8 |
| §3.7.3–§3.7.5 Ownership launch checks | 9 |
| §3.7.1–§3.7.2 Bridge-bound pages (member only) | Plan 2 (needs exact audiences: under hierarchical visibility a member page always includes admin) |
| §3.8.1–§3.8.4 Member entity surfaces (defaults, shared entities, hidden fields) | 5 |
| §3.8.5 Member page links | Plan 2 |
| §5 Strings | 2, 7, 8, 9 |
| §6 Documentation | 10 |
| §7 Test matrix (ownership rows) | 1, 5, 6, 7, 8, 9, 11 |

---

## Task 1 — `People::Ownership`

**Agent:** anysys-backend-developer

**Files:**
- Create `app/services/people/ownership.rb`
- Create `spec/services/people/ownership_spec.rb`

**Interfaces:**
- Consumes: `Entity#person?`, `Entity#bridge_entity?`, `Entity#property_schema_json`, `Entities::ReferenceLabels.reference?`, `EntityAttributeAudience::{ADMIN,MEMBER,PUBLIC}`, `FlowchartRuntime::JsonPathValidator.safe_json_path!`.
- Produces (used by Tasks 5–9 and Plans 2–3):
  - `People::Ownership.describe(entity) → Descriptor(kind:, owner:)`; `kind` ∈ `:person, :owned, :private, :open`; `owner` is `Owner(slug:, person_entity_id:)` or nil.
  - `People::Ownership.kind(entity)`, `.owner_reference(entity)` — shorthands for `describe`.
  - `People::Ownership.person_references(entity) → [{ attribute:, target_id: }]` — reference attributes (including bridge source/target refs) whose target is a person entity.
  - `People::Ownership.scope(entity, viewer:, audience:, customer_id:) → ActiveRecord::Relation<EntityEntry>`.
  - `People::Ownership.reachable_ids(entity, ids, viewer:, audience:, customer_id:) → Array<String>`.
  - `People::Ownership.person_entry_ids(user) → { "<person entity id>" => entry_id }`.
  - `People::Ownership.person_entry_id(user, person_entity_id) → Integer | nil`.

- [ ] **Step 1: Write the failing spec.** Build a small schema in `before`: `Student` (person), `Course` (open), `Enrollment` bridge between them (owned through the inferred `student` reference), `Review` with refs to `Student` and `Teacher` (both person) and no flag (private), `Assignment` with the same two refs and `"owner": true` on `student` (owned), `Note` with an `entity_entries` select to `Student` and no other person ref (owned, inferred). Cases:
  - `kind` for each entity above; a reference to a **trashed** person entity still counts (a trashed `Student` must not turn `Enrollment` into `open`).
  - `owner_reference(Enrollment)` → `slug: "student"` (the bridge source ref built by `bridge_property_schema`), `person_entity_id: student_entity.id`; nil for person, private and open entities.
  - `scope` with `audience: "admin"` → every row of the tenant for every kind; another tenant's rows never appear.
  - `scope` with `audience: "member"`: person → only rows with `user_id = viewer.id`; owned → only rows whose owner value (stored as `"12"` or `12`) is one of the viewer's linked entries; private → none; open → all tenant rows.
  - `scope` with `audience: "public"` → none for person, owned and private; all for open.
  - Fail closed: `viewer: nil` with member audience → none; a viewer from another tenant → none; unknown audience string → none; member with no linked person entry → none for owned.
  - `reachable_ids` returns only the in-scope subset, as strings, and ignores non-numeric ids.
  - `person_entry_ids` / `person_entry_id` only return entries in `user.customer_id`.
- [ ] **Step 2: Run, expect failures:** `TEST_ENV_NUMBER=31 bundle exec rspec spec/services/people/ownership_spec.rb`.
- [ ] **Step 3: Implement.**

  ```ruby
  # frozen_string_literal: true

  module People
    # Which rows of an entity each audience may reach (design §3.3–§3.4).
    # Flowchart runtime never calls this: flowcharts must see every row.
    module Ownership
      Owner = Data.define(:slug, :person_entity_id)
      Descriptor = Data.define(:kind, :owner)

      module_function

      def describe(entity)
        return Descriptor.new(kind: :person, owner: nil) if entity.person?

        references = person_references(entity)
        owner = owner_from(references)
        kind = owner ? :owned : (references.empty? ? :open : :private)
        Descriptor.new(kind: kind, owner: owner)
      end

      def kind(entity) = describe(entity).kind
      def owner_reference(entity) = describe(entity).owner

      def scope(entity, viewer:, audience:, customer_id:)
        rows = EntityEntry.where(customer_id: customer_id, entity_id: entity.id)
        return rows if audience.to_s == EntityAttributeAudience::ADMIN

        descriptor = describe(entity)
        return rows if descriptor.kind == :open && known_audience?(audience)
        return rows.none unless audience.to_s == EntityAttributeAudience::MEMBER && same_tenant?(viewer, customer_id)

        case descriptor.kind
        when :person then rows.where(user_id: viewer.id)
        when :owned then owned_rows(rows, descriptor.owner, viewer)
        else rows.none
        end
      end
      # ... reachable_ids, person_entry_ids, person_entry_id, person_references,
      # owner_from (flagged ref wins; else the single person ref; else nil),
      # owned_rows (CAST(json_extract(data, '$.<slug>') AS TEXT) = ?)
    end
  end
  ```

  - `person_references` reads `property_schema_json` (bridge refs live there after `bridge_property_schema`). Target id: `attribute["entity_id"]` for `type: "EntityReference"`, `attribute.dig("config", "entity_id")` for `entity_entries` selects. Load targets with one query: `Entity.unscoped.where(id: ids, customer_id: [entity.customer_id, nil].uniq, extended_model: <person model>)`.
  - Validate the owner slug with `FlowchartRuntime::JsonPathValidator.safe_json_path!` before interpolating it into `json_extract`.
- [ ] **Step 4: Run, expect green.** Same command.

---

## Task 2 — Owner flag definition rules

**Agent:** anysys-backend-developer

**Files:**
- Modify `app/models/concerns/entity_schema_validation.rb`
- Modify `spec/models/concerns/entity_schema_validation_spec.rb`
- Modify `config/locales/maint_core.en.yml`, `config/locales/maint_core.zh-CN.yml`

**Interfaces:**
- Consumes: existing `reference_attributes`, `reference_target`, `bridge_entity?`.
- Produces: entity save fails with `maint_core.errors.validations.entity_owner_reference_invalid` (`%{field}`) or `entity_owner_reference_multiple` (no variables). Text from design §5.

- [ ] **Step 1: Failing spec cases.**
  - `"owner": true` on a reference to a person entity → valid; `owner_reference` resolves to it.
  - `"owner": true` on a non-reference attribute, on a reference to a non-person entity, on any attribute of a person entity, or on any attribute of a bridge entity → `entity_owner_reference_invalid` naming the field.
  - Two flagged attributes → `entity_owner_reference_multiple`.
  - `"owner": false` and a missing key are equivalent (no error, not flagged).
  - Association `additional_attributes` can't carry the flag (bridges infer) → `entity_owner_reference_invalid`.
- [ ] **Step 2: Implement** `validate :validate_owner_reference` (runs when `property_schema` or `associations` changed). Reuse `reference_target`; a person target is `target.person?`.
- [ ] **Step 3: Locale keys** in both files; run `locale_parity maint_core`.
- [ ] **Step 4: Run** `TEST_ENV_NUMBER=32 bundle exec rspec spec/models/concerns/entity_schema_validation_spec.rb spec/models/entity_spec.rb`.

---

## Task 3 — Entity editor owner toggle

**Agent:** anysys-frontend-developer (consult the `shadcn` skill for the switch row; render with project ViewComponent + Tailwind conventions)

**Files:**
- Modify `app/components/admin/maintenance/entities/attribute_modal_component.{rb,html.erb}`
- Modify `app/javascript/controllers/entity_form/{attribute_manager,modal_manager,reference_manager}.js`
- Modify matching `spec/javascript/controllers/entity_form/*.test.js`
- Modify `spec/components/admin/maintenance/entities/attribute_modal_component_spec.rb`
- Modify `config/locales/comp_admin.en.yml`, `config/locales/comp_admin.zh-CN.yml`

**Interfaces:**
- Consumes: the reference target picker in `reference_manager.js`; the component knows which entities are person entities.
- Produces: saved attribute JSON gains `"owner": true` only when the toggle is on (the key is omitted otherwise).

- [ ] **Step 1: Component.** Add an "Owner" switch to the reference configuration block. The component renders the person entity ids as a JSON Stimulus value (`data-entity-form-person-entity-ids-value`) and the label/help via `t(...)` (`comp_admin.entities.attribute_modal.owner_label` "Owner", `owner_help` "Members see and submit only records they own through this field."; zh-CN 「归属人」「会员仅能查看和提交通过此字段归属于自己的记录。」). Hidden on bridge entities and person entities.
- [ ] **Step 2: JS.** `reference_manager.js` shows the switch only when the selected target id is in `personEntityIdsValue`; `attribute_manager.js` adds `owner: true` when checked; `modal_manager.js#prefillModalWithAttribute` restores it. No literal UI text in JS.
- [ ] **Step 3: Vitest** cases: switch hidden for non-person targets, shown for person targets, hidden again when the target changes, `owner` key omitted when off, prefill restores on and off. Run `npx vitest run --coverage --config config/javascript/vitest.config.js spec/javascript/controllers/entity_form` → 100% lines and branches on the three files.
- [ ] **Step 4: Component spec** — switch present with translated label; absent for bridge and person entities. `locale_parity comp_admin`. Run `TEST_ENV_NUMBER=33 bundle exec rspec spec/components/admin/maintenance/entities/attribute_modal_component_spec.rb`.

---

## Task 4 — Operations API `owner`

**Agent:** anysys-backend-developer

**Files:**
- Modify `app/services/entity_definitions/normalizer.rb` (`ATTRIBUTE_KEYS` += `owner`), `app/services/entity_definitions/serializer.rb` (echo `owner` when true)
- Modify `app/services/operations/schemas/entity.defs.json` (attribute `owner`: boolean, described), `app/services/entity_definitions/api/mapper.rb`, `app/services/entity_definitions/api/semantic_validator.rb`
- Modify the entity prompt document under `app/services/ai_assistant/assistant/prompt/` (one example that flags `student` on an `Assignment` entity)
- Modify `config/locales/operations_entity.en.yml`, `config/locales/operations_entity.zh-CN.yml`
- Specs: `spec/services/entity_definitions/api/{mapper,semantic_validator}_spec.rb`, `spec/services/operations/contract_lint_spec.rb` (stays green), `spec/services/entity_definitions/normalizer_spec.rb`, the prompt `tool_examples_contract_spec`

**Interfaces:**
- Produces: `create_entity` / `update_entity` accept `"owner": true` on a reference attribute; the semantic validator returns violations in the existing area groups, with messages at `operations.violations.<code>`:
  - `attribute.owner_invalid` (`%{slug}`): "The attribute %{slug} can mark the record's owner only when it references a person entity." / 「只有引用人员实体的属性才能设为记录所有者：%{slug}。」
  - `entity.owner_multiple` (`%{name}`): "The entity %{name} marks more than one attribute as the owner. Keep one." / 「实体 %{name} 有多个属性设为所有者，请只保留一个。」

- [ ] **Step 1: Failing specs** — mapper round-trips `owner`; validator flags the same cases as Task 2 before the write; contract lint passes (the property has a `description`).
- [ ] **Step 2: Implement**, add the locale keys, run `locale_parity operations_entity`.
- [ ] **Step 3: Run** `TEST_ENV_NUMBER=34 bundle exec rspec spec/services/entity_definitions spec/services/operations/contract_lint_spec.rb spec/services/ai_assistant/assistant/prompt`.

---

## Task 5 — Member entity surfaces

**Agent:** anysys-backend-developer

**Files:**
- Modify `app/services/member/entity_surface_builder.rb`, `app/services/member/surface.rb`, `app/services/member/effective_surface.rb`, `app/services/member/null_surface_setting.rb`, `app/services/member/sources/entities.rb`, `app/services/member/sources/builtin_surface.rb`
- Modify `app/models/member/surface_setting.rb` (`enabled_or(default)`, matching the existing `label_or` / `icon_or` overlay idiom)
- Modify `app/services/people/link.rb` (remove `member_scope`)
- Create `db/migrate/<timestamp>_make_member_surface_settings_enabled_nullable.rb`
- Specs: `spec/services/member/{entity_surface_builder,effective_surface,null_surface_setting}_spec.rb`, `spec/services/member/sources/entities_spec.rb`, `spec/models/member/surface_setting_spec.rb`, `spec/concepts/member/settings/operation/update_spec.rb` (stays green), `spec/services/people/link_spec.rb`, `spec/requests/member/surfaces_spec.rb`

**Interfaces:**
- Consumes: Task 1 (`describe`, `scope`).
- Produces:
  - `Member::Surface#default_enabled?` (true unless the descriptor says otherwise); `SurfaceSetting#enabled_or(default)` and `NullSurfaceSetting#enabled_or(default)` replace `enabled?`; `Member::EffectiveSurface#enabled?` = `@settings.enabled_or(@descriptor.default_enabled?)`.
  - `member_surface_settings.enabled` nullable with no default; nil means inherit. `Member::Settings::Operation::Update` already writes `enabled` only when the form submits it, so a row created by an overlay-only edit keeps nil.
  - `Member::EntitySurfaceBuilder.call(entity:, customer:)` — the scope is always the **member** row scope for the signed-in user (admins previewing see only rows linked to themselves, design §3.4.3).

- [ ] **Step 1: Failing specs.**
  - Hidden-field leak: an attribute with `visibility.member: false` is absent from index columns, detail fields and search (today's index shows it; detail already hides it).
  - Defaults: a person or owned entity's surface is enabled with no saved row; an open entity's surface is disabled with no saved row; a saved `enabled: true/false` wins; a row created by an overlay-only edit (label change, `enabled` not submitted) keeps the default.
  - Sources: private entities and non-owned bridges yield no surface; shared entities (`customer_id: nil`) visible to the tenant yield a surface; trashed entities yield none.
  - Owned bridge "My enrollments": index lists only enrollments whose `student` is the member's linked Student; the owner column is omitted (it is always the member).
  - Request spec `spec/requests/member/surfaces_spec.rb`: member A can't open member B's enrollment detail (404); a member of tenant 2 can't reach tenant 1's surface (404); an admin GET preview of an owned surface lists only rows linked to the admin's own person entries.
- [ ] **Step 2: Migration** `change_column_null :member_surface_settings, :enabled, true` and `change_column_default :member_surface_settings, :enabled, from: true, to: nil`. Run `bin/rails db:migrate`; re-load the task test DB.
- [ ] **Step 3: Implement.** `member_surface_field?` returns false for Calculated attributes and for attributes not visible to `EntityAttributeAudience::MEMBER`. Replace `People::Link.member_scope` with `People::Ownership.scope(entity, viewer: user, audience: EntityAttributeAudience::MEMBER, customer_id: customer.id)`. `enabled_for` compares `user.customer_id` with `customer.id` (shared entities have no `customer_id`). `BuiltinSurface` gains a `default_enabled` member; `default_enabled?` is true unless it is `false` (Plan 2's page links pass `false`).
- [ ] **Step 4: Run** `TEST_ENV_NUMBER=35 bundle exec rspec spec/services/member spec/models/member spec/concepts/member spec/services/people spec/requests/member`.

---

## Task 6 — Output row scope

**Agent:** anysys-backend-developer

**Files:**
- Modify `app/services/entities/reference_options.rb` (new `viewer:` keyword; rows from `People::Ownership.scope`)
- Modify `app/services/page_content_generator/form_fields.rb` (the generated ERB preamble passes `viewer: Current.user`)
- Modify `app/services/entities/entry_display.rb` (`viewer:`; labels for rows outside scope render as the bare id)
- Modify `app/services/page_content_generator/dynamic_options_resolver.rb` and `app/services/composite_page_renderer.rb` (lists and query options intersect the ownership scope)
- Modify `app/services/flowchart_runtime/query_builder.rb` (optional `scope:` keyword on `for_entity`; flowchart callers never pass it)
- Specs: `spec/services/entities/{reference_options,entry_display}_spec.rb`, `spec/services/page_content_generator/{dynamic_options_resolver,entity_quick_add}_spec.rb`, `spec/services/page_content_generator_safety_spec.rb` (the generated dropdown preamble), `spec/services/composite_page_renderer_spec.rb`, `spec/services/flowchart_runtime/query_builder_spec.rb`; create `spec/requests/member/page_reference_scope_spec.rb` (rendered member page dropdowns)

**Interfaces:**
- Consumes: Task 1.
- Produces: every output path that lists another entity's rows applies `People::Ownership.scope` for the viewer's audience. Admin audience output is unchanged.

- [ ] **Step 1: Failing specs.**
  - A member page's "Student" dropdown lists only the member's own Student entry; the "Course" dropdown (open) lists all courses.
  - A public page's dropdown to a person or owned entity renders no options; to an open entity renders all.
  - A composite list of an owned entity on a member page lists only the member's rows; on a public page, nothing.
  - A query list (`options_source: "query"`) over an owned entity is scoped the same way.
  - `EntryDisplay` for member audience shows the label of an in-scope reference and the bare id for an out-of-scope one (no label leak through references).
  - Admin pages and admin entry lists: unchanged results (regression examples).
  - `QueryBuilder.for_entity` without `scope:` still returns every tenant row (flowcharts are unscoped).
- [ ] **Step 2: Implement.** `ReferenceOptions#entries` becomes `People::Ownership.scope(target, viewer: @viewer, audience: @audience, customer_id: @customer_id)`; keep `limit` and ordering. `usable?` (definition-level, used by `LaunchChecks`) is unchanged.
- [ ] **Step 3: Run** `TEST_ENV_NUMBER=36 bundle exec rspec spec/services/entities spec/services/page_content_generator spec/services/page_content_generator_safety_spec.rb spec/services/composite_page_renderer_spec.rb spec/services/flowchart_runtime/query_builder_spec.rb spec/requests/member/page_reference_scope_spec.rb`.

---

## Task 7 — Input boundary

**Agent:** anysys-security-engineer

**Files:**
- Create `app/services/pages/audience_guard.rb`, `spec/services/pages/audience_guard_spec.rb`
- Modify `app/services/pages/public_submission.rb` (call the guard after `FormParams.permit_parts`; add `current_person_ids` to the context; new result status `rejected`)
- Modify `app/services/pages/form_params.rb` (`visible_field?` hides the owner reference from members)
- Modify `app/controllers/public_pages_controller.rb` (`rejected` results redirect back with the guard message; `start_page_handoff` passes the viewer)
- Modify `config/locales/common.en.yml`, `config/locales/common.zh-CN.yml`
- Specs: `spec/services/pages/{public_submission,form_params}_spec.rb`, create `spec/requests/public_pages_ownership_spec.rb` (same naming as the existing `spec/requests/public_pages_*_spec.rb`)

**Interfaces:**
- Consumes: Task 1.
- Produces:
  - `Pages::AudienceGuard.call(entity:, primary:, sections:, viewer:, audience:, customer_id:) → Result(primary:, sections:, error:)`; `error` is nil or a translated message.
  - `Pages::PublicSubmission::Result#rejected?`; nothing is written when rejected.
  - Context key `current_person_ids` (`{ "<person entity id>" => entry_id }`, empty for anonymous and admin viewers that have no links).
  - Keys `common.errors.dynamic.profile_required` (`%{entity}`), `reference_not_allowed` (`%{field}`), `sign_in_required` — text from design §5.

- [ ] **Step 1: Failing specs** (`audience_guard_spec.rb` and the request spec).
  - Member, page bound to `Assignment` (owned through the flagged `student`): a forged `student` param is dropped and replaced with the member's linked Student entry; the saved row's `student` is the member's entry. The same binding works for a primary that is an owned bridge (`Enrollment`), which the spec builds directly because the picker gains bridges only in Plan 2.
  - Member with no linked Student → rejected with `profile_required` (entity = Student's display name); nothing saved.
  - Member picks a `mentor` (reference to a person entity, not the owner) outside their scope → rejected with `reference_not_allowed` naming the field. A forged id from another tenant → same rejection. A reference to an open entity (`course`) is not checked beyond today's tenant validation.
  - Member page bound to `Student` with an `Enrollment` bridge section: the section's back-reference is set by `Pages::BridgeEntries` as today; its owner binding is the new student row (no override).
  - Public: page bound to an owned or private entity → rejected with `sign_in_required`; a filled owned/private bridge section → rejected; an empty bridge section → ignored, the primary is saved. Any filled reference to a person, owned or private entity → rejected with `reference_not_allowed` (the public scope for those kinds is empty).
  - Admin: no binding and no extra checks (regression).
  - Request spec covers the redirect and flash for each rejection and asserts `EntityEntry.count` is unchanged.
- [ ] **Step 2: Implement.** Order inside `PublicSubmission#call`: permit → guard → (rejected? return) → existing flow. `FormParams.visible_field?` hides the owner slug for member audience so the page never renders it; the required-field check skips it (it is filled server-side).
- [ ] **Step 3: Locale keys**, `locale_parity common`.
- [ ] **Step 4: Run** `TEST_ENV_NUMBER=37 bundle exec rspec spec/services/pages spec/requests/public_pages_*_spec.rb spec/requests/member/pages_spec.rb`.

---

## Task 8 — Trusted flowchart context

**Agent:** anysys-backend-developer

**Files:**
- Modify `app/services/flowchart_runtime/current_user.rb` (drop `member_profile_id`; add `person_entries` from `People::Ownership.person_entry_ids`)
- Modify `app/services/flowchart_runtime/entries.rb` (`find_current_person(ctx, entity_id:)`)
- Modify `app/services/code_generators/element_types/process/model_operations/find_model_generator.rb` (`findBy` enum gains `current_person`; version `5.0.0` → `5.1.0`), `load_current_user_generator.rb` (documents `person_entries`)
- Regenerate `app/services/flowchart_definitions/structure_schema.palette.json` (`bin/rails ai_assistant:flowchart_schema`) and `spec/javascript/fixtures/action_catalog.sample.json` (`bin/rails action_catalog:fixture`)
- Modify the `find_model` `findBy` labels in `config/locales/flowchart_actions_model_records.{en,zh-CN}.yml` (`current_person` "The signed-in member's own record" / 「当前会员本人的记录」)
- Specs: `spec/services/flowchart_runtime/{current_user,entries}_spec.rb`, `spec/services/code_generators/element_types/process/model_operations/find_model_generator_spec.rb`, `spec/services/flowchart_definitions/assistant/schema_generator_spec.rb` (stays green)

**Interfaces:**
- Consumes: Task 1; Task 7's `ctx[:current_person_ids]`.
- Produces: `find_model` with `findBy: current_person` loads the viewer's linked entry of the flowchart's bound entity from `ctx[:current_person_ids]` (never from params) through `FlowchartRuntime::Entries.find_current_person(ctx)`. The existing `fail_with(:record_not_found, ...)` covers anonymous viewers, viewers with no link, and bound entities that aren't person entities.

- [ ] **Step 1: Failing specs** — current_person finds the member's entry; ignores a forged `params[:id]`; fails `record_not_found` for anonymous, for a member with no link, and when the bound entity isn't a person entity; tenant isolation (a link in another tenant is never used).
- [ ] **Step 2: Implement**; regenerate palette and fixture; confirm the conformance and palette specs pass.
- [ ] **Step 3: Run** `TEST_ENV_NUMBER=38 bundle exec rspec spec/services/flowchart_runtime spec/services/code_generators/element_types/process/model_operations spec/services/flowchart_definitions/assistant/schema_generator_spec.rb` and `npx vitest run --config config/javascript/vitest.config.js` (fixture consumers stay green).

---

## Task 9 — Ownership launch checks

**Agent:** anysys-security-engineer

**Files:**
- Modify `app/services/pages/launch_checks.rb` (new `audience_errors(audiences)` alongside `reference_errors` / `required_field_errors`)
- Modify `app/models/concerns/page_launch_lifecycle.rb` (`launch_errors` adds `checks.audience_errors`)
- Modify `app/contracts/pages/visibility_contract.rb` (`launched_audiences_stay_submittable` also runs `audience_errors(added)`)
- Modify `config/locales/maint_core.en.yml`, `config/locales/maint_core.zh-CN.yml`
- Specs: `spec/services/pages/launch_checks_spec.rb`, `spec/contracts/pages/visibility_contract_spec.rb`, `spec/models/page_spec.rb` (launch examples)

**Interfaces:**
- Consumes: Task 1; `Page#visible_audiences` (hierarchical today, exact sets after Plan 2).
- Produces launch errors (design §5): `maint_core.errors.page_launch.owned_entity_public_audience` (`%{entity}`), `reference_private_for_audience` (`%{field}`, `%{target}`, `%{audience}`). `LaunchChecks#audience_errors(audiences)` is what Plan 2's rewritten visibility contract calls, and where Plan 2 adds `bridge_page_member_only`.

- [ ] **Step 1: Failing specs.**
  - A page bound to an owned or private entity (for example `Assignment` with `student` flagged), or carrying an owned/private bridge section, can't include the public audience (`owned_entity_public_audience`). With today's hierarchical levels that means it can't be set to `public`; `member` is allowed.
  - `reference_private_for_audience` (naming the field): a reference to a person, owned or private entity on a page with the public audience; a reference to a private entity on a page with the member audience. A reference to an open entity passes for every audience.
  - The checks also run when an audience is added to a live page (`Pages::VisibilityContract` re-runs `LaunchChecks`), not only on launch.
  - The owner reference is exempt from the required-field check for members (it is server-filled).
- [ ] **Step 2: Implement**, add keys, `locale_parity maint_core`.
- [ ] **Step 3: Run** `TEST_ENV_NUMBER=39 bundle exec rspec spec/services/pages/launch_checks_spec.rb spec/contracts/pages spec/models/page_spec.rb spec/requests/admin/maintenance/page_launches_spec.rb`.

---

## Task 10 — Docs

**Agent:** anysys-tech-lead (docs only; no code edits)

**Files:** `doc/reference/{en,zh-CN}/{person-linking,entity-builder,member-and-public,page-rendering,page-builder,flowchart-runtime,flowchart-step-actions,operations-api}.md`

- [ ] `person-linking` — ownership kinds, the owner flag, row scope table (design §3.4), trusted context; remove `member_scope`.
- [ ] `entity-builder` — the Owner switch and its validation messages.
- [ ] `member-and-public` — default-on/off surfaces, shared entities, hidden-field rule, admin preview row scope.
- [ ] `page-rendering`, `page-builder` — owner binding, the three rejections, the new launch checks.
- [ ] `flowchart-runtime`, `flowchart-step-actions` — `person_entries`, `current_person_ids`, `find_model findBy: current_person`; the note that flowcharts are never row-scoped.
- [ ] `operations-api` — the `owner` attribute property and its violations.
- [ ] Both locales have the same sections and examples. `bundle exec rspec spec/services/developer_docs` is green.

---

## Task 11 — Verification and review

**Agent:** anysys-release-engineer, then anysys-tech-lead and anysys-code-reviewer in parallel.

- [ ] `bin/rails db:migrate` is clean; `bin/rails parallel:prepare && bin/rails parallel:spec` passes (paste the summary line).
- [ ] `npx vitest run --coverage --config config/javascript/vitest.config.js` — 100% lines and branches.
- [ ] `locale_parity` for `maint_core`, `comp_admin`, `operations_entity`, `common` and `flowchart_actions_model_records` prints nothing.
- [ ] Dev server smoke. Build the entities with the standard `rm -f public/assets/.manifest.json && SKIP_AUTH=1 bin/rails server -b 0.0.0.0 -p 3000`, then restart without `SKIP_AUTH` (it signs every request in as the tenant's first user) to sign in as two different members. In a test tenant build Student, Course, the Enrollment association, and an `Assignment` entity with a flagged `student` reference. Launch a member page bound to `Assignment` and submit it as a member: the Student field never renders and the saved row belongs to the member. Create two enrollments as an admin (one per member) and confirm each member's "My enrollments" surface shows only their own.
- [ ] Reviews: tech-lead (AGENTS.md conventions: I18n parity, docs in sync, three roles, tenant scoping) and code-reviewer (IDOR on every reference input, `json_extract` slug injection, N+1 in `scope` callers, fail-closed paths). Fix findings in the owning task's files and re-run that task's specs.
