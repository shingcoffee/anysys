# AI Assistant Sub-system Generator — Design & Implementation Plan

> **For agentic workers:** Use superpowers:subagent-driven-development (with the anysys-* team, per `AGENTS.md`) or superpowers:executing-plans to carry out this plan task by task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** From requirements collected in the assistant chat (`/:cid/admin/assistant`), the assistant creates a domain, its entities, journeys with their pages, and custom processing flowcharts bound to those pages. It pauses to ask whenever it needs a value it must not invent.

**Architecture:**
- The model decides *what*: entities, the login decision, which journeys, and processing needs.
- The server builds *how*: `EntityDomains::JourneyPlanner` and `Journeys::Activities::Generate` for journeys and pages, and the default flowcharts for ordinary saves.
- The model writes flowcharts only for real processing needs.
- A background build record with stages carries the work across turns and pauses for answers.

**Tech stack:** Ruby 3.2.8, Rails 8.1.2, Reform, the Operations registry (JSON Schema contracts), RSpec.

---

## 1. Background: what exists today

| Original proposal step | What the app already has |
|---|---|
| 1. Create a domain | The `create_domain` operation; `create_entity` already requires a domain. |
| 2. Generate entities; a person entity extends User | `create_entity`. The prompt makes the domain's person entity primary and sets `extends: "Authentication::User"` with no confirmation. |
| 3. Generate journeys per audience | `EntityDomains::JourneyPlanner` proposes candidates from a domain's entity graph (admin `create`, admin `record`, `member`, `public` sign-up). `Journeys::Activities::Generate` turns one into a draft journey. Only the owner's "Generate journey" button calls it. |
| 4. Create a page per journey step | `Generate` already creates or reuses each step's page (action key, create mode, locked inputs, sign-up identity fields) and launches it. |
| 5. Create flowcharts and bind them to pages | Every new page binds the shared "Save page record" flowchart; generated sign-up pages bind the shared sign-up flowchart. The assistant's flowchart pass is owner-only, writes one flowchart per turn, and never binds it to a page. |

Constraints that shape the design:
- **Logins mean members.** Extending User links entries to accounts (`EntityEntry#user_id`) and is permanent. It is only offered when the owner has marked `Authentication::User` extendable. Members only ever see their own rows (`People::Ownership.scope`), so staff who work on other people's records are admins, not a login-enabled person entity.
- **Journeys are linear and create-only.** Every step page must accept create submissions. Approvals, status changes, notifications and payments are processing, not journeys; a page that hands off to Payments fails journey launch (`step_hands_off`).
- **Turn budget.** One assistant turn allows 8 tool-loop steps and 12 vendor calls, and yields at most one flowchart. A thread allows 40 turns.
- **Ownership drives member journeys.** Member journeys exist only for entities with an owner reference (`"owner": true`) pointing at the person entity.
- **The planner supports one person entity with logins per domain** (`starts.find(&:person?)`).
- **Flowchart secrets are stored in plain text** in flowchart config (`signingSecret`, `authToken`, `secretExpression`, …). Flowcharts have no encrypted store.

## 2. Decisions

| Topic | Decision |
|---|---|
| Who can run the full pipeline | Platform owner **and tenant admins**. Journeys and flowcharts become assistant-managed for tenant admins; the journey builder and flowchart editor UI stay owner-only. |
| Approval | **Fully automatic** after one clarify round. The only mandatory question is the login decision, because extending User cannot be undone. |
| Flowchart step palette for tenant admins | **Full palette.** Destination URLs must come from the admin's answers, never from the model's guess. |
| Undo | **Deferred** (not in v1). The build records what it created so undo can be added later. |
| Asking during the build | When the assistant is uncertain or needs a value it must not invent (e.g. a webhook URL), the build pauses, asks at most 5 questions in one round using the existing question form, and resumes on the answer. |
| Messages while a build waits | **Every message is treated as answers.** The admin cancels with a Cancel control or opens a new conversation. |
| Secrets | Never asked for in chat. Steps that need a secret are left out and listed under "needs setup". |
| Launching | Journeys that pass `Journeys::LaunchChecks` and whose processing is complete are launched automatically. A public sign-up journey launches only when the tenant's sign-up setting is on. |

## 3. Pipeline

1. **Clarify (one round):** who signs in to see their own records, how accounts are created (self sign-up / admin-created / both), organisation-specific lists, and outside values the plan already knows it needs.
2. **Pre-check:** quotas, whether User is extendable, and the sign-up setting. Stop with an explanation before any write if blocked.
3. **Domain and entities:** existing `create_domain` and `create_entity`, with owner references set and `extends` only if approved.
4. **Journeys and pages:** built server-side by the planner and `Generate`.
5. **Custom processing:** one flowchart per distinct need. The build pauses for answers when a step needs a value it can't invent; steps that need secrets are left out and flagged.
6. **Launch and report:** launch journeys that pass their checks and whose processing is complete. The summary lists what was built, the assumptions made, and what still needs setup.

## Global constraints

- Business logic goes in plain Ruby services (`def self.call(...) = new(...).call`, returning a `Result`). No new Trailblazer activities.
- Every new message key exists in both `en` and `zh-CN` with identical keys and `%{}` variables. Do not edit existing locale keys. In zh-CN, journey is 流程 and domain is 业务域.
- Operation contracts pass `Operations::SchemaLint`: root `title` and `description`; a `description` on every property and on array `items`; `x-enum-descriptions` for every enum value; `additionalProperties: false`; valid root `examples`.
- Every read and write is scoped to `context.customer`. Shared (`customer_id` NULL) rows are never changed.
- Journey generation is open to tenant admins. The journey builder, flowchart editor and their UI stay owner-only.
- No commits. The human reviewer commits. Staging with `git add` is fine.
- Do not touch `doc/reference/**` or `AGENTS.md` unless explicitly requested.
- Run the targeted specs for each task, not the full suite.

---

## Phase 1: Building blocks the assistant can call

Phase 1 works on its own: once it ships, an admin can say "build the journeys for Academics" in the assistant.

### Task 1: Fix stale flowchart guidance in the prompts

**Files:**
- Modify: `app/services/flowchart_definitions/structure_schema.prompt.txt` (the three few-shot outputs on lines 28, 42 and 46)
- Modify: `app/services/ai_assistant/assistant/prompt/documents/entity_platform.md:33-34`
- Modify: `app/services/ai_assistant/assistant/prompt/sections/entity_platform.rb:17-20`
- Create: `spec/services/flowchart_definitions/structure_schema_prompt_spec.rb`

**Interfaces:** none.

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "flowchart structure prompt few-shot examples" do
  let(:examples) do
    Rails.root.join("app/services/flowchart_definitions/structure_schema.prompt.txt").read
         .lines.select { |line| line.start_with?('{"intent"') }.map { |line| JSON.parse(line) }
  end

  it "never builds a second record in a page-bound flowchart" do
    flowcharts = examples.filter_map { |example| example["flowchart"] }
    expect(flowcharts).not_to be_empty

    flowcharts.each do |flowchart|
      actions = flowchart["elements"].flat_map { |element| Array(element["steps"]).map { |step| step["action"] } }
      expect(actions).not_to include("new_model"), flowchart["name"]
    end
  end
end
```

- [ ] **Step 2: Run it and confirm it fails**

Run: `bundle exec rspec spec/services/flowchart_definitions/structure_schema_prompt_spec.rb`
Expected: FAIL, because `new_model` is listed for "Create Student".

- [ ] **Step 3: Edit the prompt.** In `structure_schema.prompt.txt`, make two replace-all edits:
  - Delete every `{"id":"p1","type":"process","label":"New Model","steps":[{"action":"new_model","config":{"resultVar":"model"}}]},`
  - Replace every `{"from":"start_1","to":"p1"},{"from":"p1","to":"p2"}` with `{"from":"start_1","to":"p2"}`

- [ ] **Step 4: Replace the flowchart bullet** in `entity_platform.md` (lines 33–34) with:

```markdown
- **Flowcharts.** Every form page is bound to one flowchart that processes its submissions: it
  validates, saves the record and runs any side effects. New pages use the shared "Save page record" flowchart.
```

Then update the constant in `entity_platform.rb` to the identical text:

```ruby
          FLOWCHART_CAPABILITY = <<~MD
            - **Flowcharts.** Every form page is bound to one flowchart that processes its submissions: it
              validates, saves the record and runs any side effects. New pages use the shared "Save page record" flowchart.
          MD
