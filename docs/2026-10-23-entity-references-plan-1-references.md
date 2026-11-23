# Entity References Implementation Plan (Plan 1 of 3)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every dropdown that lists another entity's records, and every association, saves the record id and shows a human-readable display field. Lists only show what the viewer may see. Definitions, entries, trash and the assistant all enforce the same rule.

**Architecture:** Two new pure services own the rule:

- `Entities::ReferenceLabels` decides which attributes may label a reference and how labels read.
- `Entities::ReferenceOptions` builds one tenant's `[label, id]` choices for a target entity.

Every surface that lists or saves reference values calls these two services instead of keeping its own copy. That covers generated forms, the page-builder preview, Create Entry, quick add, the entry contract and the bridge writer.

A third service, `Entities::ReferenceDependents`, answers "what references this entity". It covers customer-owned definitions, shared defaults and tenant overrides, and backs two guards: the trash guard and the display-field save guard.

The assistant contract drops `value_field` and becomes version 2.

**Tech Stack:** Rails 8.1.2, Ruby 3.2.8, Reform, Trailblazer, ViewComponent, Stimulus, RSpec, Vitest, SQLite `json_extract`.

**Spec:** `docs/2026-10-23-entity-references-display-lifecycle-design.md`. This plan covers §3.1–§3.9, §7 and the Plan 1 rows of §8–§10.

**Sibling plans:**

- `docs/2026-10-23-entity-references-plan-2-display.md` (derived values and display)
- `docs/2026-10-23-entity-references-plan-3-forms.md` (form lifecycle)

Both build on this plan. Once this plan is in the working tree, the two can run in parallel.

## Global Constraints

- No hard-coded user-facing strings.
  - Every new key goes into the matching `en` and `zh-CN` area file, with the exact text from spec §8.
  - Stimulus text arrives through Values with an English `default:`. Placeholders and labels in this plan are rendered server-side in ERB.
- No backward-compatibility shims. `value_field` is removed outright: there is no alias, no fallback, and no data migration.
- Do NOT run `git commit`. Leave changes in the working tree. `git add -N <new file>` is allowed.
- Only edit files your task owns (see the table below). If a file outside your task needs a change, stop and report it.
- Ignore `app/services/page_layout_templates/templates/**`.
- RSpec isolation: each task uses its own database, `TEST_ENV_NUMBER=<20 + task number>`. Prepare it once with `RAILS_ENV=test TEST_ENV_NUMBER=<n> bin/rails db:schema:load`, then run `TEST_ENV_NUMBER=<n> bundle exec rspec <files>`.
- Vitest: `npx vitest run --config config/javascript/vitest.config.js <spec files>`.
  - For coverage, add `--coverage --coverage.include=<app file> --coverage.reporter=text`. Touched files must show 100% lines, branches and functions.
  - Never add `/* v8 ignore */`.
- Never claim tests pass without pasting the real command output.
- Subagents inherit the parent model: omit `model` (or pass `inherit`).
- Docs change in the same plan. Task 12 owns every `doc/reference/**` edit for Plan 1.
- Locale parity: every task that edits a locale pair runs this check, which must print nothing and exit 0. Define it once per shell:

```bash
locale_parity() { for stem in "$@"; do ruby -ryaml -e 'stem=ARGV[0]; f=->(h,p=[]){h.flat_map{|k,v| v.is_a?(Hash) ? f.(v,p+[k]) : [(p+[k]).join(".")]}}; en=f.(YAML.load_file("config/locales/#{stem}.en.yml", aliases: true)["en"]); zh=f.(YAML.load_file("config/locales/#{stem}.zh-CN.yml", aliases: true)["zh-CN"]); d=(en-zh)+(zh-en); puts(d); exit(d.empty? ? 0 : 1)' "$stem" || return 1; done; }
```

## Waves and file ownership

Tasks in one wave run in parallel. A wave starts only when the previous one has finished.

| Wave | Task | Agent | Owns |
|---|---|---|---|
| 1 | T1 Reference labels and options | anysys-backend-developer | `app/services/entities/reference_{labels,options}.rb`, their specs, `config/locales/common.{en,zh-CN}.yml` |
| 1 | T2 Assistant contract version 2 | anysys-backend-developer | `app/services/operations/schemas/{entity.defs,update_entity}.json`, `app/services/operations/{create,update}_entity.rb`, `app/services/entity_definitions/{choice_list,persist,normalizer}.rb`, `app/services/entity_definitions/api/{mapper,semantic_validator}.rb`, `app/services/entity_definitions/assistant/change_plan.rb`, `app/models/concerns/bridge_entity_management.rb` (`bridge_property_schema` only), the three prompt documents, and the specs in T2's Files list |
| 1 | T3 Plan panel and sidebar | anysys-frontend-developer | `app/components/ai_assistant/proposed_changes_component.rb`, `app/views/admin/maintenance/pages/_field_sidebar_item.html.erb`, `config/locales/ai_assistant.{en,zh-CN}.yml`, `spec/components/ai_assistant/proposed_changes_component_spec.rb`, `spec/services/entity_definitions/assistant/plan_field_labels_spec.rb` |
| 1 | T4 Editor "Use Entity Records" | anysys-frontend-developer | `app/components/admin/maintenance/entities/attribute_modal_component.html.erb` and its spec, `app/javascript/controllers/entity_form_controller.js`, `app/javascript/controllers/entity_form/*.js`, `spec/javascript/controllers/entity_form/**`, `spec/javascript/controllers/entity_form_controller.test.js`, `config/locales/comp_admin.{en,zh-CN}.yml` |
| 1 | T5 Contract existence rule, bridge writer, `Page#input_fields` | anysys-backend-developer | `app/contracts/entity_entry_contract.rb`, `app/services/pages/bridge_entries.rb`, `app/models/concerns/page_configuration_helpers.rb`, `app/services/pages/form_params.rb`, `spec/contracts/entity_entry_contract_spec.rb`, `spec/services/pages/bridge_entries_spec.rb`, `spec/models/concerns/page_configuration_helpers_spec.rb` (new) |
| 2 | T6 Generated dropdowns and query lists | anysys-backend-developer | `app/services/page_content_generator/{form_fields,dynamic_options_resolver}.rb`, `app/services/page_field_populator.rb`, `spec/services/page_content_generator*_spec.rb`, `spec/services/page_content_generator/**`, `spec/services/page_field_populator_spec.rb`, `spec/requests/admin/page_forms_spec.rb`, `spec/requests/public_pages_tenant_audience_spec.rb` |
| 2 | T8 Create Entry references | anysys-backend-developer | `app/services/entities/entry_form.rb`, `spec/services/entities/entry_form_spec.rb`, `spec/requests/admin/entity_entry_creation_spec.rb` (the Create Entry section) |
| 3 | T7 Controllers | anysys-security-engineer | `app/controllers/admin/maintenance/page_field_options_controller.rb`, `app/controllers/admin/entity_entries_controller.rb` (`quick_add_label`), `app/controllers/admin/maintenance/entities_controller.rb` (index JSON), `spec/requests/admin/maintenance/page_field_options_spec.rb`, `spec/requests/admin/entity_entry_creation_spec.rb` (the quick-add section), `spec/requests/admin/maintenance/entities_reference_targets_spec.rb` (new) |
| 4 | T9 Reference definition rules and fixture sweep | anysys-backend-developer | `app/models/concerns/entity_schema_validation.rb`, `config/locales/maint_core.{en,zh-CN}.yml`, `spec/models/concerns/entity_reference_definitions_spec.rb` (new), every spec file the sweep touches |
| 5 | T10 Dependents, trash guard, save guard | anysys-backend-developer | `app/services/entities/reference_dependents.rb` and its spec, `app/models/concerns/bridge_entity_management.rb` (`soft_delete`), `app/models/concerns/entity_schema_validation.rb`, `config/locales/maint_core.{en,zh-CN}.yml`, `spec/models/concerns/entity_reference_guards_spec.rb` (new) |
| 6 | T11 Assistant reference violations | anysys-backend-developer | `app/services/entity_definitions/api/semantic_validator.rb`, `config/locales/operations_entity.{en,zh-CN}.yml`, `spec/services/entity_definitions/api/semantic_validator_spec.rb`, `spec/services/operations/update_entity_spec.rb` |
| 6 | T12 Plan 1 docs | anysys-backend-developer | `doc/reference/{en,zh-CN}/{entity-builder,page-rendering,flowchart-runtime,operations-api}.md` |
| 7 | T13 Verification | anysys-release-engineer | nothing (runs commands only) |

Why the waves are ordered this way:

- T9 adds a definition rule that rejects any dropdown or association whose display field isn't labelable. Every spec that saves such a definition must change, so T9 runs after every task that owns one of those spec files.
- T10 and T11 read T9's rules and T10's service.
- Some spec files belong to tasks in different waves. That is safe, because each wave starts only when the previous one has finished:
  - `spec/services/operations/update_entity_spec.rb`: T2 changes the version assertions, T9 sweeps its fixtures, and T11 adds examples.
  - `spec/requests/admin/entity_entry_creation_spec.rb`: T8 edits the Create Entry section, T7 the quick-add section, and T9 sweeps its fixtures.

## Spec coverage