```

- [ ] **Step 5: Run the tests and confirm they pass**

Run: `bundle exec rspec spec/services/flowchart_definitions spec/services/ai_assistant/assistant/prompt_builder_spec.rb`
Expected: PASS. The prompt-builder spec "keeps the stripped flowchart bullet in lockstep" confirms the document and the constant match.

---

### Task 2: Give the assistant's admin form a create-page action key, so journeys reuse it

**Files:**
- Create: `app/services/pages/action_keys.rb`
- Modify: `app/services/entity_domains/journey_planner.rb` (add `create_page_key`; use it in `create_candidates`)
- Modify: `app/services/journeys/activities/generate.rb:185` and `:284-286`
- Modify: `app/services/ai_assistant/assistant/generate_page.rb:52-53`
- Test: `spec/services/ai_assistant/assistant/generate_page_spec.rb`, `spec/services/journeys/activities/generate_spec.rb`

**Interfaces:**
- Produces: `Pages::ActionKeys.unique(base, customer_id:) -> String`, `Pages::ActionKeys.taken?(key, customer_id:) -> Boolean`, and `EntityDomains::JourneyPlanner.create_page_key(entity) -> String` (e.g. `"student_new"`).

- [ ] **Step 1: Write the failing tests.** Add to `generate_page_spec.rb`:

```ruby
  it "keys the form as the entity's create page so journey generation reuses it" do
    entity = create(:entity, :with_name_status_schema, customer: customer, name: "Student")

    expect(call_for(entity).page.reload.action_key).to eq("student_new")
  end

  it "suffixes the create page key when it is taken" do
    entity = create(:entity, :with_name_status_schema, customer: customer, name: "Student")
    create(:page, customer: customer, action_key: "student_new")

    expect(call_for(entity).page.reload.action_key).to eq("student_new_2")
  end
```

Add to `generate_spec.rb`, inside the top-level `describe`:

```ruby
  it "reuses the assistant's admin form for the start page instead of composing a second one" do
    form = Current.with_customer(customer) { AiAssistant::Assistant::GeneratePage.call(entity: student_entity, customer: customer) }.page

    expect(generate.ok).to be(true)
    expect(page("student_new")).to eq(form)
    expect(Page.where(customer_id: customer.id).for_entity(student_entity.id).count).to eq(1)
  end
```

- [ ] **Step 2: Run them and confirm they fail**

Run: `bundle exec rspec spec/services/ai_assistant/assistant/generate_page_spec.rb spec/services/journeys/activities/generate_spec.rb`
Expected: the 3 new examples FAIL (`action_key` is nil, and there are 2 Student pages).

- [ ] **Step 3: Create `app/services/pages/action_keys.rb`**

```ruby
# frozen_string_literal: true

module Pages
  # Picks a free page action key for a tenant. Trashed and shared pages count
  # as taken: a restored page must not collide, and a tenant key would shadow
  # a shared one.
  module ActionKeys
    module_function

    def taken?(key, customer_id:)
      Page.unscoped.where(customer_id: [customer_id, nil]).exists?(action_key: key)
    end

    def unique(base, customer_id:)
      (1..).lazy.map { |attempt| attempt == 1 ? base : "#{base}_#{attempt}" }
           .find { |key| !taken?(key, customer_id: customer_id) }
    end
  end
end
```

- [ ] **Step 4: Add the planner key.** In `journey_planner.rb`, below `self.slug`:

```ruby
    def self.create_page_key(entity) = "#{slug(entity.name, entity)}_new"
```

In `create_candidates`, change `page_key: "#{base}_new"` to `page_key: self.class.create_page_key(entity)`.

- [ ] **Step 5: Use the helper in `Generate`.** Change line 185 to:

```ruby
        page.action_key = Pages::ActionKeys.unique(base, customer_id: @customer.id)
```

Delete `page_key_taken?` and its comment (lines 284–286).

- [ ] **Step 6: Key the assistant form.** In `generate_page.rb`, replace `result.page.launch!` with:

```ruby
          key_as_create_page(result.page)
          result.page.launch!
```

and add this private method:

```ruby
      # Keyed like the journey generator's create page, so a journey built on
      # this entity's domain reuses this form instead of composing another.
      def key_as_create_page(page)
        return if page.action_key.present?

        key = Pages::ActionKeys.unique(EntityDomains::JourneyPlanner.create_page_key(@entity), customer_id: @customer.id)
        page.update_columns(action_key: key)
      end
```

- [ ] **Step 7: Run the tests and confirm they pass**

Run: `bundle exec rspec spec/services/ai_assistant/assistant/generate_page_spec.rb spec/services/journeys spec/services/entity_domains/journey_planner_spec.rb`
Expected: PASS.

---

### Task 3: Share domain candidates and extract journey launch into a service

**Files:**
- Create: `app/services/journeys/domain_candidates.rb`
- Create: `app/services/journeys/activities/launch.rb`
- Modify: `app/services/journeys/activities/generate.rb:66-72`
- Modify: `app/controllers/admin/maintenance/journey_launches_controller.rb:14-24`
- Test: `spec/services/journeys/activities/launch_spec.rb`

**Interfaces:**
- Produces:
  - `Journeys::DomainCandidates.call(customer_id:, domain_id:) -> Array<EntityDomains::JourneyPlanner::Candidate>`
  - `Journeys::DomainCandidates.existing_journey(customer_id:, candidate:) -> Journey | nil`
  - `Journeys::Activities::Launch.call(journey:) -> Result(ok:, journey:, errors: Array<String>)`

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Journeys::Activities::Launch do
  let(:customer) { create(:customer) }
  include_context "student course association"
  let(:domain) { create(:entity_domain, customer: customer, name: "School") }

  before { [student_entity, course_entity].each { |entity| EntityDomains::Memberships.place!(entity, domain) } }

  def draft_journey
    Journeys::Activities::Generate.call(customer: customer, domain_id: domain.id, candidate_key: "create-#{student_entity.id}").journey
  end

  it "launches a journey whose checks pass" do
    result = described_class.call(journey: draft_journey)

    expect([result.ok, result.errors, result.journey.reload.launched?]).to eq([true, [], true])
  end

  it "keeps the journey a draft and returns the check errors when a step page is offline" do
    journey = draft_journey
    Page.find_by(customer_id: customer.id, action_key: "student_new").update_columns(launched: false)

    result = described_class.call(journey: journey)

    expect(result.ok).to be(false)
    expect(result.errors).not_to be_empty
    expect(journey.reload).to be_draft
  end
end
```

- [ ] **Step 2: Run it and confirm it fails**

Run: `bundle exec rspec spec/services/journeys/activities/launch_spec.rb`
Expected: FAIL with `uninitialized constant Journeys::Activities::Launch`.

- [ ] **Step 3: Create `app/services/journeys/domain_candidates.rb`**

```ruby
# frozen_string_literal: true

module Journeys
  # The journeys a customer's domain supports (EntityDomains::JourneyPlanner
  # over the entities placed in it), and the journey already generated from
  # one of them.
  module DomainCandidates
    module_function

    def call(customer_id:, domain_id:)
      section = EntityDomains::Layout.call(customer_id: customer_id, entities: EntityDomains::Catalog.entities(customer_id))
                                     .find { |item| !item.ungrouped? && item.domain.id.to_s == domain_id.to_s }
      return [] unless section

      EntityDomains::JourneyPlanner.call(customer_id: customer_id, entities: section.items.map(&:entity))
    end

    # Generate suffixes a taken key ("<key>_2"); a copy ends in "_copy" and is
    # not the generated journey.
    def existing_journey(customer_id:, candidate:)
      family = /\A#{Regexp.escape(candidate.journey_key)}(_\d+)?\z/
      Journey.for_customer(customer_id).order(:id).find { |journey| journey.key.match?(family) }
    end
  end
end
```

- [ ] **Step 4: Create `app/services/journeys/activities/launch.rb`**

```ruby
# frozen_string_literal: true

module Journeys
  module Activities
    # Takes a journey live once every launch check passes. The customer lock
    # keeps two launches from claiming the same first page and audience
    # between the check and the write.
    class Launch
      Result = Struct.new(:ok, :journey, :errors, keyword_init: true)

      def self.call(...) = new(...).call

      def initialize(journey:)
        @journey = journey
      end

      def call
        errors = @journey.customer.with_lock(requires_new: true) do
          LaunchChecks.new(@journey).errors.tap { |list| @journey.update!(status: :launched) if list.empty? }
        end
        Result.new(ok: errors.empty?, journey: @journey, errors: errors)
      end
    end
  end
end
```

- [ ] **Step 5: Point `Generate` at the shared candidates.** Replace `find_candidate` with:

```ruby
      def find_candidate
        domain = EntityDomain.for_customer(@customer.id).find_by(id: @domain_id)
        return unless domain

        [domain, Journeys::DomainCandidates.call(customer_id: @customer.id, domain_id: domain.id).find { |candidate| candidate.key == @candidate_key }]
      end
```

- [ ] **Step 6: Make the controller use the service.** Replace `create` with:

```ruby
      def create
        result = Journeys::Activities::Launch.call(journey: @journey)
        if result.ok
          redirect_to_journey(notice: t("journeys.admin.flash.launched"))
        else
          redirect_to_journey(alert: result.errors.first)
        end
      end
```

- [ ] **Step 7: Run the tests and confirm they pass**

Run: `bundle exec rspec spec/services/journeys spec/requests/admin/maintenance/journey_launches_spec.rb spec/requests/admin/maintenance/journey_generations_spec.rb`
Expected: PASS.

---

### Task 4: `list_journey_options` operation

**Files:**
- Create: `app/services/operations/domain_lookup.rb`
- Create: `app/services/operations/list_journey_options.rb`
- Create: `app/services/operations/schemas/list_journey_options.json`
- Modify: `spec/services/operations/contract_lint_spec.rb:11`
- Test: `spec/services/operations/list_journey_options_spec.rb`

**Interfaces:**
- Consumes: `Journeys::DomainCandidates` (Task 3).
- Produces:
  - The mixin `Operations::DomainLookup`, with private methods `named_domain(name) -> EntityDomain | nil` and `domain_violation(name) -> Violation | nil`. It reuses the existing code `entity_domain.not_found`.
  - The tool output `{"domain", "journeys" => [{"key", "kind", "audience", "name", "starts_with", "adds", "continues_to", "generated"}]}`.

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Operations::ListJourneyOptions do
  let(:customer) { create(:customer) }
  let(:other) { create(:customer) }
  let(:admin) { create(:user, :admin, customer: customer) }
  let(:member) { create(:user, :member, customer: customer) }
  include_context "student course association"
  let(:domain) { create(:entity_domain, customer: customer, name: "School") }
  let(:context) { Operations::Context.new(customer: customer, actor: admin, channel: "assistant") }

  before { [student_entity, course_entity].each { |entity| EntityDomains::Memberships.place!(entity, domain) } }

  def run(input, ctx: context)
    Operations::Activities::Execute.call(operation: "list_journey_options", input: input, context: ctx)
  end

  def option(outcome, key) = outcome.data["journeys"].find { |row| row["key"] == key }

  it "lists the domain's journey options with the keys generate_journeys accepts" do
    outcome = run({ "domain" => "school" })

    expect(outcome.status).to eq("succeeded"), outcome.violations.map(&:as_json).inspect
    expect(outcome.data["domain"]).to eq("School")
    keys = Journeys::DomainCandidates.call(customer_id: customer.id, domain_id: domain.id).map(&:key)
    expect(outcome.data["journeys"].map { |row| row["key"] }).to eq(keys)
    expect(option(outcome, "create-#{student_entity.id}")).to include(
      "kind" => "create", "audience" => "admin", "starts_with" => "Student", "adds" => ["Course"], "generated" => false
    )
  end

  it "marks an option generated once its journey exists" do
    Journeys::Activities::Generate.call(customer: customer, domain_id: domain.id, candidate_key: "create-#{student_entity.id}")

    expect(option(run({ "domain" => "School" }), "create-#{student_entity.id}")["generated"]).to be(true)
  end

  it "reports a domain this customer does not have, even when another customer has it" do
    create(:entity_domain, customer: other, name: "Finance")

    outcome = run({ "domain" => "Finance" })

    expect(outcome.status).to eq("invalid")
    expect(outcome.violations.map { |violation| [violation.code, violation.pointer] }).to eq([["entity_domain.not_found", "/domain"]])
  end

  it "forbids a member" do
    ctx = Operations::Context.new(customer: customer, actor: member, channel: "assistant")

    expect(run({ "domain" => "School" }, ctx: ctx).status).to eq("forbidden")
  end
end
```

- [ ] **Step 2: Run it and confirm it fails**

Run: `bundle exec rspec spec/services/operations/list_journey_options_spec.rb`
Expected: FAIL with `operation.unknown`.

- [ ] **Step 3: Create `app/services/operations/domain_lookup.rb`**

```ruby
# frozen_string_literal: true

module Operations
  # Finds the tenant domain an operation names, or the violation to return.
  module DomainLookup
    private

    def named_domain(name)
      EntityDomain.find_by_name(context.customer.id, name.to_s.strip)
    end

    def domain_violation(name)
      return if named_domain(name)

      Violation.new(pointer: "/domain", code: "entity_domain.not_found", details: { "name" => name.to_s.strip })
    end
  end
end
```

- [ ] **Step 4: Create `app/services/operations/schemas/list_journey_options.json`**

```json
{
  "title": "List journey options",
  "description": "List the guided journeys one domain supports, built from its entities and who owns which records. Read-only. Pass the returned keys to generate_journeys.",
  "type": "object",
  "additionalProperties": false,
  "required": ["domain"],
  "properties": {
    "domain": {
      "type": "string",
      "minLength": 1,
      "maxLength": 100,
      "description": "Name of an existing domain from the catalog, case-insensitive. Example: Academics."
    }
  },
  "examples": [{ "domain": "Academics" }]
}
```

- [ ] **Step 5: Create `app/services/operations/list_journey_options.rb`**

```ruby
# frozen_string_literal: true

module Operations
  class ListJourneyOptions < Base
    include DomainLookup

    key "list_journey_options"
    version 1
    title "List journey options"
    summary "List the guided journeys one domain supports: an admin creating a record and adding the rows that hang off it (create), an admin adding one kind of related row from an existing record (record), a signed-in member adding records they own (member), and a visitor signing up as a member (public). Read-only. Call it after the domain's entities exist, then pass the keys the requirements call for to generate_journeys."
    schema "list_journey_options.json"
    annotations read_only: true, idempotent: true, confirmation: :never

    register!

    def validate(input)
      Array.wrap(domain_violation(input["domain"]))
    end

    def perform(input)
      domain = named_domain(input["domain"])
      options = Journeys::DomainCandidates.call(customer_id: context.customer.id, domain_id: domain.id)
      Outcome.succeeded(
        operation: self.class.key,
        data: { "domain" => domain.name, "journeys" => options.map { |candidate| describe(candidate) } }
      )
    end

    private

    def describe(candidate)
      {
        "key" => candidate.key,
        "kind" => candidate.kind.to_s,
        "audience" => candidate.audience,
        "name" => candidate.name,
        "starts_with" => candidate.start.name,
        "adds" => candidate.steps.map(&:label),
        "continues_to" => candidate.follow&.name,
        "generated" => Journeys::DomainCandidates.existing_journey(customer_id: context.customer.id, candidate: candidate).present?
      }
    end
  end