| Spec | Task |
|---|---|
| §3.1 Stored value is the record id; `value_field` removed | T2, T3, T6, T7 |
| §3.2 Labels, fallbacks, duplicates, visibility, limit | T1, T6, T7 |
| §3.3 Entry contract existence rule; bridge writer delegates to the contract | T5 |
| §3.4 Create Entry supports references | T8 |
| §3.5 Reference launch check | Plan 3 T2 (needs Plan 3's launch-check lookup) |
| §3.6 Definition rules (target, label field, association display field) | T9 |
| §3.7 Trash guard | T10 |
| §3.8 Editor "Use Entity Records" | T4, T7 (the `labelable` flag) |
| §3.9 Display-field save guard (model and assistant) | T10, T11 |
| §7 Assistant instructions | T2 (all except `seats_remaining`, which Plan 2 adds) |
| §8 Plan 1 keys | T1, T4, T9, T10, T11 |
| §9 Plan 1 docs | T12 |
| §10 Plan 1 tests | each task, then T13 |

Three clarifications of the spec, applied in this plan:

- **"Use Entity Records" covers select and radio only.** §3.8 says "select, radio and multi-select", but entity attributes have no multi-select HTML type (`HtmlTypeOptions::SELECTION_TYPES` is `select radio checkbox`). The editor therefore offers the mode for select and radio. A checkbox reference stays a Create Entry blocker (T8).
- **`seats_remaining` moves to Plan 2.** That example reads a computed field, which only resolves once Plan 2's derived-value ordering lands, so Plan 2 adds it.
- **The emergency-contact example hides its personal fields too.** It adds a name, a relationship and a phone to Student. Those fields also get `access.visible_to` hiding them from members and the public, so the example agrees with the §7 personal-fields rule.

Later rules must not break earlier fixtures. Fixtures in T1–T8 use only labelable display fields and real targets, so T9's definition rule accepts them. None of them trashes an entity that another entity references, so T10's trash guard leaves them alone.

---

### Task 1: Reference labels and options

**Agent:** anysys-backend-developer

**Files:**
- Create: `app/services/entities/reference_labels.rb`
- Create: `app/services/entities/reference_options.rb`
- Create: `spec/services/entities/reference_labels_spec.rb`
- Create: `spec/services/entities/reference_options_spec.rb`
- Modify: `config/locales/common.en.yml`, `config/locales/common.zh-CN.yml`

**Interfaces:**
- Consumes:
  - `EntityAttributeAudience.visible_to?(attribute, audience)`
  - `Entity#resolved_current_version(customer_id)`
  - `Entity.non_bridge`
  - Entity's default `visible` scope, which excludes trashed rows.
- Produces:
  - `Entities::ReferenceLabels`:
    - constants `OPTIONS_SOURCE` and `LABEL_HTML_TYPES`;
    - `labelable?(attribute)` and `reference?(attribute)`;
    - `text(raw, id)`, `missing(id)`, `numbered(label, id)` and `disambiguate(pairs)`.
  - `Entities::ReferenceOptions`:
    - `.call(entity_id:, label_field:, customer_id:, audience:, limit: 200)` returns `Array<[String label, String id]>`;
    - instance methods `#target`, `#usable?`, `#options` and `#label_taken?(label, except_id:)`.

- [ ] **Step 1: Prepare the test database**

Run: `RAILS_ENV=test TEST_ENV_NUMBER=21 bin/rails db:schema:load`
Expected: exits 0.

- [ ] **Step 2: Write the failing label spec**

Create `spec/services/entities/reference_labels_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Entities::ReferenceLabels do
  describe ".labelable?" do
    it "accepts input attributes of the label html types, defaulting to text" do
      %w[text search email tel url number date].each do |html_type|
        expect(described_class.labelable?("name_slug" => "a", "html_type" => html_type)).to be(true)
      end
      expect(described_class.labelable?("name_slug" => "a")).to be(true)
    end

    it "rejects derived and reference attributes, other html types and non-hashes" do
      expect(described_class.labelable?("html_type" => "number", "type" => "Calculated")).to be(false)
      expect(described_class.labelable?("html_type" => "number", "type" => Entity::COMPUTED_TYPE)).to be(false)
      expect(described_class.labelable?("html_type" => "number", "storage" => "computed")).to be(false)
      expect(described_class.labelable?("html_type" => "select", "type" => Entity::ENTITY_REFERENCE_TYPE)).to be(false)
      %w[textarea select radio checkbox password file].each do |html_type|
        expect(described_class.labelable?("html_type" => html_type)).to be(false)
      end
      expect(described_class.labelable?(nil)).to be(false)
    end
  end

  describe ".reference?" do
    it "is true only for an entity_entries options source" do
      expect(described_class.reference?("config" => { "options_source" => "entity_entries" })).to be(true)
      expect(described_class.reference?("config" => { "source" => "manual" })).to be(false)
      expect(described_class.reference?("config" => nil)).to be(false)
      expect(described_class.reference?(nil)).to be(false)
    end
  end

  describe "label text" do
    it "trims labels, falls back to Untitled and names missing records" do
      expect(described_class.text(" Ada ", 7)).to eq("Ada")
      expect(described_class.text(nil, 7)).to eq("Untitled (#7)")
      expect(described_class.missing(7)).to eq("Missing record (#7)")
      expect(described_class.numbered("001", 26)).to eq("001 (#26)")
    end

    it "uses the zh-CN wording" do
      I18n.with_locale(:"zh-CN") do
        expect(described_class.text("", 7)).to eq("未命名（#7）")
        expect(described_class.missing(7)).to eq("记录不存在（#7）")
        expect(described_class.numbered("001", 26)).to eq("001（#26）")
      end
    end
  end

  describe ".disambiguate" do
    it "numbers every repeated label after trimming and leaves unique labels alone" do
      pairs = [["001", 26], ["Ann", 27], ["001 ", 31]]

      expect(described_class.disambiguate(pairs)).to eq([["001 (#26)", 26], ["Ann", 27], ["001 (#31)", 31]])
    end
  end
end
```

- [ ] **Step 3: Write the failing options spec**

Create `spec/services/entities/reference_options_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Entities::ReferenceOptions do
  let_it_be(:customer) { create(:customer) }
  let_it_be(:other_customer) { create(:customer) }

  let(:admin_only) { { "admin" => true, "member" => false, "public" => false } }
  let(:schema) do
    [
      { "name" => "Code", "name_slug" => "code", "html_type" => "text" },
      { "name" => "Bio", "name_slug" => "bio", "html_type" => "textarea" },
      { "name" => "Phone", "name_slug" => "phone", "html_type" => "tel", "visibility" => admin_only }
    ]
  end
  let(:student) { create(:entity, customer: customer, name: "Student", property_schema: schema.to_json) }

  def entry(data, owner: customer, entity: student)
    create(:entity_entry, customer: owner, entity: entity, data: data.to_json)
  end

  def options(**overrides)
    described_class.call(entity_id: student.id, label_field: "code", customer_id: customer.id,
                         audience: EntityAttributeAudience::PUBLIC, **overrides)
  end

  it "lists [label, id] pairs ordered by label, case-insensitively, then by id" do
    beta = entry("code" => "beta")
    alpha = entry("code" => "Alpha")
    blank = entry("code" => "  ")

    expect(options).to eq([
      ["Untitled (##{blank.id})", blank.id.to_s],
      ["Alpha", alpha.id.to_s],
      ["beta", beta.id.to_s]
    ])
  end

  it "numbers labels that repeat and leaves unique ones alone" do
    first = entry("code" => "001")
    other = entry("code" => "002")
    second = entry("code" => "001")

    expect(options).to eq([
      ["001 (##{first.id})", first.id.to_s],
      ["001 (##{second.id})", second.id.to_s],
      ["002", other.id.to_s]
    ])
  end

  it "lists only the tenant's records" do
    mine = entry("code" => "A")
    entry({ "code" => "B" }, owner: other_customer)

    expect(options.map(&:last)).to eq([mine.id.to_s])
  end

  it "lists nothing when the display field is hidden, not labelable, unknown, id or not a slug" do
    entry("code" => "A", "bio" => "x", "phone" => "555")

    expect(options(label_field: "phone")).to eq([])
    expect(options(label_field: "phone", audience: EntityAttributeAudience::ADMIN).size).to eq(1)
    expect(options(label_field: "bio", audience: EntityAttributeAudience::ADMIN)).to eq([])
    expect(options(label_field: "nope")).to eq([])
    expect(options(label_field: "id")).to eq([])
    expect(options(label_field: "code\"; DROP")).to eq([])
  end

  it "lists nothing for a foreign, bridge, trashed or malformed target" do
    foreign = create(:entity, customer: other_customer, property_schema: schema.to_json)
    bridge = create(:entity, customer: customer, category: :bridge, property_schema: schema.to_json)
    entry("code" => "A")

    expect(options(entity_id: foreign.id)).to eq([])
    expect(options(entity_id: bridge.id)).to eq([])
    expect(options(entity_id: "abc")).to eq([])
    expect(options(customer_id: nil)).to eq([])

    student.soft_delete
    expect(options).to eq([])
  end

  it "reads a shared target's display field through the tenant's override" do
    shared = Current.set(shared_resources_mode: true) { create(:entity, :shared, name: "Campus", property_schema: schema.to_json) }
    hidden = schema.map { |attr| attr["name_slug"] == "code" ? attr.merge("visibility" => admin_only) : attr }
    Current.set(customer: customer) { Entity.find(shared.id).update!(property_schema: hidden.to_json) }
    entry({ "code" => "North" }, entity: shared)
    entry({ "code" => "South" }, owner: other_customer, entity: shared)

    expect(options(entity_id: shared.id)).to eq([])
    expect(options(entity_id: shared.id, customer_id: other_customer.id).map(&:first)).to eq(["South"])
  end

  it "caps the list at the limit" do
    3.times { |index| entry("code" => "C#{index}") }

    expect(options(limit: 2).size).to eq(2)
  end

  describe "#usable? and #label_taken?" do
    let(:source) do
      described_class.new(entity_id: student.id, label_field: "code", customer_id: customer.id,
                          audience: EntityAttributeAudience::ADMIN)
    end

    it "says whether the display field can label choices" do
      expect(source).to be_usable
      expect(source.target).to eq(student)
      expect(described_class.new(entity_id: student.id, label_field: "bio", customer_id: customer.id,
                                 audience: EntityAttributeAudience::ADMIN)).not_to be_usable
    end

    it "says whether another record already shows a label" do
      taken = entry("code" => "001")

      expect(source.label_taken?(" 001 ", except_id: 0)).to be(true)
      expect(source.label_taken?("001", except_id: taken.id)).to be(false)
      expect(source.label_taken?("", except_id: 0)).to be(false)
    end
  end
end
```

- [ ] **Step 4: Run both specs to verify they fail**

Run: `TEST_ENV_NUMBER=21 bundle exec rspec spec/services/entities/reference_labels_spec.rb spec/services/entities/reference_options_spec.rb`
Expected: FAIL with `uninitialized constant Entities::ReferenceLabels` and `uninitialized constant Entities::ReferenceOptions`.

- [ ] **Step 5: Add the `common.references` keys**

In `config/locales/common.en.yml`, add this block under `en.common`, as a sibling of `errors:` at the same indentation:

```yaml
    references:
      untitled: "Untitled (#%{id})"
      missing: "Missing record (#%{id})"
      duplicate: "%{label} (#%{id})"
      field_path: "%{entity} › %{field}"
```

In `config/locales/common.zh-CN.yml`, add the same keys at the same position under `zh-CN.common`:

```yaml
    references:
      untitled: "未命名（#%{id}）"
      missing: "记录不存在（#%{id}）"
      duplicate: "%{label}（#%{id}）"
      field_path: "%{entity} › %{field}"
```

- [ ] **Step 6: Implement `Entities::ReferenceLabels`**

Create `app/services/entities/reference_labels.rb`:

```ruby
# frozen_string_literal: true

module Entities
  # The one rule for showing a reference: which attributes may label it and
  # how a label reads when the record is unnamed, missing or not unique.
  module ReferenceLabels
    OPTIONS_SOURCE = EntityDefinitions::Capabilities::ENTITY_ENTRIES_OPTIONS_SOURCE
    LABEL_HTML_TYPES = %w[text search email tel url number date].freeze
    UNLABELABLE_TYPES = [Entity::COMPUTED_TYPE, "Calculated", Entity::ENTITY_REFERENCE_TYPE].freeze

    module_function

    # A stored input attribute whose value reads as a name: no derived or
    # reference fields, no free text, choices, secrets or files.
    def labelable?(attribute)
      return false unless attribute.is_a?(Hash)
      return false if UNLABELABLE_TYPES.include?(attribute["type"]) || attribute["storage"] == "computed"

      LABEL_HTML_TYPES.include?(attribute["html_type"].presence || "text")
    end

    def reference?(attribute)
      attribute.is_a?(Hash) && attribute["config"].is_a?(Hash) && attribute["config"]["options_source"] == OPTIONS_SOURCE
    end

    def text(raw_label, id)
      label = raw_label.to_s.strip
      label.empty? ? I18n.t("common.references.untitled", id: id) : label
    end

    def missing(id)
      I18n.t("common.references.missing", id: id)
    end

    def numbered(label, id)
      I18n.t("common.references.duplicate", label: label, id: id)
    end

    # [[label, id], ...] with every repeated label numbered by its id.
    def disambiguate(pairs)
      counts = pairs.map { |label, _id| label.to_s.strip }.tally
      pairs.map do |label, id|
        text = label.to_s.strip
        counts[text] > 1 ? [numbered(text, id), id] : [label, id]
      end
    end
  end
end
```

- [ ] **Step 7: Implement `Entities::ReferenceOptions`**

Create `app/services/entities/reference_options.rb`:

```ruby
# frozen_string_literal: true

module Entities
  # The choices of a reference dropdown: [label, id string] pairs for the
  # target entity's records in one tenant, labelled by the display field as
  # that tenant's definition has it. A configuration that cannot produce
  # labels lists nothing; nothing here raises on bad configuration.
  class ReferenceOptions
    DEFAULT_LIMIT = 200
    ID = /\A\d+\z/
    SLUG = /\A\w+\z/

    def self.call(...) = new(...).options

    def initialize(entity_id:, label_field:, customer_id:, audience:, limit: DEFAULT_LIMIT)
      @entity_id = entity_id.to_s
      @label_field = label_field.to_s
      @customer_id = customer_id
      @audience = audience
      @limit = limit.to_i
    end

    # The tenant's own or a shared entity that is neither trashed nor a bridge.
    def target
      return @target if defined?(@target)

      @target = if @customer_id.present? && @entity_id.match?(ID)
        Entity.where(customer_id: [@customer_id, nil]).non_bridge.find_by(id: @entity_id)
      end
    end

    # The display field exists for the tenant, can label a reference, and is
    # visible to the audience.
    def usable?
      attribute = label_attribute
      ReferenceLabels.labelable?(attribute) && EntityAttributeAudience.visible_to?(attribute, @audience)
    end

    def options
      return [] unless usable?

      pairs = entries.order(Arel.sql("LOWER(CAST(#{label_sql} AS TEXT))"), :id)
                     .limit(@limit)
                     .pluck(:id, Arel.sql(label_sql))
                     .map { |id, raw| [ReferenceLabels.text(raw, id), id.to_s] }
      ReferenceLabels.disambiguate(pairs)
    rescue ActiveRecord::StatementInvalid
      []
    end

    # Whether a record other than `except_id` already shows this label.
    def label_taken?(label, except_id:)
      text = label.to_s.strip
      return false if text.empty? || !usable?

      entries.where.not(id: except_id).where("TRIM(CAST(#{label_sql} AS TEXT)) = ?", text).exists?
    end

    private

    def entries
      EntityEntry.where(customer_id: @customer_id, entity_id: target.id)
    end

    # Only reached through #usable?, so the slug matched a schema attribute
    # and the SLUG format; quoting keeps the JSON path a literal regardless.
    def label_sql
      "json_extract(entity_entries.data, #{EntityEntry.connection.quote("$.\"#{@label_field}\"")})"
    end

    def label_attribute
      return @label_attribute if defined?(@label_attribute)

      @label_attribute = (find_label_attribute if target && @label_field.match?(SLUG))
    end

    def find_label_attribute
      payload = target.resolved_current_version(@customer_id)&.content&.payload
      schema = payload.present? ? Array(JSON.parse(payload)["property_schema"]) : []
      schema.find { |attribute| attribute.is_a?(Hash) && attribute["name_slug"].to_s == @label_field }
    rescue JSON::ParserError
      nil
    end
  end
end
```

- [ ] **Step 8: Run the specs and the locale check**

Run: `TEST_ENV_NUMBER=21 bundle exec rspec spec/services/entities/reference_labels_spec.rb spec/services/entities/reference_options_spec.rb && locale_parity common`
Expected: all examples pass, and `locale_parity` prints nothing.

If the shared-override example fails while creating the shared row, compare with how `spec/factories/entities.rb`'s `:shared` trait is used elsewhere (`rg -n ":shared" spec/models`) and copy that setup. Keep the override write inside `Current.set(customer: customer)`.

- [ ] **Step 9: Leave the changes uncommitted**

Run: `git add -N app/services/entities/reference_labels.rb app/services/entities/reference_options.rb spec/services/entities/reference_labels_spec.rb spec/services/entities/reference_options_spec.rb && git status --short`
Expected: the four new files and both locale files are listed. Do not commit.

---

### Task 2: Assistant contract version 2

**Agent:** anysys-backend-developer

**Files:**
- Modify:
  - `app/services/operations/schemas/entity.defs.json`
  - `app/services/operations/schemas/update_entity.json`
  - `app/services/operations/create_entity.rb`
  - `app/services/operations/update_entity.rb`
  - `app/services/entity_definitions/choice_list.rb`
  - `app/services/entity_definitions/persist.rb`
  - `app/services/entity_definitions/normalizer.rb`
  - `app/services/entity_definitions/api/mapper.rb`
  - `app/services/entity_definitions/api/semantic_validator.rb` (the `validate_options` field loop only)
  - `app/services/entity_definitions/assistant/change_plan.rb`
  - `app/models/concerns/bridge_entity_management.rb` (`bridge_property_schema` only)
- Modify prompt documents, all under `app/services/ai_assistant/assistant/prompt/documents/`: `entity_platform.md`, `entity_authoring.md` and `entity_examples.md`.
- Modify specs:
  - `spec/services/entity_definitions/choice_list_spec.rb`
  - `spec/services/entity_definitions/normalizer_spec.rb`
  - `spec/services/entity_definitions/catalog_spec.rb`
  - `spec/services/entity_definitions/api/mapper_spec.rb`
  - `spec/services/entity_definitions/assistant/change_plan_spec.rb`
  - `spec/services/operations/create_entity_spec.rb`
  - `spec/services/operations/update_entity_spec.rb` (the version assertions only)
  - `spec/services/operations/confirm_spec.rb` (only if it asserts `operation_version == 1`)

**Interfaces:**
- Produces:
  - `options.label_field` is required when `source` is `entity_entries`, and `options.value_field` no longer exists.
  - `create_entity` and `update_entity` are at version 2.
  - `ChoiceList::Source` has the members `options_source` and `entity_name`.
  - Stored `entity_entries` configs hold exactly `options_source`, `entity_id` and `label_field`.

- [ ] **Step 1: Prepare the test database**

Run: `RAILS_ENV=test TEST_ENV_NUMBER=22 bin/rails db:schema:load`

- [ ] **Step 2: Update `choice_list_spec.rb` to the new identity (failing)**

In `spec/services/entity_definitions/choice_list_spec.rb`, make these edits:

- In "reads the same source from either shape", remove `"value_field" => "id"` from the stored config, and replace `bound_to("Course", "value_field" => "id")` with `bound_to("Course")`.
- Delete the example "treats an omitted value_field as the field Persist would store".
- Replace "distinguishes a different entity and a different value field" with:

```ruby
    it "distinguishes a different entity" do
      expect(bound_to("Course")).not_to eq(bound_to("Program"))
    end

    it "has no value field: the stored value is always the record id" do
      expect(EntityDefinitions::ChoiceList::Source.members).to eq(%i[options_source entity_name])
    end
```

- [ ] **Step 3: Update the other value_field specs (failing)**

- `spec/services/entity_definitions/assistant/change_plan_spec.rb`:
  - Change the helper to `def entity_source(name) = { "kind" => "entity", "entity_name" => name }`.
  - Delete the example "carries the value_field on both sides, so a change of key reads as one".
  - Remove every remaining `"value_field" => "id"` from the `bound_status!` and `status_update` fixtures (lines 762, 773, 789, 804, 812, 829 and 858).
- `spec/services/entity_definitions/api/mapper_spec.rb` (lines 194 and 202): remove `"value_field" => "id"` from the expected stored config and the expected API options.
- `spec/services/entity_definitions/normalizer_spec.rb` (lines 166 and 173): remove `"value_field" => "code"` from both the input and the expected output.
- `spec/services/entity_definitions/catalog_spec.rb` (line 50): remove `"value_field" => "id"`.
- `spec/services/operations/create_entity_spec.rb`:
  - Line 62: remove the `"value_field"` key from the input options.
  - Near line 112: replace the stored-config assertion with an exact match, `eq("options_source" => "entity_entries", "entity_id" => course.id.to_s, "label_field" => "title")`. Keep the spec's own receiver and variable names. Only the matcher changes.
  - Add two examples next to the spec's other validation examples, using its existing helpers for running the operation and for a minimal Course spec:
    1. An Application attribute with `"options" => { "source" => "entity_entries", "entity" => "Course" }` (no `label_field`) produces a violation with code `schema.required`.
    2. The same attribute with `"label_field" => "title", "value_field" => "code"` produces `schema.unknown_property`.
- In `spec/services/operations/update_entity_spec.rb` and `spec/services/operations/confirm_spec.rb`, change any `operation_version` assertion of `1` for these two operations to `2`. Find them with `rg -n "operation_version" spec/services/operations`.

Run: `TEST_ENV_NUMBER=22 bundle exec rspec spec/services/entity_definitions/choice_list_spec.rb spec/services/entity_definitions/assistant/change_plan_spec.rb spec/services/entity_definitions/api/mapper_spec.rb spec/services/entity_definitions/normalizer_spec.rb spec/services/entity_definitions/catalog_spec.rb spec/services/operations/create_entity_spec.rb`
Expected: FAIL. The failures come from the `value_field` assertions and the two new create examples.

- [ ] **Step 4: Change the schemas**

In `app/services/operations/schemas/entity.defs.json`, in `$defs.options.properties`:

- Replace the `label_field` description with: `"Slug of a human-readable attribute of that entity (text, search, email, tel, url, number or date) shown as the choice label. The stored value is always the record id."`
- Delete the whole `"value_field": { ... }` property, together with the comma before it.
- In `$defs.options.allOf`, change the entity_entries item to:

```json
        {
          "description": "source entity_entries requires entity and label_field.",
          "if": {
            "properties": {
              "source": {
                "const": "entity_entries",
                "description": "When source is entity_entries."
              }
            },
            "required": [
              "source"
            ]
          },
          "then": {
            "required": [
              "entity",
              "label_field"
            ]
          }
        }
```

In `$defs.optionsLite`:

- Apply the same `label_field` description and delete `value_field`.
- After `"properties": { ... }`, add an `"allOf": [ ... ]` containing exactly the item above. `optionsLite` currently has no `allOf`. The projected schemas measured 25,020 bytes (`create_entity`) and 26,633 bytes (`update_entity`) against the 32,000-byte budget, so this fits.

In `$defs.association.properties.display_field`, set the description to: `"Slug of a human-readable attribute of the related entity (text, search, email, tel, url, number or date) used as the label of each linked record."`

In `$defs.associationPatch.properties.display_field`, set the description to: `"Replacement display-field slug. The same type rule applies."`

In `app/services/operations/schemas/update_entity.json`:

- Line 203 (`options` description) becomes: `"Replacement choice list {source, values?, constant?, entity?, label_field?}. Null clears. Arrays/objects replace wholesale."`
- The association `display_field` description near line 307 becomes the same association text as in `entity.defs.json`.

- [ ] **Step 5: Bump both operation versions**

In `app/services/operations/create_entity.rb` and `app/services/operations/update_entity.rb`, change `version 1` to `version 2`.

- [ ] **Step 6: Remove `value_field` from the write path**

`app/services/entity_definitions/choice_list.rb`:

- Delete the `DEFAULT_FIELD` constant and its comment.
- Replace the `Source` comment and struct with:

```ruby
    # What list an attribute reads, independent of the shape it arrived in.
    # An entity binding always stores the record id; `label_field` is display
    # only and is deliberately absent.
    Source = Struct.new(:options_source, :entity_name, keyword_init: true)
```

- In `source_of`, remove the `value_field:` argument and the sentence about `value_field` in its comment.

`app/services/entity_definitions/persist.rb`, `resolved_option_source`: the merge becomes:

```ruby
        config.except(ChoiceList::ENTITY_NAME_KEY, "options").merge(
          "options_source" => Capabilities::ENTITY_ENTRIES_OPTIONS_SOURCE,
          ChoiceList::ENTITY_ID_KEY => target.id.to_s
        )
```

`label_field` now comes through `config` unchanged: the schema requires it, and the Mapper copies it.

`app/services/entity_definitions/api/mapper.rb`:

- Remove `value_field` from `SELECTION_CONFIG_KEYS`.
- Delete the `config["value_field"] = ...` line in `entity_entries_config`.
- Delete the `options["value_field"] = ...` line in `options_from_config`.

`app/services/entity_definitions/normalizer.rb`: remove `value_field` from `INPUT_CONFIG_KEYS`.

`app/services/entity_definitions/assistant/change_plan.rb`:

- `SOURCE_CONFIG_KEYS` becomes `%w[options options_source options_entity_name entity_id].freeze`.
- `source_value` returns `{ "kind" => "entity", "entity_name" => source.entity_name }` for a bound source.
- `predicted_config` becomes:

```ruby
      def predicted_config(config)
        return config if config[ChoiceList::ENTITY_NAME_KEY].blank?

        config.merge("options_source" => Capabilities::ENTITY_ENTRIES_OPTIONS_SOURCE)
      end
```

- Rewrite three comments so none of them mentions `value_field` or a defaulted `label_field`:
  - the `rebound_rows` comment (around line 475);
  - the comment above `source_of` (around line 505);
  - the comment above `predicted_config` (around line 530). It should say the write adds `options_source` and resolves the name to an id.

`app/services/entity_definitions/api/semantic_validator.rb`, `validate_options`: replace `%w[label_field value_field].each do |field| ... end` with:

```ruby
          value = options["label_field"]
          if value.present? && !lookup_field?(target, value)
            add(attr_pointer(attr, "options", "label_field"), "options.field_not_found", "field" => value, "entity" => target)
          end
```

Task 11 later replaces this check with the labelable rule.

- [ ] **Step 7: Bridge schema reads the display field as given**

In `app/models/concerns/bridge_entity_management.rb`, `bridge_property_schema`:

- Change the first two locals to:

```ruby
    display_field       = assoc["display_field"].to_s.strip
    display_field_label = assoc["display_field_label"].presence || display_field
```

- Delete `"value_field" => "id"` from the target reference's `config`, together with the trailing comma on the line before it.

`validate_association_display_field_present` already rejects a blank display field, so there is no `id` fallback.

- [ ] **Step 8: Update the prompt documents (§7)**

`entity_platform.md`, the **Entries** bullet (lines 7–8) becomes:

```markdown
- **Entries.** Admins create, view and delete records of the entity under
  `Modules / <entity>`; editing entries isn't available yet. Each attribute becomes a stored field on the entry.
```

and the **Forms** bullet (lines 9–10) becomes:

```markdown
- **Forms.** `attributes` render the entry form. `html_type` picks the input control,
  `description` becomes the field's help text on generated forms and on Create Entry, and `display_label` overrides the visible label.
```

`entity_authoring.md`:

- After line 52 (`Keep internal fields off member and public surfaces with `access.visible_to`.`), add:

```markdown
Visibility applies to every record of an entity, and a dropdown lists its display field for every record to
everyone who can open the form. Unless the admin asks otherwise, hide fields that identify or describe a
person (names, ID numbers, birth dates, contact details, addresses) from members and the public, and keep
grades, scores and staff notes admin-only.
```

- Lines 78–79 become:

```markdown
- Use `options.source: "static"` with `values`, or `constant` with a `constant` name, or
  `entity_entries` with `entity` and `label_field`. An `entity_entries` dropdown always saves the record id;
  `label_field` must name a human-readable attribute of that entity (text, search, email, tel, url, number or
  date), such as a name, title or code — never `id`.
```

- Line 96 (the `associations` bullet) becomes:

```markdown
- Model a genuine many-to-many with `associations`. The server creates the bridge; data that belongs
  to the link itself — grade, quantity, rate, joined-on date — goes in `bridge_attributes`. Set
  `display_field` to a human-readable attribute of the related entity under the same type rule, never `id`.
```

- After the `entity_entries` pick-one bullet (line 98), add:

```markdown
- A field that other entities display can't be deleted, retyped, or hidden from a launched form that shows it.
  Change the display field on the referencing entity first.
```

`entity_examples.md`:

- Replace line 13 (the Student `create_entity` call) with exactly this line:

```json
{"tool":"create_entity","arguments":{"entities":[{"name":"Student","display_label":"Student","description":"A person enrolled at the institution","attribute_groups":[{"key":"identity","name":"Identity","icon":"user","color":"indigo"},{"key":"contact","name":"Contact","icon":"mail","color":"sky"},{"key":"address","name":"Address","icon":"map-pin","color":"teal"},{"key":"enrollment","name":"Enrolment","icon":"calendar","color":"amber"},{"key":"internal","name":"Internal","icon":"settings","color":"slate"}],"attributes":[{"name":"Student ID","slug":"student_id","html_type":"text","description":"Institution-issued reference.","group":"identity","rules":[{"type":"presence"},{"type":"length_maximum","value":32}],"access":{"visible_to":{"member":false,"public":false}}},{"name":"First name","slug":"first_name","html_type":"text","group":"identity","rules":[{"type":"presence"}],"access":{"visible_to":{"member":false,"public":false}}},{"name":"Last name","slug":"last_name","html_type":"text","group":"identity","rules":[{"type":"presence"}],"access":{"visible_to":{"member":false,"public":false}}},{"name":"Date of birth","slug":"date_of_birth","html_type":"date","group":"identity","access":{"visible_to":{"member":false,"public":false}}},{"name":"Email","slug":"email","html_type":"email","group":"contact","rules":[{"type":"presence"},{"type":"format_email"}],"access":{"visible_to":{"member":false,"public":false}}},{"name":"Phone","slug":"phone","html_type":"tel","group":"contact","rules":[{"type":"format_phone"}],"access":{"visible_to":{"member":false,"public":false}}},{"name":"Street","slug":"street","html_type":"text","group":"address","access":{"visible_to":{"member":false,"public":false}}},{"name":"City","slug":"city","html_type":"text","group":"address","access":{"visible_to":{"member":false,"public":false}}},{"name":"Postal code","slug":"postal_code","html_type":"text","group":"address","access":{"visible_to":{"member":false,"public":false}}},{"name":"Country","slug":"country","html_type":"select","group":"address","options":{"source":"static","values":["Australia","Canada","China","Singapore","United Kingdom","United States"]},"access":{"visible_to":{"member":false,"public":false}}},{"name":"Enrollment date","slug":"enrollment_date","html_type":"date","group":"enrollment","rules":[{"type":"presence"}]},{"name":"Status","slug":"status","html_type":"select","description":"Where the student sits in the enrolment lifecycle.","group":"enrollment","options":{"source":"static","values":["Applied","Enrolled","On leave","Graduated","Withdrawn"]},"rules":[{"type":"presence"}]},{"name":"Programme","slug":"programme","html_type":"text","group":"enrollment"},{"name":"Internal notes","slug":"internal_notes","html_type":"textarea","description":"Staff-only; never shown to members or the public.","group":"internal","access":{"visible_to":{"admin":true,"member":false,"public":false}}}],"settings":{"default_values":{"status":"Applied"}}}]}}
```

- Line 17 (the Student reply): append `"Personal details are visible to admins only."` to `assumptions`, so the array ends `...,"Internal notes are visible to admins only.","Personal details are visible to admins only."]`.
- Replace line 26 (the Course `create_entity` call) with exactly this line:

```json
{"tool":"create_entity","arguments":{"entities":[{"name":"Course","display_label":"Course","attribute_groups":[{"key":"identity","name":"Identity","icon":"tag","color":"indigo"},{"key":"delivery","name":"Delivery","icon":"calendar","color":"sky"},{"key":"capacity","name":"Capacity","icon":"briefcase","color":"emerald"}],"attributes":[{"name":"Code","slug":"code","html_type":"text","group":"identity","rules":[{"type":"presence"}]},{"name":"Title","slug":"title","html_type":"text","group":"identity","rules":[{"type":"presence"}]},{"name":"Description","slug":"description","html_type":"textarea","group":"identity"},{"name":"Delivery mode","slug":"delivery_mode","html_type":"radio","group":"delivery","options":{"source":"static","values":["In person","Online","Hybrid"]}},{"name":"Starts on","slug":"starts_on","html_type":"date","group":"delivery"},{"name":"Ends on","slug":"ends_on","html_type":"date","group":"delivery"},{"name":"Credits","slug":"credits","html_type":"number","group":"capacity","rules":[{"type":"numericality_integer"},{"type":"greater_than","value":0}]},{"name":"Seats","slug":"seats","html_type":"number","description":"Maximum enrolments.","group":"capacity","rules":[{"type":"numericality_integer"}]},{"name":"Enrolled students","slug":"enrolled_students","kind":"computed","html_type":"number","group":"capacity","aggregate":{"related_entity":"Student","function":"count","filter":{"attribute":"status","operator":"=","value":"Enrolled"}}}],"associations":[{"related_entity":"Student","display_field":"student_id","display_field_label":"Student ID","bridge_attributes":[{"name":"Enrolled on","slug":"enrolled_on","html_type":"date"},{"name":"Status","slug":"status","html_type":"select","options":{"source":"static","values":["Enrolled","Waitlisted","Dropped","Completed"]},"rules":[{"type":"presence"}]},{"name":"Grade","slug":"grade","html_type":"number","description":"Percentage, 0–100.","rules":[{"type":"numericality"},{"type":"greater_than_or_equal_to","value":0},{"type":"less_than_or_equal_to","value":100}],"access":{"visible_to":{"member":false,"public":false}}}]}]}]}}
```

- Line 30 (the Course reply) becomes:

```json
{"intent":"chat","reply":"Created Course and linked it to Student through an enrolment that records the enrolment date, a status (Enrolled, Waitlisted, Dropped or Completed) and an admin-only grade. Enrolled students counts only enrolled rows."}
```

- Line 39 (the Application `update_entity` call): change `"options":{"source":"entity_entries","entity":"Course","label_field":"title","value_field":"code"}` to `"options":{"source":"entity_entries","entity":"Course","label_field":"title"}`.
- Line 84 (the emergency-contact `update_entity` call) gets three edits:
  - `"slug":"emergency_contact_name","html_type":"text","group":"emergency"}` becomes `"slug":"emergency_contact_name","html_type":"text","group":"emergency","access":{"visible_to":{"member":false,"public":false}}}`.
  - `"values":["Parent","Guardian","Spouse","Sibling","Friend","Other"]}}` becomes `"values":["Parent","Guardian","Spouse","Sibling","Friend","Other"]},"access":{"visible_to":{"member":false,"public":false}}}`.
  - `"rules":[{"type":"format_phone"}]}}]}]}}` becomes `"rules":[{"type":"format_phone"}],"access":{"visible_to":{"member":false,"public":false}}}}]}]}}`.

- [ ] **Step 9: Run the task's specs, the contract lint and the prompt contract**

Run: `TEST_ENV_NUMBER=22 bundle exec rspec spec/services/entity_definitions spec/services/operations spec/services/ai_assistant/assistant/prompt spec/models/concerns/bridge_entity_management_spec.rb spec/models/entity_spec.rb`
Expected: all pass. That includes `contract_lint_spec` (lint plus the projection budget), `tool_examples_contract_spec`, and `operations/locales_spec`.

Then run: `rg -n "value_field|DEFAULT_FIELD" app/services/entity_definitions app/services/operations app/models app/services/ai_assistant`
Expected: no output.

- [ ] **Step 10: Leave the changes uncommitted**

Run: `git status --short`
Expected: only files from this task's list appear as modified by you. Do not commit.

---

### Task 3: Plan panel and page-builder sidebar drop `value_field`

**Agent:** anysys-frontend-developer

**Files:**
- Modify: `app/components/ai_assistant/proposed_changes_component.rb`
- Modify: `app/views/admin/maintenance/pages/_field_sidebar_item.html.erb`
- Modify: `config/locales/ai_assistant.en.yml`, `config/locales/ai_assistant.zh-CN.yml`
- Modify: `spec/components/ai_assistant/proposed_changes_component_spec.rb`
- Modify: `spec/services/entity_definitions/assistant/plan_field_labels_spec.rb`

**Interfaces:**
- Consumes: plan rows whose `options_source` values are `{ "kind" => "entity", "entity_name" => ... }`, as T2 produces them.
- Produces: no `value_field` wording anywhere in the plan panel or the sidebar.

- [ ] **Step 1: Prepare the test database**

Run: `RAILS_ENV=test TEST_ENV_NUMBER=23 bin/rails db:schema:load`

- [ ] **Step 2: Update the specs (failing)**

In `spec/components/ai_assistant/proposed_changes_component_spec.rb`:

- Near line 575, change the row's `after:` to `{ "kind" => "entity", "entity_name" => "Product" }`.
- Near line 580, change the expectation to `expect(page).to have_css("code", text: t("options_source.entity", entity: "Product"))`.
- Near line 1271, change `match_array(%i[static entity entity_field other])` to `match_array(%i[static entity other])`.

In `spec/services/entity_definitions/assistant/plan_field_labels_spec.rb`, near line 327, change `{ "kind" => "entity", "entity_name" => "Course", "value_field" => "code" }` to `{ "kind" => "entity", "entity_name" => "Course" }`.

Run: `TEST_ENV_NUMBER=23 bundle exec rspec spec/components/ai_assistant/proposed_changes_component_spec.rb spec/services/entity_definitions/assistant/plan_field_labels_spec.rb`
Expected: FAIL. The `options_source` key set still includes `entity_field`.

- [ ] **Step 3: Simplify the component**

In `app/components/ai_assistant/proposed_changes_component.rb`:

- Remove `value_field` from `CONFIG_FIELDS`.
- In `options_source_label`, replace the last four lines (from `field = value["value_field"]...` through the `entity_field` call) with `plan_t("options_source.entity", entity: entity)`.
- The method comment becomes: `` # `{"kind" => "static"}`, or an entity binding. "static" is an English word in the payload, not a label. ``

- [ ] **Step 4: Remove the dead keys from both locales**

- `config/locales/ai_assistant.en.yml`: delete `entity_field: "entries of %{entity} (%{field})"` (line 231) and `value_field: "value field"` (line 290).
- `config/locales/ai_assistant.zh-CN.yml`: delete `entity_field: "「%{entity}」的记录（%{field}）"` (line 229) and `value_field: "取值字段"` (line 288).

- [ ] **Step 5: Sidebar sends only the stored keys**

In `app/views/admin/maintenance/pages/_field_sidebar_item.html.erb` (line 20), change `.slice('options_source', 'entity_id', 'label_field', 'value_field')` to `.slice('options_source', 'entity_id', 'label_field')`.

- [ ] **Step 6: Run the specs and the locale check**

Run: `rg -l "field_sidebar_item" spec`. Then run `TEST_ENV_NUMBER=23 bundle exec rspec spec/components/ai_assistant/proposed_changes_component_spec.rb spec/services/entity_definitions/assistant/plan_field_labels_spec.rb <files rg listed> && locale_parity ai_assistant`.
Expected: all pass, and parity prints nothing.

- [ ] **Step 7: Leave the changes uncommitted**

Run: `git status --short`. Do not commit.

---

### Task 4: Entity editor "Use Entity Records"

**Agent:** anysys-frontend-developer

**Files:**
- Modify: `app/components/admin/maintenance/entities/attribute_modal_component.html.erb`
- Modify: `spec/components/admin/maintenance/entities/attribute_modal_component_spec.rb`
- Create: `app/javascript/controllers/entity_form/reference_manager.js`
- Modify:
  - `app/javascript/controllers/entity_form/{index,constants_manager,type_manager,modal_manager,attribute_manager,association_manager,validator_manager}.js`
  - `app/javascript/controllers/entity_form_controller.js`
- Create: `spec/javascript/controllers/entity_form/reference_manager.test.js`
- Modify:
  - `spec/javascript/controllers/entity_form/{index,constants_manager,type_manager,modal_manager,attribute_manager,association_manager,validator_manager}.test.js`
  - `spec/javascript/controllers/entity_form_controller.test.js`
- Modify: `config/locales/comp_admin.en.yml`, `config/locales/comp_admin.zh-CN.yml`

**Interfaces:**
- Consumes: `GET /:cid/admin/maintenance/entities.json`. Each item is `{ id, name, property_schema: [{ name, name_slug, labelable, ... }] }`; T7 adds `labelable`, and tests stub `fetch`.
- Consumes: the existing controller values `selectTargetEntityMsgValue` and `selectDisplayFieldMsgValue`. They are already passed by `app/views/admin/maintenance/entities/_form.html.erb`, so no view change is needed.
- Produces: the attribute config `{ options_source: "entity_entries", entity_id: "<id>", label_field: "<slug>" }` from `TypeManager#getConfigForType` while the mode is active.

- [ ] **Step 1: Consult shadcn for the segmented control and selects**

Call `plugin-shadcn-shadcn` `search_items_in_registries` for `toggle-group` and `select`, then `get_item_examples_from_registries` for `toggle-group-demo`.

Keep the existing three-button segmented control and the `input-field` selects. Use the example only to confirm:

- the button group keeps `role="group"` and an `aria-label`;
- labels sit above the selects;
- the group wraps to full width below `sm`.

Record the decision in your report. No new CSS.

- [ ] **Step 2: Add the editor keys**

In `config/locales/comp_admin.en.yml`, under `en.comp_admin.attribute_modal`, after `use_constant:` (line 30):

```yaml
      use_entity_records: "Use Entity Records"
      display_field: "Display field"
      entity_records_hint: "Saves the record's id. The dropdown lists the display field of every record to everyone who can open the form."
```

In `config/locales/comp_admin.zh-CN.yml`, at the same position:

```yaml
      use_entity_records: "使用实体记录"
      display_field: "显示字段"
      entity_records_hint: "保存记录 ID。下拉列表会向所有能打开表单的人列出每条记录的显示字段。"
```

Run: `locale_parity comp_admin`
Expected: no output.

- [ ] **Step 3: Write the failing component spec**

In `spec/components/admin/maintenance/entities/attribute_modal_component_spec.rb`, add the example below. It renders the component with the spec's existing setup, so replace `render_inline(component)` with whatever the spec already uses:

```ruby
  it "offers Use Entity Records with an entity and a display-field select" do
    render_inline(component)

    button = page.find("button[data-entity-form-target='entityRecordsOptionsBtn']")
    expect(button).to have_text(I18n.t("comp_admin.attribute_modal.use_entity_records"))
    expect(button["data-action"]).to eq("click->entity-form#selectEntityRecordsOptions")

    section = page.find("[data-entity-form-target='entityRecordsOptionsSection']", visible: :all)
    expect(section[:class]).to include("hidden")
    expect(section).to have_css("select[data-entity-form-target='referenceEntitySelect'][data-action='change->entity-form#referenceEntityChanged']", visible: :all)
    expect(section).to have_css("select[data-entity-form-target='referenceLabelFieldSelect']", visible: :all)
    expect(section).to have_text(I18n.t("maint_core.entities.assoc.target_entity"))
    expect(section).to have_text(I18n.t("comp_admin.attribute_modal.display_field"))
    expect(section).to have_text(I18n.t("comp_admin.attribute_modal.entity_records_hint"))
  end
```

Run: `RAILS_ENV=test TEST_ENV_NUMBER=24 bin/rails db:schema:load && TEST_ENV_NUMBER=24 bundle exec rspec spec/components/admin/maintenance/entities/attribute_modal_component_spec.rb`
Expected: FAIL, because the button can't be found.

- [ ] **Step 4: Add the button and the section**

In `attribute_modal_component.html.erb`, after the `constantOptionsBtn` button (before the closing `</div>` of the `role="group"` wrapper), add:

```erb
                      <button type="button"
                              data-action="click->entity-form#selectEntityRecordsOptions"
                              data-entity-form-target="entityRecordsOptionsBtn"
                              class="flex-1 sm:flex-none px-2.5 py-1 text-xs font-medium rounded-sm transition-base
                                     text-text-muted bg-transparent border border-transparent hover:bg-surface-active">
                        <%= t("comp_admin.attribute_modal.use_entity_records") %>
                      </button>
```

After the `constantOptionsSection` div closes, add:

```erb
                    <div data-entity-form-target="entityRecordsOptionsSection" class="hidden">
                      <div class="grid grid-cols-1 sm:grid-cols-2 gap-2">
                        <label class="flex flex-col gap-1">
                          <span class="text-caption font-medium text-text-muted"><%= t("maint_core.entities.assoc.target_entity") %></span>
                          <select data-entity-form-target="referenceEntitySelect"
                                  data-action="change->entity-form#referenceEntityChanged"
                                  class="input-field text-sm py-1.5">
                            <option value=""><%= t("common.labels.em_dash") %></option>
                          </select>
                        </label>
                        <label class="flex flex-col gap-1">
                          <span class="text-caption font-medium text-text-muted"><%= t("comp_admin.attribute_modal.display_field") %></span>
                          <select data-entity-form-target="referenceLabelFieldSelect" class="input-field text-sm py-1.5">
                            <option value=""><%= t("common.labels.em_dash") %></option>
                          </select>
                        </label>
                      </div>
                      <p class="mt-1.5 text-caption text-text-muted"><%= t("comp_admin.attribute_modal.entity_records_hint") %></p>
                    </div>
```

Run the component spec again. Expected: PASS.

- [ ] **Step 5: Write the failing `ReferenceManager` tests**

Create `spec/javascript/controllers/entity_form/reference_manager.test.js`:

```js
import { describe, it, expect, vi, beforeEach } from "vitest"
import { ReferenceManager, ENTITY_ENTRIES } from "controllers/entity_form/reference_manager"
import { buildController, fakeEvent } from "./support.js"

beforeEach(() => { vi.restoreAllMocks() })

const TARGETS = [
  { id: 7, name: "Course", property_schema: [
    { name: "Title", name_slug: "title", labelable: true },
    { name: "Notes", name_slug: "notes", labelable: false }
  ] },
  { id: 9, name: "Room" }
]

const HTML =
  `<button data-entity-form-target="entityRecordsOptionsBtn"></button>` +
  `<select data-entity-form-target="referenceEntitySelect"><option value="">—</option></select>` +
  `<select data-entity-form-target="referenceLabelFieldSelect"><option value="">—</option></select>`

function setup(values = {}) {
  const { controller } = buildController(HTML, {
    values: { hasCustomerIdValue: true, customerIdValue: "5", optionsSourceMode: "manual", ...values }
  })
  controller.constantsManager = { updateOptionsSourceUI: vi.fn() }
  controller.validatorManager = { syncInclusionValidator: vi.fn() }
  return { controller, manager: new ReferenceManager(controller) }
}

const okFetch = (body = TARGETS) =>
  vi.spyOn(globalThis, "fetch").mockResolvedValue({ ok: true, json: async () => body })

const optionValues = (select) => [...select.options].map(option => option.value)

describe("ReferenceManager#loadTargets", () => {
  it("fetches the tenant's entities once and fills the entity select", async () => {
    const fetchSpy = okFetch()
    const { controller, manager } = setup()

    expect(await manager.loadTargets()).toEqual(TARGETS)
    expect(await manager.loadTargets()).toEqual(TARGETS)
    expect(fetchSpy).toHaveBeenCalledTimes(1)
    expect(fetchSpy.mock.calls[0][0]).toBe("/5/admin/maintenance/entities.json")
    expect(optionValues(controller.referenceEntitySelectTarget)).toEqual(["", "7", "9"])
    expect(controller.referenceEntitySelectTarget.options[1].textContent).toBe("Course")
  })

  it("does not fetch without a customer id", async () => {
    const fetchSpy = okFetch()
    const { manager } = setup({ hasCustomerIdValue: false })

    expect(await manager.loadTargets()).toEqual([])
    expect(fetchSpy).not.toHaveBeenCalled()
  })

  it("keeps the placeholder and retries after a failed response or a network error", async () => {
    const { controller, manager } = setup()
    const fetchSpy = vi.spyOn(globalThis, "fetch")
      .mockResolvedValueOnce({ ok: false })
      .mockRejectedValueOnce(new Error("offline"))

    expect(await manager.loadTargets()).toEqual([])
    expect(await manager.loadTargets()).toEqual([])
    expect(fetchSpy).toHaveBeenCalledTimes(2)
    expect(optionValues(controller.referenceEntitySelectTarget)).toEqual([""])
  })

  it("tolerates a missing entity select", async () => {
    okFetch()
    const { controller } = buildController("", { values: { hasCustomerIdValue: true, customerIdValue: "5" } })

    expect(await new ReferenceManager(controller).loadTargets()).toEqual(TARGETS)
  })
})

describe("ReferenceManager display fields", () => {
  it("lists only labelable attributes of the chosen entity", async () => {
    okFetch()
    const { controller, manager } = setup()
    await manager.loadTargets()

    controller.referenceEntitySelectTarget.value = "7"
    manager.entityChanged()
    expect(optionValues(controller.referenceLabelFieldSelectTarget)).toEqual(["", "title"])

    controller.referenceEntitySelectTarget.value = "9"
    manager.entityChanged()
    expect(optionValues(controller.referenceLabelFieldSelectTarget)).toEqual([""])
  })

  it("clears the display fields when nothing is loaded", () => {
    const { controller, manager } = setup()
    manager.entityChanged()
    expect(optionValues(controller.referenceLabelFieldSelectTarget)).toEqual([""])
  })

  it("tolerates a missing display-field select", () => {
    const { controller } = buildController("")
    expect(() => new ReferenceManager(controller).populateLabelFieldSelect(null)).not.toThrow()
  })
})

describe("ReferenceManager config", () => {
  it("returns the stored config only when both selects are chosen", async () => {
    okFetch()
    const { controller, manager } = setup()
    await manager.loadTargets()
    expect(manager.getConfig()).toBeNull()

    controller.referenceEntitySelectTarget.value = "7"
    manager.entityChanged()
    expect(manager.getConfig()).toBeNull()

    controller.referenceLabelFieldSelectTarget.value = "title"
    expect(manager.getConfig()).toEqual({ options_source: ENTITY_ENTRIES, entity_id: "7", label_field: "title" })
  })

  it("reports the first missing choice with the translated alert", async () => {
    okFetch()
    const { controller, manager } = setup({
      selectTargetEntityMsgValue: "Pick an entity", selectDisplayFieldMsgValue: "Pick a field"
    })
    await manager.loadTargets()
    expect(manager.validate()).toEqual({ target: "referenceEntitySelect", message: "Pick an entity" })

    controller.referenceEntitySelectTarget.value = "7"
    manager.entityChanged()
    expect(manager.validate()).toEqual({ target: "referenceLabelFieldSelect", message: "Pick a field" })

    controller.referenceLabelFieldSelectTarget.value = "title"
    expect(manager.validate()).toBeNull()
  })

  it("applies a saved config, switching the mode on", async () => {
    okFetch()
    const { controller, manager } = setup()

    await manager.applyConfig({ options_source: ENTITY_ENTRIES, entity_id: 7, label_field: "title" })

    expect(controller.optionsSourceMode).toBe(ENTITY_ENTRIES)
    expect(controller.constantsManager.updateOptionsSourceUI).toHaveBeenCalled()
    expect(controller.referenceEntitySelectTarget.value).toBe("7")
    expect(controller.referenceLabelFieldSelectTarget.value).toBe("title")
  })

  it("applies a partial config without choosing anything", async () => {
    okFetch()
    const { controller, manager } = setup()

    await manager.applyConfig({ options_source: ENTITY_ENTRIES })

    expect(controller.referenceEntitySelectTarget.value).toBe("")
    expect(controller.referenceLabelFieldSelectTarget.value).toBe("")
  })

  it("applies a config without the select targets", async () => {
    okFetch()
    const { controller } = buildController("", { values: { hasCustomerIdValue: true, customerIdValue: "5" } })
    controller.constantsManager = { updateOptionsSourceUI: vi.fn() }

    await expect(new ReferenceManager(controller).applyConfig({ entity_id: 7 })).resolves.toBeUndefined()
  })

  it("resets both selects", async () => {
    okFetch()
    const { controller, manager } = setup()
    await manager.applyConfig({ entity_id: 7, label_field: "title" })

    manager.reset()

    expect(controller.referenceEntitySelectTarget.selectedIndex).toBe(0)
    expect(optionValues(controller.referenceLabelFieldSelectTarget)).toEqual([""])
  })

  it("resets without targets", () => {
    const { controller } = buildController("")
    expect(() => new ReferenceManager(controller).reset()).not.toThrow()
  })
})

describe("ReferenceManager mode", () => {
  it("selectEntityRecordsOptions switches the mode, syncs inclusion and loads entities", async () => {
    const fetchSpy = okFetch()
    const { controller, manager } = setup()
    const event = fakeEvent({ preventDefault: vi.fn() })

    await manager.selectEntityRecordsOptions(event)

    expect(event.preventDefault).toHaveBeenCalled()
    expect(controller.optionsSourceMode).toBe(ENTITY_ENTRIES)
    expect(controller.constantsManager.updateOptionsSourceUI).toHaveBeenCalled()
    expect(controller.validatorManager.syncInclusionValidator).toHaveBeenCalled()
    expect(fetchSpy).toHaveBeenCalled()
  })

  it("offers the mode for select and radio only and leaves it when the type changes", () => {
    const { controller, manager } = setup({ optionsSourceMode: ENTITY_ENTRIES })

    manager.syncAvailability("radio")
    expect(controller.entityRecordsOptionsBtnTarget.classList.contains("hidden")).toBe(false)
    expect(controller.optionsSourceMode).toBe(ENTITY_ENTRIES)

    manager.syncAvailability("checkbox")
    expect(controller.entityRecordsOptionsBtnTarget.classList.contains("hidden")).toBe(true)
    expect(controller.optionsSourceMode).toBe("manual")
    expect(controller.constantsManager.updateOptionsSourceUI).toHaveBeenCalledTimes(1)

    manager.syncAvailability("text")
    expect(controller.constantsManager.updateOptionsSourceUI).toHaveBeenCalledTimes(1)
  })

  it("syncs availability without a button target", () => {
    const { controller } = buildController("", { values: { optionsSourceMode: "manual" } })
    expect(() => new ReferenceManager(controller).syncAvailability("select")).not.toThrow()
  })
})
```

Run: `npx vitest run --config config/javascript/vitest.config.js spec/javascript/controllers/entity_form/reference_manager.test.js`
Expected: FAIL, because the module can't be resolved.

- [ ] **Step 6: Implement `ReferenceManager`**

Create `app/javascript/controllers/entity_form/reference_manager.js`:

```js
import { BaseManager, CSS } from "controllers/entity_form/base_manager"

export const ENTITY_ENTRIES = "entity_entries"
const REFERENCE_HTML_TYPES = ["select", "radio"]

// "Use Entity Records": a select or radio attribute whose choices are another
// entity's records. The saved config is { options_source, entity_id,
// label_field }. An entry stores the record id; the display field only labels
// the choices, so only attributes the server marks `labelable` are offered.
export class ReferenceManager extends BaseManager {
  async loadTargets() {
    if (!this.c.referenceTargets && this.c.hasCustomerIdValue) {
      try {
        const response = await fetch(`/${this.customerIdValue}/admin/maintenance/entities.json`, {
          headers: { Accept: "application/json" }
        })
        if (response.ok) this.c.referenceTargets = await response.json()
      } catch (_error) {
        // The selects keep their placeholders; the next open retries.
      }
      this.populateEntitySelect()
    }
    return this.c.referenceTargets || []
  }

  populateEntitySelect() {
    if (!this.c.hasReferenceEntitySelectTarget) return
    const select = this.c.referenceEntitySelectTarget
    while (select.options.length > 1) select.remove(1)
    ;(this.c.referenceTargets || []).forEach(entity => {
      const option = document.createElement("option")
      option.value = String(entity.id)
      option.textContent = entity.name
      select.appendChild(option)
    })
  }

  populateLabelFieldSelect(entity) {
    if (!this.c.hasReferenceLabelFieldSelectTarget) return
    const select = this.c.referenceLabelFieldSelectTarget
    while (select.options.length > 1) select.remove(1)
    const schema = entity?.property_schema || []
    schema.filter(attribute => attribute.labelable).forEach(attribute => {
      const option = document.createElement("option")
      option.value = attribute.name_slug
      option.textContent = attribute.name
      select.appendChild(option)
    })
  }

  selectedTarget() {
    const id = this.getTargetValue("referenceEntitySelect")
    return (this.c.referenceTargets || []).find(entity => String(entity.id) === id) || null
  }

  entityChanged() {
    this.populateLabelFieldSelect(this.selectedTarget())
  }

  selectEntityRecordsOptions(event) {
    event.preventDefault()
    this.c.optionsSourceMode = ENTITY_ENTRIES
    this.c.constantsManager.updateOptionsSourceUI()
    this.c.validatorManager.syncInclusionValidator()
    return this.loadTargets()
  }

  // Offered for select and radio only; any other type drops back to manual entry.
  syncAvailability(htmlType) {
    const available = REFERENCE_HTML_TYPES.includes(htmlType)
    if (this.c.hasEntityRecordsOptionsBtnTarget) {
      this.c.entityRecordsOptionsBtnTarget.classList.toggle(CSS.hidden, !available)
    }
    if (!available && this.c.optionsSourceMode === ENTITY_ENTRIES) {
      this.c.optionsSourceMode = "manual"
      this.c.constantsManager.updateOptionsSourceUI()
    }
  }

  getConfig() {
    const entityId = this.getTargetValue("referenceEntitySelect")
    const labelField = this.getTargetValue("referenceLabelFieldSelect")
    if (!entityId || !labelField) return null
    return { options_source: ENTITY_ENTRIES, entity_id: entityId, label_field: labelField }
  }

  // The first missing choice as { target, message }, or null when complete.
  validate() {
    if (!this.getTargetValue("referenceEntitySelect")) {
      return { target: "referenceEntitySelect", message: this.c.selectTargetEntityMsgValue }
    }
    if (!this.getTargetValue("referenceLabelFieldSelect")) {
      return { target: "referenceLabelFieldSelect", message: this.c.selectDisplayFieldMsgValue }
    }
    return null
  }

  async applyConfig(config) {
    this.c.optionsSourceMode = ENTITY_ENTRIES
    this.c.constantsManager.updateOptionsSourceUI()
    await this.loadTargets()
    if (this.c.hasReferenceEntitySelectTarget) {
      this.c.referenceEntitySelectTarget.value = String(config.entity_id ?? "")
    }
    this.populateLabelFieldSelect(this.selectedTarget())
    if (this.c.hasReferenceLabelFieldSelectTarget) {
      this.c.referenceLabelFieldSelectTarget.value = config.label_field || ""
    }
  }

  reset() {
    if (this.c.hasReferenceEntitySelectTarget) this.c.referenceEntitySelectTarget.selectedIndex = 0
    this.populateLabelFieldSelect(null)
  }
}
```

In `app/javascript/controllers/entity_form/index.js`, add:

```js
export { ReferenceManager, ENTITY_ENTRIES } from "controllers/entity_form/reference_manager"
```

In `spec/javascript/controllers/entity_form/index.test.js`, add `ReferenceManager` and `ENTITY_ENTRIES` to the list of exports it checks, following the file's existing pattern.

Run the `ReferenceManager` tests again. Expected: PASS.

- [ ] **Step 7: Three-way source toggle (test first)**

In `spec/javascript/controllers/entity_form/constants_manager.test.js`, extend `ui(mode)` with the two new targets: append `<button data-entity-form-target="entityRecordsOptionsBtn"></button>` and `<div data-entity-form-target="entityRecordsOptionsSection"></div>`. Then add:

```js
  it("entity_entries mode: records active + section visible, the other sections hidden", () => {
    const c = ui("entity_entries")
    expect(c.entityRecordsOptionsBtnTarget.classList.contains("bg-accent-subtle")).toBe(true)
    expect(c.manualOptionsBtnTarget.classList.contains("bg-accent-subtle")).toBe(false)
    expect(c.entityRecordsOptionsSectionTarget.classList.contains("hidden")).toBe(false)
    expect(c.manualOptionsSectionTarget.classList.contains("hidden")).toBe(true)
    expect(c.constantOptionsSectionTarget.classList.contains("hidden")).toBe(true)
  })

  it("works without the entity-records targets", () => {
    const { controller } = buildController(
      `<button data-entity-form-target="manualOptionsBtn"></button>` +
      `<button data-entity-form-target="constantOptionsBtn"></button>`,
      { values: { optionsSourceMode: "constant" } }
    )
    new ConstantsManager(controller).updateOptionsSourceUI()
    expect(controller.constantOptionsBtnTarget.classList.contains("bg-accent-subtle")).toBe(true)
  })
```

Then, in `constants_manager.js`, add these constants above the class:

```js
// The options-source switch, in button order.
const OPTION_SOURCES = [
  { mode: "manual", button: "manualOptionsBtn", section: "manualOptionsSection" },
  { mode: "constant", button: "constantOptionsBtn", section: "constantOptionsSection" },
  { mode: "entity_entries", button: "entityRecordsOptionsBtn", section: "entityRecordsOptionsSection" }
]
const ACTIVE_CLASSES = ["text-accent-text", "bg-accent-subtle", "border-accent", "shadow-sm"]
const INACTIVE_CLASSES = ["text-text-muted", "bg-transparent", "border-transparent"]
```

and replace `updateOptionsSourceUI()` with:

```js
  updateOptionsSourceUI() {
    if (!this.c.hasManualOptionsBtnTarget || !this.c.hasConstantOptionsBtnTarget) return
    OPTION_SOURCES.forEach(({ mode, button, section }) => {
      const active = this.c.optionsSourceMode === mode
      if (this.hasTarget(button)) {
        this.target(button).classList.add(...(active ? ACTIVE_CLASSES : INACTIVE_CLASSES))
        this.target(button).classList.remove(...(active ? INACTIVE_CLASSES : ACTIVE_CLASSES))
      }
      if (this.hasTarget(section)) this.target(section).classList.toggle("hidden", !active)
    })
  }
```

- [ ] **Step 8: Records mode never builds an inclusion validator (test first)**

In `validator_manager.test.js`, add an example:

- Set up a `select` HTML type with one manual option row whose value is `a`, an existing inclusion badge, and `optionsSourceMode = "entity_entries"`.
- Call `syncInclusionValidator()`.
- Assert that no `[data-validator-value="inclusion"]` badge remains.

Build the controller the way the file's other `syncInclusionValidator` examples do.

In `validator_manager.js` `syncInclusionValidator`, change `} else {` (the manual branch) to `} else if (this.c.optionsSourceMode !== "entity_entries") {`.

- [ ] **Step 9: Type changes and config (test first)**

In `type_manager.test.js`, add three examples:

1. `htmlTypeChanged` calls `controller.referenceManager.syncAvailability` with the new type when a `referenceManager` is attached. Keep one existing example without a `referenceManager` so that the other branch stays covered.
2. In the `selection` case, `getConfigForType("select")` returns `controller.referenceManager.getConfig()` when `optionsSourceMode === "entity_entries"`. Stub `getConfig` to return `{ options_source: "entity_entries", entity_id: "7", label_field: "title" }`.
3. `getConfigForType("select")` returns `null` in the same mode when the stub returns `null`.

In `type_manager.js`:

- In `htmlTypeChanged()`, after computing `htmlType`, add `if (this.c.referenceManager) this.c.referenceManager.syncAvailability(htmlType)`.
- In `getConfigForType`, at the top of `case "selection": {`, add `if (this.c.optionsSourceMode === "entity_entries") return this.c.referenceManager.getConfig()`.

- [ ] **Step 10: Prefill, reset and validation (test first)**

In `modal_manager.test.js`, add four examples:

- `prefillModalWithAttribute({ html_type: "select", config: { options_source: "entity_entries", entity_id: "7", label_field: "title" } })` calls `referenceManager.applyConfig` with that config and adds no manual option rows.
- `openModal`, `openModalForAssociationAttribute` and `resetModalFields` each call `referenceManager.reset()` when a `referenceManager` is attached. Keep their existing examples without a `referenceManager` so that the other branch stays covered.

In `modal_manager.js`:

- In `openModal` and `openModalForAssociationAttribute`, after `this.c.constantsManager.updateOptionsSourceUI()`, add `if (this.c.referenceManager) this.c.referenceManager.reset()`.
- In `resetModalFields`, after `this.c.optionsSourceMode = "manual"`, add the same line.
- In the prefill block, change `if (configType === "selection" && config.options?.length) {` to:

```js
        if (configType === "selection" && config.options_source === "entity_entries") {
          this.c.referenceManager.applyConfig(config)
        } else if (configType === "selection" && config.options?.length) {
```

In `attribute_manager.test.js`, add two examples:

- `validateAttribute` returns `false` and calls `showFieldError` on `referenceEntitySelectTarget` with the entity alert when the mode is `entity_entries` and `referenceManager.validate()` returns `{ target: "referenceEntitySelect", message: "Pick an entity" }`.
- It returns `true` when `validate()` returns `null`.

In `attribute_manager.js` `validateAttribute`, after the computed-mode block and before the final `return true`, add:

```js
    if (this.c.attributeMode !== "computed" && this.c.optionsSourceMode === "entity_entries") {
      const problem = this.c.referenceManager.validate()
      if (problem) {
        this.showFieldError(this.c[`${problem.target}Target`], problem.message)
        return false
      }
    }
```

- [ ] **Step 11: Association display fields and the edit reset (test first)**

In `association_manager.test.js`, add two examples:

- `populateDisplayFieldDropdown({ property_schema: [{ name: "Title", name_slug: "title", labelable: true }, { name: "Notes", name_slug: "notes", labelable: false }] })` leaves only the placeholder and `title`.
- `editAssociationAttribute` keeps an entity-records mode that the prefill set. Stub `modalManager.prefillModalWithAttribute` to set `controller.optionsSourceMode = "entity_entries"`, and assert that the mode is still `entity_entries` afterwards.

In `association_manager.js`:

- In `populateDisplayFieldDropdown`, change `schema.forEach(prop => {` to `schema.filter(prop => prop.labelable).forEach(prop => {`.
- In `editAssociationAttribute`, move these two lines to just before `this.c.modalManager.prefillModalWithAttribute(attribute)`:

```js
    this.c.optionsSourceMode = "manual"
    this.c.constantsManager.updateOptionsSourceUI()
```

- [ ] **Step 12: Wire the controller (test first)**

In `spec/javascript/controllers/entity_form_controller.test.js`, add examples, following the file's existing delegation tests, that check two things:

- `connect()` creates `controller.referenceManager`;
- `selectEntityRecordsOptions(event)` and `referenceEntityChanged()` delegate to it.

In `app/javascript/controllers/entity_form_controller.js`:

- Add `import { ReferenceManager } from "controllers/entity_form/reference_manager"` after the `ConstantsManager` import.
- Add `"entityRecordsOptionsBtn", "entityRecordsOptionsSection", "referenceEntitySelect", "referenceLabelFieldSelect"` to `static targets`.
- In `connect()`, after `this.constantsManager = new ConstantsManager(this)`, add `this.referenceManager = new ReferenceManager(this)`, and after `this.constants = []` add `this.referenceTargets = null`.
- Under the ConstantsManager delegations, add:

```js
  // =========================================================================
  // Delegated Actions -> ReferenceManager
  // =========================================================================

  selectEntityRecordsOptions(event) { this.referenceManager.selectEntityRecordsOptions(event) }
  referenceEntityChanged() { this.referenceManager.entityChanged() }
```

- [ ] **Step 13: Run Vitest with coverage**

Run:

```bash
npx vitest run --config config/javascript/vitest.config.js spec/javascript/controllers/entity_form spec/javascript/controllers/entity_form_controller.test.js --coverage --coverage.include='app/javascript/controllers/entity_form/**' --coverage.include=app/javascript/controllers/entity_form_controller.js --coverage.reporter=text
```

Expected: every test passes, and every listed file shows `100 | 100 | 100 | 100`. Paste the coverage table into your report.

- [ ] **Step 14: Run the component spec and leave the changes uncommitted**

Run: `TEST_ENV_NUMBER=24 bundle exec rspec spec/components/admin/maintenance/entities/attribute_modal_component_spec.rb && git add -N app/javascript/controllers/entity_form/reference_manager.js spec/javascript/controllers/entity_form/reference_manager.test.js && git status --short`
Expected: PASS. Do not commit.

---

### Task 5: Contract existence rule, bridge writer, `Page#input_fields`

**Agent:** anysys-backend-developer

**Files:**
- Modify: `app/contracts/entity_entry_contract.rb`
- Modify: `app/services/pages/bridge_entries.rb`
- Modify: `app/models/concerns/page_configuration_helpers.rb`
- Modify: `app/services/pages/form_params.rb`
- Modify: `spec/contracts/entity_entry_contract_spec.rb`, `spec/services/pages/bridge_entries_spec.rb`
- Create: `spec/models/concerns/page_configuration_helpers_spec.rb`

**Interfaces:**
- Consumes: `EntityDefinitions::Capabilities::ENTITY_ENTRIES_OPTIONS_SOURCE`, and the existing key `common.errors.dynamic.association_target_missing`.
- Produces:
  - Contracts built by `EntityEntryContract.build_for` reject reference ids that are not records of the target entity in the entry's customer. The error goes on `:base`.
  - `Page#input_fields`, and `Page.input_fields_in(configuration_hash)`, which returns `Array<Hash>`: input fields on every step, columns flattened, layout elements dropped.

- [ ] **Step 1: Prepare the test database**

Run: `RAILS_ENV=test TEST_ENV_NUMBER=25 bin/rails db:schema:load`

- [ ] **Step 2: Write the failing contract examples**

Append to `spec/contracts/entity_entry_contract_spec.rb`, inside the top-level `describe`:

```ruby
  describe "entity_entries references" do
    let(:customer) { create(:customer) }
    let(:course) do
      create(:entity, customer: customer, name: "Course",
                      property_schema: [{ "name" => "Title", "name_slug" => "title", "html_type" => "text" }].to_json)
    end
    let(:application) do
      create(:entity, customer: customer, name: "Application", property_schema: [
        { "name" => "Course", "name_slug" => "course", "html_type" => "select",
          "config" => { "options_source" => "entity_entries", "entity_id" => course.id.to_s, "label_field" => "title" } },
        { "name" => "Note", "name_slug" => "note", "html_type" => "text" }
      ].to_json)
    end
    let(:biology) { create(:entity_entry, customer: customer, entity: course, data: { title: "Biology" }.to_json) }
    let(:missing) { I18n.t("common.errors.dynamic.association_target_missing", field: "Course") }

    def contract_for(entry, writable_slugs: nil)
      described_class.build_for(application, audience: EntityAttributeAudience::ADMIN, writable_slugs: writable_slugs).new(entry)
    end

    def new_entry = EntityEntry.build_for(application).new(entity: application, customer_id: customer.id)

    it "accepts the id of a record of the target entity in the same customer" do
      expect(contract_for(new_entry).validate("course" => biology.id.to_s)).to be(true)
    end

    it "accepts a blank reference" do
      expect(contract_for(new_entry).validate("course" => "")).to be(true)
    end

    it "rejects a foreign tenant's record, another entity's record and a non-id on :base" do
      foreign = create(:entity_entry, customer: create(:customer), entity: course, data: { title: "X" }.to_json)
      other_entity_entry = create(:entity_entry, customer: customer, entity: application, data: {}.to_json)

      [foreign.id.to_s, other_entity_entry.id.to_s, "abc", "999999"].each do |value|
        contract = contract_for(new_entry)
        expect(contract.validate("course" => value)).to be(false)
        expect(contract.errors[:base]).to include(missing)
      end
    end

    it "checks every value of a multi-valued reference" do
      contract = contract_for(new_entry)

      expect(contract.validate("course" => [biology.id.to_s, "999999"])).to be(false)
      expect(contract.errors[:base]).to include(missing)
    end

    it "skips a reference the caller may not write" do
      expect(contract_for(new_entry, writable_slugs: %w[note]).validate("note" => "hi")).to be(true)
    end

    it "keeps an unchanged reference on a persisted entry even after its target is deleted" do
      entry = create(:entity_entry, customer: customer, entity: application, data: { course: biology.id.to_s }.to_json)
      biology.destroy!

      contract = contract_for(EntityEntry.build_for(application).find(entry.id))
      expect(contract.validate("course" => entry.data_json["course"], "note" => "edited")).to be(true)
    end
  end
```

Run: `TEST_ENV_NUMBER=25 bundle exec rspec spec/contracts/entity_entry_contract_spec.rb`
Expected: FAIL. The rejection examples pass validation.

- [ ] **Step 3: Implement the rule**

In `app/contracts/entity_entry_contract.rb`:

- After the `include` lines, add `class_attribute :reference_rules, instance_accessor: false, default: [].freeze`.
- In `build_for`, inside the `Class.new(self) do ... end` block, add this line after `schema.each { ... }`:

```ruby
        declare_reference_rules(schema, writable_slugs: write_set)
```

- In the `class << self` block's `private` section (line 85), add:

```ruby
    # One rule per writable entity_entries attribute; #validate_reference_targets
    # checks them all in one pass.
    def declare_reference_rules(schema, writable_slugs:)
      rules = schema.filter_map do |attr|
        next unless attr.is_a?(Hash) && attr["config"].is_a?(Hash)
        next unless attr["config"]["options_source"] == EntityDefinitions::Capabilities::ENTITY_ENTRIES_OPTIONS_SOURCE

        slug = attr["name_slug"].to_s
        next if slug.empty? || (writable_slugs && !writable_slugs.include?(slug))

        { slug: slug, entity_id: attr["config"]["entity_id"].to_s,
          label: attr["display_label"].presence || attr["name"].presence || slug }
      end
      return if rules.empty?

      self.reference_rules = rules.freeze
      validate :validate_reference_targets
    end
```

- In the instance-level `private` section (create one at the end of the class if none exists), add:

```ruby
  # A reference holds record ids of the target entity in the entry's own
  # customer. A persisted entry may keep an unchanged value whose record is
  # gone, so editing other fields never locks it.
  def validate_reference_targets
    self.class.reference_rules.each do |rule|
      values = reference_target_values(public_send(rule[:slug]))
      next if values.empty? || reference_target_unchanged?(rule[:slug], values)
      next if reference_targets_found?(rule[:entity_id], values)

      errors.add(:base, I18n.t("common.errors.dynamic.association_target_missing", field: rule[:label]))
    end
  end

  def reference_target_values(raw)
    Array(raw).map { |value| value.to_s.strip }.reject(&:empty?)
  end

  def reference_target_unchanged?(slug, values)
    model.respond_to?(:persisted?) && model.persisted? && model.respond_to?(slug) &&
      reference_target_values(model.public_send(slug)) == values
  end

  def reference_targets_found?(entity_id, values)
    ids = values.uniq
    return false unless ids.all? { |value| value.match?(/\A\d+\z/) }

    EntityEntry.where(customer_id: model.customer_id, entity_id: entity_id, id: ids).count == ids.size
  end
```

Run the contract spec again. Expected: PASS, and every pre-existing example still passes.

- [ ] **Step 4: Bridge writer delegates the check (test first)**

In `spec/services/pages/bridge_entries_spec.rb`:

- Give the Student reference fixture in the bridge schema `"html_type" => "select"` and `"config" => { "options_source" => "entity_entries", "entity_id" => student.id.to_s, "label_field" => "code" }`. Check that the student entity's schema has a text attribute `code`; if it doesn't, add one.
- Change the expectations at lines 48 and 53 to `course_entry.id.to_s`. The link back to the primary entry is now stored as an id string.
- Leave the foreign-tenant example as it is. It must still return exactly `[I18n.t("common.errors.dynamic.association_target_missing", field: "Learner")]`.

Run: `TEST_ENV_NUMBER=25 bundle exec rspec spec/services/pages/bridge_entries_spec.rb`
Expected: FAIL on lines 48 and 53, because the link is still an integer.

In `app/services/pages/bridge_entries.rb`:

- Delete the two lines `errors = targets.filter_map { |ref| missing_target(ref, values[ref["name_slug"]]) }` and `return errors if errors.any?`.
- Delete the `missing_target` method.
- `links` becomes:

```ruby
    def links(bridge)
      references(bridge).select { |ref| ref["entity_id"].to_s == @entity.id.to_s }
                        .to_h { |ref| [ref["name_slug"], @entry.id.to_s] }
    end
```

- Replace the class comment's second paragraph with:

```ruby
  # A section is written only when one of its target references (the bridge's
  # EntityReference to the associated entity) is filled; the reference back to
  # the primary entity is always set here, never taken from the submission.
  # EntityEntryContract checks that each target id is a record of the target
  # entity in this customer.
```

Run the bridge spec again. Expected: PASS.

- [ ] **Step 5: `Page#input_fields` (test first)**

Create `spec/models/concerns/page_configuration_helpers_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe PageConfigurationHelpers do
  let(:config) do
    {
      "pages" => [
        { "fields" => [
          { "id" => "a", "property_type" => "input" },
          { "id" => "h", "property_type" => "layout", "field_type" => "heading" },
          { "id" => "cols", "field_type" => "columns", "property_type" => "layout", "columns" => [
            { "fields" => [{ "id" => "b" }, { "id" => "d", "property_type" => "layout" }] },
            { "fields" => [{ "field_type" => "columns", "columns" => [{ "fields" => [{ "id" => "c" }] }] }] },
            "junk"
          ] },
          "junk"
        ] },
        "junk",
        { "fields" => [{ "id" => "e" }] }
      ]
    }
  end

  it "flattens columns on every step and drops layout elements" do
    expect(Page.input_fields_in(config).map { |field| field["id"] }).to eq(%w[a b c e])
  end

  it "reads a page's own configuration" do
    page = build(:page)
    page.configuration_json = config

    expect(page.input_fields.map { |field| field["id"] }).to eq(%w[a b c e])
  end

  it "is empty for a missing or malformed configuration" do
    expect(Page.input_fields_in(nil)).to eq([])
    expect(Page.input_fields_in("x")).to eq([])
  end
end
```

Run: `TEST_ENV_NUMBER=25 bundle exec rspec spec/models/concerns/page_configuration_helpers_spec.rb`
Expected: FAIL with `undefined method 'input_fields_in'`.

In `app/models/concerns/page_configuration_helpers.rb`:

- Add `#   #input_fields        — every input field, columns flattened, layout dropped` to the header list.
- After `def fields ... end`, add:

```ruby
  # Every input field on every step: column layouts flattened, headings,
  # dividers and spacers dropped.
  def input_fields
    self.class.input_fields_in(configuration_json)
  end

  class_methods do
    # The same walk over a raw configuration hash, e.g. a tenant override's payload.
    def input_fields_in(config)
      return [] unless config.is_a?(Hash)

      collect_input_fields(Array(config["pages"]).grep(Hash).flat_map { |step| Array(step["fields"]) })
    end

    private

    def collect_input_fields(items)
      items.flat_map do |field|
        next [] unless field.is_a?(Hash)

        if field["field_type"] == "columns"
          collect_input_fields(Array(field["columns"]).grep(Hash).flat_map { |column| Array(column["fields"]) })
        elsif field["property_type"] == "layout"
          []
        else
          [field]
        end
      end
    end
  end
```

In `app/services/pages/form_params.rb`:

- Replace the private `fields` method with `def fields = @fields ||= @page.input_fields`.
- Delete `collect_fields`.

- [ ] **Step 6: Run the task's specs**

Run: `TEST_ENV_NUMBER=25 bundle exec rspec spec/contracts/entity_entry_contract_spec.rb spec/services/pages spec/models/concerns/page_configuration_helpers_spec.rb spec/models/page_spec.rb spec/requests/public_pages_tenant_audience_spec.rb`
Expected: all pass.

- [ ] **Step 7: Leave the changes uncommitted**

Run: `git add -N spec/models/concerns/page_configuration_helpers_spec.rb && git status --short`. Do not commit.

---

### Task 6: Generated dropdowns and query lists

**Agent:** anysys-backend-developer

**Files:**
- Modify: `app/services/page_content_generator/form_fields.rb`
- Modify: `app/services/page_content_generator/dynamic_options_resolver.rb`
- Modify: `app/services/page_field_populator.rb`
- Modify specs:
  - `spec/services/page_content_generator_safety_spec.rb`
  - `spec/services/page_content_generator_runtime_spec.rb`
  - `spec/services/page_content_generator/entity_quick_add_spec.rb`
  - `spec/services/page_field_populator_spec.rb`
  - `spec/requests/admin/page_forms_spec.rb`
  - `spec/requests/public_pages_tenant_audience_spec.rb`
- Create: `spec/services/page_content_generator/dynamic_options_resolver_spec.rb` (if it doesn't already exist; otherwise extend it)

**Interfaces:**
- Consumes: `Entities::ReferenceOptions.call` (T1), `Entities::ReferenceLabels.{labelable?,text,disambiguate}` (T1).
- Produces:
  - The generated ERB calls `Entities::ReferenceOptions.call(...)` for every `entity_entries` field.
  - `DynamicOptionsResolver` `query` options are `{ "label" => ReferenceLabels text, "value" => id string }`.
  - `PageFieldPopulator` copies `options_source`, `entity_id` and `label_field` only.

- [ ] **Step 1: Prepare the test database**

Run: `RAILS_ENV=test TEST_ENV_NUMBER=26 bin/rails db:schema:load`

- [ ] **Step 2: Write the failing generator examples**

In `spec/services/page_content_generator_safety_spec.rb`, in "reads data_json through a schema allowlist instead of sending AR methods" (line 131):

- Rename it to "lists entity records through Entities::ReferenceOptions instead of sending AR methods".
- Replace `expect(content).to include("__e.data_json")` with:

```ruby
      expect(content).to include('Entities::ReferenceOptions.call(entity_id: 1, label_field: "destroy"')
      expect(content).to include("EntityAttributeAudience.for_user(Current.user, customer_id: __cid)")
      expect(content).not_to include("EntityEntry.build_for")
```

- Keep `expect(content).not_to include(".send(")` and `expect(content).to include("Current.customer_id || @page.customer_id")`.

In `spec/services/page_content_generator_runtime_spec.rb`:

- In the `%w[query entity_entries].each` loop (line 111), remove `"value_field" => "id"` from `dynamic_options`.
- After the loop, add:

```ruby
  it "labels entity_entries choices with the display field, Untitled and numbered repeats" do
    entity = create(:entity, customer: customer, property_schema: [
      { "name" => "Title", "name_slug" => "title", "html_type" => "text" }
    ].to_json)
    first = create(:entity_entry, customer: customer, entity: entity, data: { "title" => "Intro" }.to_json)
    second = create(:entity_entry, customer: customer, entity: entity, data: { "title" => "Intro" }.to_json)
    blank = create(:entity_entry, customer: customer, entity: entity, data: {}.to_json)

    html = generate_and_render({ "pages" => [{ "fields" => [
      { "id" => "choice", "property_slug" => "choice", "html_type" => "select", "dynamic_options" => {
        "options_source" => "entity_entries", "entity_id" => entity.id, "label_field" => "title"
      } }
    ] }] })
    options = Nokogiri::HTML.fragment(html).css('option:not([value=""])').to_h { |option| [option["value"], option.text.strip] }

    expect(options).to eq(
      blank.id.to_s => "Untitled (##{blank.id})",
      first.id.to_s => "Intro (##{first.id})",
      second.id.to_s => "Intro (##{second.id})"
    )
  end
```

Run: `TEST_ENV_NUMBER=26 bundle exec rspec spec/services/page_content_generator_safety_spec.rb spec/services/page_content_generator_runtime_spec.rb`
Expected: FAIL. The preamble still inlines the query and doesn't number repeated labels.

- [ ] **Step 3: Replace the preamble**

In `app/services/page_content_generator/form_fields.rb`, replace the whole `build_dynamic_options_preamble` method (including its comment) with:

```ruby
    # ERB that lists the target entity's records at render time for the
    # viewing tenant and audience (shared pages have a NULL customer_id).
    # Entities::ReferenceOptions owns the label rule and never raises on bad
    # configuration, so the template needs no rescue.
    def build_dynamic_options_preamble(field_id, config)
      var_name = "_dyn_opts_#{field_id.to_s.gsub(/[^a-z0-9_]/, '_')}"

      <<~ERB.strip
        <%- __cid = Current.customer_id || @page.customer_id
            #{var_name} = Entities::ReferenceOptions.call(entity_id: #{config["entity_id"].to_i}, label_field: #{rb_str(config["label_field"].to_s)},
              customer_id: __cid, audience: EntityAttributeAudience.for_user(Current.user, customer_id: __cid)) -%>
      ERB
    end
```

Run the two specs again. Expected: PASS.

- [ ] **Step 4: Query lists use the same label rule (test first)**

Create (or extend) `spec/services/page_content_generator/dynamic_options_resolver_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe PageContentGenerator::DynamicOptionsResolver do
  let_it_be(:customer) { create(:customer) }
  let(:schema) do
    [{ "name" => "Title", "name_slug" => "title", "html_type" => "text" },
     { "name" => "Notes", "name_slug" => "notes", "html_type" => "textarea" }]
  end
  let(:course) { create(:entity, customer: customer, name: "Course", property_schema: schema.to_json) }

  def field(label_field)
    { "id" => "f", "html_type" => "select",
      "dynamic_options" => { "options_source" => "query", "entity_id" => course.id.to_s, "label_field" => label_field } }
  end

  def resolve(label_field)
    described_class.new(customer.id, audience: EntityAttributeAudience::ADMIN).resolve([field(label_field)]).first["options"]
  end

  it "stores the record id and labels with the display field, numbering repeats" do
    first = create(:entity_entry, customer: customer, entity: course, data: { title: "Intro" }.to_json)
    second = create(:entity_entry, customer: customer, entity: course, data: { title: "Intro" }.to_json)
    blank = create(:entity_entry, customer: customer, entity: course, data: {}.to_json)

    expect(resolve("title")).to contain_exactly(
      { "label" => "Intro (##{first.id})", "value" => first.id.to_s },
      { "label" => "Intro (##{second.id})", "value" => second.id.to_s },
      { "label" => "Untitled (##{blank.id})", "value" => blank.id.to_s }
    )
  end

  it "lists nothing for a display field that is not labelable, unknown or id" do
    create(:entity_entry, customer: customer, entity: course, data: { title: "Intro", notes: "n" }.to_json)

    expect(resolve("notes")).to eq([])
    expect(resolve("missing")).to eq([])
    expect(resolve("id")).to eq([])
  end
end
```

Run it. Expected: FAIL, because labels are not numbered and `id` is accepted.

In `dynamic_options_resolver.rb`:

- Replace lines 45–50 (from `allowed = ...` through the `return empty unless [label_field, value_field]...` line) with:

```ruby
      schema = Array(entity.property_schema_json).grep(Hash)
      allowed = schema.filter_map do |attribute|
        attribute["name_slug"].to_s if EntityAttributeAudience.visible_to?(attribute, @audience)
      end
      label_field = dynamic["label_field"].to_s
      label_attribute = schema.find { |attribute| attribute["name_slug"].to_s == label_field }
      return empty unless Entities::ReferenceLabels.labelable?(label_attribute) && allowed.include?(label_field)
```

- Replace the `options = result.records.map do ... end` block with:

```ruby
      pairs = result.records.map { |record| [Entities::ReferenceLabels.text(record.data_json[label_field], record.id), record.id.to_s] }
      options = Entities::ReferenceLabels.disambiguate(pairs).map { |label, value| { "label" => label, "value" => value } }
```

- The class comment's first paragraph becomes: "Resolves `query` option lists for select / radio / multi-select fields at page-generation time. Values are record ids; labels follow `Entities::ReferenceLabels`, and the label field must be labelable and visible to the audience."

- [ ] **Step 5: The populator copies the stored keys only**

In `app/services/page_field_populator.rb` (line 147), change `.slice("options_source", "entity_id", "label_field", "value_field")` to `.slice("options_source", "entity_id", "label_field")`. In `spec/services/page_field_populator_spec.rb`, remove `value_field` from any expected `dynamic_options` hash.

- [ ] **Step 6: Sweep the remaining `value_field` fixtures in this task's specs**

Run: `rg -n "value_field" spec/services/page_content_generator*_spec.rb spec/services/page_content_generator spec/services/page_field_populator_spec.rb spec/requests/admin/page_forms_spec.rb spec/requests/public_pages_tenant_audience_spec.rb`

For each hit, remove the `value_field` key. Where a test relied on `value_field` to store a non-id value, change the expectation to the record id. Then run:

`TEST_ENV_NUMBER=26 bundle exec rspec spec/services/page_content_generator_spec.rb spec/services/page_content_generator_runtime_spec.rb spec/services/page_content_generator_safety_spec.rb spec/services/page_content_generator spec/services/page_field_populator_spec.rb spec/requests/admin/page_forms_spec.rb spec/requests/public_pages_tenant_audience_spec.rb`
Expected: all pass.

- [ ] **Step 7: Leave the changes uncommitted**

Run: `git status --short`. Do not commit.

---

### Task 7: Controllers — field options, quick-add label, `labelable` flag

**Agent:** anysys-security-engineer

**Files:**
- Modify: `app/controllers/admin/maintenance/page_field_options_controller.rb`
- Modify: `app/controllers/admin/entity_entries_controller.rb` (`quick_add_label` only)
- Modify: `app/controllers/admin/maintenance/entities_controller.rb` (the index `format.json` only)
- Modify: `spec/requests/admin/maintenance/page_field_options_spec.rb`
- Modify: `spec/requests/admin/entity_entry_creation_spec.rb` (the quick-add `describe` block only)
- Create: `spec/requests/admin/maintenance/entities_reference_targets_spec.rb`

**Interfaces:**
- Consumes: `Entities::ReferenceOptions` (T1), `Entities::ReferenceLabels` (T1), `Page#input_fields` (T5), and `DynamicOptionsResolver` with `audience:` (T6).
- Produces:
  - `GET .../page_field_options` returns `[{label, value}]` for both `entity_entries` and `query` fields, found anywhere on the page.
  - `entities.json` attributes carry `labelable`.
  - The quick-add label follows `ReferenceLabels`.

Authorization: all three actions keep their existing `before_action` guards (admin or owner, current customer). Do not add or relax any guard. The lists are always built for `current_customer_id` with the admin audience.

- [ ] **Step 1: Prepare the test database**

Run: `RAILS_ENV=test TEST_ENV_NUMBER=27 bin/rails db:schema:load`

- [ ] **Step 2: Write the failing request examples**

In `spec/requests/admin/maintenance/page_field_options_spec.rb`:

- The "dynamic options with non-query source" block (line 148) now covers `entity_entries`. Change its expectation from `[]` to the labelled list. Give the entity a text attribute `title`, create two entries titled `Biology` and `Chemistry`, and expect `[{ "label" => "Biology", "value" => biology.id.to_s }, { "label" => "Chemistry", "value" => chemistry.id.to_s }]`.
- Add an example: an `entity_entries` field nested inside a `columns` layout is found, so the response is not 404.
- Add an example: a `query` field whose `label_field` is `id` returns `[]`.
- Keep the auth-guard and cross-tenant examples unchanged. They must still pass.

In `spec/requests/admin/entity_entry_creation_spec.rb`, in the quick-add `describe`:

- The two fallback examples (lines 892–901) now expect `"Untitled (##{EntityEntry.last.id})"` instead of the bare id.
- Add an example: when an existing entry already shows the label `New primary record`, the created entry's `data-entry-label` is `"New primary record (##{EntityEntry.last.id})"`.

Create `spec/requests/admin/maintenance/entities_reference_targets_spec.rb`. Copy the customer, admin-user and sign-in setup from the top of `spec/requests/admin/maintenance/entities_spec.rb`, then add:

```ruby
  let!(:course) do
    create(:entity, customer: customer, name: "Course", property_schema: [
      { "name" => "Title", "name_slug" => "title", "html_type" => "text" },
      { "name" => "Notes", "name_slug" => "notes", "html_type" => "textarea" }
    ].to_json)
  end

  it "marks which attributes can label a reference" do
    get admin_maintenance_entities_path(customer.id, format: :json)

    item = response.parsed_body.find { |entity| entity["id"] == course.id }
    expect(item["property_schema"].to_h { |attr| [attr["name_slug"], attr["labelable"]] })
      .to eq("title" => true, "notes" => false)
  end
```

Also add a member-role example, mirroring `entities_spec.rb`'s existing auth examples: the same request as a member is rejected.

Run: `TEST_ENV_NUMBER=27 bundle exec rspec spec/requests/admin/maintenance/page_field_options_spec.rb spec/requests/admin/entity_entry_creation_spec.rb spec/requests/admin/maintenance/entities_reference_targets_spec.rb`
Expected: FAIL in the changed examples.

- [ ] **Step 3: Page field options**

Replace the body of `Admin::Maintenance::PageFieldOptionsController` from `def show` to the end of the class with:

```ruby
      def show
        @page = definition_scope(Page).find(params[:page_id])
        field = @page.input_fields.find { |item| item["id"] == params[:field_id] }
        return render json: [], status: :not_found unless field

        render json: field_options(field)
      end

      private

      # The builder previews as an admin of the URL tenant.
      def field_options(field)
        dynamic = field["dynamic_options"]
        return [] unless dynamic.is_a?(Hash)

        case dynamic["options_source"]
        when EntityDefinitions::Capabilities::ENTITY_ENTRIES_OPTIONS_SOURCE
          ::Entities::ReferenceOptions.call(entity_id: dynamic["entity_id"], label_field: dynamic["label_field"],
                                            customer_id: current_customer_id, audience: EntityAttributeAudience::ADMIN)
                                      .map { |label, value| { label: label, value: value } }
        when "query"
          PageContentGenerator::DynamicOptionsResolver.new(current_customer_id, audience: EntityAttributeAudience::ADMIN)
                                                      .resolve([field]).first.fetch("options")
        else
          []
        end
      end
```

- [ ] **Step 4: Quick-add label**

In `app/controllers/admin/entity_entries_controller.rb`, replace `quick_add_label` and its comment with:

```ruby
    # The label the dropdown would show for this entry: the display field when
    # it can label a reference for admins, numbered when another record already
    # shows the same text, and "Untitled (#id)" otherwise.
    def quick_add_label(entry)
      source = ::Entities::ReferenceOptions.new(entity_id: @entity.id, label_field: quick_add_label_field,
                                                customer_id: current_customer_id, audience: EntityAttributeAudience::ADMIN)
      return ::Entities::ReferenceLabels.text(nil, entry.id) unless source.usable?

      raw = entry.data_json[quick_add_label_field]
      label = ::Entities::ReferenceLabels.text(raw, entry.id)
      source.label_taken?(raw, except_id: entry.id) ? ::Entities::ReferenceLabels.numbered(label, entry.id) : label
    end
```

- [ ] **Step 5: `labelable` in `entities.json`**

In `app/controllers/admin/maintenance/entities_controller.rb`, change the index `format.json` render (line 56) to `render json: entities.map { |entity| reference_target_item(entity) }`. Then add this private method:

```ruby
    # The palette item, with each attribute marked by whether it may label a
    # reference; the editor offers only those as display fields.
    def reference_target_item(entity)
      item = entity.as_palette_item
      item.merge(property_schema: item[:property_schema].map do |attribute|
        attribute.is_a?(Hash) ? attribute.merge("labelable" => ::Entities::ReferenceLabels.labelable?(attribute)) : attribute
      end)
    end
```

- [ ] **Step 6: Run the specs and confirm no `value_field` remains in app code**

Run: `TEST_ENV_NUMBER=27 bundle exec rspec spec/requests/admin/maintenance/page_field_options_spec.rb spec/requests/admin/entity_entry_creation_spec.rb spec/requests/admin/maintenance/entities_reference_targets_spec.rb spec/requests/admin/maintenance/entities_spec.rb`
Expected: all pass.

Run: `rg -n "value_field" app config --glob '!app/services/page_layout_templates/templates/**'`
Expected: no output.

- [ ] **Step 7: Leave the changes uncommitted**

Run: `git add -N spec/requests/admin/maintenance/entities_reference_targets_spec.rb && git status --short`. Do not commit.

---

### Task 8: Create Entry supports references

**Agent:** anysys-backend-developer

**Files:**
- Modify: `app/services/entities/entry_form.rb`
- Modify: `spec/services/entities/entry_form_spec.rb`
- Modify: `spec/requests/admin/entity_entry_creation_spec.rb` (the Create Entry section, not the quick-add block)

**Interfaces:**
- Consumes: `Entities::ReferenceOptions` (T1) and the contract existence rule (T5).
- Produces:
  - `EntryForm::Field#reference`, which is `true` for an `entity_entries` attribute.
  - Select, radio and multi-select references are supported when the target is active and its display field is admin-visible and labelable; every other reference is a blocker.
  - Their choices are `ReferenceOptions` pairs.

- [ ] **Step 1: Prepare the test database**

Run: `RAILS_ENV=test TEST_ENV_NUMBER=28 bin/rails db:schema:load`

- [ ] **Step 2: Write the failing EntryForm examples**

In `spec/services/entities/entry_form_spec.rb`, replace the blocker example near line 219 (the one whose config is `options_source: "entity_entries", options: []`) with the block below. The fixtures stay valid under T9's definition rule and T10's trash guard:

- the hidden display field is labelable but hidden from admins;
- the course is trashed before anything references it.

```ruby
  describe "entity_entries references" do
    let(:course) do
      create(:entity, customer: customer, name: "Course", property_schema: [
        { "name" => "Title", "name_slug" => "title", "html_type" => "text" },
        { "name" => "Secret", "name_slug" => "secret", "html_type" => "text",
          "visibility" => { "admin" => false, "member" => false, "public" => false } }
      ].to_json)
    end

    def application_with(html_type: "select", label_field: "title", target: course)
      create(:entity, customer: customer, name: "Application", property_schema: [
        { "name" => "Course", "name_slug" => "course", "html_type" => html_type,
          "config" => { "options_source" => "entity_entries", "entity_id" => target.id.to_s, "label_field" => label_field } }
      ].to_json)
    end

    def blocker_slugs(entity) = described_class.new(entity: entity, customer: customer).blockers.map(&:slug)

    it "lists the target's records as choices and accepts any id for the contract to check" do
      biology = create(:entity_entry, customer: customer, entity: course, data: { title: "Biology" }.to_json)
      form = described_class.new(entity: application_with, customer: customer, params: { "course" => "999999" })

      field = form.groups.flat_map(&:fields).find { |item| item.slug == "course" }
      expect(field.reference).to be(true)
      expect(field.options).to eq([["Biology", biology.id.to_s]])
      expect(form.blockers).to be_empty
      expect(form.errors_for("course")).to be_empty
    end

    it "supports radio references" do
      expect(blocker_slugs(application_with(html_type: "radio"))).to be_empty
    end

    it "blocks a reference whose display field is hidden from admins" do
      expect(blocker_slugs(application_with(label_field: "secret"))).to eq(["course"])
    end

    it "blocks a reference to a trashed entity" do
      course.soft_delete
      expect(blocker_slugs(application_with)).to eq(["course"])
    end

    it "blocks a checkbox reference, which Create Entry would read as a boolean" do
      expect(blocker_slugs(application_with(html_type: "checkbox"))).to eq(["course"])
    end
  end
```

`customer` is the spec's existing `let`.

If `EntityAttributeAudience` refuses to hide an attribute from admins, the hidden-field example can't be built this way. In that case, delete it and keep the trashed-target example, which covers the same blocker path.

Run: `TEST_ENV_NUMBER=28 bundle exec rspec spec/services/entities/entry_form_spec.rb`
Expected: FAIL, because `reference` is an unknown Field member.

- [ ] **Step 3: Implement**

In `app/services/entities/entry_form.rb`:

- Add `:reference` to `Field` (after `:invalid_literal`).
- In `initialize`, add `@customer = customer` as the first line.
- In `describe(attribute)`:
  - before `Field.new`, add `reference = Entities::ReferenceLabels.reference?(attribute)`;
  - change the `options:` line to `options: reference ? reference_source(attribute).options : (options.is_a?(Array) ? options.filter_map { |option| option_pair(option) } : []),`;
  - add `reference: reference` to `Field.new` (after `invalid_literal: false`).
- In `supported?`, right after `return false unless HTML_TYPES.include?(field.html_type)`, add:

```ruby
      # A checkbox without options reads as a boolean here, so a reference
      # must be a select, radio or multi-select.
      return CHOICE_TYPES.include?(field.html_type) && reference_source(attribute).usable? if field.reference
```

- Add a private method:

```ruby
    def reference_source(attribute)
      (@reference_sources ||= {})[attribute["name_slug"]] ||= ReferenceOptions.new(
        entity_id: attribute.dig("config", "entity_id"), label_field: attribute.dig("config", "label_field"),
        customer_id: @customer.id, audience: EntityAttributeAudience::ADMIN
      )
    end
```

- In `normalize_input`, change the `invalid_choice` line to:

```ruby
        if !field.reference && attempted.any? { |value| !empty_literal?(value) && !choices.include?(value) }
          add_error(field.slug, "invalid_choice")
        end
```

  The contract checks a reference's ids against every record, not only the 200 that are listed.

Run the EntryForm spec again. Expected: PASS.

- [ ] **Step 4: Create Entry request examples (test, then confirm)**

In `spec/requests/admin/entity_entry_creation_spec.rb`, in the Create Entry `describe` (outside the quick-add block), add the examples below. They use the spec's existing signed-in admin, `customer`, and params shape; if the neighbouring create examples post `entry[data][...]` differently, mirror them.

```ruby
  describe "entity_entries references" do
    let(:course) do
      create(:entity, customer: customer, name: "Course",
                      property_schema: [{ "name" => "Title", "name_slug" => "title", "html_type" => "text" }].to_json)
    end
    let(:application) do
      create(:entity, customer: customer, name: "Application", property_schema: [
        { "name" => "Course", "name_slug" => "course", "html_type" => "select",
          "config" => { "options_source" => "entity_entries", "entity_id" => course.id.to_s, "label_field" => "title" } }
      ].to_json)
    end

    it "lists the target's records and stores the chosen record id" do
      biology = create(:entity_entry, customer: customer, entity: course, data: { title: "Biology" }.to_json)

      get new_admin_entity_entry_path(customer.id, application)
      expect(response.body).to include(">Biology</option>")

      expect {
        post admin_entity_entries_path(customer.id, application), params: { entry: { data: { course: biology.id.to_s } } }
      }.to change(EntityEntry.where(entity_id: application.id), :count).by(1)
      expect(EntityEntry.where(entity_id: application.id).last.data_json["course"]).to eq(biology.id.to_s)
    end

    it "rejects another tenant's record id" do
      foreign = create(:entity_entry, customer: create(:customer), entity: course, data: { title: "X" }.to_json)

      post admin_entity_entries_path(customer.id, application), params: { entry: { data: { course: foreign.id.to_s } } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include(CGI.escapeHTML(I18n.t("common.errors.dynamic.association_target_missing", field: "Course")))
    end
  end
```

Run: `TEST_ENV_NUMBER=28 bundle exec rspec spec/services/entities/entry_form_spec.rb spec/requests/admin/entity_entry_creation_spec.rb spec/components/admin/entities/entry_form_component_spec.rb`
Expected: all pass. If the base error isn't rendered in the form, report it: showing `errors[:base]` is the component's job. Do not edit the component yourself.

- [ ] **Step 5: Leave the changes uncommitted**

Run: `git status --short`. Do not commit.

---

### Task 9: Reference definition rules and fixture sweep

**Agent:** anysys-backend-developer

**Files:**
- Modify: `app/models/concerns/entity_schema_validation.rb`
- Modify: `config/locales/maint_core.en.yml`, `config/locales/maint_core.zh-CN.yml`
- Create: `spec/models/concerns/entity_reference_definitions_spec.rb`
- Modify, in the sweep:
  - the 21 spec files that hold `display_field: "id"` fixtures, listed in Step 6;
  - any other spec that saves an entity with an `entity_entries` dropdown lacking a valid display field.

**Interfaces:**
- Consumes: `Entities::ReferenceLabels` (T1).
- Produces:
  - When the definition changes, an entity save fails with `reference_target_missing`, `reference_label_field_invalid` or `association_display_field_invalid`.
  - Saves that only change status (trash or restore) are never checked.

- [ ] **Step 1: Prepare the test database**

Run: `RAILS_ENV=test TEST_ENV_NUMBER=29 bin/rails db:schema:load`

- [ ] **Step 2: Write the failing model spec**

Create `spec/models/concerns/entity_reference_definitions_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe EntitySchemaValidation, "reference definitions" do
  let_it_be(:customer) { create(:customer) }
  let(:course_schema) do
    [{ "name" => "Title", "name_slug" => "title", "html_type" => "text" },
     { "name" => "Notes", "name_slug" => "notes", "html_type" => "textarea" }]
  end
  let(:course) { create(:entity, customer: customer, name: "Course", property_schema: course_schema.to_json) }

  def dropdown(entity_id:, label_field: "title", name: "Course", slug: "course")
    { "name" => name, "name_slug" => slug, "html_type" => "select",
      "config" => { "options_source" => "entity_entries", "entity_id" => entity_id.to_s, "label_field" => label_field } }
  end

  def application(schema)
    build(:entity, customer: customer, name: "Application", property_schema: schema.to_json)
  end

  it "accepts a dropdown whose display field is a labelable attribute of the target" do
    expect(application([dropdown(entity_id: course.id)])).to be_valid
  end

  it "rejects a missing or foreign target" do
    foreign = create(:entity, customer: create(:customer), property_schema: course_schema.to_json)

    [999_999, foreign.id].each do |target_id|
      entity = application([dropdown(entity_id: target_id)])
      expect(entity).not_to be_valid
      expect(entity.errors[:property_schema]).to include(
        I18n.t("maint_core.errors.validations.reference_target_missing", field: "Course")
      )
    end
  end

  it "rejects a display field that is not labelable, unknown or id" do
    { "notes" => "Notes", "missing" => "missing", "id" => "id" }.each do |label_field, label|
      entity = application([dropdown(entity_id: course.id, label_field: label_field)])
      expect(entity).not_to be_valid
      expect(entity.errors[:property_schema]).to include(
        I18n.t("maint_core.errors.validations.reference_label_field_invalid",
               field: "Course", label: label, entity: course.display_label)
      )
    end
  end

  it "checks a self-reference against the schema being saved" do
    person = create(:entity, customer: customer, name: "Person",
                             property_schema: [{ "name" => "Name", "name_slug" => "name", "html_type" => "text" }].to_json)
    person.property_schema = [{ "name" => "Name", "name_slug" => "name", "html_type" => "textarea" },
                              dropdown(entity_id: person.id, label_field: "name", name: "Mentor", slug: "mentor")].to_json

    expect(person).not_to be_valid
    expect(person.errors[:property_schema]).to include(
      I18n.t("maint_core.errors.validations.reference_label_field_invalid",
             field: "Mentor", label: "Name", entity: person.display_label)
    )
  end

  it "rejects an association whose display field is not labelable" do
    student = build(:entity, customer: customer, name: "Student", property_schema: [].to_json, associations: [
      { "target_entity_id" => course.id.to_s, "target_entity_name" => "Course",
        "display_field" => "notes", "display_field_label" => "Notes" }
    ].to_json)

    expect(student).not_to be_valid
    expect(student.errors[:associations]).to include(
      I18n.t("maint_core.errors.validations.association_display_field_invalid", target_name: course.display_label, label: "Notes")
    )
  end

  it "does not check status-only saves, so trash and restore work after a target is deleted" do
    entity = application([dropdown(entity_id: course.id)])
    entity.save!
    entity.soft_delete
    course.destroy

    restored = Entity.unscope(where: :status).find(entity.id)
    expect(restored.restore).to be_truthy
  end
end
```

If `build(:entity, associations: ...)` doesn't accept a JSON string, pass the array the way `spec/models/concerns/bridge_entity_management_spec.rb` builds associations.

Run: `TEST_ENV_NUMBER=29 bundle exec rspec spec/models/concerns/entity_reference_definitions_spec.rb`
Expected: FAIL. The invalid definitions are reported as valid.

- [ ] **Step 3: Add the keys**

In `config/locales/maint_core.en.yml`, under `en.maint_core.errors.validations`, after `entity_has_associations:` (line 33):

```yaml
        reference_target_missing: "%{field}: the referenced entity doesn't exist"
        reference_label_field_invalid: "%{field}: display field %{label} must be a text, search, email, phone, URL, number or date field of %{entity}"
        association_display_field_invalid: "association with %{target_name}: display field %{label} must be a text, search, email, phone, URL, number or date field"
```

In `config/locales/maint_core.zh-CN.yml`, at the same position:

```yaml
        reference_target_missing: "%{field}：引用的实体不存在"
        reference_label_field_invalid: "%{field}：显示字段“%{label}”须为%{entity}的文本、搜索、邮箱、电话、网址、数字或日期字段"
        association_display_field_invalid: "与%{target_name}的关联：显示字段“%{label}”须为文本、搜索、邮箱、电话、网址、数字或日期字段"
```

Run: `locale_parity maint_core`
Expected: no output.

- [ ] **Step 4: Implement the rules**

In `app/models/concerns/entity_schema_validation.rb`, inside `included do`, after `validate :validate_computed_definitions`, add:

```ruby
    validate :validate_reference_definitions, if: :reference_definitions_changed?
```

Then add these private methods after `validate_association_target_exists`:

```ruby
  # Definition edits only: a status-only save (trash, restore) never fails on
  # a reference whose target went away in the meantime.
  def reference_definitions_changed?
    new_record? || will_save_change_to_property_schema? || will_save_change_to_associations?
  end

  def validate_reference_definitions
    reference_attributes.each { |attr| validate_reference_attribute(attr) }
    validate_association_display_fields unless bridge_entity?
  end

  # Entity-records dropdowns, including an association's extra attributes.
  def reference_attributes
    extras = associations_list.flat_map { |assoc| Array(assoc["additional_attributes"]) }
    (schema_attributes + extras).select { |attr| Entities::ReferenceLabels.reference?(attr) }
  end

  def validate_reference_attribute(attr)
    field = attr["display_label"].presence || attr["name"].presence || attr["name_slug"].to_s
    target = reference_target(attr.dig("config", "entity_id"))
    unless target
      errors.add(:property_schema, I18n.t("maint_core.errors.validations.reference_target_missing", field: field))
      return
    end

    label_field = attr.dig("config", "label_field").to_s
    return if Entities::ReferenceLabels.labelable?(attribute_on(target, label_field))

    errors.add(:property_schema, I18n.t("maint_core.errors.validations.reference_label_field_invalid",
                                        field: field, label: attribute_name_on(target, label_field),
                                        entity: target.display_label))
  end

  # A blank display field and a missing target are reported by
  # validate_association_display_field_present / validate_association_target_exists.
  def validate_association_display_fields
    associations_list.each do |assoc|
      display_field = assoc["display_field"].to_s.strip
      target = reference_target(assoc["target_entity_id"])
      next if display_field.empty? || target.nil?
      next if Entities::ReferenceLabels.labelable?(attribute_on(target, display_field))

      errors.add(:associations, I18n.t("maint_core.errors.validations.association_display_field_invalid",
                                       target_name: target.display_label,
                                       label: assoc["display_field_label"].presence || display_field))
    end
  end

  # Any status, so restoring after a target was trashed still works. A shared
  # default may target shared entities; a customer's entity or a tenant's
  # override may also target that customer's own.
  def reference_target(target_id)
    id = target_id.to_s.strip
    return unless id.match?(/\A\d+\z/)
    return self if persisted? && id == self.id.to_s

    owner = customer_id || override_customer_id
    Entity.unscope(where: :status).where(customer_id: [owner, nil].uniq).find_by(id: id)
  end

  # A self-reference reads the schema being saved, not the stored one.
  def attribute_on(target, slug)
    schema = target.equal?(self) ? schema_attributes : Array(target.property_schema_json)
    schema.find { |attr| attr.is_a?(Hash) && attr["name_slug"].to_s == slug.to_s }
  end

  def attribute_name_on(target, slug)
    attribute_on(target, slug)&.dig("name").presence || slug.to_s
  end
```

Run the new spec again. Expected: PASS.

- [ ] **Step 5: Sweep the fixtures**

These spec files hold 48 `display_field: "id"` fixtures between them:

- `spec/integration/computed_fields_integration_spec.rb`
- `spec/models/concerns/bridge_entity_management_spec.rb`
- `spec/models/concerns/entity_versioning_spec.rb`
- `spec/models/entity_backend_audit_spec.rb`
- `spec/models/entity_spec.rb`
- `spec/requests/admin/entity_entry_creation_spec.rb`
- `spec/requests/admin/maintenance/entities_route_audit_spec.rb`
- `spec/requests/admin/maintenance/entities_spec.rb`
- `spec/services/admin/entities/directory_spec.rb`
- `spec/services/ai_assistant/assistant/finalizer_spec.rb`
- `spec/services/ai_assistant/assistant/mentions_spec.rb`
- `spec/services/code_generators/reference_sources_spec.rb`
- `spec/services/entities/computed_options_spec.rb`
- `spec/services/entities/promote_version_spec.rb`
- `spec/services/entities_contributor_spec.rb`
- `spec/services/entity_association_graph_spec.rb`
- `spec/services/entity_definitions/api/change_set_spec.rb`
- `spec/services/entity_definitions/catalog_spec.rb`
- `spec/services/entity_definitions/normalizer_spec.rb`
- `spec/services/entity_definitions/persist_spec.rb`
- `spec/services/operations/update_entity_spec.rb`

For each fixture:

- Point `display_field` at a text attribute of the target, and set `display_field_label` to that attribute's name. If the target's schema in that spec has no text attribute, add one (for example `{ "name" => "Name", "name_slug" => "name", "html_type" => "text" }`) and use it.
- Where an example asserts the bridge's `label_field`, update the expectation to the new slug.
- Don't change what an example tests. Only make its fixture valid.

Then find every remaining failure the new rule causes:

```bash
TEST_ENV_NUMBER=29 bundle exec rspec spec/models spec/services spec/requests spec/components spec/integration spec/contracts --format progress 2>&1 | tail -80
```

For each failure whose message contains `the referenced entity doesn't exist`, `display field` or `association with`, fix the fixture in the same way: give the dropdown a real target with a labelable `label_field`. Repeat until no such failure remains. Any failure unrelated to this rule must be reported, not fixed.

- [ ] **Step 6: Confirm the sweep**

Run: `rg -n --pcre2 "display_field['\"]?\s*(=>|:)\s*['\"]id['\"]" spec`
Expected: no output.

Run: `TEST_ENV_NUMBER=29 bundle exec rspec spec/models/concerns/entity_reference_definitions_spec.rb` together with the 21 swept files listed above.
Expected: all pass.

- [ ] **Step 7: Leave the changes uncommitted**

Run: `git add -N spec/models/concerns/entity_reference_definitions_spec.rb && git status --short`. Do not commit.

---

### Task 10: Reference dependents, trash guard, display-field save guard

**Agent:** anysys-backend-developer

**Files:**
- Create: `app/services/entities/reference_dependents.rb`
- Create: `spec/services/entities/reference_dependents_spec.rb`
- Create: `spec/models/concerns/entity_reference_guards_spec.rb`
- Modify: `app/models/concerns/bridge_entity_management.rb` (`soft_delete`)
- Modify: `app/models/concerns/entity_schema_validation.rb`
- Modify: `config/locales/maint_core.en.yml`, `config/locales/maint_core.zh-CN.yml`

**Interfaces:**
- Consumes: `Entities::ReferenceLabels` (T1), `Page.input_fields_in` (T5), `Page.launched`, `Page#visible_audiences`, and `Versionable` heads (`entity_customer_heads`, `page_customer_heads`, `current_version.content.payload`).
- Produces:
  - `Entities::ReferenceDependents`:
    - factories `.for_trash(entity)` and `.for_save(entity)`;
    - `#references`, which returns `[Reference(entity, field_label, label_field)]`;
    - `#forms(label_field)`, which returns `[Form(page, field_label, audiences)]`;
    - `.field_paths(references)`, which returns `Array<String>`.
  - The trash guard returns `entity_referenced`.
  - The save guard returns `display_field_in_use` and `display_field_hidden_from_form`.

- [ ] **Step 1: Prepare the test database**

Run: `RAILS_ENV=test TEST_ENV_NUMBER=30 bin/rails db:schema:load`

- [ ] **Step 2: Write the failing dependents spec**

Create `spec/services/entities/reference_dependents_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Entities::ReferenceDependents do
  let_it_be(:customer) { create(:customer) }
  let_it_be(:other_customer) { create(:customer) }
  let(:title) { { "name" => "Title", "name_slug" => "title", "html_type" => "text" } }

  def dropdown(target, name: "Course", slug: "course", label_field: "title")
    { "name" => name, "name_slug" => slug, "html_type" => "select",
      "config" => { "options_source" => "entity_entries", "entity_id" => target.id.to_s, "label_field" => label_field } }
  end

  def form_config(target, label_field: "title", nested: false)
    field = { "id" => "f1", "label" => "Pick a course", "html_type" => "select",
              "dynamic_options" => { "options_source" => "entity_entries", "entity_id" => target.id.to_s, "label_field" => label_field } }
    field = { "field_type" => "columns", "columns" => [{ "fields" => [field] }] } if nested
    { "metadata" => {}, "pages" => [{ "fields" => [field] }] }
  end

  describe "#references" do
    it "finds dropdowns of the tenant's other entities and skips trashed, bridge and self references" do
      course = create(:entity, customer: customer, name: "Course", property_schema: [title].to_json)
      application = create(:entity, customer: customer, name: "Application", property_schema: [dropdown(course)].to_json)
      trashed = create(:entity, customer: customer, name: "Old", property_schema: [dropdown(course, name: "Old course", slug: "old")].to_json)
      trashed.soft_delete
      create(:entity, customer: other_customer, name: "Foreign", property_schema: [title].to_json)

      refs = described_class.for_trash(course).references

      expect(refs.map { |ref| [ref.entity, ref.field_label, ref.label_field] }).to eq([[application, "Course", "title"]])
      expect(described_class.field_paths(refs)).to eq(["Application › Course"])
    end

    it "sees a shared entity's referrers in every tenant and in tenant overrides" do
      campus = Current.set(shared_resources_mode: true) { create(:entity, :shared, name: "Campus", property_schema: [title].to_json) }
      create(:entity, customer: other_customer, name: "Room", property_schema: [dropdown(campus, name: "Campus", slug: "campus")].to_json)
      event = Current.set(shared_resources_mode: true) { create(:entity, :shared, name: "Event", property_schema: [title].to_json) }
      Current.set(customer: customer) do
        Entity.find(event.id).update!(property_schema: [title, dropdown(campus, name: "Venue", slug: "venue")].to_json)
      end

      expect(described_class.for_trash(campus).references.map(&:field_label)).to contain_exactly("Campus", "Venue")
    end

    it "reports associations to the entity with their display field" do
      course = create(:entity, customer: customer, name: "Course", property_schema: [title].to_json)
      create(:entity, customer: customer, name: "Student", property_schema: [title].to_json, associations: [
        { "target_entity_id" => course.id.to_s, "target_entity_name" => "Course", "display_field" => "title", "display_field_label" => "Title" }
      ].to_json)

      expect(described_class.for_save(course).references.map(&:label_field)).to include("title")
    end
  end

  describe "#forms" do
    it "lists launched forms whose dropdown shows the field, including nested columns" do
      course = create(:entity, customer: customer, name: "Course", property_schema: [title].to_json)
      launched = create(:page, customer: customer, launched: true)
      launched.update!(configuration_json: form_config(course, nested: true))
      offline = create(:page, customer: customer, launched: false)
      offline.update!(configuration_json: form_config(course))

      forms = described_class.for_save(course).forms("title")

      expect(forms.map(&:page)).to eq([launched])
      expect(forms.first.field_label).to eq("Pick a course")
      expect(forms.first.audiences).to eq(launched.visible_audiences)
      expect(described_class.for_save(course).forms("code")).to eq([])
    end
  end
end
```

If `update!(configuration_json: ...)` on `Page` doesn't commit a version, build the page through the configuration transient in `spec/factories/pages.rb` instead.

Run: `TEST_ENV_NUMBER=30 bundle exec rspec spec/services/entities/reference_dependents_spec.rb`
Expected: FAIL with `uninitialized constant Entities::ReferenceDependents`.

- [ ] **Step 3: Implement `Entities::ReferenceDependents`**

Create `app/services/entities/reference_dependents.rb`:

```ruby
# frozen_string_literal: true

module Entities
  # What reads an entity's records as references, in the definitions the
  # affected tenants actually use: customer-owned definitions, shared defaults
  # and every tenant override of them. Backs the trash guard and the
  # display-field save guard.
  class ReferenceDependents
    Reference = Data.define(:entity, :field_label, :label_field)
    Form = Data.define(:page, :field_label, :audiences)

    OPTIONS_SOURCE = ReferenceLabels::OPTIONS_SOURCE

    # A shared entity can be referenced from any tenant; a customer's only
    # from that customer.
    def self.for_trash(entity)
      new(entity, tenant_ids: entity.customer_id ? [entity.customer_id] : nil)
    end

    # The tenants whose view of `entity` this save changes: its owner, the
    # tenant whose override is being written, or, for a shared default, every
    # tenant that has no override of its own.
    def self.for_save(entity)
      if entity.customer_id
        new(entity, tenant_ids: [entity.customer_id])
      elsif (tenant_id = entity.override_customer_id)
        new(entity, tenant_ids: [tenant_id])
      else
        new(entity, tenant_ids: nil, excluded_tenant_ids: entity.entity_customer_heads.pluck(:customer_id))
      end
    end

    def self.field_paths(references)
      references.map do |ref|
        I18n.t("common.references.field_path", entity: ref.entity.display_label, field: ref.field_label)
      end.uniq
    end

    def initialize(entity, tenant_ids:, excluded_tenant_ids: [])
      @entity = entity
      @tenant_ids = tenant_ids
      @excluded = excluded_tenant_ids.to_set
    end

    def references
      @references ||= definitions(referrers).flat_map { |record, payload| references_in(record, payload) }
    end

    # Launched forms whose entity-records dropdowns list this entity by `label_field`.
    def forms(label_field)
      slug = label_field.to_s
      launched_pages.flat_map do |page, config|
        Page.input_fields_in(config).filter_map do |field|
          dynamic = field["dynamic_options"]
          next unless dynamic.is_a?(Hash) && dynamic["options_source"] == OPTIONS_SOURCE
          next unless dynamic["entity_id"].to_s == @entity.id.to_s && dynamic["label_field"].to_s == slug

          Form.new(page: page, field_label: field["label"].presence || field["id"].to_s, audiences: page.visible_audiences)
        end
      end
    end

    private

    # Other non-bridge entities; trashed ones are outside the default scope.
    # A bridge's reference mirrors its source's association, which is
    # reported from the source.
    def referrers
      scope = Entity.non_bridge.where.not(id: @entity.id)
      owned = @tenant_ids ? scope.where(customer_id: @tenant_ids) : scope.where.not(customer_id: nil)
      owned.to_a + scope.where(customer_id: nil).to_a
    end

    def launched_pages
      @launched_pages ||= begin
        scope = Page.launched
        owned = @tenant_ids ? scope.where(customer_id: @tenant_ids) : scope.where.not(customer_id: nil)
        definitions(owned.to_a + scope.where(customer_id: nil).to_a)
      end
    end

    # [[record, parsed payload], ...] for every definition line that applies
    # to an affected tenant.
    def definitions(records)
      records.flat_map do |record|
        applicable_versions(record).filter_map do |version|
          payload = version&.content&.payload
          [record, JSON.parse(payload)] if payload.present?
        rescue JSON::ParserError
          nil
        end
      end
    end

    def applicable_versions(record)
      return [record.current_version] if record.customer_id

      reflection = record.class.versionable_options[:customer_head_reflection]
      heads = record.public_send(reflection).includes(current_version: :content).to_a
      overridden = heads.map(&:customer_id)
      versions = heads.select { |head| affected?(head.customer_id) }.map(&:current_version)
      versions << record.current_version if @tenant_ids.nil? || (@tenant_ids - overridden).any?
      versions
    end

    def affected?(tenant_id)
      (@tenant_ids.nil? || @tenant_ids.include?(tenant_id)) && !@excluded.include?(tenant_id)
    end

    def references_in(record, payload)
      schema = Array(payload["property_schema"]).grep(Hash)
      associations = Array(payload["associations"]).grep(Hash)
      extras = associations.flat_map { |assoc| Array(assoc["additional_attributes"]).grep(Hash) }

      dropdowns = (schema + extras).select { |attr| references_entity?(attr) }.map do |attr|
        Reference.new(entity: record,
                      field_label: attr["display_label"].presence || attr["name"].presence || attr["name_slug"].to_s,
                      label_field: attr.dig("config", "label_field").to_s)
      end
      links = associations.select { |assoc| assoc["target_entity_id"].to_s == @entity.id.to_s }.map do |assoc|
        Reference.new(entity: record, field_label: assoc["target_entity_name"].presence || @entity.display_label,
                      label_field: assoc["display_field"].to_s)
      end
      dropdowns + links
    end

    def references_entity?(attr)
      ReferenceLabels.reference?(attr) && attr.dig("config", "entity_id").to_s == @entity.id.to_s
    end
  end
end
```

Run the dependents spec again. Expected: PASS.

- [ ] **Step 4: Write the failing guard spec**

Create `spec/models/concerns/entity_reference_guards_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Entity reference guards" do
  let_it_be(:customer) { create(:customer) }
  let(:title) { { "name" => "Title", "name_slug" => "title", "html_type" => "text" } }
  let!(:course) { create(:entity, customer: customer, name: "Course", property_schema: [title].to_json) }

  def dropdown(target)
    { "name" => "Course", "name_slug" => "course", "html_type" => "select",
      "config" => { "options_source" => "entity_entries", "entity_id" => target.id.to_s, "label_field" => "title" } }
  end

  describe "trash" do
    it "refuses to trash an entity other entities reference, naming the fields" do
      create(:entity, customer: customer, name: "Application", property_schema: [dropdown(course)].to_json)

      expect(course.soft_delete).to be(false)
      expect(course.errors[:base]).to include(
        I18n.t("maint_core.errors.validations.entity_referenced", fields: "Application › Course")
      )
      expect(Entity.find(course.id)).to be_present
    end

    it "trashes an entity nothing references" do
      expect(course.soft_delete).to be_truthy
    end
  end

  describe "saving a display field" do
    before { create(:entity, customer: customer, name: "Application", property_schema: [dropdown(course)].to_json) }

    it "refuses to retype or delete a display field others use" do
      course.property_schema = [title.merge("html_type" => "textarea")].to_json
      expect(course.save).to be(false)
      expect(course.errors[:property_schema]).to include(
        I18n.t("maint_core.errors.validations.display_field_in_use", label: "Title", fields: "Application › Course")
      )

      fresh = Entity.find(course.id)
      fresh.property_schema = [].to_json
      expect(fresh.save).to be(false)
    end

    it "refuses to hide a display field from an audience of a launched form that lists it" do
      page = create(:page, customer: customer, launched: true, name: "Apply")
      page.update!(configuration_json: { "metadata" => {}, "pages" => [{ "fields" => [
        { "id" => "f1", "label" => "Course", "html_type" => "select",
          "dynamic_options" => { "options_source" => "entity_entries", "entity_id" => course.id.to_s, "label_field" => "title" } }
      ] }] })
      audience = page.visible_audiences.first

      fresh = Entity.find(course.id)
      fresh.property_schema = [title.merge("visibility" => { audience => false })].to_json

      expect(fresh.save).to be(false)
      expect(fresh.errors[:property_schema]).to include(
        I18n.t("maint_core.errors.validations.display_field_hidden_from_form",
               label: "Title", audience: I18n.t("common.visibility.#{audience}"), form: "Apply", field: "Course")
      )
    end

    it "allows unrelated edits" do
      fresh = Entity.find(course.id)
      fresh.property_schema = [title, { "name" => "Code", "name_slug" => "code", "html_type" => "text" }].to_json

      expect(fresh.save).to be(true)
    end
  end
end
```

Run: `TEST_ENV_NUMBER=30 bundle exec rspec spec/models/concerns/entity_reference_guards_spec.rb`
Expected: FAIL. Trash succeeds, and so does the retype.

- [ ] **Step 5: Add the keys**

In `config/locales/maint_core.en.yml`, under `errors.validations`, after the T9 keys:

```yaml
        entity_referenced: "Cannot delete an entity that other entities reference: %{fields}. Remove those fields or point them at another entity first."
        display_field_in_use: "%{label} is the display field of %{fields}. Keep it as a text, search, email, phone, URL, number or date field, or choose another display field there first."
        display_field_hidden_from_form: "%{label} must stay visible to %{audience}: the launched form %{form} shows it in %{field}."
```

In `config/locales/maint_core.zh-CN.yml`, at the same position:

```yaml
        entity_referenced: "无法删除仍被其他实体引用的实体：%{fields}。请先移除这些字段，或改为引用其他实体。"
        display_field_in_use: "“%{label}”是%{fields}的显示字段。请保留为文本、搜索、邮箱、电话、网址、数字或日期字段，或先在那里改用其他显示字段。"
        display_field_hidden_from_form: "“%{label}”须对%{audience}保持可见：已上线的表单“%{form}”在“%{field}”中显示该字段。"
```

Run: `locale_parity maint_core`
Expected: no output.

- [ ] **Step 6: Trash guard**

In `app/models/concerns/bridge_entity_management.rb`, `soft_delete`, add this after the `has_active_associations?` block and before `deleted = false`:

```ruby
    references = bridge_entity? ? [] : Entities::ReferenceDependents.for_trash(self).references
    if references.any?
      errors.add(:base, I18n.t("maint_core.errors.validations.entity_referenced",
                               fields: Entities::ReferenceDependents.field_paths(references).to_sentence))
      return false
    end
```

Change the method comment to `# Refuse to trash an entity that has associations or that other entities reference`.

- [ ] **Step 7: Save guard**

In `app/models/concerns/entity_schema_validation.rb`, inside `included do`, after T9's line, add:

```ruby
    validate :validate_referenced_display_fields, if: :referenced_display_fields_check?
```

Then add these private methods after T9's methods:

```ruby
  def referenced_display_fields_check?
    persisted? && !bridge_entity? && will_save_change_to_property_schema?
  end

  # A display field others rely on must stay labelable, and visible to every
  # audience of a launched form that lists it. Only a change that breaks a
  # working reference is refused, so an existing inconsistency never blocks
  # unrelated edits.
  def validate_referenced_display_fields
    dependents = Entities::ReferenceDependents.for_save(self)
    current = schema_attributes.grep(Hash).index_by { |attr| attr["name_slug"].to_s }
    previous = Array(JSON.parse(property_schema_was.presence || "[]")).grep(Hash).index_by { |attr| attr["name_slug"].to_s }

    dependents.references.group_by(&:label_field).each do |slug, refs|
      next if slug.blank? || !Entities::ReferenceLabels.labelable?(previous[slug])
      next if Entities::ReferenceLabels.labelable?(current[slug])

      errors.add(:property_schema, I18n.t("maint_core.errors.validations.display_field_in_use",
                                          label: previous[slug]["name"].presence || slug,
                                          fields: Entities::ReferenceDependents.field_paths(refs).to_sentence))
    end

    current.each do |slug, attr|
      next unless previous[slug]

      dependents.forms(slug).each do |form|
        audience = form.audiences.find do |aud|
          EntityAttributeAudience.visible_to?(previous[slug], aud) && !EntityAttributeAudience.visible_to?(attr, aud)
        end
        next unless audience

        errors.add(:property_schema, I18n.t("maint_core.errors.validations.display_field_hidden_from_form",
                                            label: attr["name"].presence || slug, audience: I18n.t("common.visibility.#{audience}"),
                                            form: form.page.name, field: form.field_label))
      end
    end
  rescue JSON::ParserError
    nil
  end
```

- [ ] **Step 8: Run the task's specs and the neighbours**

Run: `rg -l "soft_delete|restore" spec/requests/admin/maintenance | head -5`. Then run `TEST_ENV_NUMBER=30 bundle exec rspec spec/services/entities/reference_dependents_spec.rb spec/models/concerns spec/models/entity_spec.rb spec/requests/admin/maintenance/entities_spec.rb <files rg listed>`.
Expected: all pass.

- [ ] **Step 9: Leave the changes uncommitted**

Run: `git add -N app/services/entities/reference_dependents.rb spec/services/entities/reference_dependents_spec.rb spec/models/concerns/entity_reference_guards_spec.rb && git status --short`. Do not commit.

---

### Task 11: Assistant reference violations

**Agent:** anysys-backend-developer

**Files:**
- Modify: `app/services/entity_definitions/api/semantic_validator.rb`
- Modify: `config/locales/operations_entity.en.yml`, `config/locales/operations_entity.zh-CN.yml`
- Modify: `spec/services/entity_definitions/api/semantic_validator_spec.rb`
- Modify: `spec/services/operations/update_entity_spec.rb` (two end-to-end examples)

**Interfaces:**
- Consumes: `Entities::ReferenceLabels` (T1), `Entities::ReferenceDependents` (T10), and `Mapper#attribute_to_stored`.
- Produces four violation codes:
  - `options.label_field_not_labelable`, with `field` and `entity`;
  - `association.display_field_not_labelable`, with `field` and `entity`;
  - `attribute.display_field_in_use`, with `slug` and `fields`;
  - `attribute.display_field_hidden`, with `slug`, `audience` (the key) and `form`.

- [ ] **Step 1: Prepare the test database**

Run: `RAILS_ENV=test TEST_ENV_NUMBER=31 bin/rails db:schema:load`

- [ ] **Step 2: Write the failing examples**

In `spec/services/entity_definitions/api/semantic_validator_spec.rb`, add the block below. `for_create` returns violations, and `customer` is the spec's existing `let`:

```ruby
  describe "reference display fields" do
    let(:course_spec) do
      { "name" => "Course", "attributes" => [
        { "name" => "Title", "slug" => "title", "html_type" => "text" },
        { "name" => "Summary", "slug" => "summary", "html_type" => "textarea" }
      ] }
    end

    def application_with(label_field)
      { "name" => "Application", "attributes" => [
        { "name" => "Course", "slug" => "course", "html_type" => "select",
          "options" => { "source" => "entity_entries", "entity" => "Course", "label_field" => label_field } }
      ] }
    end

    def codes(specs) = described_class.for_create(specs, customer: customer).map(&:code)

    it "rejects a label field that cannot label a choice, including id" do
      %w[summary id].each do |label_field|
        expect(codes([course_spec, application_with(label_field)])).to include("options.label_field_not_labelable")
      end
    end

    it "accepts a labelable label field and reports an unknown one as not found" do
      expect(codes([course_spec, application_with("title")]))
        .not_to include("options.label_field_not_labelable", "options.field_not_found")
      expect(codes([course_spec, application_with("nope")])).to include("options.field_not_found")
    end

    it "rejects an association display field that cannot label a record" do
      student = { "name" => "Student", "attributes" => [{ "name" => "Name", "slug" => "name", "html_type" => "text" }],
                  "associations" => [{ "related_entity" => "Course", "display_field" => "summary", "display_field_label" => "Summary" }] }

      expect(codes([course_spec, student])).to include("association.display_field_not_labelable")
    end
  end
```

In `spec/services/operations/update_entity_spec.rb`, add two examples using the spec's own `execute` helper and setup:

1. Retyping a display field:
   - Create a Course with a text `title`.
   - Create an Application whose dropdown lists Course by `title`.
   - Run `update_entity` on Course with `{"op":"update_attribute","slug":"title","set":{"html_type":"textarea"}}` and the current `expected_version`.
   - Expect `outcome.violations.map(&:code)` to include `"attribute.display_field_in_use"`, and that violation's `details["fields"]` to eq `"Application › Course"`.
2. Hiding a display field:
   - Create a launched page with public visibility whose dropdown lists Course by `title`. Set visibility the way the spec's other page fixtures do.
   - Run `update_entity` setting `access.visible_to.public` to `false` on `title`.
   - Expect a violation `"attribute.display_field_hidden"` with `details` including `"slug" => "title"`, `"audience" => "public"` and `"form" => page.name`.

Run: `TEST_ENV_NUMBER=31 bundle exec rspec spec/services/entity_definitions/api/semantic_validator_spec.rb spec/services/operations/update_entity_spec.rb`
Expected: FAIL. The codes are missing.

- [ ] **Step 3: Add the violation messages**

In `config/locales/operations_entity.en.yml`, under `operations.violations`:

- in the `options:` section, add:

```yaml
        label_field_not_labelable: "The field %{field} on entity %{entity} can't label a choice. Use a text, search, email, tel, url, number or date field."
```

- in the `association:` section, add:

```yaml
        display_field_not_labelable: "The display field %{field} on entity %{entity} must be a text, search, email, tel, url, number or date field."
```

- in the `attribute:` section, add:

```yaml
        display_field_in_use: "The attribute %{slug} is the display field of %{fields}. Keep it as a text, search, email, tel, url, number or date field, or change the display field there first."
        display_field_hidden: "The attribute %{slug} must stay visible to %{audience} because the launched form %{form} lists it."
```

In `config/locales/operations_entity.zh-CN.yml`, at the same positions:

```yaml
        label_field_not_labelable: "实体 %{entity} 上的字段 %{field} 不能作为选项标签，请使用文本、搜索、邮箱、电话、网址、数字或日期字段。"
```

```yaml
        display_field_not_labelable: "实体 %{entity} 上的显示字段 %{field} 须为文本、搜索、邮箱、电话、网址、数字或日期字段。"
```

```yaml
        display_field_in_use: "属性 %{slug} 是%{fields}的显示字段。请保留为文本、搜索、邮箱、电话、网址、数字或日期字段，或先在那里更换显示字段。"
        display_field_hidden: "属性 %{slug} 须对 %{audience} 保持可见，因为已上线的表单 %{form} 使用了该字段。"
```

- [ ] **Step 4: Implement the labelable checks**

In `semantic_validator.rb`:

- In `validate_options`'s `entity_entries` branch, replace T2's `label_field` check with:

```ruby
          validate_label_slug(attr_pointer(attr, "options", "label_field"), target, options["label_field"],
                              missing: "options.field_not_found", unlabelable: "options.label_field_not_labelable")
```

- In `validate_associations`, replace the `display = ...` block (the two lines starting `display = assoc["display_field"].to_s` through its `end`) with:

```ruby
          validate_label_slug(assoc_pointer(target, "display_field"), target, assoc["display_field"],
                              missing: "association.display_field_not_found", unlabelable: "association.display_field_not_labelable")
```

- Add these private methods after `lookup_field?`:

```ruby
      # A label or display field must be an attribute of the target that
      # Entities::ReferenceLabels can show; `id` never is. An unknown entity
      # is already reported where it is named.
      def validate_label_slug(pointer, entity_name, slug, missing:, unlabelable:)
        slug = slug.to_s
        return if slug.blank? || !known_entity?(entity_name)

        attribute = stored_attribute(entity_name, slug)
        if attribute.nil? && !SYSTEM_FIELDS.include?(slug)
          add(pointer, missing, "field" => slug, "entity" => entity_name)
        elsif !Entities::ReferenceLabels.labelable?(attribute)
          add(pointer, unlabelable, "field" => slug, "entity" => entity_name)
        end
      end

      # `slug` on `entity_name` in stored form, as this call leaves it: from a
      # spec in this call, else the catalog, else the record.
      def stored_attribute(entity_name, slug)
        spec = @specs_by_name[entity_name]
        if spec
          attr = Array(spec["attributes"]).find { |item| attribute_slug(item) == slug }
          return attr && mapper.attribute_to_stored(attr)
        end

        doc = @catalog[entity_name]
        schema = doc ? doc["property_schema"] : Entity.where(customer_id: customer.id).non_bridge.find_by(name: entity_name)&.property_schema_json
        Array(schema).find { |item| item.is_a?(Hash) && item["name_slug"].to_s == slug }
      end
```

- [ ] **Step 5: Implement the update-mode save guard**

In `validate_update`, replace `@specs.each_with_index { |spec, index| validate_spec(spec, index) }` with:

```ruby
        @specs.each_with_index { |spec, index| validate_spec(spec, index) }
        # Only an otherwise valid update reaches the guard, so every
        # attribute maps to a stored shape.
        @specs.each_with_index { |spec, index| guard_display_fields(spec, index) } if @violations.empty?
```

Then add this private method:

```ruby
      # update_entity: a display field that other entities or launched forms
      # rely on must stay labelable, and visible to those forms' audiences.
      # Mirrors EntitySchemaValidation#validate_referenced_display_fields.
      def guard_display_fields(spec, index)
        record = Entity.where(customer_id: customer.id).non_bridge.find_by(name: spec["name"].to_s)
        return unless record

        @entity_index = index
        @spec = spec
        dependents = Entities::ReferenceDependents.for_save(record)
        previous = Array(record.property_schema_json).grep(Hash).index_by { |attr| attr["name_slug"].to_s }
        current = Array(spec["attributes"]).to_h { |attr| [attribute_slug(attr), mapper.attribute_to_stored(attr)] }

        dependents.references.group_by(&:label_field).each do |slug, refs|
          next if slug.blank? || !Entities::ReferenceLabels.labelable?(previous[slug])
          next if Entities::ReferenceLabels.labelable?(current[slug])

          add(origin_or("attribute", slug), "attribute.display_field_in_use",
              "slug" => slug, "fields" => Entities::ReferenceDependents.field_paths(refs).to_sentence)
        end

        current.each do |slug, stored|
          next unless previous[slug]

          dependents.forms(slug).each do |form|
            audience = form.audiences.find do |aud|
              EntityAttributeAudience.visible_to?(previous[slug], aud) && !EntityAttributeAudience.visible_to?(stored, aud)
            end
            next unless audience

            add(origin_or("attribute", slug, "access"), "attribute.display_field_hidden",
                "slug" => slug, "audience" => audience, "form" => form.page.name)
          end
        end
      end
```

- [ ] **Step 6: Run the specs, the lint and the locale parity checks**

Run: `TEST_ENV_NUMBER=31 bundle exec rspec spec/services/entity_definitions spec/services/operations && locale_parity operations_entity`
Expected: all pass, including `contract_lint_spec` (key and interpolation parity) and `locales_spec`, and parity prints nothing.

- [ ] **Step 7: Leave the changes uncommitted**

Run: `git status --short`. Do not commit.

---

### Task 12: Plan 1 docs

**Agent:** anysys-backend-developer

**Files:**
- Modify: `doc/reference/en/entity-builder.md`, `doc/reference/zh-CN/entity-builder.md`
- Modify: `doc/reference/en/page-rendering.md`, `doc/reference/zh-CN/page-rendering.md`
- Modify: `doc/reference/en/flowchart-runtime.md`, `doc/reference/zh-CN/flowchart-runtime.md`
- Modify: `doc/reference/en/operations-api.md`, `doc/reference/zh-CN/operations-api.md`

Each zh-CN page mirrors the en page's structure. Find each zh-CN anchor by its matching heading or table, then insert the zh-CN text given below at the same place.

- [ ] **Step 1: `entity-builder.md`: references section**

After the bridge paragraph (en line 79, the one starting `` `BridgeEntityManagement#sync_bridge_entities!` ``), add:

```markdown
### Entity-record dropdowns

A select or radio attribute can list another entity's records: the editor's **Use Entity Records** mode saves `config: { options_source: "entity_entries", entity_id:, label_field: }`. An entry always stores the record **id**; `label_field` (the display field) only labels the choices. There is no `value_field`.

- **Display fields.** `Entities::ReferenceLabels.labelable?` allows text, search, email, tel, url, number and date input attributes; never calculated, computed or reference fields, and never `id`. The same rule applies to an association's `display_field`. `GET /:cid/admin/maintenance/entities.json` marks each attribute `labelable`, and the editor offers only those.
- **Choices.** `Entities::ReferenceOptions` lists the target's records in the viewing tenant, ordered by label then id, at most 200. A record without a label reads `Untitled (#id)`; repeated labels are numbered `label (#id)`. The list is empty when the target is trashed, a bridge, foreign, or when the display field is hidden from the viewer's audience.
- **Definition rules.** Saving a definition rejects a dropdown whose target doesn't exist (`reference_target_missing`) or whose display field isn't labelable (`reference_label_field_invalid`), and an association whose display field isn't (`association_display_field_invalid`). Status-only saves (trash, restore) skip these checks.
- **Trash.** `soft_delete` refuses an entity that other entities still reference and names them (`entity_referenced`). `Entities::ReferenceDependents` finds referrers in customer-owned definitions, shared defaults and every tenant override.
- **Display field changes.** Deleting or retyping a field other entities display is refused (`display_field_in_use`), as is hiding it from an audience of a launched form that lists it (`display_field_hidden_from_form`).
- **Visibility.** A dropdown lists the display field of every record to everyone who can open the form, so a person's name or ID used as a display field should be hidden from members and the public unless the form is admin-only.
```

zh-CN, at the same place:

```markdown
### 实体记录下拉列表

下拉或单选属性可以列出另一个实体的记录：编辑器的“使用实体记录”模式保存 `config: { options_source: "entity_entries", entity_id:, label_field: }`。条目始终保存记录 **ID**；`label_field`（显示字段）只用作选项标签。不存在 `value_field`。

- **显示字段。** `Entities::ReferenceLabels.labelable?` 只接受文本、搜索、邮箱、电话、网址、数字和日期输入属性；计算字段、汇总字段、引用字段和 `id` 均不可用。关联的 `display_field` 遵循同一规则。`GET /:cid/admin/maintenance/entities.json` 为每个属性标注 `labelable`，编辑器只提供这些字段。
- **选项。** `Entities::ReferenceOptions` 列出当前租户中目标实体的记录，按标签再按 ID 排序，最多 200 条。没有标签的记录显示为“未命名（#id）”；重复的标签编号为“标签（#id）”。目标实体已在回收站、是桥接实体、属于其他租户，或显示字段对当前受众不可见时，列表为空。
- **定义规则。** 保存定义时，若下拉列表的目标实体不存在（`reference_target_missing`）或显示字段不可作标签（`reference_label_field_invalid`），或关联的显示字段不可作标签（`association_display_field_invalid`），保存会被拒绝。仅改变状态的保存（移入回收站、恢复）不做这些检查。
- **回收站。** 仍被其他实体引用的实体无法移入回收站，并会列出引用位置（`entity_referenced`）。`Entities::ReferenceDependents` 会在客户自有定义、共享默认定义和每个租户的覆盖中查找引用方。
- **修改显示字段。** 删除或更改其他实体正在显示的字段会被拒绝（`display_field_in_use`）；对已上线表单的受众隐藏该字段同样会被拒绝（`display_field_hidden_from_form`）。
- **可见性。** 下拉列表会向所有能打开表单的人列出每条记录的显示字段；除非表单仅限管理员，用作显示字段的人员姓名或编号应对成员和公众隐藏。
```

- [ ] **Step 2: `entity-builder.md`: Create Entry, quick add and Stimulus**

- In **Admin Create Entry**, add:
  - en: "Select, radio and multi-select attributes with an `entity_entries` source are supported: their choices come from `Entities::ReferenceOptions` for the admin audience, and the entry contract checks that each submitted id is a record of the target entity in this customer (`common.errors.dynamic.association_target_missing`). The attribute is a blocker when the target is trashed or its display field can't label a reference for admins; a checkbox reference is always a blocker."
  - zh-CN: "支持 `entity_entries` 来源的下拉、单选和多选属性：选项来自面向管理员受众的 `Entities::ReferenceOptions`，条目契约会校验提交的每个 ID 都是本客户中目标实体的记录（`common.errors.dynamic.association_target_missing`）。目标实体已在回收站或其显示字段无法为管理员作标签时，该属性会阻止创建；复选框引用始终阻止创建。"
- In **Quick add from a page dropdown**, replace the sentence starting "The label is `data[label_field]` only when…" with:
  - en: "The label follows `Entities::ReferenceLabels`: the display field when it can label a reference for admins, numbered `label (#id)` when another record already shows the same text, and `Untitled (#id)` otherwise."
  - zh-CN: "标签遵循 `Entities::ReferenceLabels`：显示字段可为管理员作标签时使用该字段；已有其他记录显示相同文本时编号为“标签（#id）”；否则为“未命名（#id）”。"
- In the Stimulus section, add `ReferenceManager` to the manager list:
  - en: "`ReferenceManager` — the Use Entity Records mode: loads `entities.json` once, offers labelable display fields only, validates both selects, and returns `{ options_source, entity_id, label_field }`."
  - zh-CN: "`ReferenceManager`：“使用实体记录”模式，只加载一次 `entities.json`，仅提供可作标签的显示字段，校验两个下拉框，并返回 `{ options_source, entity_id, label_field }`。"

- [ ] **Step 3: `page-rendering.md`**

- In **Entity quick add in dropdowns** (en line 79), before the first paragraph, add:
  - en: "An `entity_entries` dropdown's choices are rendered by `Entities::ReferenceOptions.call` in the generated template, for the viewing tenant (`Current.customer_id`, falling back to the page's customer) and the viewer's audience. Values are record ids; labels follow `Entities::ReferenceLabels`. `query` lists (`PageContentGenerator::DynamicOptionsResolver`) use the same label rule. The page-builder preview (`GET /:customer_id/admin/maintenance/pages/:page_id/field_options/:field_id`, and the same path under `maintenance/platform/pages`) finds the field anywhere on the page, including inside columns, and previews both sources as an admin of the URL tenant."
  - zh-CN: "`entity_entries` 下拉列表的选项由生成模板中的 `Entities::ReferenceOptions.call` 渲染，面向当前访问租户（`Current.customer_id`，缺省时使用页面所属客户）和访问者受众。选项值为记录 ID，标签遵循 `Entities::ReferenceLabels`。`query` 列表（`PageContentGenerator::DynamicOptionsResolver`）使用同一标签规则。页面构建器预览（`GET /:customer_id/admin/maintenance/pages/:page_id/field_options/:field_id`，以及 `maintenance/platform/pages` 下的同一路径）可在页面任意位置（包括分栏内）找到字段，并以 URL 租户管理员身份预览两种来源。"
- In the `Pages::FormParams` paragraph (en line 123), after its first sentence, add:
  - en: "Fields are read through `Page#input_fields` (columns flattened, layout elements dropped)."
  - zh-CN: "字段通过 `Page#input_fields` 读取（分栏展开，布局元素除外）。"

- [ ] **Step 4: `flowchart-runtime.md`**

In the bridge-rows paragraph (en line 413), replace the sentence that says how a missing or foreign target is rejected with the text below. If the paragraph has no such sentence, append the text to it.

- en: "`EntityEntryContract` checks each target reference: every id must be a record of the target entity in this customer, otherwise the row fails with `common.errors.dynamic.association_target_missing` and the submission rolls back. The reference back to the primary entry is stored as its id string."
- zh-CN: "`EntityEntryContract` 会校验每个目标引用：每个 ID 都必须是本客户中目标实体的记录，否则该行以 `common.errors.dynamic.association_target_missing` 失败，整个提交回滚。指回主条目的引用以 ID 字符串保存。"

- [ ] **Step 5: `operations-api.md`**

- In the mapping table, replace the `entity_entries` row (en line 284) with:

```markdown
| `options` with `source: "entity_entries"`, `entity`, `label_field` (required) | `config.options_source: "entity_entries"`, `entity_id` (resolved from `entity` on write) and `label_field`; the stored value is always the record id |
```

- After the table, add a paragraph:
  - en: "`create_entity` and `update_entity` are at contract version 2: `options.value_field` no longer exists (`schema.unknown_property`), and `label_field` is required with `source: "entity_entries"` (`schema.required`). A proposal parked under version 1 is refused with `operation.version_changed`. `label_field` and an association's `display_field` must name a text, search, email, tel, url, number or date attribute (`options.label_field_not_labelable`, `association.display_field_not_labelable`). On update, a display field that other entities or launched forms rely on can't be deleted, retyped (`attribute.display_field_in_use`) or hidden from those forms' audiences (`attribute.display_field_hidden`)."
  - zh-CN: "`create_entity` 与 `update_entity` 的契约版本为 2：`options.value_field` 已移除（`schema.unknown_property`），`source: "entity_entries"` 时必须提供 `label_field`（`schema.required`）。以版本 1 挂起的提案会以 `operation.version_changed` 被拒绝。`label_field` 和关联的 `display_field` 必须是文本、搜索、邮箱、电话、网址、数字或日期属性（`options.label_field_not_labelable`、`association.display_field_not_labelable`）。更新时，其他实体或已上线表单依赖的显示字段不可删除、不可更改类型（`attribute.display_field_in_use`），也不可对这些表单的受众隐藏（`attribute.display_field_hidden`）。"
- Change the zh-CN table row to:

```markdown
| `options`（`source: "entity_entries"`、`entity`、`label_field`（必填）） | `config.options_source: "entity_entries"`、`entity_id`（写入时由 `entity` 解析）和 `label_field`；保存值始终为记录 ID |
```

- If the `display_field` example at en line 317 uses an attribute that isn't labelable, change it to a text attribute of the example's related entity, in both locales.

- [ ] **Step 6: Check the docs**

Run: `rg -n "value_field" doc/reference/`
Expected: no output.

Run: `rg -c "ReferenceOptions|ReferenceLabels" doc/reference/en doc/reference/zh-CN`
Expected: each changed en page and its zh-CN twin show the same counts.

- [ ] **Step 7: Leave the changes uncommitted**

Run: `git status --short`. Do not commit.

---

### Task 13: Plan 1 verification

**Agent:** anysys-release-engineer

- [ ] **Step 1: Run the full RSpec suite in parallel**

Run: `bin/rails parallel:prepare && bin/rails parallel:spec`
Expected: 0 failures. Paste the summary lines. If any example fails, report the file, the example and the first error. Do not edit anything.

- [ ] **Step 2: Run Vitest with full coverage**

Run: `npx vitest run --config config/javascript/vitest.config.js --coverage`
Expected: all tests pass, and `All files` shows 100 for statements, branches, functions and lines. Paste the `All files` row and the rows for `entity_form/*`.

- [ ] **Step 3: Run the repository checks**

Define `locale_parity` from the Global Constraints, then run:

```bash
rg -n "value_field" app config doc/reference --glob '!app/services/page_layout_templates/templates/**'
rg -n --pcre2 "display_field['\"]?\s*(=>|:)\s*['\"]id['\"]" app spec
locale_parity common maint_core comp_admin ai_assistant operations_entity
```

Expected: no output from any of them.

- [ ] **Step 4: Smoke-test the editor and the entities JSON**

Start the server in the background: `rm -f public/assets/.manifest.json && SKIP_AUTH=1 bin/rails server -b 0.0.0.0 -p 3000`. Then:

- `curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/81721200/admin/maintenance/entities/new`. Expected: `200`, and the page body contains `entityRecordsOptionsBtn`.
- `curl -s http://localhost:3000/81721200/admin/maintenance/entities.json | head -c 400`. Expected: JSON whose attributes carry `"labelable"`.

Stop the server afterwards.

- [ ] **Step 5: Report**

Report PASS or FAIL with the trimmed output of each step. Do not commit.