end
```

- [ ] **Step 6: Register the key in the lint spec.** In `contract_lint_spec.rb` line 11, add `"list_journey_options"` to the `include(...)` list.

- [ ] **Step 7: Run the tests and confirm they pass**

Run: `bundle exec rspec spec/services/operations/list_journey_options_spec.rb spec/services/operations/contract_lint_spec.rb`
Expected: PASS.

---

### Task 5: `generate_journeys` operation

**Files:**
- Create: `app/services/operations/generate_journeys.rb`
- Create: `app/services/operations/schemas/generate_journeys.json`
- Create: `config/locales/operations_journey.en.yml`, `config/locales/operations_journey.zh-CN.yml`
- Modify: `spec/services/operations/contract_lint_spec.rb` (key list, plus a parity check per area file)
- Test: `spec/services/operations/generate_journeys_spec.rb`

**Interfaces:**
- Consumes: `Journeys::DomainCandidates`, `Journeys::Activities::Launch` (Task 3), and `Operations::DomainLookup` (Task 4).
- Produces: the tool output `{"domain", "journeys" => [{"key", "name", "status", "reused", "audiences", "pages" => [action_key], "launch_blockers" => [String]}]}`. Phases 3 and 4 bind flowcharts using `pages` plus `audiences`.

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Operations::GenerateJourneys do
  let(:customer) { create(:customer) }
  let(:other) { create(:customer) }
  let(:admin) { create(:user, :admin, customer: customer) }
  let(:member) { create(:user, :member, customer: customer) }
  let(:foreign_admin) { create(:user, :admin, customer: other) }
  include_context "student course association"
  let(:domain) { create(:entity_domain, customer: customer, name: "School") }
  let(:context) { Operations::Context.new(customer: customer, actor: admin, channel: "assistant") }
  let(:create_key) { "create-#{student_entity.id}" }

  before { [student_entity, course_entity].each { |entity| EntityDomains::Memberships.place!(entity, domain) } }

  def run(input, ctx: context)
    Operations::Activities::Execute.call(operation: "generate_journeys", input: input, context: ctx)
  end

  it "builds the chosen journey with its pages and launches it" do
    outcome = run({ "domain" => "School", "journeys" => [create_key] })

    expect(outcome.status).to eq("succeeded"), outcome.violations.map(&:as_json).inspect
    row = outcome.data["journeys"].sole
    expect(row).to include("key" => create_key, "status" => "launched", "reused" => false,
                           "audiences" => %w[admin], "pages" => %w[student_new student_add_course], "launch_blockers" => [])
    expect(Journey.for_customer(customer.id).sole).to be_launched
    expect(outcome.effects).to eq([{ "kind" => "journey", "action" => "created", "name" => row["name"] }])
  end

  it "leaves the journey a draft when launch is false" do
    outcome = run({ "domain" => "School", "journeys" => [create_key], "launch" => false })

    expect(outcome.data["journeys"].sole["status"]).to eq("draft")
  end

  it "reports an already generated journey instead of building a second one" do
    run({ "domain" => "School", "journeys" => [create_key] })
    outcome = run({ "domain" => "School", "journeys" => [create_key] })

    expect(outcome.data["journeys"].sole).to include("reused" => true, "status" => "launched")
    expect(outcome.effects).to eq([])
    expect(Journey.for_customer(customer.id).count).to eq(1)
  end

  it "keeps a sign-up journey a draft while sign-up is off" do
    person_model = EntityDefinitions::Capabilities::PERSON_MODEL
    enable_module!("authentication", customer).set_extendable_model!(person_model, true)
    student_entity.update_columns(extended_model: person_model)
    signup_key = Journeys::DomainCandidates.call(customer_id: customer.id, domain_id: domain.id).find(&:public?).key

    row = run({ "domain" => "School", "journeys" => [signup_key] }).data["journeys"].sole

    expect(row["status"]).to eq("draft")
    expect(row["launch_blockers"]).to eq([I18n.t("operations.journeys.sign_up_disabled")])
  end

  it "rejects a key the domain does not offer and writes nothing" do
    outcome = run({ "domain" => "School", "journeys" => ["create-999999"] })

    expect(outcome.status).to eq("invalid")
    expect(outcome.violations.map { |violation| [violation.code, violation.pointer] }).to eq([["journey.option_not_found", "/journeys/0"]])
    expect(Journey.for_customer(customer.id)).to be_empty
  end

  it "rejects a domain this customer does not have" do
    create(:entity_domain, customer: other, name: "Finance")

    expect(run({ "domain" => "Finance", "journeys" => [create_key] }).violations.map(&:code)).to eq(["entity_domain.not_found"])
  end

  it "rolls everything back when one journey cannot be built" do
    allow(Journeys::Activities::Generate).to receive(:call).and_call_original
    allow(Journeys::Activities::Generate).to receive(:call).with(hash_including(candidate_key: "create-#{course_entity.id}"))
      .and_return(Journeys::Activities::Generate::Result.new(ok: false, journey: nil, errors: ["Page limit reached"]))

    outcome = run({ "domain" => "School", "journeys" => [create_key, "create-#{course_entity.id}"] })

    expect(outcome.status).to eq("invalid")
    expect(outcome.violations.map(&:code)).to eq(["journey.generation_failed"])
    expect(outcome.violations.first.resolution).to eq("blocked")
    expect(Journey.for_customer(customer.id)).to be_empty
  end

  it "forbids a member and another customer's admin" do
    [member, foreign_admin].each do |actor|
      ctx = Operations::Context.new(customer: customer, actor: actor, channel: "assistant")
      expect(run({ "domain" => "School", "journeys" => [create_key] }, ctx: ctx).status).to eq("forbidden")
    end
    expect(Journey.for_customer(customer.id)).to be_empty
  end

  it "replays a stored outcome for the same idempotency key" do
    ctx = Operations::Context.new(customer: customer, actor: admin, channel: "assistant", idempotency_key: "gen-journeys-1")
    run({ "domain" => "School", "journeys" => [create_key] }, ctx: ctx)

    expect(run({ "domain" => "School", "journeys" => [create_key] }, ctx: ctx).replayed).to be(true)
    expect(Journey.for_customer(customer.id).count).to eq(1)
  end

  it "returns a dry_run plan without writing" do
    ctx = Operations::Context.new(customer: customer, actor: admin, channel: "assistant", dry_run: true)
    outcome = run({ "domain" => "School", "journeys" => [create_key] }, ctx: ctx)

    expect(outcome.status).to eq("dry_run")
    expect(outcome.plan).to eq([{ "kind" => "journey", "action" => "created",
                                  "name" => I18n.t("journeys.generate.journey_name", start: "Student") }])
    expect(Journey.for_customer(customer.id)).to be_empty
  end
end
```

- [ ] **Step 2: Run it and confirm it fails**

Run: `bundle exec rspec spec/services/operations/generate_journeys_spec.rb`
Expected: FAIL with `operation.unknown`.

- [ ] **Step 3: Create `app/services/operations/schemas/generate_journeys.json`**

```json
{
  "title": "Generate journeys",
  "description": "Build the journeys chosen from list_journey_options for one domain, with the form pages their steps need, and launch each journey whose launch checks pass.",
  "type": "object",
  "additionalProperties": false,
  "required": ["domain", "journeys"],
  "properties": {
    "domain": {
      "type": "string",
      "minLength": 1,
      "maxLength": 100,
      "description": "Name of the domain the journeys belong to, as list_journey_options returned it."
    },
    "journeys": {
      "type": "array",
      "minItems": 1,
      "maxItems": 10,
      "uniqueItems": true,
      "description": "Keys of the journeys to build, copied from list_journey_options. Choose only the journeys the requirements call for.",
      "items": {
        "type": "string",
        "minLength": 1,
        "maxLength": 120,
        "description": "One journey key from list_journey_options, for example create-12."
      }
    },
    "launch": {
      "type": "boolean",
      "default": true,
      "description": "Launch each generated journey whose launch checks pass. A visitor sign-up journey stays a draft while the workspace has sign-up turned off. Default true."
    }
  },
  "examples": [{ "domain": "Academics", "journeys": ["create-12", "member-15"] }]
}
```

- [ ] **Step 4: Create `app/services/operations/generate_journeys.rb`**

```ruby
# frozen_string_literal: true

module Operations
  class GenerateJourneys < Base
    include DomainLookup

    key "generate_journeys"
    version 1
    title "Generate journeys"
    summary "Build the journeys you chose from list_journey_options for one domain, with the form pages their steps need (matching forms are reused), and launch each journey whose launch checks pass. Call list_journey_options first and pass only keys it returned. A journey already generated from an option is reported, not built again. Does not create entities or change existing journeys. Applies immediately."
    schema "generate_journeys.json"
    annotations destructive: false, confirmation: :never

    register!

    def validate(input)
      missing = domain_violation(input["domain"])
      return [missing] if missing

      known = candidates_by_key(input).keys
      Array(input["journeys"]).each_with_index.filter_map do |key, index|
        next if known.include?(key)

        Violation.new(pointer: "/journeys/#{index}", code: "journey.option_not_found",
                      details: { "key" => key, "domain" => named_domain(input["domain"]).name,
                                 "candidates" => Violation.candidates(key, known) })
      end
    end

    def plan(input)
      Array(input["journeys"]).filter_map do |key|
        candidate = candidates_by_key(input)[key]
        { "kind" => "journey", "action" => "created", "name" => candidate.name } if candidate
      end
    end

    def perform(input)
      domain = named_domain(input["domain"])
      launch = input["launch"] != false
      rows = Array(input["journeys"]).map do |key|
        candidate = candidates_by_key(input).fetch(key)
        existing = Journeys::DomainCandidates.existing_journey(customer_id: context.customer.id, candidate: candidate)
        next row_for(existing, key, reused: true) if existing

        result = Journeys::Activities::Generate.call(customer: context.customer, domain_id: domain.id, candidate_key: key)
        return Outcome.invalid(operation: self.class.key, violations: [generation_failed(key, result.errors)]) unless result.ok

        row_for(result.journey, key, reused: false, launch_blockers: launch ? launch_blockers(result.journey, candidate) : [])
      end

      Outcome.succeeded(
        operation: self.class.key,
        data: { "domain" => domain.name, "journeys" => rows },
        effects: rows.reject { |row| row["reused"] }.map { |row| { "kind" => "journey", "action" => "created", "name" => row["name"] } }
      )
    end

    private

    def candidates_by_key(input)
      @candidates_by_key ||= begin
        domain = named_domain(input["domain"])
        list = domain ? Journeys::DomainCandidates.call(customer_id: context.customer.id, domain_id: domain.id) : []
        list.index_by(&:key)
      end
    end

    def launch_blockers(journey, candidate)
      if candidate.public? && !Authentication::Settings.for(context.customer.id).signup_enabled?
        return [I18n.t("operations.journeys.sign_up_disabled")]
      end

      Journeys::Activities::Launch.call(journey: journey).errors
    end

    def row_for(journey, key, reused:, launch_blockers: [])
      {
        "key" => key,
        "name" => journey.name,
        "status" => journey.reload.status,
        "reused" => reused,
        "audiences" => journey.visible_audiences,
        "pages" => journey.steps_definition.page_steps.map(&:action_key),
        "launch_blockers" => launch_blockers
      }
    end

    def generation_failed(key, errors)
      Violation.new(pointer: "/journeys", code: "journey.generation_failed", resolution: "blocked",
                    details: { "key" => key, "errors" => Array(errors) })
    end
  end
end
```

- [ ] **Step 5: Create the locale files.** `config/locales/operations_journey.en.yml`:

```yaml
en:
  operations:
    violations:
      journey:
        option_not_found: "%{domain} has no journey option %{key}. Call list_journey_options and use one of its keys."
        generation_failed: "The journey %{key} could not be built: %{errors}"
    journeys:
      sign_up_disabled: "Sign-up is turned off for this workspace, so the sign-up journey stays a draft."
```

`config/locales/operations_journey.zh-CN.yml`:

```yaml
zh-CN:
  operations:
    violations:
      journey:
        option_not_found: "%{domain} 没有流程选项 %{key}。请调用 list_journey_options，并使用其返回的键。"
        generation_failed: "无法生成流程 %{key}：%{errors}"
    journeys:
      sign_up_disabled: "本工作区未开启注册，注册流程保持为草稿。"
```

- [ ] **Step 6: Extend the lint spec.**
  - Add `"generate_journeys"` to the key list on line 11.
  - Replace the single parity example (lines 19–30) with one example per area file:

```ruby
  def flatten_locale(value, path = [])
    case value
    when Hash then value.flat_map { |key, item| flatten_locale(item, path + [key.to_s]) }
    else [[path.join("."), value.to_s.scan(/%\{([^}]+)\}/).flatten.sort]]
    end
  end

  %w[operations_entity operations_journey].each do |area|
    it "keeps #{area} locale keys and interpolations in parity" do
      english = YAML.safe_load_file(Rails.root.join("config/locales/#{area}.en.yml")).fetch("en").fetch("operations")
      chinese = YAML.safe_load_file(Rails.root.join("config/locales/#{area}.zh-CN.yml")).fetch("zh-CN").fetch("operations")
      expect(flatten_locale(english).to_h).to eq(flatten_locale(chinese).to_h)
    end
  end
```

- [ ] **Step 7: Run the tests and confirm they pass**

Run: `bundle exec rspec spec/services/operations/generate_journeys_spec.rb spec/services/operations/contract_lint_spec.rb spec/services/operations/locales_spec.rb`
Expected: PASS.

---

### Task 6: Page binding service and `bind_page_flowchart` operation (owner-only in Phase 1)

**Files:**
- Create: `app/services/pages/activities/bind_flowchart.rb`
- Create: `app/services/operations/bind_page_flowchart.rb`
- Create: `app/services/operations/schemas/bind_page_flowchart.json`
- Create: `config/locales/operations_page.en.yml`, `config/locales/operations_page.zh-CN.yml`
- Modify: `spec/services/operations/contract_lint_spec.rb` (key list, and `operations_page` in the parity area list)
- Test: `spec/services/operations/bind_page_flowchart_spec.rb`, `spec/services/pages/activities/bind_flowchart_spec.rb`

**Interfaces:**
- Produces:
  - `Pages::Activities::BindFlowchart.call(page:, flowchart_id:) -> Result(ok:, page:, errors:)`. It raises `ArgumentError` for a shared page.
  - The operation's `available?` is `FlowchartVisibility.allowed?(actor)`. Phase 4 opens it to tenant admins.

- [ ] **Step 1: Write the failing tests**

```ruby
# spec/services/pages/activities/bind_flowchart_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pages::Activities::BindFlowchart do
  it "refuses a shared page, which is rebound on the platform prefix only" do
    expect { described_class.call(page: Page.new(customer_id: nil), flowchart_id: 1) }.to raise_error(ArgumentError)
  end
end
```

```ruby
# spec/services/operations/bind_page_flowchart_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Operations::BindPageFlowchart do
  let(:customer) { create(:customer) }
  let(:other) { create(:customer) }
  let(:owner) { find_or_create_platform_owner }
  let(:admin) { create(:user, :admin, customer: customer) }
  let(:context) { Operations::Context.new(customer: customer, actor: owner, channel: "assistant") }
  let!(:page) { create(:page, customer: customer, action_key: "student_new", audience_admin: true) }
  let!(:flowchart) { create(:flowchart, :draft, customer: customer, name: "Save and notify") }
  let(:input) { { "page" => "student_new", "audience" => "admin", "flowchart" => "Save and notify" } }

  def run(payload = input, ctx: context)
    Operations::Activities::Execute.call(operation: "bind_page_flowchart", input: payload, context: ctx)
  end

  it "binds the named flowchart to the page" do
    outcome = run

    expect(outcome.status).to eq("succeeded"), outcome.violations.map(&:as_json).inspect
    expect(page.reload.flowchart).to eq(flowchart)
    expect(outcome.data).to eq("page" => "student_new", "audience" => "admin", "flowchart" => "Save and notify")
  end

  it "refuses an offline flowchart for a launched page and keeps its processing" do
    page.update_columns(launched: true)
    before = page.reload.flowchart_id

    outcome = run

    expect(outcome.violations.map(&:code)).to eq(["page.processing_rejected"])
    expect(page.reload.flowchart_id).to eq(before)
  end

  it "reports an unknown page and an unknown flowchart" do
    outcome = run(input.merge("page" => "nope_new", "flowchart" => "Missing"))

    expect(outcome.violations.map { |violation| [violation.code, violation.pointer] })
      .to eq([["page.not_found", "/page"], ["flowchart.not_found", "/flowchart"]])
  end

  it "never binds another customer's flowchart" do
    create(:flowchart, :launched_status, customer: other, name: "Foreign")

    expect(run(input.merge("flowchart" => "Foreign")).violations.map(&:code)).to eq(["flowchart.not_found"])
  end

  it "is not offered to a tenant admin in this phase" do
    ctx = Operations::Context.new(customer: customer, actor: admin, channel: "assistant")

    expect(described_class.available?(ctx)).to be(false)
    expect(run(ctx: ctx).status).to eq("forbidden")
  end

  it "returns a dry_run plan without writing" do
    before = page.reload.flowchart_id
    outcome = run(ctx: Operations::Context.new(customer: customer, actor: owner, channel: "assistant", dry_run: true))

    expect(outcome.plan).to eq([{ "kind" => "page", "action" => "updated", "name" => page.name }])
    expect(page.reload.flowchart_id).to eq(before)
  end
end
```

- [ ] **Step 2: Run them and confirm they fail**

Run: `bundle exec rspec spec/services/operations/bind_page_flowchart_spec.rb spec/services/pages/activities/bind_flowchart_spec.rb`
Expected: FAIL with an uninitialized constant and `operation.unknown`.

- [ ] **Step 3: Create `app/services/pages/activities/bind_flowchart.rb`**

```ruby
# frozen_string_literal: true

module Pages
  module Activities
    # Rebinds the flowchart that processes a customer-owned page's
    # submissions, through the same contract as the page's Processing card.
    class BindFlowchart
      Result = Struct.new(:ok, :page, :errors, keyword_init: true)

      def self.call(...) = new(...).call

      def initialize(page:, flowchart_id:)
        raise ArgumentError, "a shared page is rebound on the platform prefix only" if page.customer_id.nil?

        @page = page
        @flowchart_id = flowchart_id
      end

      def call
        contract = Pages::ProcessingContract.new(@page)
        return Result.new(ok: true, page: @page, errors: []) if contract.validate("flowchart_id" => @flowchart_id.to_s) && contract.save

        Result.new(ok: false, page: @page, errors: contract.errors.full_messages)
      end
    end
  end
end
```

- [ ] **Step 4: Create `app/services/operations/schemas/bind_page_flowchart.json`**

```json
{
  "title": "Bind page flowchart",
  "description": "Set the flowchart that processes one of this workspace's form pages when it is submitted.",
  "type": "object",
  "additionalProperties": false,
  "required": ["page", "audience", "flowchart"],
  "properties": {
    "page": {
      "type": "string",
      "pattern": "^[a-z][a-z0-9_]{1,62}$",
      "description": "Action key of the page, as generate_journeys reports it in pages. Example: student_new."
    },
    "audience": {
      "type": "string",
      "enum": ["admin", "member", "public"],
      "description": "Which audience's page carries that action key.",
      "x-enum-descriptions": {
        "admin": "The page administrators fill in.",
        "member": "The page signed-in members fill in.",
        "public": "The page anonymous visitors fill in."
      }
    },
    "flowchart": {
      "type": "string",
      "minLength": 1,
      "maxLength": 255,
      "description": "Name of a live flowchart of this workspace, or a shared one."
    }
  },
  "examples": [{ "page": "student_new", "audience": "admin", "flowchart": "Save student and notify registrar" }]
}
```

- [ ] **Step 5: Create `app/services/operations/bind_page_flowchart.rb`**

```ruby
# frozen_string_literal: true

module Operations
  class BindPageFlowchart < Base
    key "bind_page_flowchart"
    version 1
    title "Bind page flowchart"
    summary "Set the flowchart that processes one of this workspace's form pages when it is submitted, replacing the one it uses now. Name the page by the action key and audience generate_journeys reports, and the flowchart by name. A launched page accepts only a launched flowchart that fits its entity. Does not create or change flowcharts. Applies immediately."
    schema "bind_page_flowchart.json"
    annotations destructive: false, confirmation: :never

    register!

    def self.available?(context)
      FlowchartVisibility.allowed?(context.actor)
    end

    def validate(input)
      violations = []
      violations << page_missing(input) unless target_page(input)
      violations << flowchart_missing(input["flowchart"]) unless target_flowchart(input["flowchart"])
      violations
    end

    def plan(input)
      page = target_page(input)
      page ? [{ "kind" => "page", "action" => "updated", "name" => page.name }] : []
    end

    def perform(input)
      page = target_page(input)
      flowchart = target_flowchart(input["flowchart"])
      result = Pages::Activities::BindFlowchart.call(page: page, flowchart_id: flowchart.id)
      unless result.ok
        return Outcome.invalid(operation: self.class.key, violations: [
          Violation.new(pointer: "/flowchart", code: "page.processing_rejected",
                        details: { "page" => page.name, "errors" => result.errors })
        ])
      end

      Outcome.succeeded(
        operation: self.class.key,
        data: { "page" => page.action_key, "audience" => input["audience"], "flowchart" => flowchart.name },
        effects: [{ "kind" => "page", "action" => "updated", "name" => page.name }]
      )
    end

    private

    def target_page(input)
      @target_page ||= Page.where(customer_id: context.customer.id, action_key: input["page"])
                           .for_audience(input["audience"]).order(:id).first
    end

    def target_flowchart(name)
      @target_flowchart ||= Flowchart.where(customer_id: [context.customer.id, nil], name: name.to_s.strip)
                                     .where.not(status: :deleted)
                                     .order(Arel.sql("customer_id IS NULL"), :id).first
    end

    def page_missing(input)
      Violation.new(pointer: "/page", code: "page.not_found", details: { "key" => input["page"], "audience" => input["audience"] })
    end

    def flowchart_missing(name)
      known = Flowchart.where(customer_id: [context.customer.id, nil]).where.not(status: :deleted).pluck(:name)
      Violation.new(pointer: "/flowchart", code: "flowchart.not_found",
                    details: { "name" => name.to_s.strip, "candidates" => Violation.candidates(name, known) })
    end
  end
end
```

- [ ] **Step 6: Create the locale files.** `config/locales/operations_page.en.yml`:

```yaml
en:
  operations:
    violations:
      page:
        not_found: "No page with the action key %{key} is visible to the %{audience} audience."
        processing_rejected: "%{page} cannot use this flowchart: %{errors}"
      flowchart:
        not_found: "No live flowchart named %{name} was found."
```

`config/locales/operations_page.zh-CN.yml`:

```yaml
zh-CN:
  operations:
    violations:
      page:
        not_found: "未找到对 %{audience} 受众可见、操作键为 %{key} 的页面。"
        processing_rejected: "%{page} 无法使用此流程图：%{errors}"
      flowchart:
        not_found: "未找到名为 %{name} 的可用流程图。"
```

- [ ] **Step 7: Extend the lint spec.** Add `"bind_page_flowchart"` to the key list on line 11 of `contract_lint_spec.rb`, and add `operations_page` to the parity area list (`%w[operations_entity operations_journey operations_page]`).

- [ ] **Step 8: Run the tests and confirm they pass**

Run: `bundle exec rspec spec/services/operations spec/services/pages/activities/bind_flowchart_spec.rb spec/contracts/pages/processing_contract_spec.rb`
Expected: PASS, including all three parity examples.

---

### Task 7: Teach the assistant to build journeys

**Files:**
- Create: `app/services/ai_assistant/assistant/prompt/documents/journey_authoring.md`
- Create: `app/services/ai_assistant/assistant/prompt/sections/journey_authoring.rb`
- Modify: `app/services/ai_assistant/assistant/prompt/composer.rb:25` (insert after `Sections::EntityExamples`)
- Modify: `spec/services/ai_assistant/assistant/prompt/composer_spec.rb:21-22`

**Interfaces:**
- Consumes: the `list_journey_options` and `generate_journeys` tools (Tasks 4–5). `tool_examples_contract_spec` validates the fenced examples against their schemas.

- [ ] **Step 1: Update the composer spec (it fails first).** Change lines 21–22 to:

```ruby
    expect(described_class::OUTLINES[:entity].size).to eq(17)
    expect(prompt.scan(/^## /).size).to eq(9)
```

and add:

```ruby
  it "teaches journeys after the entity examples" do
    entity = described_class::OUTLINES[:entity]
    sections = AiAssistant::Assistant::Prompt::Sections

    expect(entity.index(sections::JourneyAuthoring)).to eq(entity.index(sections::EntityExamples) + 1)
    expect(prompt).to include("## Building journeys")
  end
```

- [ ] **Step 2: Run it and confirm it fails**

Run: `bundle exec rspec spec/services/ai_assistant/assistant/prompt/composer_spec.rb`
Expected: FAIL with `uninitialized constant ...Sections::JourneyAuthoring`.

- [ ] **Step 3: Create `documents/journey_authoring.md`**

````markdown
A journey walks an admin, a member or a visitor through the form pages of one domain in order,
carrying each saved record to the next step. Journeys are built from the domain's entities, so
build them only after those entities exist.

- Call `list_journey_options` with the domain name. Each option has a `key`, a `kind`, an
  `audience` and a `name`:
  - `create` — an admin creates a record, then adds the rows that hang off it.
  - `record` — an admin adds one kind of related row from an existing record's page.
  - `member` — a signed-in member adds records they own.
  - `public` — a visitor signs up as a member, then continues on the member page named in
    `continues_to`; without `continues_to` the journey ends at sign-up.
- Call `generate_journeys` once with every key the requirements call for. Do not build an option
  nobody asked for: a `record` option only when admins add that row from the record's page, and a
  `member` or `public` option only when the people of the domain sign in.
- Never invent a key. Pass only keys `list_journey_options` returned in this conversation.
- An option marked `generated` already has its journey; do not build it again.
- A journey that reports `launch_blockers` stayed a draft. Name it and its blocker in `reply`.
- Journeys only add records, one form after another. Approvals, status changes, notifications and
  payments are not journeys; say plainly what you built and what is not covered.

```json
{"tool": "list_journey_options", "arguments": {"domain": "Academics"}}
```

```json
{"tool": "generate_journeys", "arguments": {"domain": "Academics", "journeys": ["create-12", "member-15"]}}
```
````

- [ ] **Step 4: Create `sections/journey_authoring.rb`**

```ruby
# frozen_string_literal: true

module AiAssistant
  module Assistant
    module Prompt
      module Sections
        class JourneyAuthoring < Section
          heads "Building journeys"
          document "journey_authoring"

          private

          def body = document
        end
      end
    end
  end
end
```

- [ ] **Step 5: Insert it into the outline.** In `composer.rb`, add `Sections::JourneyAuthoring,` directly after `Sections::EntityExamples,` in `OUTLINES[:entity]`.

- [ ] **Step 6: Run the Phase 1 verification set**

```bash
bundle exec rspec spec/services/ai_assistant/assistant/prompt spec/services/ai_assistant/assistant/prompt_builder_spec.rb \
  spec/services/ai_assistant/assistant/tools spec/services/ai_assistant/assistant/generate_page_spec.rb \
  spec/services/operations spec/services/journeys spec/services/entity_domains spec/services/flowchart_definitions \
  spec/services/pages/activities spec/contracts/pages/processing_contract_spec.rb \
  spec/requests/admin/maintenance/journey_launches_spec.rb spec/requests/admin/maintenance/journey_generations_spec.rb
```

Expected: PASS.

---

## Phase 2: Login decision and pre-check

**Facts this phase builds on:**
- `SemanticValidator#owner_allowed?` accepts `"owner": true` only on an `entity_entries` reference to a person entity that extends `Authentication::User`. A domain without logins therefore has no owner references and no member journeys.
- Extending User can't be undone (`Entity#person_extension_is_permanent`), but an entity that doesn't extend it can be changed later. "No logins" is the safe default.
- `JourneyPlanner` offers `public` sign-up only for a person entity that extends User. The admin `create` journey of such a person starts by creating the account.
- Bridges count toward the `entity` quota (`Entity.for_customer`). `Billing::Quota#allow?(key, by:)` checks a batch.

### Task 1: Ask before a person entity gets logins

**Files:**
- Modify `app/services/ai_assistant/assistant/prompt/documents/entity_authoring.md`:
  - §1 becomes four entity blockers; the fourth is the unsettled login decision.
  - Rewrite the person bullet in §5.
- Modify `app/services/ai_assistant/assistant/prompt/documents/clarifying.md`: add the login decision to "When to ask", and say a costly-to-undo choice pre-selects the option that can still be changed.
- Modify `app/services/ai_assistant/assistant/prompt/sections/entity_capabilities.rb`: the person-model line says it is for people who sign in, asked first.
- Modify `app/services/ai_assistant/assistant/prompt/documents/entity_platform.md`: the Extension bullet.
- Modify `app/services/ai_assistant/assistant/prompt/documents/journey_authoring.md`: map the answers to options. `public` only when people sign themselves up; `member` only when they sign in; an admin `create` journey for a person who signs in creates the account.
- Test `spec/services/ai_assistant/assistant/prompt/composer_spec.rb`.

**Rules the prompt must state:**
- Model the person entity as today (first, owns the links), but set `extends` only after the admin has confirmed that these people sign in to see and manage *their own* records.
- Ask in the same single clarify round:
  - "Will <people> sign in to see their own records?" (`single`, default: no);
  - "How are their accounts created?" (self sign-up / staff create them / both).
- Don't ask when the matrix lists no person base model, when the catalog's person entity already extends it, or when the conversation already settled it.
- Staff who work on other people's records are admins, never a person entity.
- `"owner": true` only on a reference to a person entity that signs in. It decides which member journeys exist.
- One person entity with logins per domain. When a second group of people needs logins, say so in `reply` instead of modelling it.

**Spec:** the person-model capability line names sign-in.

### Task 2: Worked examples that ask, then build entities and journeys in one turn

**Files:**
- Modify `app/services/ai_assistant/assistant/prompt/documents/entity_examples.md`:
  - Every existing example that sets `extends` gains the state "the admin confirmed students sign in to see their own records".
  - New example: a new school system → `clarify` with the two login questions (default: not signing in) and one organisation-specific list if needed.
  - New example: the answers ("Yes", "Both") → `create_entity` (Student extends User and owns a Course association; an Assignment with an `owner` reference) → `list_journey_options` → `generate_journeys` with the create, member and public keys → final envelope naming the journeys and the assumptions.
- Test `composer_spec.rb` ("the worked examples"):
  - The login question is `single`, with the "not signing in" option as its default.
  - A `create_entity` example is followed by `list_journey_options`, then `generate_journeys`.
  - `tool_examples_contract_spec` validates the new payloads against the live schemas and semantic rules automatically.

### Task 3: `AiAssistant::Subsystems::Preflight`

**Files:**
- Create `app/services/ai_assistant/subsystems/preflight.rb`.
- Create `config/locales/ai_assistant_subsystems.{en,zh-CN}.yml`.
- Test `spec/services/ai_assistant/subsystems/preflight_spec.rb`.

**Interface:**
- `Preflight.call(customer:, plan:)` takes `plan` as `Preflight::Plan.new(entities:, pages:, logins:, signup:)`. The counts are new rows the build will write, bridges included.
- It returns `Result(ok:, blockers:, warnings:)` of `Issue(code:, message:)`:
  - `entity_quota` / `page_quota` blocker: `Billing::Quota#allow?(key, by: count)` fails; the message names the count needed, the room left and the limit;
  - `logins_unavailable` blocker: `logins` but `Capabilities.person_model(customer.id)` is nil;
  - `signup_disabled` warning: `logins && signup` and `Authentication::Settings#signup_enabled?` is false. It reuses `operations.journeys.sign_up_disabled`, because the build goes on and the sign-up journey stays a draft.
- Messages are translated at call time; new keys are under `ai_assistant.subsystems.preflight`.

**Spec:**
- Within limits: ok.
- Each blocker and the warning.
- No quota blocker for the platform owner customer (unlimited).
- Tenant isolation: another customer's usage, extendable models and sign-up setting never count.
- en/zh-CN key and `%{}` parity of the new locale files.

**Done when:** prompt, composer, tool-example and preflight specs pass (`bundle exec rspec spec/services/ai_assistant`).

## Phase 3: Background build with pause and resume

**Shape decided from the code (supersedes the sketch below where they differ):**
- **Entities stay in the turn.** The entities stay where Phase 2 put them: in the model's own `create_domain` / `create_entity` calls in the answers turn. A blueprint carrying full entity specs would duplicate the `create_entity` schema, and the projected tool schema would blow the 32 KB budget.
- **The build covers what spans turns:** journeys, processing, binding, launch and the report. The model starts it with `start_subsystem_build` after the entities exist and `list_journey_options` has returned keys.
- **Owner-only for now:** like `bind_page_flowchart`, the operation is owner-only (`FlowchartVisibility`) in Phase 3. Phase 4 opens it to tenant admins (and renames `bind_page_flowchart` to `set_page_processing`).
- **The job and its budget:** stages run in `AiAssistant::SubsystemBuildJob`, outside any generation. Each processing need gets its own `ProviderClient` with a budget of 4 calls.
- **Waiting builds:** a waiting build takes the next message as answers inside `Activities::Reply`, before `PendingConfirmation` and before any vendor call. While a build runs, a message gets a short "still building" reply with no vendor call. A build idle for 30 minutes counts as stalled and is failed.
- **URL rule:** a destination URL must appear verbatim in one of the admin's own messages (`role: "user"`). Values the model passes are not trusted for this.
- **Secrets:** steps needing a secret value (`api_call.authToken` / `authPassword`, `send_chat_message.signingSecret`, `send_webhook.secretExpression`) are rejected by a screen, so the model leaves them out and names them in `needs_setup`.
- **One question round per need:** a need that still lacks a value after one round of answers is left out and listed as needing setup.

### Task 1: `AiAssistant::SubsystemBuild`
- Migration `ai_assistant_subsystem_builds`:
  - `customer_id`, `conversation_id`, `user_id`;
  - `status` (running / waiting_for_answers / finished / failed / cancelled) and `stage` (journeys / processing / binding / launch / report);
  - JSON `blueprint`, `questions`, `answers`, `results`;
  - a unique partial index on `conversation_id` while running or waiting.
- Model: `TenantScoped`, `active` scope, `stalled?`, `name` (the domain).
- Spec: one active build per conversation; scoping.

### Task 2: Flowchart author hooks
- `FlowchartDefinitions::Assistant::Extraction` keeps optional `questions` (sanitized by `AiAssistant::Assistant::Questions`) and `needs_setup` (short strings).
- `Processor` takes `screen:`, a callable that returns extra errors for a normalized document; they feed the existing repair loop.
- Specs on both.

### Task 3: `start_subsystem_build` operation
- Input:
  - `domain`;
  - `journeys`: 1–10 unique option keys;
  - `processing`: 0–5 needs, each `{name, entity, audience, purpose, values: [{label, value}]}`.
- Validate:
  - domain;
  - keys;
  - each need names a page a chosen journey will have (its start or step entity, with its audience);
  - unique need names;
  - no active build in the conversation;
  - a conversation is present;
  - `Preflight` blockers (pages: an upper bound over options without a journey; logins and sign-up from public options).
- Perform: create the build, enqueue the job after commit, and return `{build, status, warnings}` with a `subsystem_build started` effect.
- Locale `operations_subsystem.{en,zh-CN}.yml`, added to the parity list.
- Prompt guidance `subsystem_builds.md` and `Sections::SubsystemBuilds`, owner-only, after `PageProcessing`.
- Specs per the Operations API checklist.

### Task 4: Stages
- `AiAssistant::Subsystems::Build` runs from the stored stage. It re-checks the user (active, admin of the customer or owner), the module and the provider, stops when the build is cancelled, and saves results after every item, so a re-run skips finished work:
  - **journeys:** generate the missing ones (no launch);
  - **processing:** `AuthorProcessing` per need → created, questions, failed or skipped; collect questions from every need, then pause;
  - **binding:** `Pages::Activities::BindFlowchart` per created need;
  - **launch:** `Journeys::Activities::Launch`, skipping journeys whose pages wait on unbound processing and public ones while sign-up is off;
  - **report:** an assistant message listing what was built, what needs setup and the warnings; earlier build messages are re-rendered.
- Pausing posts an assistant message with the existing `questions` metadata and sets `waiting_for_answers`.
- Specs (vendor stubbed): each stage, pause, resume, the URL rule, the secret screen, the one-round rule, cancel mid-run, an unauthorized user and the report.

### Task 5: Answers and the starting reply
- `AiAssistant::Subsystems::Answer.consume` in `Activities::Reply`:
  - waiting → store the answers, set running, enqueue, and reply "continuing";
  - running → reply "still building";
  - stalled → fail the build and continue normally.
- `Tools::Session` records a `subsystem_build` effect. `Finalizer` writes `metadata["subsystem_build"]` and keeps it out of `changes`.
- Specs.

### Task 6: Cancel
- `post :cancel_build` on assistant messages (`/:cid/admin/modules/ai_assistant/messages/:id/cancel_build`, admin category).
- `AiAssistant::Activities::CancelSubsystemBuild` reaches the build only through a message in the caller's own conversation.
- `MessageComponent` shows the build's status and, while active, a Cancel button (`button_to`, Turbo confirm, no new JS).
- Request spec (admin, member forbidden, other tenant 404), component spec.

**Done when:** `bundle exec rspec spec/services/ai_assistant spec/services/operations spec/services/flowchart_definitions spec/models/ai_assistant spec/requests/admin/modules/ai_assistant spec/components/ai_assistant spec/jobs` passes.

**Original sketch:**

- **New table** `ai_assistant_subsystem_builds`, with:
  - `customer_id`, `conversation_id`, `user_id`;
  - `status` (running, waiting_for_answers, finished, failed, cancelled), `stage`;
  - `blueprint`, `questions`, `answers` and `created` (JSON);
  - at most one active build per conversation.
- **Blueprint:** the answers turn returns a validated blueprint covering the domain, entities, the login decision, journeys (named by kind and entity names, resolved to candidate keys once the entities exist), and processing needs with the values the admin supplied.
- **Stages:** `AiAssistant::Subsystems::Build` runs the stages in `SubsystemBuildJob`. Each stage is safe to re-run and has its own vendor-call budget:
  1. entities, through `Operations::Activities::Execute` with build-scoped idempotency keys (`extends` passed only when the blueprint's login decision is yes);
  2. journeys, through `generate_journeys` with `launch: false`;
  3. processing, one flowchart per need;
  4. binding, through `Pages::Activities::BindFlowchart`;
  5. launch, through `Journeys::Activities::Launch`, but only when processing is complete and, for public journeys, sign-up is on;
  6. the report: what was built, assumptions, needs setup, skipped items.
- **Pausing:** a stage that needs values first finishes everything that doesn't depend on them, then posts at most 5 questions through the existing question metadata and sets `waiting_for_answers`. While a build waits, every message in that conversation goes to it as answers, the same way a reply to a pending proposal is routed today. A Cancel control lives on an admin-guarded route under `/:cid/admin/`.
- **Asking rules:** ask only for facts that must never be invented (destination URLs, recipients, organisation-specific lists, prices, which template) and for choices that are costly to undo. Decide everything else and list it as assumptions. Skipped questions use their default; a value with no safe default (e.g. a URL) leaves that piece out and lists it in the report.
- **Safety rules:**
  - Destination URLs must appear verbatim in the admin's answers; otherwise the build asks.
  - Steps that need a secret field (`signingSecret`, `authToken`, `secretExpression`, …) are left out and listed under "needs setup". Secrets are never collected in chat.
  - A journey whose page is waiting on custom processing is not launched until that flowchart is bound.
- **Limits:** each answer round counts toward the 40-turn thread limit and the hourly rate limit.
- **Done when:** specs cover each stage with `AiAssistant::ScriptedCompletion`, pause and resume, cancel, a member being forbidden, cross-tenant resume being refused, and the final report contents.

## Phase 4: Processing for tenant admins

**Shape decided from the code (supersedes the sketch below where they differ):**
- **One neutral vocabulary.** The surfaces this phase opens use "form processing" / "what happens when the form is submitted" for every viewer instead of two copies per audience. The owner-only flowchart pass, editor, catalog UI, mentions and artifacts are unchanged and stay owner-only.
- **What a tenant admin's model sees.** The entity-mode system prompt and the tool definitions available to a tenant admin never contain "flowchart":
  - `bind_page_flowchart` is renamed `set_page_processing`, with its input field `processing`;
  - the entity settings descriptions in `entity.defs.json` (they were the one leak already there) say what the settings do;
  - `list_catalog` returns the workspace's own processing under `processing`, replacing the owner-only `flowcharts` key. This is the catalog under a neutral heading, read on demand instead of costing every prompt.
- **What a tenant admin reads.** Server text in tenant builds is neutral:
  - binding refusals use the reasons any admin may read (unavailable / offline / doesn't fit the entity), not the code generator's step-level problems. The owner keeps the detailed reasons.
  - Authoring failures that come from the flowchart pass ("could not generate a flowchart", the repair message) become one neutral line for tenant builds.
  - "Needs setup" items name the step and field by their palette labels (e.g. "Signing secret of the Send Webhook step").
  - The build instruction tells the model that questions, `needs_setup` and its reply are read by the admin and must describe what happens on submit without the word "flowchart". Model text can't be proven; server text is.
- **Gates removed:**
  - `start_subsystem_build`, `set_page_processing` and the `PageProcessing` / `SubsystemBuilds` prompt sections are open to every admin (the operation framework already refuses members and other tenants);
  - `Build#allowed?` drops `FlowchartVisibility`.

### Task 1: Neutral surfaces for the entity-mode model
- `entity.defs.json` settings descriptions; `list_catalog` returns `processing` for every viewer; the `ListCatalog` description.
- `prompt_builder_spec`: a tenant admin's entity prompt teaches form processing and background builds and never matches `/flowchart|流程图/i`. A probe over `Operations.all` tool definitions available to a tenant admin finds no "flowchart".

### Task 2: `set_page_processing`
- Rename of `bind_page_flowchart`: key, class, schema (`page`, `audience`, `processing`), neutral summary, no `available?` override.
- New violation codes `processing.not_found` and `page.processing_refused` in `operations_page.{en,zh-CN}.yml`. The Phase 1 keys `page.processing_rejected` / `flowchart.not_found` are left in place, since existing keys are frozen.
- `Pages::Activities::BindFlowchart::Result#reasons`: reasons any admin may read. The operation shows `errors` to the owner and `reasons` to anyone else.
- `page_processing.md` rewritten neutrally under the heading "What happens when a form is submitted".
- Specs: a tenant admin binds; a member is forbidden; another tenant's page is not found; a tenant's refusal is neutral while the owner's is detailed; shared processing by name; `contract_lint_spec`.

### Task 3: Builds for tenant admins
- Remove the `start_subsystem_build` gate, the `SubsystemBuilds` section gate and `Build#allowed?`'s `FlowchartVisibility` check.
- `AuthorProcessing`: neutral failure line for non-owner builds; needs-setup items from palette labels; the instruction rule for admin-read text.
- `Build#bind`: owner → `errors`, others → `reasons`.
- Specs: a tenant admin's build runs end to end; its report and question messages never match `/flowchart|流程图/i`, including after a failed authoring and a refused binding; the operation is available to a tenant admin.

**Done when:** `bundle exec rspec spec/services/ai_assistant spec/services/operations spec/services/flowchart_definitions spec/services/pages spec/models/ai_assistant spec/requests/admin/modules/ai_assistant spec/components/ai_assistant spec/jobs` passes.

**Original sketch:**

- Run the flowchart stage for tenant admins and remove `bind_page_flowchart`'s owner gate.
- Tenant-facing copy says "what happens when the form is submitted" and never "flowchart". This needs new en/zh-CN keys.
- The flowchart catalog in the prompt shows only the tenant's own flowcharts, under a neutral heading.
- The editor, sidebar and catalog UI stay owner-only.
- **Done when:** the tenant-admin prompt and reply specs prove the word "flowchart" never appears, and binding specs pass for tenant admins.

## Phase 5: Documentation (only when explicitly requested)

- Update `AGENTS.md`: the journey and flowchart policy exceptions for assistant-managed resources, and the stale text (flowchart `crud_type`, `after_submit` / `next_page` / `handoff`, journey step kinds `record` and `user`).
- Update `doc/reference/{en,zh-CN}/operations-api.md` for the new operations.
- Update `doc/reference/{en,zh-CN}/ai-assistant.md`: `list_catalog`'s neutral `processing`, the narrower `FlowchartVisibility` gate, and a "Sub-system builds" section.
- Delete the locale keys left unused by the Phase 4 rename: `operations.violations.page.processing_rejected` and `operations.violations.flowchart.not_found`.
- **Done when:** both locales of each page keep the same sections, examples and callouts, and the developer-docs and locale parity specs pass.

## Later (not in v1)

- "Undo this build", using the build's record of what it created, until the first real record is saved.
- An encrypted per-tenant secret store that flowchart steps refer to by name.
- A custom-shape `create_journey` operation, if the planner's options prove too narrow.

---

## Execution notes

- Execution is subagent-driven with the anysys team: the QA engineer writes each task's specs first (red), the backend developer implements (green), and the security engineer handles the one controller edit in Task 3. Each task gets a task review. After Phase 1: the release engineer, then the tech lead and code reviewer in parallel.
- No commits: each approved task is staged with `git add`, so the unstaged diff is always the task under review.
