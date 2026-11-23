# Linked Pages, Automations and Journeys: Implementation Plan (Phases 1–2)

> **For agentic workers:** REQUIRED SUB-SKILL: use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to carry out this plan task by task. Steps use checkbox (`- [ ]`) syntax for tracking. Dispatch the `anysys-*` subagents with `model` omitted (inherit).

**Goal:** Pages save their record through one writer. Flowcharts become record automations. Pages pass the record they create to the next page as locked inputs. A platform-owner-only journey layer turns a domain such as "student enrolls course" into a guided New student → Choose courses flow, which can be generated or built by hand.

**Architecture:**
- **Data:** entities and contracts stay as they are.
- **Behaviour:** `Flowchart` rows with a trigger timing run from `Entries::Save`, whichever surface saves the record.
- **Presentation:** pages declare submission modes, locked inputs and an "After submit" action.
- **Navigation:** a `JourneyRun` row stored in the database carries records between pages. A `Journey` sequences pages by action key.

**Tech stack:** Ruby 3.2.8, Rails 8.1.2 (SQLite), Trailblazer Activity, Reform, ViewComponent, Tailwind, Stimulus, RSpec, Vitest.

## Global constraints

- **Roles:** only `owner`, `admin` and `member`.
  - Journeys are built **only by the platform owner**, through `JourneyVisibility`, which is registered in `OwnerOnlySurfaces`.
  - Automations stay owner-only through the existing `FlowchartVisibility`.
- **URL categories:**
  - Admin: `/:cid/admin/...`.
  - Public: `/:cid/journeys/:key`.
  - No new member URLs.
- **Tenancy:** every new table has `customer_id`, and every lookup is scoped to `current_customer`.
- **Customer-facing wording:** customers never see the word "flowchart".
- **I18n:** no hard-coded user-facing strings, and every new key exists in both `en` and `zh-CN`. Existing keys are frozen: don't edit or delete them, even when they become unused.
- **JavaScript coverage:** `app/javascript/**` stays at 100% lines and branches under `npx vitest run --coverage`.
- **Responsiveness:** every new page and component uses Tailwind responsive classes.
- **Git:** never run `git commit`. Steps marked "Checkpoint" mean "run the specs and stop for review".
- **Documentation:** no doc changes beyond this plan file and the `AGENTS.md` update in Task 15, Step 6 (both requested by the user). `doc/reference/**` stays untouched.
- **Compatibility:** no backward-compatibility shims. Leftover `flowchart_id` keys in stored page configurations are simply ignored.

## File map

| Area | Create | Modify / delete |
|---|---|---|
| Automations | `app/models/flowchart/trigger.rb`, `app/services/automations/{context,condition,dispatcher}.rb`, `app/jobs/automations/run_job.rb` | `app/models/flowchart.rb`, `app/models/current.rb`, `app/services/flowchart_runtime/registration.rb` |
| Writer | `app/services/entries/save.rb` | `entities/activities/{entry_writer,create_association_entries,update_association_entry}.rb`, `pages/bridge_entries.rb` |
| Submission | `app/services/flowchart_runtime/runtime_flowchart.rb` (moved) | `pages/public_submission.rb`, `public_pages_controller.rb`, `page_configuration_helpers.rb`, `set_submission_outcome_generator.rb`, palette json. Delete `pages/submission_process.rb` |
| Unbinding | | `entry_page_resolver.rb`, `launch_checks.rb`, `page.rb`, `flowchart.rb`, `flowchart_launches_controller.rb`, `create_from_entity_version.rb`, `pages_controller.rb`, `_editor.html.erb`, `new.html.erb`, `activity_tracer.rb`, `activity_class_builder.rb`. Delete `page_builder/flows_section_component.*` |
| Inputs and After submit | `app/models/journey_run.rb`, `pages/{input_bindings,after_submit,run_link}.rb`, `components/pages/locked_inputs_component.*`, `helpers/page_inputs_helper.rb`, `jobs/journey_runs/purge_job.rb` | `page_rendering.rb`, `page_content_generator{.rb,/form_fields.rb}`, `admin/entity_entries_controller.rb` |
| Builder UI | | `settings_modal_component.*`, `property_manager.js`, `page_manager.js`, `page_builder_controller.js`, `tab_manager.js` |
| Trigger UI | `admin/maintenance/flowchart_triggers_controller.rb` | `flowchart_info_card_component.*`, `routes.rb` |
| Journeys | `app/models/journey.rb`, `services/journeys/**`, `services/entity_domains/journey_planner.rb`, `services/journey_visibility.rb`, `controllers/journeys/starts_controller.rb`, `controllers/admin/maintenance/{journeys,journey_launches,journey_generations}_controller.rb`, `controllers/admin/domains/journeys_controller.rb`, `components/journeys/**`, `components/page_builder/journey_usage_component.*`, `javascript/controllers/journey_builder_controller.js`, `config/locales/journeys.{en,zh-CN}.yml` | `owner_only_surfaces.rb`, `admin/domains/browse_component.rb`, `routes.rb` |

---

# Phase 1: Foundation

### Task 1: Flowchart trigger columns

**Files:**
- Create: `db/migrate/20261112100000_add_trigger_to_flowcharts.rb`, `app/models/flowchart/trigger.rb`
- Modify: `app/models/flowchart.rb` (add `Flowchart::Trigger` to the includes at L4–10), `app/models/current.rb` (add `attribute :automation_stack`), `config/locales/maint_core.{en,zh-CN}.yml`
- Test: `spec/models/flowchart_trigger_spec.rb`

**Interfaces:**
- Produces:
  - `Flowchart::Trigger::TIMINGS` (`%w[before_save after_save after_commit]`) and `EVENTS` (`%w[create update]`).
  - `Flowchart.automations(customer_id:, entity_id:, event:, timing:)`, which returns an ordered relation.
  - `Flowchart#automation?` and `Flowchart#trigger_condition_json` (an array of `ConditionEvaluator` rows).
  - `Current.automation_stack`.

- [ ] **Step 1: Write the failing spec**

```ruby
# spec/models/flowchart_trigger_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Flowchart::Trigger do
  let(:customer) { create(:customer) }
  let(:entity) { create(:entity, customer: customer) }

  def automation(**attrs)
    build(:flowchart, :simple, customer: customer, entity: entity, crud_type: "create", trigger_timing: "after_save", **attrs)
  end

  it "accepts a customer-owned create/update flowchart with a timing" do
    expect(automation).to be_valid
  end

  it "rejects an unknown timing" do
    expect(automation(trigger_timing: "sometimes")).not_to be_valid
  end

  it "requires a create or update event" do
    flowchart = automation(crud_type: "read")
    expect(flowchart).not_to be_valid
    expect(flowchart.errors[:base]).to include(I18n.t("maint_core.errors.validations.flowchart_trigger_event"))
  end

  it "lists launched automations of one entity, event and timing in position order" do
    second = create(:flowchart, :simple, :launched_status, customer:, entity:, crud_type: "create", trigger_timing: "after_save", trigger_position: 2)
    first = create(:flowchart, :simple, :launched_status, customer:, entity:, crud_type: "create", trigger_timing: "after_save", trigger_position: 1)
    create(:flowchart, :simple, :draft, customer:, entity:, crud_type: "create", trigger_timing: "after_save")
    create(:flowchart, :simple, :launched_status, customer:, entity:, crud_type: "create")
    create(:flowchart, :simple, :launched_status, customer:, entity:, crud_type: "update", trigger_timing: "after_save")

    expect(Flowchart.automations(customer_id: customer.id, entity_id: entity.id, event: "create", timing: "after_save"))
      .to eq([first, second])
  end
end
```

- [ ] **Step 2: Run it and confirm it fails**

  Run `bundle exec rspec spec/models/flowchart_trigger_spec.rb`. Expected: it fails with `uninitialized constant Flowchart::Trigger`.

- [ ] **Step 3: Write the migration, the concern and the locale keys**

```ruby
# db/migrate/20261112100000_add_trigger_to_flowcharts.rb
# frozen_string_literal: true

class AddTriggerToFlowcharts < ActiveRecord::Migration[8.1]
  def change
    add_column :flowcharts, :trigger_timing, :string
    add_column :flowcharts, :trigger_condition, :text
    add_column :flowcharts, :trigger_position, :integer, null: false, default: 0
    add_index :flowcharts, %i[customer_id entity_id trigger_timing],
              where: "trigger_timing IS NOT NULL", name: "idx_flowcharts_automations"
  end
end
```

```ruby
# app/models/flowchart/trigger.rb
# frozen_string_literal: true

# A flowchart with a trigger timing is an automation: once launched it runs
# whenever a record of its entity is created or updated (crud_type), from any
# surface. The timing is a separate opt-in so create/update flowcharts written
# for forms never start firing on their own.
module Flowchart::Trigger
  extend ActiveSupport::Concern

  TIMINGS = %w[before_save after_save after_commit].freeze
  EVENTS = %w[create update].freeze

  included do
    json_attribute :trigger_condition, default: []

    validates :trigger_timing, inclusion: { in: TIMINGS }, allow_nil: true
    validates :trigger_position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
    validate :trigger_needs_entity_event

    scope :automations, lambda { |customer_id:, entity_id:, event:, timing:|
      launched.where(customer_id: customer_id, entity_id: entity_id, crud_type: event.to_s, trigger_timing: timing.to_s)
              .order(:trigger_position, :id)
    }
  end

  def automation? = trigger_timing.present?

  private

  def trigger_needs_entity_event
    return unless automation?

    errors.add(:base, I18n.t("maint_core.errors.validations.flowchart_trigger_shared")) if customer_id.blank?
    errors.add(:base, I18n.t("maint_core.errors.validations.flowchart_trigger_entity")) if entity_id.blank?
    errors.add(:base, I18n.t("maint_core.errors.validations.flowchart_trigger_event")) unless EVENTS.include?(crud_type.to_s)
  end
end
```

Add these under `maint_core.errors.validations` (`maint_core.en.yml` ~L40):

```yaml
        flowchart_trigger_shared: "Shared flowcharts can't run as automations."
        flowchart_trigger_entity: "Bind an entity before choosing when this flowchart runs."
        flowchart_trigger_event: "Set the CRUD type to create or update before choosing when this flowchart runs."
```

And the `zh-CN` equivalents:

```yaml
        flowchart_trigger_shared: "共享流程图不能作为自动化运行。"
        flowchart_trigger_entity: "请先绑定实体，再设置运行时机。"
        flowchart_trigger_event: "请先将 CRUD 类型设为新建或更新，再设置运行时机。"
```

- [ ] **Step 4: Migrate and run the spec**

  Run `bin/rails db:migrate && bundle exec rspec spec/models/flowchart_trigger_spec.rb spec/models/flowchart_spec.rb`. Expected: all pass.

- [ ] **Step 5: Checkpoint.** Stop for review.

---

### Task 2: Automations engine

**Files:**
- Create: `app/services/automations/context.rb`, `app/services/automations/condition.rb`, `app/services/automations/dispatcher.rb`, `app/jobs/automations/run_job.rb`
- Modify:
  - `app/services/flowchart_runtime/registration.rb`: the existing-email path (L90–100) and the quota path set `ctx[:discard_record] = true`.
  - `config/locales/flowchart_runtime.{en,zh-CN}.yml`.
- Test: `spec/services/automations/dispatcher_spec.rb`, `spec/jobs/automations/run_job_spec.rb`, plus one new example in the existing Registration spec.

**Interfaces:**
- Consumes: `Flowchart.automations`, `Current.automation_stack` (from Task 1); `ActivityTracer.new(flowchart).call(ctx, trace: false)`.
- Produces:
  - `Automations::Context.build(audience:, source:, actor: nil, identity: {}, authentication: nil, continuation: nil, journey: nil, current_person_ids: {}, request: {})`, with `#to_ctx`, `#to_job_payload` and `.from_job_payload(hash)`.
  - `Automations::Dispatcher.call(entry:, event:, timing:, context:, changes: [])`, which returns `Result(errors:, outcome:, discard:, timing_started_at:)` with `#ok?`.
  - `Automations::Dispatcher.ctx_for(entry:, event:, timing:, context:, changes:)`.
  - `Automations::RunJob.perform_later(flowchart_id, entry_id, event, payload, changes)`.
  - Condition fields reserved for the system (`@` can't appear in a slug): `@audience`, `@surface`, `@action_key`, `@changed`.

- [ ] **Step 1: Write the failing dispatcher spec**

```ruby
# spec/services/automations/dispatcher_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Automations::Dispatcher do
  let(:customer) { create(:customer) }
  let(:entity) do
    create(:entity, customer: customer, property_schema: [
      { "name" => "Title", "name_slug" => "title", "type" => "String", "html_type" => "text" },
      { "name" => "Notes", "name_slug" => "notes", "type" => "String", "html_type" => "text" }
    ].to_json)
  end
  let(:entry) { EntityEntry.build_for(entity).new(entity: entity, customer_id: customer.id, data: { "title" => "Hi" }.to_json) }
  let(:context) { Automations::Context.build(audience: "public", source: { "surface" => "page" }) }

  def activity(name, body)
    <<~RUBY
      class #{name} < Trailblazer::Activity::Railway
        CANVAS = { steps: {} }.freeze
        step :run
        def run(ctx, **)
          #{body}
        end
      end
    RUBY
  end

  def automation(code, timing: "before_save", event: "create", **attrs)
    create(:flowchart, :simple, :launched_status, customer:, entity:, crud_type: event, trigger_timing: timing, **attrs)
      .tap { |flowchart| flowchart.update_column(:activity, code) }
  end

  def dispatch(timing:, changes: [], ctx: context)
    described_class.call(entry: entry, event: "create", timing: timing, context: ctx, changes: changes)
  end

  it "runs matching automations with the record and audience in ctx" do
    automation(activity("StampNotes", 'ctx[:model].notes = "by #{ctx[:audience]}"; true'))
    expect(dispatch(timing: "before_save")).to be_ok
    expect(entry.notes).to eq("by public")
  end

  it "skips automations whose condition does not match" do
    automation(activity("NeverRuns", 'ctx[:model].notes = "ran"; true'),
               trigger_condition: [{ "field_id" => "@audience", "operator" => "equals", "value" => "admin" }].to_json)
    dispatch(timing: "before_save")
    expect(entry.notes).to be_nil
  end

  it "returns the automation's messages when it fails" do
    automation(activity("Refuses", 'ctx[:errors] = ["Course is full"]; false'))
    expect(dispatch(timing: "before_save").errors).to eq(["Course is full"])
  end

  it "collects the submission outcome and the discard flag after save" do
    automation(activity("Outcome", 'ctx[:submission_outcome] = { "preset" => "thank_you" }; ctx[:discard_record] = true; true'),
               timing: "after_save")
    entry.save!
    result = dispatch(timing: "after_save")
    expect(result.outcome).to eq("preset" => "thank_you")
    expect(result.discard).to be(true)
  end

  it "queues after_commit automations without identity or authentication" do
    flowchart = automation(activity("Later", "true"), timing: "after_commit")
    entry.save!
    secret = Automations::Context.build(audience: "public", source: { "surface" => "page" }, identity: { "password" => "x" })
    expect { dispatch(timing: "after_commit", changes: ["title"], ctx: secret) }
      .to have_enqueued_job(Automations::RunJob).with(flowchart.id, entry.id, "create", hash_excluding("identity"), ["title"])
  end

  it "stops a runaway chain at the depth limit" do
    Current.automation_stack = [%w[a 1 x], %w[b 2 y], %w[c 3 z]]
    automation(activity("Deep", "true"))
    expect(dispatch(timing: "before_save").errors).to eq([I18n.t("flowchart_runtime.automations.too_deep")])
  ensure
    Current.automation_stack = nil
  end
end
```

If `have_enqueued_job` can't see jobs because of `enqueue_after_transaction_commit`, copy whatever the `Billing::FinalizeInvoiceJob` specs do.

- [ ] **Step 2: Run it and confirm it fails**

  Run `bundle exec rspec spec/services/automations/dispatcher_spec.rb`. Expected: it fails with `uninitialized constant Automations`.

- [ ] **Step 3: Implement**

```ruby
# app/services/automations/context.rb
# frozen_string_literal: true

module Automations
  # Who saved a record, from where, and the request facts automations may
  # read. Secrets (identity, authentication) never leave the request.
  Context = Data.define(:audience, :actor_id, :actor_role, :source, :identity, :authentication,
                        :continuation, :journey, :current_person_ids, :request) do
    def self.build(audience:, source:, actor: nil, identity: {}, authentication: nil, continuation: nil,
                   journey: nil, current_person_ids: {}, request: {})
      new(audience: audience.to_s, actor_id: actor&.id, actor_role: actor&.primary_role_key,
          source: source.to_h.stringify_keys, identity: identity.to_h, authentication: authentication,
          continuation: continuation, journey: journey, current_person_ids: current_person_ids.to_h,
          request: request.to_h.symbolize_keys)
    end

    def self.from_job_payload(payload)
      data = payload.to_h.stringify_keys
      new(audience: data["audience"].to_s, actor_id: data["actor_id"], actor_role: data["actor_role"],
          source: data["source"].to_h, identity: {}, authentication: nil, continuation: nil,
          journey: data["journey"], current_person_ids: {}, request: {})
    end

    def to_ctx
      {
        audience: audience, current_user_id: actor_id, current_user_role: actor_role, source: source,
        identity: identity, authentication: authentication, continuation: continuation, journey: journey,
        current_person_ids: current_person_ids
      }.merge(request).compact
    end

    def to_job_payload
      { "audience" => audience, "actor_id" => actor_id, "actor_role" => actor_role,
        "source" => source, "journey" => journey }
    end
  end
end
```

```ruby
# app/services/automations/condition.rb
# frozen_string_literal: true

module Automations
  # An automation's optional "only when" rows, in ConditionEvaluator format.
  # An empty list always matches.
  module Condition
    def self.match?(rows, values)
      ConditionEvaluator.new(Array(rows).grep(Hash), values).evaluate
    end
  end
end
```

```ruby
# app/services/automations/dispatcher.rb
# frozen_string_literal: true

module Automations
  # Runs the launched automations of one entity for one save event and timing.
  # before_save / after_save run inline inside the caller's transaction, so a
  # failure rolls the write back; after_commit is queued and never undoes it.
  class Dispatcher
    include Loggable

    MAX_DEPTH = 3
    INLINE = %w[before_save after_save].freeze

    Result = Data.define(:errors, :outcome, :discard, :timing_started_at) do
      def ok? = errors.empty?
    end

    def self.call(...) = new(...).call

    def self.ctx_for(entry:, event:, timing:, context:, changes:)
      context.to_ctx.merge(
        model: entry, bound_entity: entry.entity, customer_id: entry.customer_id,
        params: entry.data_json.to_h.stringify_keys, event: event.to_s, timing: timing.to_s, changes: Array(changes)
      )
    end

    def initialize(entry:, event:, timing:, context:, changes: [])
      @entry = entry
      @event = event.to_s
      @timing = timing.to_s
      @context = context
      @changes = Array(changes)
    end

    def call
      flowcharts = matching
      return empty if flowcharts.empty?
      return enqueue(flowcharts) unless INLINE.include?(@timing)

      guarded { run_inline(flowcharts) }
    end

    private

    def matching
      Flowchart.automations(customer_id: @entry.customer_id, entity_id: @entry.entity_id, event: @event, timing: @timing)
               .select { |flowchart| Condition.match?(flowchart.trigger_condition_json, condition_values) }
    end

    def condition_values
      data = @entry.data_json.to_h.to_h { |key, value| [key.to_s, value.is_a?(Array) ? value.join(",") : value.to_s] }
      data.merge(
        "@audience" => @context.audience.to_s,
        "@surface" => @context.source["surface"].to_s,
        "@action_key" => @context.source["action_key"].to_s,
        "@changed" => @changes.join(",")
      )
    end

    def run_inline(flowcharts)
      outcome = {}
      discard = false
      started = nil
      flowcharts.each do |flowchart|
        trace = ActivityTracer.new(flowchart).call(self.class.ctx_for(entry: @entry, event: @event, timing: @timing,
                                                                     context: @context, changes: @changes), trace: false)
        ctx = trace.ctx.is_a?(Hash) ? trace.ctx : {}
        return failure(ctx, flowchart) unless trace.success?

        outcome.merge!((ctx[:submission_outcome] || {}).to_h.deep_stringify_keys)
        discard ||= @timing == "after_save" && ctx[:discard_record] == true
        started ||= ctx[:uniform_timing_started_at]
      end
      Result.new(errors: [], outcome: outcome, discard: discard, timing_started_at: started)
    end

    def enqueue(flowcharts)
      flowcharts.each do |flowchart|
        RunJob.perform_later(flowchart.id, @entry.id, @event, @context.to_job_payload, @changes)
      end
      empty
    end

    def guarded
      stack = Current.automation_stack || []
      key = [@entry.entity_id.to_s, (@entry.id || @entry.object_id).to_s, @timing]
      return empty if stack.include?(key)
      return Result.new(errors: [I18n.t("flowchart_runtime.automations.too_deep")], outcome: {}, discard: false, timing_started_at: nil) if stack.size >= MAX_DEPTH

      Current.automation_stack = stack + [key]
      yield
    ensure
      Current.automation_stack = stack
    end

    def failure(ctx, flowchart)
      log_error "Automation #{flowchart.id} failed for entity #{@entry.entity_id} (#{@event}/#{@timing})"
      messages = Array(ctx[:errors]).grep(String).reject(&:blank?).uniq
      Result.new(errors: messages.presence || [I18n.t("flowchart_runtime.automations.failed")],
                 outcome: {}, discard: false, timing_started_at: nil)
    end

    def empty = Result.new(errors: [], outcome: {}, discard: false, timing_started_at: nil)
  end
end
```

```ruby
# app/jobs/automations/run_job.rb
# frozen_string_literal: true

module Automations
  # Runs one after_commit automation. Enqueued only once the saving
  # transaction commits; a failure is logged and never undoes the write.
  class RunJob < ApplicationJob
    include Loggable

    queue_as :default
    self.enqueue_after_transaction_commit = true
    discard_on ActiveRecord::RecordNotFound

    def perform(flowchart_id, entry_id, event, payload, changes)
      flowchart = Flowchart.launched.find(flowchart_id)
      entity = flowchart.entity
      entry = EntityEntry.build_for(entity).find_by!(id: entry_id, customer_id: flowchart.customer_id, entity_id: entity.id)

      Current.set(customer: Customer.find(flowchart.customer_id)) do
        ctx = Dispatcher.ctx_for(entry: entry, event: event, timing: "after_commit",
                                 context: Context.from_job_payload(payload), changes: changes)
        trace = ActivityTracer.new(flowchart).call(ctx, trace: false)
        log_error "Background automation #{flowchart.id} failed for entry #{entry.id}" unless trace.success?
      end
    end
  end
end
```

In `FlowchartRuntime::Registration`, set `ctx[:discard_record] = true` immediately before each existing early return on the existing-email path (L90–100) and on the quota-exhausted path. The anti-enumeration preset (`registration_pending`) stays exactly as it is.

Add under `flowchart_runtime:`:

```yaml
    automations:
      failed: "We couldn't save this record. Please try again."
      too_deep: "This change triggers too many follow-up updates. Contact your administrator."
```

And the `zh-CN` equivalents:

```yaml
    automations:
      failed: "无法保存该记录，请重试。"
      too_deep: "该更改触发的后续更新过多，请联系管理员。"
```

- [ ] **Step 4: Add the job and Registration examples**

  `spec/jobs/automations/run_job_spec.rb` needs two examples:
  - "reloads the entry and runs the automation under the customer": the stub activity writes `ctx[:model].update_column(:data, …)`, and the spec asserts the new data.
  - "ignores a deleted entry": nothing is raised.

  In the Registration spec, add "flags the record for discard when the email already belongs to a member", asserting `ctx[:discard_record] == true`.

- [ ] **Step 5: Run the specs**

  Run `bundle exec rspec spec/services/automations spec/jobs/automations spec/services/flowchart_runtime/registration_spec.rb`. Expected: all pass.

- [ ] **Step 6: Checkpoint.**

---

### Task 3: The record writer, wired into every existing writer

**Files:**
- Create: `app/services/entries/save.rb`
- Modify:
  - `app/services/entities/activities/entry_writer.rb` (`persist`, L25–36)
  - `app/services/entities/activities/create_association_entries.rb` (`persist_rows`, L50–60)
  - `app/services/entities/activities/update_association_entry.rb`
  - `app/services/pages/bridge_entries.rb` (`initialize` and `save_section`)
- Test: `spec/services/entries/save_spec.rb`, plus one "runs the entity's automations" example each in `create_entry_spec.rb`, `create_association_entries_spec.rb`, `update_association_entry_spec.rb` and `bridge_entries_spec.rb`.

**Interfaces:**
- Consumes: `Automations::Dispatcher`, `Automations::Context`.
- Produces:
  - `Entries::Save.call(contract:, context:)`, which returns `Result(entry:, errors:, outcome:, timing_started_at:)` with `#ok?`. The contract must already have passed `validate`. `entry` is nil when an automation discarded the record.
  - `Pages::BridgeEntries.call(entry:, entity:, sections:, customer_id:, audience:, context:)`.

- [ ] **Step 1: Write the failing spec**

```ruby
# spec/services/entries/save_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Entries::Save do
  let(:customer) { create(:customer) }
  let(:entity) do
    create(:entity, customer: customer, property_schema: [
      { "name" => "Title", "name_slug" => "title", "type" => "String", "html_type" => "text" },
      { "name" => "Notes", "name_slug" => "notes", "type" => "String", "html_type" => "text" }
    ].to_json)
  end
  let(:context) { Automations::Context.build(audience: "admin", source: { "surface" => "admin" }) }

  def activity(name, body)
    "class #{name} < Trailblazer::Activity::Railway\n CANVAS = { steps: {} }.freeze\n step :run\n def run(ctx, **)\n #{body}\n end\nend\n"
  end

  def automation(code, timing:, event: "create")
    create(:flowchart, :simple, :launched_status, customer:, entity:, crud_type: event, trigger_timing: timing)
      .tap { |flowchart| flowchart.update_column(:activity, code) }
  end

  def contract_for(model, input)
    EntityEntryContract.build_for(entity, audience: "admin", writable_slugs: input.keys).new(model)
                       .tap { |contract| expect(contract.validate(input)).to be(true) }
  end

  def new_entry = EntityEntry.build_for(entity).new(entity: entity, customer_id: customer.id)
  def count = EntityEntry.where(entity_id: entity.id).count

  it "saves, then runs before_save and after_save automations around the write" do
    automation(activity("Before", 'ctx[:model].notes = "before"; true'), timing: "before_save")
    automation(activity("After", 'ctx[:submission_outcome] = { "message" => "saved #{ctx[:model].id}" }; true'), timing: "after_save")

    result = described_class.call(contract: contract_for(new_entry, "title" => "Hi"), context: context)

    expect(result).to be_ok
    expect(result.entry.reload.notes).to eq("before")
    expect(result.outcome["message"]).to eq("saved #{result.entry.id}")
  end

  it "rolls back when an after_save automation fails" do
    automation(activity("After", 'ctx[:errors] = ["No seats"]; false'), timing: "after_save")
    result = nil
    expect { result = described_class.call(contract: contract_for(new_entry, "title" => "Hi"), context: context) }
      .not_to(change { count })
    expect(result.errors).to eq(["No seats"])
  end

  it "reports success without keeping the record when an automation discards it" do
    automation(activity("Discard", 'ctx[:discard_record] = true; ctx[:submission_outcome] = { "preset" => "registration_pending" }; true'),
               timing: "after_save")
    result = nil
    expect { result = described_class.call(contract: contract_for(new_entry, "title" => "Hi"), context: context) }
      .not_to(change { count })
    expect(result).to be_ok
    expect(result.entry).to be_nil
    expect(result.outcome["preset"]).to eq("registration_pending")
  end

  it "passes the changed slugs to update automations" do
    entry = new_entry.tap { |record| record.title = "A"; record.save! }
    automation(activity("Changes", 'ctx[:submission_outcome] = { "message" => ctx[:changes].join(",") }; true'),
               timing: "after_save", event: "update")
    persisted = EntityEntry.build_for(entity).find(entry.id)

    result = described_class.call(contract: contract_for(persisted, "title" => "B"), context: context)

    expect(result.outcome["message"]).to eq("title")
  end
end
```

- [ ] **Step 2: Run it and confirm it fails** with `uninitialized constant Entries`.

- [ ] **Step 3: Implement**

```ruby
# app/services/entries/save.rb
# frozen_string_literal: true

module Entries
  # The one way an entity entry is written. Each surface validates its own
  # contract (audience, writable fields), then calls this so the entity's
  # automations run the same way from a page, the admin dialog or a bridge row.
  class Save
    Result = Data.define(:entry, :errors, :outcome, :timing_started_at) do
      def ok? = errors.empty?
    end

    def self.call(...) = new(...).call

    def initialize(contract:, context:)
      @contract = contract
      @context = context
      @outcome = {}
      @errors = []
      @discarded = false
      @timing_started_at = nil
    end

    def call
      entry = @contract.model
      event = entry.new_record? ? "create" : "update"
      before = stored_data(entry)

      EntityEntry.transaction(requires_new: true) do
        @contract.sync
        changes = changed_slugs(before, entry.data_json.to_h)
        raise ActiveRecord::Rollback unless dispatch(entry, event, "before_save", changes)
        raise ActiveRecord::Rollback unless persist(entry)
        raise ActiveRecord::Rollback unless dispatch(entry, event, "after_save", changes)
        raise ActiveRecord::Rollback if @discarded

        dispatch(entry, event, "after_commit", changes)
      end

      Result.new(entry: kept?(entry) ? entry : nil, errors: @errors, outcome: @outcome, timing_started_at: @timing_started_at)
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotSaved
      Result.new(entry: nil, errors: save_errors(entry), outcome: {}, timing_started_at: nil)
    end

    private

    def dispatch(entry, event, timing, changes)
      result = Automations::Dispatcher.call(entry: entry, event: event, timing: timing, context: @context, changes: changes)
      @outcome.merge!(result.outcome)
      @discarded ||= result.discard
      @timing_started_at ||= result.timing_started_at
      @errors = result.errors unless result.ok?
      result.ok?
    end

    def persist(entry)
      return true if entry.save

      @errors = save_errors(entry)
      false
    end

    def kept?(entry) = @errors.empty? && !@discarded && entry.persisted?

    def stored_data(entry)
      return {} unless entry.persisted?

      JSON.parse(entry.attribute_in_database("data").presence || "{}")
    rescue JSON::ParserError
      {}
    end

    def changed_slugs(before, after)
      (before.keys | after.keys).map(&:to_s).select { |slug| before[slug] != after[slug] }
    end

    def save_errors(entry)
      entry.errors.full_messages.presence || [I18n.t("common.errors.dynamic.activity_execution_failed")]
    end
  end
end
```

Wire the existing writers:
- **`EntryWriter#persist`:** replace the `contract.save` block with:

  ```ruby
  result = Entries::Save.call(contract: contract, context: Automations::Context.build(audience: "admin", actor: ctx[:actor], source: { "surface" => "admin" }))
  form.add_errors!("base" => result.errors) unless result.ok?
  result.ok?
  ```

  Keep the `rescue`.
- **`CreateAssociationEntries#persist_rows` and `UpdateAssociationEntry`:** the same change, with `source: { "surface" => "association" }`.
- **`Pages::BridgeEntries`:**
  - Add a `context:` keyword argument and store it in `@context`.
  - In `save_section`, replace `return [] if contract.save` and the line after it with:

    ```ruby
    result = Entries::Save.call(contract: contract, context: @context)
    result.ok? ? [] : result.errors
    ```

- [ ] **Step 4: Add one automation example to each writer spec.** In each, a `before_save` stub sets a field, and the spec asserts the saved row has it.

- [ ] **Step 5: Run the specs**

  Run `bundle exec rspec spec/services/entries spec/services/entities/activities spec/services/pages/bridge_entries_spec.rb spec/requests/admin/entity_association_entries_spec.rb`. Expected: all pass.

- [ ] **Step 6: Checkpoint.**

---

### Task 4: Page submission without flowcharts

**Files:**
- Create: `app/services/flowchart_runtime/runtime_flowchart.rb` (moved verbatim from `public_submission.rb` L281–310, renamed `FlowchartRuntime::RuntimeFlowchart`)
- Modify:
  - `app/models/concerns/page_configuration_helpers.rb`
  - `app/services/pages/public_submission.rb`
  - `app/controllers/public_pages_controller.rb`: delete `outcome_page_path`; in `complete_submission`, use `redirect_to post_submit_path, type => text` at the end.
  - `app/services/code_generators/element_types/process/outcome/set_submission_outcome_generator.rb`: remove `TARGETS`, the `target`/`page` config and `target_expr`; the body writes `preset`, `message` and `flash` only.
  - `app/services/flowchart_definitions/structure_schema.palette.json`: remove the `target` and `page` fields from `set_submission_outcome` (L5481–5530).
  - `app/services/activity_tracer.rb` L71 and `app/services/concerns/activity_class_builder.rb` L148: point at `FlowchartRuntime::RuntimeFlowchart`.
- Delete: `app/services/pages/submission_process.rb` and `spec/services/pages/submission_process_spec.rb`.
- Test:
  - New: `spec/requests/public_pages_record_submission_spec.rb`.
  - Rewrite (remove flowchart creation and `form_settings.flowchart_id`; replace stub-activity failures with entity `presence` validators; turn `build_register_member_flowchart` into an `after_save` automation with condition `@audience equals public`):
    - `spec/services/pages/public_submission_spec.rb`
    - `spec/services/pages/runtime_flowchart_spec.rb`, renamed to `spec/services/flowchart_runtime/runtime_flowchart_spec.rb`
    - `spec/services/concerns/activity_class_builder_spec.rb`
    - `spec/support/public_registration_helpers.rb`
    - every `spec/requests/public_pages_*_spec.rb` listed in the research (admin_form_return, authentication, captcha, continuation, ownership, password_lockout, prefill, reserved_entry_fields, submission_outcome, submission, tenant_audience, visibility)
    - `captcha/page_shortcut_gate_spec.rb`, `member/page_reference_scope_spec.rb`, `page_shortcuts_spec.rb`, `feature_modules/handoffs_spec.rb`
    - `admin/entity_entry_{creation,update}_spec.rb`, `admin/maintenance/page_renders_spec.rb`
    - the `set_submission_outcome` generator spec

**Interfaces:**
- Produces:
  - `PageConfigurationHelpers::SUBMISSION_MODES` (`%w[create update]`), `Page#submission_modes`, `Page#serves?(action)`.
  - `PublicSubmission.new(..., bindings: {})` (the bindings argument is used from Task 6).
  - `Result#submission_outcome` now comes from automations.

- [ ] **Step 1: Write the failing request spec**

```ruby
# spec/requests/public_pages_record_submission_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Page submission saves the page's record", type: :request do
  let(:customer) { create(:customer) }
  let(:entity) do
    create(:entity, customer: customer, property_schema: [
      { "name" => "Title", "name_slug" => "title", "type" => "String", "html_type" => "text",
        "validators" => [{ "type" => "presence" }] }
    ].to_json)
  end

  def page_with(form_settings = {})
    Current.set(customer: customer) do
      create(:page, :public_only, customer: customer, entity: entity, launched: true, configuration: {
        pages: [{ id: "page_1", name: "Form", order: 1, fields: [
          { id: "f1", field_type: "text", property_slug: "title", property_type: "string", label: "Title",
            source: "entity", source_section: entity.display_label }
        ] }],
        metadata: { entity_id: entity.id },
        form_settings: form_settings
      }.to_json)
    end
  end

  def submit(page, title)
    post "/#{customer.id}/page/#{page.public_uuid}", params: { entity: { title: title } }
  end

  def automation(body, timing:)
    code = "class A#{SecureRandom.hex(4)} < Trailblazer::Activity::Railway\n CANVAS = { steps: {} }.freeze\n step :run\n def run(ctx, **)\n #{body}\n end\nend\n"
    create(:flowchart, :simple, :launched_status, customer:, entity:, crud_type: "create", trigger_timing: timing)
      .tap { |flowchart| flowchart.update_column(:activity, code) }
  end

  it "creates the record with no flowchart bound" do
    expect { submit(page_with, "Hello") }.to change { EntityEntry.where(entity_id: entity.id).count }.by(1)
    expect(flash[:notice]).to eq(I18n.t("public_views.flash.response_submitted"))
  end

  it "shows entity validation errors and writes nothing" do
    expect { submit(page_with, "") }.not_to(change { EntityEntry.where(entity_id: entity.id).count })
    expect(flash[:alert]).to be_present
  end

  it "uses an automation's outcome message as the flash" do
    automation('ctx[:submission_outcome] = { "preset" => "custom", "message" => "Welcome aboard" }; true', timing: "after_save")
    submit(page_with, "Hello")
    expect(flash[:notice]).to eq("Welcome aboard")
  end

  it "rolls back when a before_save automation rejects the record" do
    automation('ctx[:errors] = ["Closed for enrolment"]; false', timing: "before_save")
    expect { submit(page_with, "Hello") }.not_to(change { EntityEntry.where(entity_id: entity.id).count })
    expect(flash[:alert]).to include("Closed for enrolment")
  end

  it "refuses an admin edit on a create-only page" do
    admin = create(:user, :admin, customer: customer)
    sign_in admin
    entry = EntityEntry.build_for(entity).create!(entity: entity, customer_id: customer.id, data: { "title" => "A" }.to_json)
    page = page_with("modes" => ["create"])
    page.update!(audience_admin: true)
    post "/#{customer.id}/page/#{page.public_uuid}?return_to=entity_entry&entry_id=#{entry.id}", params: { entity: { title: "B" } }
    expect(response).to have_http_status(:method_not_allowed)
  end
end
```

- [ ] **Step 2: Run it and confirm it fails.** Expected: 405 `page_not_executable`, because no flowchart is bound.

- [ ] **Step 3: Implement**

  In `page_configuration_helpers.rb`:

```ruby
  SUBMISSION_MODES = %w[create update].freeze

  # Which submissions the page accepts; a page without a setting does both.
  def submission_modes
    modes = Array(configuration_json&.dig("form_settings", "modes")).map(&:to_s) & SUBMISSION_MODES
    modes.presence || SUBMISSION_MODES
  end

  def serves?(action) = submission_modes.include?(action.to_s)
```

In `Pages::PublicSubmission`, keep `Result`, `prepare_input`, `audience`, `current_person_ids`, `verified_continuation` and the logging helpers. Delete `flowchart_bound?`, `bind_flowchart_and_entity!`, `entity_mismatch?`, `extract_entry`, `extract_outcome` and the nested `RuntimeFlowchart`. Then replace:

```ruby
    def initialize(page:, params:, customer_id:, current_user:, user_agent:, authentication: nil, entry_id: nil, bindings: {})
      # ...existing assignments...
      @bindings = bindings.to_h
    end

    def call(&completion)
      @entity = @page.entity
      return invalid(:method_not_allowed, "common.errors.dynamic.page_not_executable") unless @page.serves?(action)

      error = validation_error
      return error if error

      prepare_input
      return rejected(@guard_result.error) if @guard_result.error

      execute(&completion)
    end

    private

    def action
      return :update if @entry_id
      return :update if !@page.serves?(:create) && own_person_entry

      :create
    end

    def validation_error
      return invalid(:not_found, "common.errors.dynamic.entity_required") unless @entity
      if Pages::FormParams.base_submission?(@params)
        return invalid(:unprocessable_entity, "common.errors.dynamic.base_model_submission_not_supported")
      end
      return if action == :create || edited_entry

      invalid(:not_found, "common.errors.dynamic.entry_unavailable")
    end

    def edited_entry
      @edited_entry ||= @entry_id ? admin_edited_entry : own_person_entry
    end

    def admin_edited_entry
      return unless audience == EntityAttributeAudience::ADMIN && @entry_id.to_s.match?(/\A[1-9]\d*\z/)

      EntityEntry.build_for(@entity).find_by(id: @entry_id, customer_id: @customer_id, entity_id: @entity.id)
    end

    # An update-only page edits the signed-in member's own person record.
    def own_person_entry
      return @own_person_entry if defined?(@own_person_entry)
      return @own_person_entry = nil unless audience == EntityAttributeAudience::MEMBER && @entity.person?

      id = People::Ownership.person_entry_id(@current_user, @entity.id)
      @own_person_entry = id && EntityEntry.build_for(@entity).find_by(id: id, customer_id: @customer_id, entity_id: @entity.id)
    end

    def execute
      result = nil
      bridge_errors = []
      ActiveRecord::Base.transaction(requires_new: true) do
        Authentication::PasswordEffects.transaction(customer_id: @customer_id) do
          result = save_entry
          bridge_errors = save_bridge_entries(result.entry) if result.ok? && result.entry
          yield result.entry, result.outcome if result.ok? && bridge_errors.empty? && block_given?
        end
        raise ActiveRecord::Rollback unless result.ok? && bridge_errors.empty?
      end
      Authentication::UniformTiming.pad(result&.timing_started_at)

      return failure(result.errors.uniq.to_sentence.presence) unless result.ok?
      return failure(bridge_errors.uniq.to_sentence) if bridge_errors.any?

      Result.new(status: :success, entry: result.entry, submission_outcome: result.outcome)
    rescue FeatureModules::ModuleNotEnabled, FeatureModules::InputContractViolation, FeatureModules::RegistrationError
      raise
    rescue StandardError => e
      log_error "Submission failed - #{e.class}: #{e.message}"
      failure
    end

    def save_entry
      model = edited_entry || EntityEntry.build_for(@entity).new(entity: @entity, customer_id: @customer_id)
      input = @primary.merge(@bindings)
      contract = EntityEntryContract.build_for(@entity, audience: audience, writable_slugs: input.keys).new(model)
      unless contract.validate(input)
        return Entries::Save::Result.new(entry: nil, errors: contract.errors.full_messages, outcome: {}, timing_started_at: nil)
      end

      Entries::Save.call(contract: contract, context: automation_context)
    end

    def automation_context
      Automations::Context.build(
        audience: audience, actor: @current_user,
        source: { "surface" => "page", "page_id" => @page.id, "action_key" => @page.action_key },
        identity: @identity || {}, authentication: @authentication, continuation: verified_continuation,
        current_person_ids: current_person_ids,
        request: { request_ip: Current.ip_address, user_agent: @user_agent, locale: I18n.locale.to_s,
                   request_id: Current.request_id, device_type: Pages::DeviceType.call(@user_agent) }
      )
    end

    def save_bridge_entries(entry)
      return [] if @bridge_sections.blank? || !entry.previously_new_record?

      Pages::BridgeEntries.call(entry: entry, entity: @entity, sections: @bridge_sections,
                                customer_id: @customer_id, audience: audience, context: automation_context)
    end
```

If `Authentication::UniformTiming.pad` doesn't accept `nil`, guard the call with `if result&.timing_started_at`.

- [ ] **Step 4: Rewrite the spec files listed under Files.** Each should follow this rule:
  - delete the flowchart and its `form_settings.flowchart_id`;
  - express failures through entity validators;
  - put registration in an `after_save` automation.

  Keep each spec's original assertions.

- [ ] **Step 5: Run the specs**

  Run `bundle exec rspec spec/requests/public_pages_*_spec.rb spec/services/pages spec/services/flowchart_runtime spec/services/concerns/activity_class_builder_spec.rb spec/requests/admin/entity_entry_creation_spec.rb spec/requests/admin/entity_entry_update_spec.rb spec/requests/feature_modules/handoffs_spec.rb`. Expected: all pass.

- [ ] **Step 6: Checkpoint.**

---

### Task 5: Remove the binding everywhere else

**Files:**
- Modify:
  - **`app/services/pages/entry_page_resolver.rb`:** `serves?` becomes `page.serves?(action)`. Drop the flowchart lookup.
  - **`app/services/pages/launch_checks.rb`:** delete `submission_process_errors` and `Lookup#flowchart` with its `@flowcharts` memo; `submission_blockers` becomes `required_field_errors`.
  - **`app/models/page.rb`:** delete `CONFIG_FLOWCHART_BINDING_SQL` and `scope :bound_to_flowchart` (L131–146).
  - **`app/models/flowchart.rb`:** in `soft_delete` (L115), delete the bound-pages guard.
  - **`app/controllers/admin/maintenance/flowchart_launches_controller.rb`:** delete the `forms_stopped` branch at L50.
  - **`app/services/pages/activities/create_from_entity_version.rb`:** delete `FLOWCHART_NAME`, `UPDATE_FLOWCHART_NAME`, `shared_flowchart`, `bind_flowchart!` and the `:flowchart_missing` failure. This makes bridge-entity versions generate pages too.
  - **`app/controllers/admin/maintenance/pages_controller.rb`:**
    - delete `@flowcharts` (L109), `load_flows_for_page`, `entity_flows`, `flow_json`, `bindable_flowcharts` and `@flowcharts_with_entities`;
    - `load_entity_options` lists every active, accessible entity, bridges included.
  - **`app/views/admin/maintenance/pages/new.html.erb` L26:** use `options_from_collection_for_select(@entities, :id, :display_label, @page.entity_id)`.
  - **`app/views/admin/maintenance/pages/_editor.html.erb`:** delete L22–24, L110, the five flowchart label values (L168–172) and the `FlowsSectionComponent` render (L480–485).
  - **`config/routes.rb`:** delete the `entity_flows` routes (L515, L591).
  - **`app/javascript/controllers/page_builder/tab_manager.js`:** delete the `entity_flows` fetch (~L361) and the code that renders its result.
  - **`page_manager.js`:** delete `_buildFlowchartBindingHtml`, `updateFlowchartBinding` and their footer call (L410–412, L445–450).
  - **`page_builder_controller.js`:** delete `availableFlowcharts`, the five label values (L204–208) and the `updateFlowchartBinding` delegation.
- Delete: `app/components/page_builder/flows_section_component.*` and its spec.
- Test: update the following specs.
  - `entry_page_resolver_spec.rb`: modes replace the flowchart binding.
  - `launch_checks_spec.rb`: delete the `#submission_process_errors` block; drop the key from the "never names the flowchart" list.
  - `form_health_spec.rb`.
  - `page_bindings_spec.rb`: delete the file.
  - `flowchart_trash_guard_spec.rb`: now trashing a flowchart "succeeds and stops the automation".
  - `flowchart_launches_spec.rb`.
  - `create_from_entity_version_spec.rb`: drop the flowchart examples; add "generates a page for a bridge entity version".
  - `ai_assistant/**` specs and `requests/maintenance/entity_versions_spec.rb`, `shared_resources_spec.rb`, `assistant_confirmation_spec.rb`, `assistant_generated_pages_spec.rb`, `activity_generator_structure_wiring_spec.rb`, `structure_validator_spec.rb`: stop creating "Create Entity Entry" flowcharts.
  - `page_manager.test.js`: delete the flowchart footer and binding tests (L530 assertion, L550, L560–581).
  - `page_builder_controller.test.js`: delete the delegation row at L228.
  - The `tab_manager` tests for the fetch.
  - `spec/javascript/support/page_builder.js`: delete the five label defaults at L101–105.

- [ ] **Step 1: Write the resolver test first.** In `entry_page_resolver_spec.rb`, replace the binding examples with:

```ruby
it "returns the newest launched page that serves the action" do
  create_only = create(:page, :launched, customer: customer, entity: entity,
                       configuration: config_with("form_settings" => { "modes" => ["create"] }))
  both = create(:page, :launched, customer: customer, entity: entity, configuration: config_with({}))
  expect(described_class.page_for(entity: entity, audience: "admin", action: :create)).to eq(both)
  expect(described_class.page_for(entity: entity, audience: "admin", action: :update)).to eq(both)
  both.update!(launched: false)
  expect(described_class.page_for(entity: entity, audience: "admin", action: :update)).to be_nil
  expect(described_class.page_for(entity: entity, audience: "admin", action: :create)).to eq(create_only)
end
```

Here `config_with(extra)` is a local helper that merges `extra` into the spec's minimal configuration hash.

- [ ] **Step 2: Run it and confirm it fails.**

- [ ] **Step 3: Make every change listed under Files.**

- [ ] **Step 4: Confirm nothing references the binding any more**

  Run `rg -n "update_flowchart_id|SubmissionProcess|bound_to_flowchart|FLOWCHART_NAME|flowchart_missing\b|availableFlowcharts|entity_flows" app spec config lib`. Expected: no matches, apart from the frozen `flowchart_missing` locale key.

- [ ] **Step 5: Run the specs**

  Run `bundle exec rspec spec/services/pages spec/models spec/requests/admin/maintenance spec/requests/maintenance spec/services/ai_assistant spec/requests/admin/assistant_generated_pages_spec.rb && npx vitest run --coverage`. Expected: all pass, with 100% lines and branches on the touched JavaScript.

- [ ] **Step 6: Checkpoint.**

---

### Task 6: Run store, locked inputs and the "After submit" runtime

**Files:**
- Create:
  - `db/migrate/20261112100100_create_journey_runs.rb`
  - `app/models/journey_run.rb`
  - `app/services/pages/input_bindings.rb`, `app/services/pages/after_submit.rb`, `app/services/pages/run_link.rb`
  - `app/components/pages/locked_inputs_component.{rb,html.erb}`
  - `app/helpers/page_inputs_helper.rb`
  - `app/jobs/journey_runs/purge_job.rb`
- Modify:
  - **`page_configuration_helpers.rb`:** add `page_inputs`, `input_slugs`, `after_submit_mode` and `next_page_config`.
  - **`app/controllers/concerns/page_rendering.rb`:** add `page_run`; `prepare_page_render` sets `@page_bindings`.
  - **`page_content_generator.rb` (`generate_field`, L313–323) and `page_content_generator/form_fields.rb` (`hidden_page_id_field`):**
    - add a hidden `_run` field and the locked-input card;
    - fields used as inputs are wrapped in `page_input_bound?`.
  - **`app/controllers/public_pages_controller.rb`:**
    - pass `bindings:`;
    - `complete_submission` checks, in order: handoff, the page's "go to page", then its message;
    - add the run token to the redirect.
  - **`app/controllers/admin/entity_entries_controller.rb` (L81–93):**
    - honour `params[:page]`, the specific launched admin page for this entity, if it serves the action;
    - otherwise fall back to the resolver.
  - **`config/recurring.yml`:** run `journey_runs_purge` daily.
- Test:
  - `spec/models/journey_run_spec.rb`
  - `spec/services/pages/input_bindings_spec.rb`, `spec/services/pages/after_submit_spec.rb`
  - `spec/components/pages/locked_inputs_component_spec.rb`
  - `spec/requests/public_pages_after_submit_spec.rb`

**Interfaces:**
- Produces:
  - `JourneyRun.issue!(customer_id:, user:, session:, state: {}, **attrs)`, which returns `[run, raw_token]`.
  - `JourneyRun.find_usable(token:, customer_id:, user:, session:)`.
  - `JourneyRun#bindings_for(page)`, which returns a hash of slug to id string.
  - `Pages::InputBindings.resolve(page:, run:, viewer:, audience:, customer_id:)`.
  - `Pages::AfterSubmit.destination(page:, entry:, audience:, customer_id:)`, which returns `Destination(page:, bindings:)` or nil; `Pages::AfterSubmit.message(page)`.
  - `Pages::RunLink.append(path, token, page: nil)`.
  - Page configuration shapes:
    - `form_settings.inputs = [{ "field" => slug, "entity_id" => id }]`
    - `form_settings.after_submit` is one of `message`, `page`, `handoff`
    - `form_settings.next_page = { "page_id" => id, "input" => slug_or_nil }`

- [ ] **Step 1: Write the failing specs.** First the model spec:

```ruby
# spec/models/journey_run_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe JourneyRun do
  let(:customer) { create(:customer) }
  let(:session) { {} }

  it "stores only a digest and finds an anonymous run through the same session" do
    run, token = described_class.issue!(customer_id: customer.id, user: nil, session: session, state: { "a" => 1 })
    expect(run.token_digest).not_to eq(token)
    expect(described_class.find_usable(token: token, customer_id: customer.id, user: nil, session: session)).to eq(run)
    expect(described_class.find_usable(token: token, customer_id: customer.id, user: nil, session: {})).to be_nil
  end

  it "ties a signed-in run to its user and customer" do
    user = create(:user, :admin, customer: customer)
    _run, token = described_class.issue!(customer_id: customer.id, user: user, session: session)
    expect(described_class.find_usable(token: token, customer_id: customer.id, user: create(:user, :admin, customer: customer), session: session)).to be_nil
    expect(described_class.find_usable(token: token, customer_id: create(:customer).id, user: user, session: session)).to be_nil
  end

  it "ignores expired runs" do
    run, token = described_class.issue!(customer_id: customer.id, user: nil, session: session)
    run.update_column(:expires_at, 1.minute.ago)
    expect(described_class.find_usable(token: token, customer_id: customer.id, user: nil, session: session)).to be_nil
  end
end
```

The request spec uses the existing `"student course association"` shared context from `spec/support/association_fixtures.rb`. It builds:
- a Student page whose "After submit" opens a launched admin bridge page;
- a bridge page with `inputs: [{ field: "student", entity_id: student.id }]`.

It checks these behaviours:
- **"opens the course page with the new student locked in":**
  1. Post the Student form.
  2. Follow the redirect.
  3. Assert `[data-role='locked-inputs']` shows the student's label and there is no `select[name='entity[student]']`.
- **"ignores a forged student on submit":** post the bridge form with `_run` and `entity[student]=<other student id>`. The saved bridge row's student must be the run's student.
- **"drops a run from another tenant":** a token issued for another customer renders the normal select.
- **"shows the page's own message when After submit is message":** the flash equals `success_message`.

- [ ] **Step 2: Run them and confirm they fail.**

- [ ] **Step 3: Implement**

```ruby
# db/migrate/20261112100100_create_journey_runs.rb
# frozen_string_literal: true

class CreateJourneyRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :journey_runs do |t|
      t.references :customer, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :user, null: true, foreign_key: { to_table: :users, on_delete: :cascade }, index: false
      t.string :token_digest, null: false
      t.integer :status, null: false, default: 0
      t.text :state
      t.datetime :expires_at, null: false
      t.timestamps null: false
    end
    add_index :journey_runs, :token_digest, unique: true
    add_index :journey_runs, %i[customer_id user_id]
    add_index :journey_runs, :expires_at
  end
end
```

```ruby
# app/models/journey_run.rb
# frozen_string_literal: true

# A visitor's pass through linked pages: today a one-hop handover from a
# page's After submit. Only a SHA-256 digest of the token is stored, and an
# anonymous run is also pinned to the browser session that started it.
class JourneyRun < ApplicationRecord
  include JsonSerializable

  EXPIRES_IN = 3.days
  SESSION_KEY = :journey_runs
  SESSION_LIMIT = 10

  belongs_to :customer
  belongs_to :user, class_name: "Authentication::User", optional: true

  enum :status, { active: 0, completed: 1 }, default: :active
  json_attribute :state, default: {}

  scope :usable, -> { active.where("expires_at > ?", Time.current) }

  def self.digest_for(raw) = Digest::SHA256.hexdigest(raw.to_s)

  def self.issue!(customer_id:, user:, session:, state: {}, **attributes)
    raw = SecureRandom.urlsafe_base64(32)
    run = create!(customer_id: customer_id, user_id: user&.id, token_digest: digest_for(raw),
                  state: state.to_json, expires_at: EXPIRES_IN.from_now, **attributes)
    session[SESSION_KEY] = (Array(session[SESSION_KEY]) + [run.token_digest]).last(SESSION_LIMIT) unless user
    [run, raw]
  end

  def self.find_usable(token:, customer_id:, user:, session:)
    return unless token.is_a?(String) && token.length.between?(20, 100)

    run = usable.find_by(customer_id: customer_id, token_digest: digest_for(token))
    return unless run

    owned = run.user_id ? run.user_id == user&.id : Array(session[SESSION_KEY]).include?(run.token_digest)
    run if owned
  end

  def bindings_for(page)
    handover = state_json.to_h["handover"].to_h
    handover["page_id"].to_s == page.id.to_s ? handover["bindings"].to_h : {}
  end
end
```

```ruby
# app/services/pages/input_bindings.rb
# frozen_string_literal: true

module Pages
  # Server-side values for a page's locked inputs, taken from the visitor's run
  # and re-checked on every render and submit: the record must exist in this
  # tenant, belong to the input's entity, and be reachable by the viewer.
  module InputBindings
    ID = /\A[1-9]\d*\z/

    def self.resolve(page:, run:, viewer:, audience:, customer_id:)
      return {} unless run

      raw = run.bindings_for(page)
      page.page_inputs.each_with_object({}) do |input, kept|
        id = raw[input["field"]].to_s
        next unless id.match?(ID)

        entity = Entity.where(customer_id: [customer_id, nil]).find_by(id: input["entity_id"])
        next unless entity && EntityEntry.where(customer_id: customer_id, entity_id: entity.id, id: id).exists?
        next unless People::Ownership.reachable_ids(entity, [id], viewer: viewer, audience: audience, customer_id: customer_id).include?(id)

        kept[input["field"]] = id
      end
    end
  end
end
```

```ruby
# app/services/pages/after_submit.rb
# frozen_string_literal: true

module Pages
  # What a page does after a successful submit when no journey is running:
  # show its own message, or open another page with the new record locked in.
  module AfterSubmit
    Destination = Data.define(:page, :bindings)

    def self.destination(page:, entry:, audience:, customer_id:)
      return unless page.after_submit_mode == "page"

      config = page.next_page_config
      target = Page.launched.where(customer_id: [customer_id, nil]).find_by(id: config["page_id"])
      target = Pages::ActionResolver.counterpart(page: target, audience: audience, customer_id: customer_id) if target && !target.visible_to?(audience)
      return unless target

      Destination.new(page: target, bindings: bindings(target, config["input"].to_s, entry))
    end

    def self.message(page)
      return unless page.after_submit_mode == "message"

      page.configuration_json&.dig("form_settings", "success_message").presence
    end

    def self.bindings(target, field, entry)
      return {} unless entry && field.present?

      declared = target.page_inputs.any? { |input| input["field"] == field && input["entity_id"].to_s == entry.entity_id.to_s }
      declared ? { field => entry.id.to_s } : {}
    end
    private_class_method :bindings
  end
end
```

```ruby
# app/services/pages/run_link.rb
# frozen_string_literal: true

module Pages
  # Adds a run token (and, for the admin entry surface, the exact page) to a
  # destination path without disturbing its existing query.
  module RunLink
    def self.append(path, token, page: nil)
      uri = Addressable::URI.parse(path)
      values = uri.query_values || {}
      values["run"] = token if token.present?
      values["page"] = page.id.to_s if page
      uri.query_values = values if values.any?
      uri.to_s
    end
  end
end
```

In `page_configuration_helpers.rb`:

```ruby
  AFTER_SUBMIT_MODES = %w[message page handoff].freeze

  def page_inputs
    Array(configuration_json&.dig("form_settings", "inputs")).grep(Hash).map { |input| input.slice("field", "entity_id").transform_values(&:to_s) }
  end

  def input_slugs = page_inputs.map { |input| input["field"] }

  def after_submit_mode
    mode = configuration_json&.dig("form_settings", "after_submit").to_s
    AFTER_SUBMIT_MODES.include?(mode) ? mode : "message"
  end

  def next_page_config = configuration_json&.dig("form_settings", "next_page").to_h
```

In `page_rendering.rb`, add this and call `@page_bindings = page_bindings_for(page)` from `prepare_page_render`:

```ruby
  def page_run
    return @page_run if defined?(@page_run)

    token = params[:run].presence || params[:_run]
    @page_run = JourneyRun.find_usable(token: token, customer_id: current_customer_id, user: current_user, session: session)
    @page_run_token = token if @page_run
    @page_run
  end

  def page_bindings_for(page)
    Pages::InputBindings.resolve(page: page, run: page_run, viewer: page_runtime_user,
                                 audience: page_runtime_audience, customer_id: current_customer_id)
  end
```

`app/helpers/page_inputs_helper.rb`:

```ruby
module PageInputsHelper
  def page_input_bound?(slug) = @page_bindings.to_h.key?(slug.to_s)
end
```

Generator changes:
- **`form_fields.rb`:** `hidden_page_id_field` returns

  ```ruby
  %(<%= hidden_field_tag :_page_id, @page.id %>#{hidden_continuation_field}#{hidden_run_field}#{locked_inputs_card})
  ```

  with:
  - `hidden_run_field`: `%(<%= hidden_field_tag :_run, @page_run_token if @page_run_token.present? %>)`
  - `locked_inputs_card`: `%(<%= render Pages::LockedInputsComponent.new(page: @page, bindings: @page_bindings) if @page_bindings.present? %>)`
- **`page_content_generator.rb`, end of `generate_field`:** wrap the field when its slug is a declared input:

  ```ruby
  slug = (field["property_slug"] || field["id"]).to_s
  return html unless declared_input_slugs.include?(slug)

  %(<% unless page_input_bound?(#{rb_str(slug)}) %>#{html}<% end %>)
  ```

  `declared_input_slugs` reads `Array(settings["inputs"]).grep(Hash).map { _1["field"].to_s }` from the `form_settings` hash the generator already holds (L89).
- **Wizard mode:** the card appears in step 1 only. That's acceptable for Phase 1.

In `PublicPagesController#submit`, pass `bindings: page_bindings_for(@page)` to `Pages::PublicSubmission.call`. Then:

```ruby
  def complete_submission(handed_off, result)
    return redirect_to(feature_module_handoff_path(current_customer_id)) if handed_off

    outcome = result.submission_outcome || {}
    type, text = outcome_flash(outcome)
    text = Pages::AfterSubmit.message(@page) || text unless outcome_configured?(outcome)
    if (path = after_submit_path(result.entry))
      return redirect_to(path, type => text)
    end
    if (landing = entity_entry_landing(result.entry))
      text = landing[:notice] unless outcome_configured?(outcome)
      return redirect_to(landing[:path], type => text, flash: landing[:flash])
    end

    redirect_to post_submit_path, type => text
  end

  def after_submit_path(entry)
    destination = Pages::AfterSubmit.destination(page: @page, entry: entry, audience: page_runtime_audience,
                                                 customer_id: current_customer_id)
    return unless destination

    token = nil
    if destination.bindings.any?
      _run, token = JourneyRun.issue!(customer_id: current_customer_id, user: page_runtime_user, session: session,
                                      state: { "handover" => { "page_id" => destination.page.id, "bindings" => destination.bindings } })
    end
    admin = page_runtime_audience == EntityAttributeAudience::ADMIN
    Pages::RunLink.append(audience_surface_path(destination.page), token, page: (destination.page if admin))
  end
```

The locked-inputs component:

```ruby
# app/components/pages/locked_inputs_component.rb
# frozen_string_literal: true

module Pages
  # Read-only summary of the records a page's locked inputs are filled with,
  # e.g. "Student — Alice Wang" on the step that adds her courses.
  class LockedInputsComponent < ViewComponent::Base
    Item = Data.define(:label, :value)

    def initialize(page:, bindings:)
      @page = page
      @bindings = bindings.to_h
    end

    def render? = items.any?

    def items
      @items ||= @page.page_inputs.filter_map do |input|
        id = @bindings[input["field"]]
        attribute = reference_attribute(input["field"])
        next if id.blank? || attribute.nil?

        Item.new(label: attribute["name"].to_s, value: record_label(input, attribute, id))
      end
    end

    private

    def reference_attribute(slug)
      Array(@page.entity&.property_schema_json).grep(Hash).find { |attribute| attribute["name_slug"] == slug }
    end

    def record_label(input, attribute, id)
      entity = Entity.where(customer_id: [Current.customer_id, nil]).find_by(id: input["entity_id"])
      entry = entity && EntityEntry.build_for(entity).find_by(id: id, customer_id: Current.customer_id)
      label_field = attribute.dig("config", "label_field").to_s
      entry&.data_json.to_h[label_field].presence || "##{id}"
    end
  end
end
```

```erb
<%# app/components/pages/locked_inputs_component.html.erb %>
<div class="mb-6 rounded-lg border border-slate-200 bg-slate-50 p-4" data-role="locked-inputs">
  <dl class="grid grid-cols-1 gap-3 sm:grid-cols-2">
    <% items.each do |item| %>
      <div class="min-w-0">
        <dt class="text-xs font-medium uppercase tracking-wide text-slate-500"><%= item.label %></dt>
        <dd class="mt-1 truncate text-sm font-semibold text-slate-900"><%= item.value %></dd>
      </div>
    <% end %>
  </dl>
</div>
```

The purge job:

```ruby
# app/jobs/journey_runs/purge_job.rb
# frozen_string_literal: true

module JourneyRuns
  class PurgeJob < ApplicationJob
    queue_as :default

    def perform = JourneyRun.where("expires_at < ?", 7.days.ago).delete_all
  end
end
```

In `Admin::EntityEntriesController#prepare_entry_page_render`, choose the page like this:

```ruby
@page = requested_entry_page(action) || ::Pages::EntryPageResolver.page_for(entity: @entity, audience: EntityAttributeAudience::ADMIN, action: action)
```

```ruby
def requested_entry_page(action)
  return unless params[:page].to_s.match?(/\A[1-9]\d*\z/)

  page = Page.accessible.launched.for_audience(EntityAttributeAudience::ADMIN).for_entity(@entity.id).find_by(id: params[:page])
  page if page&.serves?(action)
end
```

- [ ] **Step 4: Migrate and run the specs**

  Run `bin/rails db:migrate && bundle exec rspec spec/models/journey_run_spec.rb spec/services/pages spec/components/pages spec/requests/public_pages_after_submit_spec.rb spec/requests/admin/entity_entries_spec.rb`. Expected: all pass.

- [ ] **Step 5: Checkpoint.**

---

### Task 7: Page builder settings (modes, locked inputs, "go to page")

**Files:**
- Modify:
  - `app/components/page_builder/settings_modal_component.{rb,html.erb}`
  - `app/javascript/controllers/page_builder/property_manager.js`
  - `app/javascript/controllers/page_builder_controller.js` (delegate the three new handlers)
  - `app/models/page.rb` (add `form_settings_are_valid` next to L105–109)
  - `config/locales/comp_page_builder.{en,zh-CN}.yml`, `config/locales/maint_core.{en,zh-CN}.yml`
- Test:
  - `spec/components/page_builder/settings_modal_component_spec.rb`
  - `spec/models/page_form_settings_spec.rb`
  - `spec/javascript/controllers/page_builder/property_manager.test.js`: also fix the `after_submit_mode` fixture to `after_submit` (L647, L658).
  - `spec/javascript/controllers/page_builder_controller.test.js`

**Interfaces:**
- Consumes: the `form_settings` shapes from Task 6.
- Produces:
  - `SettingsModalComponent#submission_modes`, `#reference_fields`, `#next_page_options`, `#next_page_value`.
  - JavaScript handlers `updateSubmissionModes()`, `updatePageInputs()` and `updateNextPage(event)`.

- [ ] **Step 1: Write the failing tests.** First the model spec:

```ruby
# spec/models/page_form_settings_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Page, "form settings" do
  let(:customer) { create(:customer) }
  let(:student) { create(:entity, customer: customer, name: "Student") }
  let(:bridge) do
    create(:entity, customer: customer, name: "Enrolment", property_schema: [
      { "name" => "Student", "name_slug" => "student", "type" => "EntityReference", "html_type" => "select", "entity_id" => student.id.to_s }
    ].to_json)
  end

  def page_with(form_settings)
    Current.set(customer: customer) { build(:page, customer: customer, entity: bridge) }.tap do |page|
      page.configuration_json = page.configuration_json.merge("form_settings" => form_settings)
    end
  end

  it("accepts a reference field as a locked input") { expect(page_with("inputs" => [{ "field" => "student", "entity_id" => student.id }])).to be_valid }

  it "rejects a locked input that is not a reference field of the page entity" do
    page = page_with("inputs" => [{ "field" => "title", "entity_id" => student.id }])
    expect(page).not_to be_valid
    expect(page.errors[:base].join).to include("title")
  end

  it("rejects empty modes") { expect(page_with("modes" => [])).not_to be_valid }
  it("requires a page for 'go to page'") { expect(page_with("after_submit" => "page")).not_to be_valid }
end
```

Then the Vitest cases. Use the existing `buildController()` harness, the same way the `updateFormSettings` tests at L40–72 do.

```js
describe("PropertyManager — linked pages", () => {
  it("stores the checked submission modes", () => {
    const { controller, element } = buildController()
    element.insertAdjacentHTML("beforeend", `<input type="checkbox" data-submission-mode value="create" checked><input type="checkbox" data-submission-mode value="update">`)
    controller.propertyManager.updateSubmissionModes()
    expect(controller.configuration.form_settings.modes).toEqual(["create"])
  })

  it("stores the checked reference fields as locked inputs", () => {
    const { controller, element } = buildController()
    element.insertAdjacentHTML("beforeend", `<input type="checkbox" data-page-input value="student" data-entity-id="7" checked><input type="checkbox" data-page-input value="course" data-entity-id="8">`)
    controller.propertyManager.updatePageInputs()
    expect(controller.configuration.form_settings.inputs).toEqual([{ field: "student", entity_id: 7 }])
  })

  it("parses the next page and its receiving input, and clears it when blank", () => {
    const { controller } = buildController()
    controller.propertyManager.updateNextPage({ target: { value: "12:student" } })
    expect(controller.configuration.form_settings.next_page).toEqual({ page_id: 12, input: "student" })
    controller.propertyManager.updateNextPage({ target: { value: "12:" } })
    expect(controller.configuration.form_settings.next_page).toEqual({ page_id: 12, input: null })
    controller.propertyManager.updateNextPage({ target: { value: "" } })
    expect(controller.configuration.form_settings.next_page).toBeNull()
  })
})
```

- [ ] **Step 2: Run both and confirm they fail.**

- [ ] **Step 3: Implement**

  In `property_manager.js`:

```js
  updateSubmissionModes() {
    const modes = Array.from(this.c.element.querySelectorAll("[data-submission-mode]"))
      .filter((box) => box.checked)
      .map((box) => box.value)
    this._writeFormSetting("modes", modes)
  }

  updatePageInputs() {
    const inputs = Array.from(this.c.element.querySelectorAll("[data-page-input]"))
      .filter((box) => box.checked)
      .map((box) => ({ field: box.value, entity_id: Number(box.dataset.entityId) }))
    this._writeFormSetting("inputs", inputs)
  }

  updateNextPage(event) {
    const [pageId, input] = event.target.value.split(":")
    this._writeFormSetting("next_page", pageId ? { page_id: Number(pageId), input: input || null } : null)
  }

  _writeFormSetting(key, value) {
    this.c.undoRedoManager.saveState()
    this.c.configuration.form_settings = this.c.configuration.form_settings || {}
    this.c.configuration.form_settings[key] = value
    this.c.saveManager.markDirty()
  }
```

In `SettingsModalComponent`:
- **Sections:** add an `inputs` section after `general`.
- **`after_submit` options:** `message` / `page` / `handoff`. The `redirect` option is removed, and its old key stays in the locale file.
- **Methods:**

```ruby
    def submission_modes = @page.submission_modes

    def reference_fields
      locked = @page.input_slugs
      Array(@page.entity&.property_schema_json).grep(Hash).filter_map do |attribute|
        next unless attribute["type"] == Entity::ENTITY_REFERENCE_TYPE

        { slug: attribute["name_slug"], label: attribute["name"], entity_id: attribute["entity_id"].to_s,
          locked: locked.include?(attribute["name_slug"]) }
      end
    end

    def next_page_options
      Page.launched.where(customer_id: [@page.customer_id, nil]).where.not(id: @page.id).order(:name).flat_map do |target|
        passes = target.page_inputs.select { |input| input["entity_id"] == @page.entity_id.to_s }
        [[target.name, "#{target.id}:"]] + passes.map do |input|
          [t(".next_page_passes", page: target.name, field: input["field"]), "#{target.id}:#{input['field']}"]
        end
      end
    end

    def next_page_value
      config = @page.next_page_config
      config["page_id"].present? ? "#{config['page_id']}:#{config['input']}" : ""
    end
```

Template changes:
- **General section:** two checkboxes, each with `data-submission-mode`, `value="create"` or `value="update"`, and `data-action="change->page-builder#updateSubmissionModes"`.
- **Inputs section:** one checkbox per `reference_fields` row, with `data-page-input`, `value=slug`, `data-entity-id` and `data-action="change->page-builder#updatePageInputs"`. If there are no rows, show `inputs_empty`.
- **"page" after-submit panel:** a `select` with `next_page_none` as the blank option, then `next_page_options`; `data-action="change->page-builder#updateNextPage"`.

All layouts use `grid grid-cols-1 sm:grid-cols-2 gap-3`.

In `Page#form_settings_are_valid`, use the `maint_core.errors.validations` keys below:
- modes, when present, must be a non-empty subset of `SUBMISSION_MODES`;
- each input must be an `EntityReference` attribute whose `entity_id` matches;
- `after_submit` must be in `AFTER_SUBMIT_MODES`;
- the `page` mode needs `next_page.page_id`.

Locale keys go under the `settings_modal` scope the component already uses (`comp_page_builder.*.yml` L396–434):

```yaml
# en
sections:
  inputs:
    label: "Inputs"
    hint: "Fields filled from an earlier step"
submission_modes_title: "Submission"
mode_create: "Create new records"
mode_update: "Edit existing records"
inputs_title: "Locked inputs"
inputs_desc: "When this page opens from a previous step or another page, these fields are filled with that record and can't be changed."
inputs_empty: "This record type has no reference fields."
go_to_page: "Go to another page"
next_page: "Page to open"
next_page_none: "Choose a page"
next_page_passes: "%{page} — passes the new record as %{field}"
```

```yaml
# zh-CN
sections:
  inputs:
    label: "输入"
    hint: "由前序步骤填入的字段"
submission_modes_title: "提交方式"
mode_create: "新建记录"
mode_update: "编辑已有记录"
inputs_title: "锁定字段"
inputs_desc: "从前序步骤或其他页面打开本页时，这些字段会自动填入对应记录，且不可修改。"
inputs_empty: "该记录类型没有引用字段。"
go_to_page: "跳转到其他页面"
next_page: "要打开的页面"
next_page_none: "请选择页面"
next_page_passes: "%{page}——将新记录填入%{field}"
```

Add under `maint_core.errors.validations`:

```yaml
# en
page_modes_blank: "Choose at least one submission mode."
page_input_invalid: "%{field} can't be a locked input: it isn't a reference field on this page."
page_next_page_missing: "Choose a page to open after submit."
```

```yaml
# zh-CN
page_modes_blank: "请至少选择一种提交方式。"
page_input_invalid: "%{field}不能设为锁定字段：它不是本页面上的引用字段。"
page_next_page_missing: "请选择提交后要打开的页面。"
```

- [ ] **Step 4: Run the specs**

  Run `bundle exec rspec spec/models/page_form_settings_spec.rb spec/components/page_builder && npx vitest run --coverage`. Expected: all pass, and `property_manager.js` and `page_builder_controller.js` are at 100% lines and branches.

- [ ] **Step 5: Checkpoint.**

---

### Task 8: Flowchart trigger settings (owner only)

**Files:**
- Create: `app/controllers/admin/maintenance/flowchart_triggers_controller.rb`
- Modify:
  - `config/routes.rb`: in the tenant flowchart block, next to L496, add `resource :trigger, only: :update, controller: "maintenance/flowchart_triggers"`. There is no platform route, because shared flowcharts can't be automations.
  - `app/components/flowchart_info_card_component.{rb,html.erb}`: add a `trigger_editable:` argument and a "Runs automatically" section.
  - `app/views/admin/maintenance/flowcharts/show.html.erb` (L86–89): pass `trigger_editable: publishing_editable?(@flowchart) && !@flowchart.shared?`.
  - `config/locales/chrome.{en,zh-CN}.yml`, `config/locales/maint_core.{en,zh-CN}.yml`
- Test: `spec/requests/maintenance/flowchart_triggers_spec.rb` (copy the structure of `flowchart_crud_types_spec.rb`), `spec/components/flowchart_info_card_component_spec.rb`

**Interfaces:**
- Consumes: `Flowchart::Trigger`.
- Produces: `PATCH /:cid/admin/maintenance/flowcharts/:flowchart_id/trigger` with params `flowchart[trigger_timing|trigger_position|trigger_condition][]`.

- [ ] **Step 1: Write the failing request spec.** It needs these examples:
  - **The owner** saves `after_save` with position 2 and condition `@audience equals public`. Expected: the columns are persisted and the success flash shows.
  - **Blank timing** clears the trigger.
  - **An invalid timing** writes nothing and shows the invalid flash.
  - **Read type:** a flowchart with `crud_type: "read"` writes nothing and shows the `flowchart_trigger_event` message.
  - **A tenant admin** gets 403 or 404 (`OwnerOnlySurfaces` gates any path containing "flowchart").
  - **A launched flowchart** stays launched and stays editable.

- [ ] **Step 2: Run it and confirm it fails.** Expected: a routing error.

- [ ] **Step 3: Implement**

```ruby
# app/controllers/admin/maintenance/flowchart_triggers_controller.rb
# frozen_string_literal: true

module Admin
  module Maintenance
    # When a flowchart runs automatically. Like the CRUD type, this is
    # metadata: it is editable while launched and never regenerates the logic.
    class FlowchartTriggersController < ApplicationController
      include Admin::Maintenance::SharedResourceMode

      OPERATORS = %w[equals not_equals contains greater_than less_than is_empty is_not_empty].freeze
      MAX_CONDITIONS = 5

      before_action :find_flowchart
      guard_shared_global_writes :@flowchart

      def update
        @flowchart.assign_attributes(trigger_attributes)
        @flowchart.validate
        messages = @flowchart.errors.full_messages_for(:trigger_timing) + @flowchart.errors.full_messages_for(:trigger_position) +
                   @flowchart.errors[:base].grep(/#{Regexp.escape(I18n.t('maint_core.errors.validations.flowchart_trigger_event')[0, 12])}/)
        return redirect_back_with(alert: messages.first || t("maint_core.flash.flowchart_triggers.invalid")) if trigger_errors?

        @flowchart.update_columns(trigger_attributes.merge(updated_at: Time.current))
        redirect_back_with(notice: t("maint_core.flash.flowchart_triggers.updated"))
      end

      private

      def find_flowchart
        @flowchart = definition_scope(Flowchart).find(params[:flowchart_id])
      end

      def trigger_errors?
        (@flowchart.errors.attribute_names & %i[trigger_timing trigger_position]).any? ||
          (@flowchart.automation? && !Flowchart::Trigger::EVENTS.include?(@flowchart.crud_type.to_s)) ||
          (@flowchart.automation? && (@flowchart.shared? || @flowchart.entity_id.blank?))
      end

      def trigger_attributes
        raw = params.fetch(:flowchart, {})
        {
          trigger_timing: raw[:trigger_timing].presence,
          trigger_position: raw[:trigger_position].to_i.clamp(0, 999),
          trigger_condition: conditions(raw[:trigger_condition]).to_json
        }
      end

      def conditions(rows)
        Array(rows).first(MAX_CONDITIONS).filter_map do |row|
          row = row.respond_to?(:permit) ? row.permit(:field_id, :operator, :value).to_h : row.to_h
          next if row["field_id"].blank? || !OPERATORS.include?(row["operator"])

          { "field_id" => row["field_id"].to_s, "operator" => row["operator"], "value" => row["value"].to_s, "logic" => "and" }
        end
      end

      def redirect_back_with(flash)
        redirect_to admin_maintenance_flowchart_path(current_customer_id, @flowchart), flash
      end
    end
  end
end
```

The `messages` line above is too clever. Simplify it before merging: compute `messages = @flowchart.errors.full_messages` and alert with the first message when `trigger_errors?`. The spec asserts the `flowchart_trigger_event` text.

Card section, rendered when `trigger_editable` is true: a `form_with url: admin_maintenance_flowchart_trigger_path(...), method: :patch, scope: :flowchart`. It contains:
- a timing select: "Never" plus the three timings;
- a position number field (`min=0`);
- three condition rows. Each row has a field select (`@audience`, `@surface`, `@action_key`, `@changed`, then the entity's attribute slugs labelled by name), an operator select (`OPERATORS`) and a value text input.

The layout is `grid grid-cols-1 gap-3 sm:grid-cols-3`.

Locale keys go under `chrome.flowchart_info_card` (copy the nesting of the existing `crud_type` keys):

```yaml
# en
trigger_title: "Runs automatically"
trigger_none: "Never"
trigger_timing:
  before_save: "Before the record is saved"
  after_save: "After the record is saved"
  after_commit: "In the background after saving"
trigger_position: "Order"
trigger_condition: "Only when"
trigger_field:
  audience: "Audience"
  surface: "Saved from"
  action_key: "Action key"
  changed: "Changed fields"
trigger_operator:
  equals: "equals"
  not_equals: "does not equal"
  contains: "contains"
  greater_than: "is greater than"
  less_than: "is less than"
  is_empty: "is empty"
  is_not_empty: "is not empty"
trigger_save: "Save"
```

```yaml
# zh-CN
trigger_title: "自动运行"
trigger_none: "不自动运行"
trigger_timing:
  before_save: "记录保存前"
  after_save: "记录保存后"
  after_commit: "保存后在后台运行"
trigger_position: "顺序"
trigger_condition: "仅当"
trigger_field:
  audience: "受众"
  surface: "保存来源"
  action_key: "操作标识"
  changed: "已变更字段"
trigger_operator:
  equals: "等于"
  not_equals: "不等于"
  contains: "包含"
  greater_than: "大于"
  less_than: "小于"
  is_empty: "为空"
  is_not_empty: "不为空"
trigger_save: "保存"
```

Add under `maint_core.flash.flowchart_triggers`:
- `updated`: "Automation settings saved." / "自动运行设置已保存。"
- `invalid`: "Those automation settings aren't valid." / "自动运行设置无效。"

- [ ] **Step 4: Run the specs**

  Run `bundle exec rspec spec/requests/maintenance/flowchart_triggers_spec.rb spec/components/flowchart_info_card_component_spec.rb spec/requests/maintenance/flowchart_crud_types_spec.rb`. Expected: all pass.

- [ ] **Step 5: Phase 1 gate.** This phase touches auth and the submit path across the whole app, so run the full suite:

  `bin/rails parallel:prepare && bin/rails parallel:spec && npx vitest run --coverage`

  Expected: 0 failures, and JavaScript at 100%.

- [ ] **Step 6: Checkpoint.** Stop for review before starting Phase 2.

---

# Phase 2: Journeys

### Task 9: Journey model, definition, save activity and owner gate

**Files:**
- Create:
  - `db/migrate/20261112110000_create_journeys.rb`
  - `app/models/journey.rb`
  - `app/services/journeys/definition.rb`
  - `app/services/journeys/step_params.rb`
  - `app/contracts/journeys/contract.rb`
  - `app/services/journeys/activities/save.rb`
  - `app/services/journey_visibility.rb`
  - `config/locales/journeys.{en,zh-CN}.yml`
- Modify:
  - `app/services/owner_only_surfaces.rb`: `surfaces = [FlowchartVisibility, EntityDomainVisibility, JourneyVisibility]`.
  - `app/models/journey_run.rb`: add `belongs_to :journey, optional: true`, `records`, `record!(step_key, id)`, and the journey branch of `bindings_for`.
- Test:
  - `spec/services/journeys/definition_spec.rb`, `spec/models/journey_spec.rb`, `spec/services/journeys/activities/save_spec.rb`
  - `spec/services/journey_visibility_spec.rb`
  - `spec/factories/journeys.rb`: factory `:journey` with a valid two-step definition plus a finish step; trait `:launched`.

**Interfaces:**
- Produces:
  - **`Journey`:** `steps_definition`, which returns `Journeys::Definition`; `visible_audiences`, `visible_to?(audience)`, `visible_audiences=`; scopes `for_customer` and `by_name`; enum statuses `draft` and `launched`.
  - **`Journeys::Definition`:** `#steps` (Step objects with `key`, `kind`, `action_key`, `label`, `inputs`, `repeat` and `target`, plus `#finish?` and `#display_label`), `#step(key)`, `#first_step`, `#finish`, `#next_after(key)`, `#action_keys`, `#errors`, `#valid?`, `#to_h`, `.blank`.
  - **`Journeys::StepParams.to_definition(rows, customer_id:)`:** returns a hash. It turns `page_id` into an action key and assigns a unique action key when the page has none.
  - **`Journeys::Activities::Save.call(journey:, params:, customer_id:)`:** returns `Result(ok:, journey:, errors:)`.
  - **`JourneyVisibility`:** `allowed?(user)` is `user&.platform_owner?`; `controller?(path)` matches `%r{\Aadmin/(?:maintenance/journey|domains/journeys)}`; `route_subject?(subject)` matches the `route_admin_maintenance_journey` and `route_admin_domains_journeys` prefixes.

- [ ] **Step 1: Write the failing definition spec**

```ruby
# spec/services/journeys/definition_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Journeys::Definition do
  def definition(steps) = described_class.new("steps" => steps)

  let(:valid_steps) do
    [
      { "key" => "start", "kind" => "create", "action_key" => "student_new" },
      { "key" => "relate_1", "kind" => "relate", "action_key" => "student_add_course", "inputs" => { "student" => "start" }, "repeat" => true },
      { "key" => "finish", "kind" => "finish", "target" => { "kind" => "record", "step" => "start" } }
    ]
  end

  it "accepts a create, a repeatable relate and a record finish" do
    expect(definition(valid_steps)).to be_valid
    expect(definition(valid_steps).next_after("start").key).to eq("relate_1")
  end

  it "requires the journey to start by creating a record" do
    steps = valid_steps.dup.tap { |list| list[0] = list[0].merge("kind" => "relate", "inputs" => { "x" => "y" }) }
    expect(definition(steps).errors).to include(I18n.t("journeys.definition.errors.start_kind"))
  end

  it "requires exactly one finish at the end" do
    expect(definition(valid_steps.first(2)).errors).to include(I18n.t("journeys.definition.errors.finish_last"))
  end

  it "only lets relate steps repeat" do
    steps = valid_steps.dup.tap { |list| list[0] = list[0].merge("repeat" => true) }
    expect(definition(steps).errors.join).to include(I18n.t("journeys.definition.errors.repeat_relate_only", step: "start"))
  end

  it "only takes records from earlier steps" do
    steps = valid_steps.dup.tap { |list| list[1] = list[1].merge("inputs" => { "student" => "finish" }) }
    expect(definition(steps).errors.join).to include(I18n.t("journeys.definition.errors.input_source_invalid", step: "relate_1"))
  end

  it "rejects a record finish that points at no earlier step" do
    steps = valid_steps.dup.tap { |list| list[2] = list[2].merge("target" => { "kind" => "record", "step" => "nope" }) }
    expect(definition(steps).errors).to include(I18n.t("journeys.definition.errors.finish_record_invalid"))
  end
end
```

The other specs in this task check:
- **Journey model:** the key format; key uniqueness per customer (the same key in two customers is fine); at least one audience.
- **Save activity:**
  - normalising `page_id` assigns `student_new` to an unkeyed page;
  - a cross-tenant `entity_domain_id` is rejected;
  - an invalid definition returns errors and writes nothing.
- **JourneyVisibility:** `controller?("admin/maintenance/journeys")` is true; `controller?("journeys/starts")` is false.

- [ ] **Step 2: Run them and confirm they fail.**

- [ ] **Step 3: Implement**

```ruby
# db/migrate/20261112110000_create_journeys.rb
# frozen_string_literal: true

class CreateJourneys < ActiveRecord::Migration[8.1]
  def change
    create_table :journeys do |t|
      t.references :customer, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :entity_domain, null: true, foreign_key: { on_delete: :nullify }
      t.string :key, null: false
      t.string :name, null: false
      t.text :description
      t.integer :status, null: false, default: 0
      t.boolean :audience_admin, null: false, default: true
      t.boolean :audience_member, null: false, default: false
      t.boolean :audience_public, null: false, default: false
      t.text :definition
      t.timestamps null: false
    end
    add_index :journeys, %i[customer_id key], unique: true
    add_index :journeys, %i[customer_id status]

    add_reference :journey_runs, :journey, null: true, foreign_key: { on_delete: :cascade }
    add_column :journey_runs, :current_step, :string
  end
end
```

```ruby
# app/models/journey.rb
# frozen_string_literal: true

# A guided sequence of pages for one customer, built by the platform owner.
# Steps point at page action keys, so each audience gets its own page.
class Journey < ApplicationRecord
  include JsonSerializable

  AUDIENCES = PageVisibility::AUDIENCES

  belongs_to :customer
  belongs_to :entity_domain, optional: true
  has_many :runs, class_name: "JourneyRun", dependent: :delete_all

  enum :status, { draft: 0, launched: 1 }, default: :draft
  json_attribute :definition, default: {}

  validates :name, presence: true, length: { maximum: 120 }
  validates :key, format: { with: PageVisibility::ACTION_KEY }, uniqueness: { scope: :customer_id }
  validate :audience_present

  scope :for_customer, ->(customer_id) { where(customer_id: customer_id) }
  scope :by_name, -> { order(Arel.sql("LOWER(journeys.name)"), :id) }

  def steps_definition = Journeys::Definition.new(definition_json)

  def visible_audiences = AUDIENCES.select { |audience| public_send("audience_#{audience}") }
  def visible_to?(audience) = visible_audiences.include?(audience.to_s)

  def visible_audiences=(list)
    selected = Array(list).map(&:to_s)
    AUDIENCES.each { |audience| public_send("audience_#{audience}=", selected.include?(audience)) }
  end

  private

  def audience_present
    errors.add(:base, I18n.t("journeys.launch.errors.audiences_blank")) if visible_audiences.empty?
  end
end
```

```ruby
# app/services/journeys/definition.rb
# frozen_string_literal: true

module Journeys
  # Parses and checks a journey's steps. Journeys are linear: a create step,
  # then relate steps in order, ending in exactly one finish step.
  class Definition
    KINDS = %w[create relate finish].freeze
    KEY = /\A[a-z][a-z0-9_]{0,39}\z/

    Step = Data.define(:key, :kind, :action_key, :label, :inputs, :repeat, :target) do
      def finish? = kind == "finish"
      def display_label = label.presence || key
    end

    attr_reader :steps

    def self.blank = new("steps" => [])

    def initialize(raw)
      hash = raw.is_a?(String) ? parse(raw) : raw.to_h.stringify_keys
      @steps = Array(hash["steps"]).grep(Hash).map { |row| build(row.stringify_keys) }
    end

    def to_h = { "steps" => steps.map { |step| step.to_h.transform_keys(&:to_s).compact } }
    def step(key) = steps.find { |step| step.key == key.to_s }
    def first_step = steps.first
    def finish = steps.find(&:finish?)
    def action_keys = steps.reject(&:finish?).map(&:action_key)
    def valid? = errors.empty?

    def next_after(key)
      index = steps.index { |step| step.key == key.to_s }
      index && steps[index + 1]
    end

    def errors
      @errors ||= (structure_errors + steps.each_with_index.flat_map { |step, index| step_errors(step, index) }).uniq
    end

    private

    def parse(raw)
      JSON.parse(raw.presence || "{}")
    rescue JSON::ParserError
      {}
    end

    def build(row)
      Step.new(
        key: row["key"].to_s, kind: row["kind"].to_s, action_key: row["action_key"].to_s.presence,
        label: row["label"].to_s.strip.presence,
        inputs: row["inputs"].is_a?(Hash) ? row["inputs"].to_h { |field, from| [field.to_s, from.to_s] } : {},
        repeat: ActiveModel::Type::Boolean.new.cast(row["repeat"]) == true,
        target: row["target"].is_a?(Hash) ? row["target"].stringify_keys : nil
      )
    end

    def structure_errors
      list = []
      list << t(:too_short) if steps.size < 2
      list << t(:finish_last) unless steps.last&.finish? && steps.count(&:finish?) == 1
      list << t(:start_kind) unless steps.first&.kind == "create"
      list << t(:duplicate_keys) if steps.map(&:key).uniq.size != steps.size
      list
    end

    def step_errors(step, index)
      list = []
      list << t(:key_invalid, step: step.display_label) unless step.key.match?(KEY)
      list << t(:kind_invalid, step: step.display_label) unless KINDS.include?(step.kind)
      return list + finish_errors(step, index) if step.finish?

      earlier = steps.first(index).reject(&:finish?).map(&:key)
      list << t(:action_key_invalid, step: step.display_label) unless step.action_key.to_s.match?(PageVisibility::ACTION_KEY)
      list << t(:repeat_relate_only, step: step.display_label) if step.repeat && step.kind != "relate"
      list << t(:relate_needs_input, step: step.display_label) if step.kind == "relate" && step.inputs.empty?
      list << t(:input_source_invalid, step: step.display_label) if step.inputs.values.any? { |from| !earlier.include?(from) }
      list
    end

    def finish_errors(step, index)
      target = step.target.to_h
      case target["kind"]
      when "record" then steps.first(index).reject(&:finish?).map(&:key).include?(target["step"].to_s) ? [] : [t(:finish_record_invalid)]
      when "page" then target["action_key"].to_s.match?(PageVisibility::ACTION_KEY) ? [] : [t(:finish_page_invalid)]
      else [t(:finish_target_invalid)]
      end
    end

    def t(key, **vars) = I18n.t("journeys.definition.errors.#{key}", **vars)
  end
end
```

`Journeys::StepParams.to_definition(rows, customer_id:)` converts each builder row into a definition step:
- **Keys:** the step key comes from the row, or `step_<n>` when blank. The last row is always the finish.
- **Pages:** `page_id` is looked up as `Page.where(customer_id: [customer_id, nil]).find_by(id:)`. If the page has no action key, it gets `"#{SectionSlug.for(page.name)}_#{page.id}"`, truncated to 63 characters and guaranteed unique per customer, saved with `page.update_columns(action_key:)`.
- **Relate inputs:** become `{ page.page_inputs.first["field"] => row["input_from"] }`.
- **Finish target:** `finish_kind: "record"` becomes `{ "kind" => "record", "step" => finish_step }`. `finish_kind: "page"` becomes `{ "kind" => "page", "action_key" => <action key of finish_page_id> }`.

Other pieces:
- **`Journeys::Contract < Reform::Form`:** properties `name`, `key`, `description`, `entity_domain_id`, `definition`. It validates that the domain belongs to the customer and adds `Journeys::Definition.new(definition).errors` to the base errors.
- **`Journeys::Activities::Save`:** a Trailblazer Railway with steps `normalize` (`StepParams` plus audiences), `validate` (contract) and `persist`, then `fail :collect_errors`. It follows `EntityDomains::Activities::Save` exactly: `self.call(journey:, params:, customer_id:)` runs under `Current.set(customer:)` and returns a `Result` struct.
- **`JourneyRun` additions:**

```ruby
  belongs_to :journey, optional: true

  def records = state_json.to_h["records"].to_h

  def record!(step_key, id)
    data = state_json.to_h
    data["records"] = records.merge(step_key.to_s => (Array(records[step_key.to_s]) + [id.to_s]).uniq)
    update!(state: data.to_json)
  end

  def bindings_for(page)
    return handover_bindings(page) unless journey

    step = journey.steps_definition.step(current_step)
    return {} unless step && step.action_key == page.action_key

    step.inputs.each_with_object({}) do |(field, from), bound|
      id = Array(records[from]).last
      bound[field] = id if id.present?
    end
  end
```

Rename the Phase 1 body of `bindings_for` to the private `handover_bindings(page)`.

Locale files: create `config/locales/journeys.en.yml` with the full `journeys:` tree below, and the matching `journeys.zh-CN.yml`.

```yaml
en:
  journeys:
    definition:
      errors:
        too_short: "A journey needs at least one step and a finish."
        finish_last: "End the journey with exactly one finish step."
        start_kind: "The first step must create a record."
        duplicate_keys: "Each step needs its own key."
        key_invalid: "%{step}: the step key must start with a letter and use only lowercase letters, numbers and underscores."
        kind_invalid: "%{step}: choose a step type."
        action_key_invalid: "%{step}: choose a page for this step."
        repeat_relate_only: "%{step}: only steps that add related records can repeat."
        relate_needs_input: "%{step}: choose which earlier step's record this step adds to."
        input_source_invalid: "%{step}: records can only come from an earlier step."
        finish_record_invalid: "Finish: choose an earlier step whose record to open."
        finish_page_invalid: "Finish: choose a page to open."
        finish_target_invalid: "Finish: choose where the journey ends."
    launch:
      errors:
        audiences_blank: "Choose at least one audience."
        page_missing: "%{step}: no launched page for %{audience}."
        input_undeclared: "%{step}: the page has no locked input to receive the record."
        input_entity_mismatch: "%{step}: the page's locked input expects a different record type."
        start_taken: "Another launched journey (%{name}) already starts on this page for the same audience."
    audiences:
      admin: "Admins"
      member: "Members"
      public: "Public visitors"
    runtime:
      step_of: "Step %{current} of %{total}"
      save_and_add_another: "Save and add another"
      saved_add_another: "Saved. Add another."
      completed: "All done."
      unavailable: "This journey isn't available."
    generate:
      journey_name: "%{start} journey"
      relate_page_name: "Add %{target} for %{parent}"
    admin:
      title: "Journeys"
      description: "Guide people from one page to the next, carrying each new record forward."
      new: "New journey"
      edit: "Edit journey"
      generate: "Generate journey"
      fields:
        name: "Name"
        key: "Key"
        description: "Description"
        domain: "Domain"
        audiences: "Audiences"
      steps: "Steps"
      add_step: "Add step"
      remove_step: "Remove"
      move_up: "Move up"
      move_down: "Move down"
      step_kind:
        create: "Create a record"
        relate: "Add related records"
        finish: "Finish"
      step_page: "Page"
      step_page_none: "Choose a page"
      step_label: "Step label"
      step_input_from: "Add to the record from"
      step_repeat: "Allow “Save and add another”"
      finish_kind:
        record: "Open the record from"
        page: "Open a page"
      create_page: "Create a page"
      save: "Save"
      launch: "Launch"
      take_offline: "Take offline"
      preview: "Preview"
      delete: "Delete"
      delete_confirm: "Delete this journey? People partway through it will stop at their current page."
      status:
        draft: "Draft"
        launched: "Launched"
      columns:
        name: "Name"
        status: "Status"
        steps: "Steps"
        audiences: "Audiences"
        updated: "Updated"
      empty_title: "No journeys yet"
      empty_description: "Generate one from this domain or build it step by step."
      flash:
        created: "Journey created."
        updated: "Journey saved."
        deleted: "Journey deleted."
        launched: "Journey launched."
        taken_offline: "Journey taken offline."
        generated: "Journey generated. Review its steps, then launch it."
      generation:
        title: "Generate a journey"
        description: "Pick a starting record type. A page is created and launched for admins for each step, and the journey is saved as a draft for you to review."
        no_candidates: "No record type in this domain collects related records yet."
        then_steps: "Then: %{steps}"
        submit: "Generate"
      usage:
        title: "Used in journeys"
        empty: "This page isn't part of a journey."
```

```yaml
zh-CN:
  journeys:
    definition:
      errors:
        too_short: "流程至少需要一个步骤和一个结束步骤。"
        finish_last: "流程须以唯一的结束步骤收尾。"
        start_kind: "第一步必须是新建记录。"
        duplicate_keys: "步骤标识不能重复。"
        key_invalid: "%{step}：步骤标识须以字母开头，只能包含小写字母、数字和下划线。"
        kind_invalid: "%{step}：请选择步骤类型。"
        action_key_invalid: "%{step}：请为该步骤选择页面。"
        repeat_relate_only: "%{step}：只有添加关联记录的步骤可以重复。"
        relate_needs_input: "%{step}：请选择要关联到哪个前序步骤的记录。"
        input_source_invalid: "%{step}：记录只能来自前序步骤。"
        finish_record_invalid: "结束：请选择要打开哪个前序步骤的记录。"
        finish_page_invalid: "结束：请选择要打开的页面。"
        finish_target_invalid: "结束：请选择流程结束后的去向。"
    launch:
      errors:
        audiences_blank: "请至少选择一类受众。"
        page_missing: "%{step}：没有面向%{audience}的已发布页面。"
        input_undeclared: "%{step}：该页面没有用于接收记录的锁定字段。"
        input_entity_mismatch: "%{step}：该页面的锁定字段需要另一种记录类型。"
        start_taken: "已有已发布的流程（%{name}）以该页面为起点并面向相同受众。"
    audiences:
      admin: "管理员"
      member: "会员"
      public: "公众访客"
    runtime:
      step_of: "第 %{current} 步，共 %{total} 步"
      save_and_add_another: "保存并继续添加"
      saved_add_another: "已保存，可继续添加。"
      completed: "已全部完成。"
      unavailable: "该流程当前不可用。"
    generate:
      journey_name: "%{start}流程"
      relate_page_name: "为%{parent}添加%{target}"
    admin:
      title: "引导流程"
      description: "引导用户逐页办理，并将每一步新建的记录带入下一步。"
      new: "新建流程"
      edit: "编辑流程"
      generate: "生成流程"
      fields:
        name: "名称"
        key: "标识"
        description: "说明"
        domain: "业务域"
        audiences: "受众"
      steps: "步骤"
      add_step: "添加步骤"
      remove_step: "移除"
      move_up: "上移"
      move_down: "下移"
      step_kind:
        create: "新建记录"
        relate: "添加关联记录"
        finish: "结束"
      step_page: "页面"
      step_page_none: "请选择页面"
      step_label: "步骤名称"
      step_input_from: "关联到以下步骤的记录"
      step_repeat: "允许“保存并继续添加”"
      finish_kind:
        record: "打开以下步骤的记录"
        page: "打开页面"
      create_page: "新建页面"
      save: "保存"
      launch: "发布"
      take_offline: "下线"
      preview: "预览"
      delete: "删除"
      delete_confirm: "确定删除该流程？正在办理的用户将停留在当前页面。"
      status:
        draft: "草稿"
        launched: "已发布"
      columns:
        name: "名称"
        status: "状态"
        steps: "步骤"
        audiences: "受众"
        updated: "更新时间"
      empty_title: "暂无流程"
      empty_description: "可从本业务域生成，或逐步手动搭建。"
      flash:
        created: "流程已创建。"
        updated: "流程已保存。"
        deleted: "流程已删除。"
        launched: "流程已发布。"
        taken_offline: "流程已下线。"
        generated: "流程已生成。请检查各步骤后再发布。"
      generation:
        title: "生成流程"
        description: "选择起始记录类型。系统会为每个步骤创建页面并向管理员发布，流程以草稿保存，供您审核。"
        no_candidates: "本业务域中暂无可收集关联记录的记录类型。"
        then_steps: "随后：%{steps}"
        submit: "生成"
      usage:
        title: "所属流程"
        empty: "该页面未加入任何流程。"
```

- [ ] **Step 4: Migrate and run the specs**

  Run `bin/rails db:migrate && bundle exec rspec spec/services/journeys spec/models/journey_spec.rb spec/models/journey_run_spec.rb spec/services/journey_visibility_spec.rb`. Expected: all pass.

- [ ] **Step 5: Checkpoint.**

---

### Task 10: Journey runtime

**Files:**
- Create:
  - `app/services/journeys/{starter,advance}.rb`
  - `app/controllers/concerns/journey_navigation.rb`
  - `app/controllers/journeys/starts_controller.rb`
  - `app/components/journeys/progress_component.{rb,html.erb}`
  - `app/components/journeys/repeat_button_component.{rb,html.erb}`
- Modify:
  - **`config/routes.rb`:** in the public section, after `actions/:action_key` (~L211), add

    ```ruby
    get "journeys/:key", to: "journeys/starts#show", as: :journey_start, constraints: { key: /[a-z][a-z0-9_]{1,62}/ }
    ```

  - **`app/controllers/concerns/page_rendering.rb`:** add `assign_journey_context(page)`, called from `prepare_page_render`.
  - **`page_content_generator.rb` and `entry_presentation.rb`:**
    - the progress snippet is the first child inside `<form>` in all three presentations (single L145–169, wizard L171–215, entry L15–32);
    - the repeat button sits next to every submit button;
    - a hidden `_journey` field is added in `form_fields.rb`.
  - **`app/controllers/public_pages_controller.rb`:** include `JourneyNavigation`; `complete_submission` tries `journey_next_path(result)` right after the handoff.
- Test:
  - `spec/services/journeys/advance_spec.rb`, `spec/services/journeys/starter_spec.rb`
  - `spec/components/journeys/progress_component_spec.rb`
  - `spec/requests/journeys_runtime_spec.rb`, `spec/requests/journeys/starts_spec.rb`

**Interfaces:**
- Consumes: `JourneyRun#record!`, `#bindings_for`; `Journey#steps_definition`; `Pages::RunLink`; `Pages::ActionResolver.page_for`.
- Produces:
  - `Journeys::Starter.for_page(page:, audience:, customer_id:)` and `.preview(key:, page:, customer_id:, viewer:)`.
  - `Journeys::Advance.call(run:, entry:, intent:)`, which returns `Next(kind: :step | :finish, step:)`.
  - `JourneyNavigation#journey_next_path(result)`.

- [ ] **Step 1: Write the failing specs.** First `Advance`:

```ruby
# spec/services/journeys/advance_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Journeys::Advance do
  let(:journey) { create(:journey, :launched) }
  let(:run) { JourneyRun.issue!(customer_id: journey.customer_id, user: nil, session: {}, journey: journey, current_step: "start").first }
  let(:entry) { instance_double(EntityEntry, id: 42) }

  it "records the start record and moves to the relate step" do
    result = described_class.call(run: run, entry: entry, intent: nil)
    expect(result.kind).to eq(:step)
    expect(run.reload.current_step).to eq("relate_1")
    expect(run.records).to eq("start" => ["42"])
  end

  it "stays on a repeatable step when adding another" do
    run.update!(current_step: "relate_1")
    result = described_class.call(run: run, entry: instance_double(EntityEntry, id: 7), intent: "add_another")
    expect(result.step.key).to eq("relate_1")
    expect(run.reload.records["relate_1"]).to eq(["7"])
  end

  it "finishes after the last working step and completes the run" do
    run.update!(current_step: "relate_1")
    result = described_class.call(run: run, entry: instance_double(EntityEntry, id: 8), intent: "continue")
    expect(result.kind).to eq(:finish)
    expect(run.reload).to be_completed
  end
end
```

The request spec `spec/requests/journeys_runtime_spec.rb` uses the `"student course association"` context, signed in as an admin. It sets up:
- a Student page with action key `student_new` and modes create/update;
- a launched admin bridge page with action key `student_add_course` and input `student`;
- a launched journey (create, repeatable relate, finish record "start").

It walks the flow:
1. `GET new_admin_entity_entry_path(student entity)` shows the "Step 1 of 2" progress.
2. Posting the Student form redirects to a URL containing `run=` and `page=<bridge page id>`.
3. That page shows the locked student and "Save and add another".
4. Posting with `_intent=add_another` redirects back to the same page, with the `saved_add_another` flash.
5. Posting without an intent redirects to `admin_entity_entry_path(cid, student entity, student id)`, and the run is `completed`.

It also covers:
- **"a page that isn't the current step ignores the run":** the normal select is rendered.
- **"a draft journey doesn't start":** the start page shows no progress.

`spec/requests/journeys/starts_spec.rb` covers:
- a launched public journey: 303 to its first public page;
- a draft or unknown key: 404 with the `unavailable` text;
- a member-only journey for an anonymous visitor: redirect to sign-in.

- [ ] **Step 2: Run them and confirm they fail.**

- [ ] **Step 3: Implement**

```ruby
# app/services/journeys/starter.rb
# frozen_string_literal: true

module Journeys
  # Finds the journey a page starts. Launch checks keep at most one launched
  # journey per first page and audience, so the answer is unambiguous.
  module Starter
    def self.for_page(page:, audience:, customer_id:)
      return if page.action_key.blank?

      Journey.launched.where(customer_id: customer_id).find do |journey|
        journey.visible_to?(audience) && journey.steps_definition.first_step&.action_key == page.action_key
      end
    end

    # Owner preview of a draft through ?journey=<key>.
    def self.preview(key:, page:, customer_id:, viewer:)
      return if key.blank? || !JourneyVisibility.allowed?(viewer)

      journey = Journey.find_by(customer_id: customer_id, key: key.to_s)
      journey if journey && journey.steps_definition.first_step&.action_key == page.action_key
    end
  end
end
```

```ruby
# app/services/journeys/advance.rb
# frozen_string_literal: true

module Journeys
  # Records what the current step produced and decides where the run goes.
  class Advance
    INTENTS = %w[continue add_another].freeze
    Next = Data.define(:kind, :step)

    def self.call(...) = new(...).call

    def initialize(run:, entry:, intent: nil)
      @run = run
      @entry = entry
      @intent = INTENTS.include?(intent.to_s) ? intent.to_s : "continue"
    end

    def call
      definition = @run.journey.steps_definition
      step = definition.step(@run.current_step)
      return finish(definition) unless step

      @run.record!(step.key, @entry.id) if @entry
      return Next.new(kind: :step, step: step) if step.repeat && @intent == "add_another"

      upcoming = definition.next_after(step.key)
      return finish(definition) if upcoming.nil? || upcoming.finish?

      @run.update!(current_step: upcoming.key)
      Next.new(kind: :step, step: upcoming)
    end

    private

    def finish(definition)
      @run.update!(status: :completed, current_step: definition.finish&.key)
      Next.new(kind: :finish, step: definition.finish)
    end
  end
end
```

```ruby
# app/controllers/concerns/journey_navigation.rb
# frozen_string_literal: true

# After a successful submit, moves a running (or just started) journey to its
# next page, or to its finish destination.
module JourneyNavigation
  extend ActiveSupport::Concern

  private

  def journey_next_path(result)
    run = page_run || start_journey_run
    return unless run&.journey

    current = run.journey.steps_definition.step(run.current_step)
    return unless current && current.action_key == @page.action_key

    upcoming = Journeys::Advance.call(run: run, entry: result.entry, intent: params[:_intent])
    if upcoming.kind == :finish
      journey_finish_path(run, upcoming.step)
    else
      flash[:notice] = t("journeys.runtime.saved_add_another") if upcoming.step.key == current.key
      journey_step_path(upcoming.step)
    end
  end

  def start_journey_run
    journey = Journeys::Starter.for_page(page: @page, audience: page_runtime_audience, customer_id: current_customer_id) ||
              Journeys::Starter.preview(key: params[:_journey], page: @page, customer_id: current_customer_id, viewer: current_user)
    return unless journey

    run, @page_run_token = JourneyRun.issue!(customer_id: current_customer_id, user: page_runtime_user, session: session,
                                             journey: journey, current_step: journey.steps_definition.first_step.key)
    run
  end

  def journey_step_path(step)
    page = Pages::ActionResolver.page_for(customer_id: current_customer_id, action_key: step.action_key, audience: page_runtime_audience)
    return post_submit_path unless page

    admin = page_runtime_audience == EntityAttributeAudience::ADMIN
    Pages::RunLink.append(audience_surface_path(page), @page_run_token, page: (page if admin))
  end

  def journey_finish_path(run, finish)
    target = finish&.target.to_h
    flash[:notice] = t("journeys.runtime.completed")
    case target["kind"]
    when "record" then journey_record_path(run, target["step"]) || post_submit_path
    when "page" then journey_finish_page_path(target["action_key"]) || post_submit_path
    else post_submit_path
    end
  end

  def journey_record_path(run, step_key)
    id = Array(run.records[step_key.to_s]).last
    entry = id && EntityEntry.find_by(id: id, customer_id: current_customer_id)
    return unless entry

    case page_runtime_audience
    when EntityAttributeAudience::ADMIN then admin_entity_entry_path(current_customer_id, entry.entity_id, entry.id)
    when EntityAttributeAudience::MEMBER then member_surface_path(current_customer_id, "entity_#{entry.entity_id}", entry.id)
    end
  end

  def journey_finish_page_path(action_key)
    page = Pages::ActionResolver.page_for(customer_id: current_customer_id, action_key: action_key, audience: page_runtime_audience)
    page && audience_surface_path(page)
  end
end
```

`PublicPagesController#complete_submission` changes: after the handoff line, add

```ruby
if (path = journey_next_path(result))
  return redirect_to(path, type => (flash[:notice] || text))
end
```

before the `after_submit_path` check from Task 6.

Add `assign_journey_context(page)` to `page_rendering.rb` and call it from `prepare_page_render`:

```ruby
  def assign_journey_context(page)
    run = page_run
    if run&.journey
      step = run.journey.steps_definition.step(run.current_step)
      @journey, @journey_step = run.journey, step if step && step.action_key == page.action_key
    elsif (journey = Journeys::Starter.for_page(page: page, audience: page_runtime_audience, customer_id: current_customer_id) ||
                     Journeys::Starter.preview(key: params[:journey], page: page, customer_id: current_customer_id, viewer: current_user))
      @journey, @journey_step = journey, journey.steps_definition.first_step
      @journey_start_key = journey.key if journey.draft?
    end
  end
```

The two components:

```ruby
# app/components/journeys/progress_component.rb
# frozen_string_literal: true

module Journeys
  class ProgressComponent < ViewComponent::Base
    def initialize(journey:, current_key:)
      @steps = journey.steps_definition.steps.reject(&:finish?)
      @current_index = @steps.index { |step| step.key == current_key.to_s } || 0
    end

    def steps = @steps
    def current_index = @current_index
    def label_for(step) = step.label.presence || Pages::ActionResolver.page_for(customer_id: Current.customer_id, action_key: step.action_key, audience: helpers.page_runtime_audience)&.name.to_s
  end
end
```

```erb
<%# app/components/journeys/progress_component.html.erb %>
<nav class="mb-6" aria-label="<%= t("journeys.runtime.step_of", current: current_index + 1, total: steps.size) %>" data-role="journey-progress">
  <p class="text-sm font-medium text-slate-600"><%= t("journeys.runtime.step_of", current: current_index + 1, total: steps.size) %></p>
  <ol class="mt-2 flex flex-wrap gap-2">
    <% steps.each_with_index do |step, index| %>
      <li class="flex items-center gap-2 rounded-full px-3 py-1 text-xs font-medium <%= index == current_index ? "bg-slate-900 text-white" : (index < current_index ? "bg-emerald-50 text-emerald-700" : "bg-slate-100 text-slate-500") %>">
        <span><%= index + 1 %></span><span class="hidden sm:inline"><%= label_for(step) %></span>
      </li>
    <% end %>
  </ol>
</nav>
```

`RepeatButtonComponent.new(step:)`:
- renders only when `step&.repeat`;
- markup: `<button type="submit" name="_intent" value="add_another" class="…secondary button classes…"><%= t("journeys.runtime.save_and_add_another") %></button>`.

Generated ERB snippets:
- progress: `<%= render Journeys::ProgressComponent.new(journey: @journey, current_key: @journey_step&.key) if @journey %>`
- repeat button: `<%= render Journeys::RepeatButtonComponent.new(step: @journey_step) %>`
- hidden field: `<%= hidden_field_tag :_journey, @journey_start_key if @journey_start_key.present? %>`

```ruby
# app/controllers/journeys/starts_controller.rb
# frozen_string_literal: true

module Journeys
  # /:cid/journeys/:key — opens a launched journey's first page for the
  # visitor's audience. The page starts the run when it is submitted.
  class StartsController < ApplicationController
    include PageRendering
    include PageAudienceRouting
    include PageShortcuts::PublicPathContext

    def show
      journey = Journey.launched.find_by(customer_id: current_customer_id, key: params[:key])
      audience = page_runtime_audience
      first = journey&.steps_definition&.first_step
      page = first && journey.visible_to?(audience) &&
             Pages::ActionResolver.page_for(customer_id: current_customer_id, action_key: first.action_key, audience: audience)
      return redirect_to(audience_surface_path(page), status: :see_other) if page

      if journey && !user_signed_in? && journey.visible_to?(EntityAttributeAudience::MEMBER)
        store_location_for(:user, request.fullpath)
        return redirect_to(new_user_session_path)
      end

      render plain: t("journeys.runtime.unavailable"), status: :not_found
    end
  end
end
```

- [ ] **Step 4: Run the specs**

  Run `bundle exec rspec spec/services/journeys spec/components/journeys spec/requests/journeys_runtime_spec.rb spec/requests/journeys spec/requests/public_pages_*_spec.rb`. Expected: all pass.

- [ ] **Step 5: Checkpoint.**

---

### Task 11: Journey launch checks

**Files:**
- Create: `app/services/journeys/launch_checks.rb`, `app/controllers/admin/maintenance/journey_launches_controller.rb`
- Modify: `config/routes.rb` (Task 13 adds the maintenance block; declare `resource :launch` inside it)
- Test: `spec/services/journeys/launch_checks_spec.rb`, `spec/requests/admin/maintenance/journey_launches_spec.rb`

**Interfaces:**
- Produces:
  - `Journeys::LaunchChecks.new(journey).errors`, which returns an array of strings.
  - `POST` and `DELETE /:cid/admin/maintenance/journeys/:journey_id/launch`.

- [ ] **Step 1: Write the failing spec.** It needs these examples:
  - **"passes when every step has a launched page for every audience and inputs line up".**
  - **"names a step with no launched page for an audience":** the `page_missing` message, with the `journeys.audiences.member` label.
  - **"flags a relate page without a locked input":** `input_undeclared`.
  - **"flags an input that expects another entity":** `input_entity_mismatch`.
  - **"refuses a second launched journey on the same first page and audience":** `start_taken`.

  The request spec covers:
  - the owner launches (status becomes `launched`, flash) and takes offline;
  - failing checks keep it a draft and show the first error;
  - a tenant admin gets 403 or 404.

- [ ] **Step 2: Run it and confirm it fails.**

- [ ] **Step 3: Implement**

```ruby
# app/services/journeys/launch_checks.rb
# frozen_string_literal: true

module Journeys
  # Everything that must hold before a journey goes live: a valid definition,
  # a launched page per step and audience, inputs that can receive the earlier
  # step's record, and no other live journey starting on the same page.
  class LaunchChecks
    def initialize(journey)
      @journey = journey
      @definition = journey.steps_definition
    end

    def errors
      return @definition.errors unless @definition.valid?
      return [t(:audiences_blank)] if @journey.visible_audiences.empty?

      (step_errors + start_errors).uniq
    end

    private

    def step_errors
      @definition.steps.reject(&:finish?).flat_map do |step|
        @journey.visible_audiences.flat_map do |audience|
          page = page_for(step.action_key, audience)
          next [t(:page_missing, step: step.display_label, audience: I18n.t("journeys.audiences.#{audience}"))] unless page

          input_errors(step, page, audience)
        end
      end
    end

    def input_errors(step, page, audience)
      step.inputs.filter_map do |field, from|
        declared = page.page_inputs.find { |input| input["field"] == field }
        next t(:input_undeclared, step: step.display_label) unless declared

        source_page = page_for(@definition.step(from)&.action_key, audience)
        t(:input_entity_mismatch, step: step.display_label) unless source_page && source_page.entity_id.to_s == declared["entity_id"]
      end
    end

    def start_errors
      first = @definition.first_step.action_key
      clash = Journey.launched.where(customer_id: @journey.customer_id).where.not(id: @journey.id).find do |other|
        other.steps_definition.first_step&.action_key == first && (other.visible_audiences & @journey.visible_audiences).any?
      end
      clash ? [t(:start_taken, name: clash.name)] : []
    end

    def page_for(action_key, audience)
      action_key && Pages::ActionResolver.page_for(customer_id: @journey.customer_id, action_key: action_key, audience: audience)
    end

    def t(key, **vars) = I18n.t("journeys.launch.errors.#{key}", **vars)
  end
end
```

```ruby
# app/controllers/admin/maintenance/journey_launches_controller.rb
# frozen_string_literal: true

module Admin
  module Maintenance
    class JourneyLaunchesController < ApplicationController
      before_action :find_journey

      def create
        Customer.transaction do
          Customer.lock.find(current_customer.id)
          errors = Journeys::LaunchChecks.new(@journey).errors
          if errors.any?
            redirect_to edit_admin_maintenance_journey_path(current_customer.id, @journey), alert: errors.first
            raise ActiveRecord::Rollback
          end
          @journey.update!(status: :launched)
        end
        redirect_to edit_admin_maintenance_journey_path(current_customer.id, @journey), notice: t("journeys.admin.flash.launched") unless performed?
      end

      def destroy
        @journey.update!(status: :draft)
        redirect_to edit_admin_maintenance_journey_path(current_customer.id, @journey), notice: t("journeys.admin.flash.taken_offline")
      end

      private

      def find_journey = @journey = Journey.for_customer(current_customer.id).find(params[:journey_id])
    end
  end
end
```

- [ ] **Step 4: Run the specs**

  Run `bundle exec rspec spec/services/journeys/launch_checks_spec.rb spec/requests/admin/maintenance/journey_launches_spec.rb`. Expected: all pass.

- [ ] **Step 5: Checkpoint.**

---

### Task 12: Planner and generation

**Files:**
- Create: `app/services/entity_domains/journey_planner.rb`, `app/services/journeys/activities/generate.rb`
- Test:
  - `spec/services/entity_domains/journey_planner_spec.rb`, using the `"student course association"` context.
  - `spec/services/journeys/activities/generate_spec.rb`.

**Interfaces:**
- Produces:
  - `EntityDomains::JourneyPlanner.call(customer_id:, entities:)`, which returns an array of `Candidate(start:, steps: [RelateStep(entity:, parent_slug:, label:)])`.
  - `Journeys::Activities::Generate.call(customer:, domain_id:, index:)`, which returns `Result(ok:, journey:, errors:)`.

- [ ] **Step 1: Write the failing planner spec**

```ruby
# spec/services/entity_domains/journey_planner_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe EntityDomains::JourneyPlanner do
  include_context "student course association"

  it "starts at the entity that declares the bridge and adds a relate step on the bridge" do
    candidates = described_class.call(customer_id: customer.id, entities: [student_entity, course_entity, bridge_entity])
    expect(candidates.map { |candidate| candidate.start }).to eq([student_entity])
    step = candidates.first.steps.first
    expect([step.entity, step.parent_slug]).to eq([bridge_entity, "student"])
  end

  it "treats a child entity that references the start entity as a relate step" do
    note = create(:entity, customer: customer, name: "Note", property_schema: [
      { "name" => "Student", "name_slug" => "student", "type" => "EntityReference", "html_type" => "select", "entity_id" => student_entity.id.to_s }
    ].to_json)
    steps = described_class.call(customer_id: customer.id, entities: [student_entity, course_entity, bridge_entity, note]).first.steps
    expect(steps.map(&:entity)).to contain_exactly(bridge_entity, note)
  end

  it "proposes nothing for a domain whose entities collect no related rows" do
    expect(described_class.call(customer_id: customer.id, entities: [course_entity])).to be_empty
  end
end
```

Use whatever `let` names that shared context really defines. Read `spec/support/association_fixtures.rb` and adjust `student_entity`, `course_entity` and `bridge_entity` to match.

The `Generate` spec checks:
- **Pages:** generating for a Student/Course domain creates a launched admin Student page (`student_new`) and a launched admin bridge page (`student_add_course`), and the bridge page has input `student`.
- **Journey:** a draft journey whose steps are start, relate_1 (repeat) and finish (record start).
- **Re-running:** it reuses both pages and creates a second journey with a suffixed key.
- **Bad index:** an out-of-range `index` returns `ok: false` and writes nothing.

- [ ] **Step 2: Run them and confirm they fail.**

- [ ] **Step 3: Implement**

```ruby
# app/services/entity_domains/journey_planner.rb
# frozen_string_literal: true

module EntityDomains
  # Proposes journeys for one domain from its entity graph. A journey starts at
  # an entity that collects related rows, through a bridge it declares or a
  # child entity that references it. Entities that are only ever chosen from
  # (the far end of a bridge) are catalog data, never a step.
  class JourneyPlanner
    Candidate = Data.define(:start, :steps)
    RelateStep = Data.define(:entity, :parent_slug, :label)

    def self.call(...) = new(...).candidates

    def initialize(customer_id:, entities:)
      @customer_id = customer_id
      @entities = Array(entities)
    end

    def candidates
      @entities.reject(&:bridge_entity?).filter_map do |entity|
        steps = (bridge_steps(entity) + child_steps(entity)).sort_by { |step| step.label.downcase }
        Candidate.new(start: entity, steps: steps) if steps.any?
      end.sort_by { |candidate| [-candidate.steps.size, candidate.start.display_label.to_s.downcase] }
    end

    private

    def bridge_steps(entity)
      entity.associations_list.filter_map do |association|
        bridge = find(association["bridge_entity_id"])
        target = find(association["target_entity_id"])
        slug = bridge && target && reference_slug(bridge, entity)
        RelateStep.new(entity: bridge, parent_slug: slug, label: target.display_label.to_s) if slug
      end
    end

    def child_steps(entity)
      @entities.reject { |other| other.bridge_entity? || other.id == entity.id }.filter_map do |child|
        slug = reference_slug(child, entity)
        RelateStep.new(entity: child, parent_slug: slug, label: child.display_label.to_s) if slug
      end
    end

    def reference_slug(entity, target)
      Array(entity.property_schema_json).grep(Hash).find do |attribute|
        attribute["type"] == Entity::ENTITY_REFERENCE_TYPE && attribute["entity_id"].to_s == target.id.to_s
      end&.dig("name_slug")
    end

    def find(id) = @entities.find { |entity| entity.id.to_s == id.to_s }
  end
end
```

```ruby
# app/services/journeys/activities/generate.rb
# frozen_string_literal: true

module Journeys
  module Activities
    # Turns a planner candidate into launched admin pages and a draft journey
    # for the owner to review. A launched page of the same entity and action
    # key is reused, so generating twice doesn't duplicate forms.
    class Generate < Trailblazer::Activity::Railway
      Result = Struct.new(:ok, :journey, :errors, keyword_init: true)

      step :find_candidate
      step :prepare_pages
      step :persist_journey
      fail :collect_errors

      def self.call(customer:, domain_id:, index:)
        Current.set(customer: customer, shared_resources_mode: false) do
          signal, (ctx, _) = super([{ customer: customer, domain_id: domain_id, index: index.to_i, errors: [] }, {}])
          Result.new(ok: signal.to_h[:semantic] == :success, journey: ctx[:journey], errors: ctx[:errors])
        end
      end

      def find_candidate(ctx, customer:, domain_id:, index:, **)
        section = EntityDomains::Layout.call(customer_id: customer.id, entities: EntityDomains::Catalog.entities(customer.id))
                                       .find { |item| !item.ungrouped? && item.domain.id.to_s == domain_id.to_s }
        return false unless section

        ctx[:domain] = section.domain
        ctx[:candidate] = EntityDomains::JourneyPlanner.call(customer_id: customer.id, entities: section.items.map(&:entity))[index]
        ctx[:candidate].present?
      end

      def prepare_pages(ctx, customer:, candidate:, **)
        base = SectionSlug.for(candidate.start.name).first(30)
        ctx[:pages] = [page_for(customer, candidate.start, "#{base}_new", nil, nil)] +
                      candidate.steps.map do |step|
                        name = I18n.t("journeys.generate.relate_page_name", target: step.label, parent: candidate.start.display_label)
                        input = { "field" => step.parent_slug, "entity_id" => candidate.start.id.to_s }
                        page_for(customer, step.entity, "#{base}_add_#{SectionSlug.for(step.label).first(24)}", name, input)
                      end
        ctx[:pages].all?(&:present?)
      end

      def persist_journey(ctx, customer:, domain:, candidate:, pages:, **)
        steps = [{ "key" => "start", "kind" => "create", "action_key" => pages.first.action_key }]
        candidate.steps.each_with_index do |step, index|
          steps << { "key" => "relate_#{index + 1}", "kind" => "relate", "action_key" => pages[index + 1].action_key,
                     "inputs" => { step.parent_slug => "start" }, "repeat" => true }
        end
        steps << { "key" => "finish", "kind" => "finish", "target" => { "kind" => "record", "step" => "start" } }

        ctx[:journey] = Journey.create!(
          customer: customer, entity_domain: domain, status: :draft, audience_admin: true,
          key: unique(Journey.where(customer_id: customer.id), "#{SectionSlug.for(candidate.start.name).first(40)}_journey"),
          name: I18n.t("journeys.generate.journey_name", start: candidate.start.display_label),
          definition: { "steps" => steps }.to_json
        )
      end

      def collect_errors(ctx, **)
        ctx[:errors] << I18n.t("journeys.admin.generation.no_candidates") if ctx[:errors].empty?
      end

      private

      def page_for(customer, entity, action_key, name, input)
        page = Page.launched.where(customer_id: customer.id).for_entity(entity.id).find_by(action_key: action_key) ||
               create_page(customer, entity, unique(Page.where(customer_id: customer.id), action_key), name)
        return unless page

        attach_input!(page, input) if input
        page.launch! unless page.launched?
        page
      rescue ActiveRecord::RecordInvalid
        nil
      end

      def create_page(customer, entity, action_key, name)
        version = entity.resolved_current_version
        result = Pages::Activities::CreateFromEntityVersion.call(entity: entity, version: version, customer: customer, shared: false)
        page = result.ok ? result.page : Page.where(customer_id: customer.id, entity_version_id: version&.id).first
        page&.tap { |record| record.update!({ action_key: action_key, name: name.presence || record.name }.compact) }
      end

      def attach_input!(page, input)
        config = page.configuration_json
        settings = (config["form_settings"] ||= {})
        settings["inputs"] = (Array(settings["inputs"]).reject { |row| row["field"] == input["field"] } + [input])
        page.configuration_json = config
        page.save!
      end

      def unique(scope, base)
        key = base.gsub(/[^a-z0-9_]/, "_").sub(/\A[^a-z]+/, "j").first(60)
        candidate = key
        suffix = 1
        candidate = "#{key}_#{suffix += 1}" while scope.exists?(action_key_column(scope) => candidate)
        candidate
      end

      def action_key_column(scope) = scope.klass == Journey ? :key : :action_key
    end
  end
end
```

`unique` needs `suffix = 1`, so the first collision becomes `_2`. Keep the loop exactly as written.

- [ ] **Step 4: Run the specs**

  Run `bundle exec rspec spec/services/entity_domains/journey_planner_spec.rb spec/services/journeys/activities`. Expected: all pass.

- [ ] **Step 5: Checkpoint.**

---

### Task 13: Journey builder UI (owner only)

**Files:**
- Create:
  - `app/controllers/admin/maintenance/journeys_controller.rb`, `app/controllers/admin/maintenance/journey_generations_controller.rb`
  - `app/views/admin/maintenance/journeys/{index,new,edit}.html.erb`
  - `app/views/admin/maintenance/journey_generations/new.html.erb`
  - `app/components/journeys/{list,editor,step_row}_component.{rb,html.erb}`
  - `app/javascript/controllers/journey_builder_controller.js`
- Modify: `config/routes.rb`. Add this to the tenant maintenance block next to `resources :pages` (~L502–523), using the same controller-path style as the existing maintenance resources:

  ```ruby
  resources :journeys, except: :show do
    resource :launch, only: %i[create destroy], controller: "journey_launches"
    collection do
      get :generate, to: "journey_generations#new"
      post :generate, to: "journey_generations#create"
    end
  end
  ```

- Test:
  - `spec/requests/admin/maintenance/journeys_spec.rb`, `spec/requests/admin/maintenance/journey_generations_spec.rb`
  - `spec/components/journeys/editor_component_spec.rb`, `spec/components/journeys/list_component_spec.rb`
  - `spec/javascript/controllers/journey_builder_controller.test.js`

**Interfaces:**
- Consumes: `Journeys::Activities::Save`, `Journeys::Activities::Generate`, `EntityDomains::JourneyPlanner`, `Journeys::LaunchChecks`.
- Produces: the form params `journey[name|key|description|entity_domain_id]`, `journey[visible_audiences][]`, and `journey[steps][][key|kind|page_id|label|input_from|repeat|finish_kind|finish_step|finish_page_id]`.

- [ ] **Step 1: Write the failing tests.** The request spec covers:
  - **Guards:** `it_behaves_like "an admin-guarded GET"` for the index, plus explicit cases: a tenant admin gets 403 or 404 on index, new, create and edit; a member gets 403 or 404; the platform owner on the tenant gets 200.
  - **Owner create:** valid steps redirect to edit with the `created` flash. Invalid steps re-render with the definition errors (status 422).
  - **Isolation:** editing another customer's journey returns 404.
  - **Delete:** removes the journey and its runs.
  - **Generations:** `new` lists candidate summaries ("Then: Course"); `create` redirects to the generated journey's edit page with the `generated` flash.
  - **zh-CN:** the editor renders "引导流程" with `locale: "zh-CN"`.

  Vitest:

```js
import { describe, it, expect, beforeEach } from "vitest"
import { Application } from "@hotwired/stimulus"
import JourneyBuilderController from "../../../app/javascript/controllers/journey_builder_controller"

describe("journey_builder_controller", () => {
  let application
  beforeEach(async () => {
    document.body.innerHTML = `
      <div data-controller="journey-builder">
        <template data-journey-builder-target="template"><div data-journey-builder-target="row" data-kind="create"><span data-step-position></span>
          <select data-action="change->journey-builder#changeKind"><option value="create">c</option><option value="relate">r</option></select>
          <button data-action="journey-builder#moveUp" id="up">u</button><button data-action="journey-builder#moveDown" id="down">d</button>
          <button data-action="journey-builder#remove" id="rm">x</button></div></template>
        <div data-journey-builder-target="list"></div>
        <button data-action="journey-builder#add" id="add">+</button>
      </div>`
    application = Application.start()
    application.register("journey-builder", JourneyBuilderController)
    await Promise.resolve()
  })

  const rows = () => Array.from(document.querySelectorAll("[data-journey-builder-target='list'] [data-journey-builder-target='row']"))
  const positions = () => rows().map((row) => row.querySelector("[data-step-position]").textContent)

  it("adds rows and numbers them", () => {
    document.getElementById("add").click()
    document.getElementById("add").click()
    expect(positions()).toEqual(["1", "2"])
  })

  it("moves rows up and down, ignoring moves past the ends", () => {
    document.getElementById("add").click(); document.getElementById("add").click()
    rows()[0].dataset.kind = "first"
    rows()[0].querySelector("#up").click()
    expect(rows()[0].dataset.kind).toBe("first")
    rows()[0].querySelector("#down").click()
    expect(rows()[1].dataset.kind).toBe("first")
    rows()[1].querySelector("#down").click()
    expect(rows()[1].dataset.kind).toBe("first")
  })

  it("removes a row and renumbers", () => {
    document.getElementById("add").click(); document.getElementById("add").click()
    rows()[0].querySelector("#rm").click()
    expect(positions()).toEqual(["1"])
  })

  it("records the chosen kind on the row so kind-specific fields show", () => {
    document.getElementById("add").click()
    const select = rows()[0].querySelector("select")
    select.value = "relate"
    select.dispatchEvent(new Event("change"))
    expect(rows()[0].dataset.kind).toBe("relate")
  })
})
```

- [ ] **Step 2: Run them and confirm they fail.**

- [ ] **Step 3: Implement**

```js
// app/javascript/controllers/journey_builder_controller.js
import { Controller } from "@hotwired/stimulus"

// Step list editing for the journey builder: add, remove and reorder rows,
// and expose each row's kind so Tailwind shows only the fields it needs.
export default class extends Controller {
  static targets = ["list", "template", "row"]

  add() {
    this.listTarget.appendChild(this.templateTarget.content.cloneNode(true))
    this.renumber()
  }

  remove(event) {
    this.rowFor(event).remove()
    this.renumber()
  }

  moveUp(event) {
    const row = this.rowFor(event)
    if (row.previousElementSibling) this.listTarget.insertBefore(row, row.previousElementSibling)
    this.renumber()
  }

  moveDown(event) {
    const row = this.rowFor(event)
    if (row.nextElementSibling) this.listTarget.insertBefore(row.nextElementSibling, row)
    this.renumber()
  }

  changeKind(event) {
    this.rowFor(event).dataset.kind = event.target.value
  }

  rowFor(event) {
    return event.target.closest("[data-journey-builder-target='row']")
  }

  renumber() {
    this.listTarget.querySelectorAll("[data-journey-builder-target='row']").forEach((row, index) => {
      row.querySelectorAll("[data-step-position]").forEach((el) => { el.textContent = String(index + 1) })
    })
  }
}
```

`Admin::Maintenance::JourneysController`:

```ruby
module Admin
  module Maintenance
    # Owner-only journey builder (gated by JourneyVisibility via OwnerOnlySurfaces).
    class JourneysController < ApplicationController
      before_action :find_journey, only: %i[edit update destroy]

      def index
        @journeys = Journey.for_customer(current_customer.id).includes(:entity_domain).by_name
      end

      def new
        @journey = Journey.new(customer: current_customer, audience_admin: true, entity_domain_id: params[:domain_id],
                               definition: Journeys::Definition.blank.to_h.to_json)
      end

      def create
        save(Journey.new(customer: current_customer), :new, "journeys.admin.flash.created")
      end

      def edit; end

      def update
        save(@journey, :edit, "journeys.admin.flash.updated")
      end

      def destroy
        @journey.destroy!
        redirect_to admin_maintenance_journeys_path(current_customer.id), notice: t("journeys.admin.flash.deleted")
      end

      private

      def save(journey, template, notice)
        result = Journeys::Activities::Save.call(journey: journey, params: journey_params, customer_id: current_customer.id)
        return redirect_to(edit_admin_maintenance_journey_path(current_customer.id, result.journey), notice: t(notice)) if result.ok

        @journey = result.journey || journey
        @errors = result.errors
        render template, status: :unprocessable_entity
      end

      def find_journey = @journey = Journey.for_customer(current_customer.id).find(params[:id])

      def journey_params
        params.require(:journey).permit(:name, :key, :description, :entity_domain_id, visible_audiences: [],
                                        steps: %i[key kind page_id label input_from repeat finish_kind finish_step finish_page_id])
      end
    end
  end
end
```

Saving a launched journey also runs `Journeys::LaunchChecks`. Do this inside `Save#validate` when `journey.launched?`, so a live journey can never be saved into a broken state.

`Admin::Maintenance::JourneyGenerationsController`:
- `new` loads `@domain` with `EntityDomain.for_customer(current_customer.id).find(params[:domain_id])` and builds `@candidates` with the planner over that domain's Layout section items.
- `create` calls `Journeys::Activities::Generate.call(customer: current_customer, domain_id: params[:domain_id], index: params[:index])` and redirects to edit with the `generated` flash, or back to `new` with the first error.

Components:
- **`Journeys::ListComponent.new(journeys:, customer_id:)`:**
  - a table on `sm:` and up, with columns name, status `BadgeComponent`, step count, audience labels and updated time;
  - a stacked card list on mobile;
  - each row links to edit;
  - `EmptyStateComponent` when there are no journeys.
- **`Journeys::EditorComponent.new(journey:, customer_id:, pages:, domains:, errors: [])`:**
  - wrapped in `AdminPageComponent`, with actions Save, Launch/Take offline, Preview (opens the first step's page with `?journey=<key>` in a new tab), "Create a page" (`new_admin_maintenance_page_path`, new tab) and Delete (with confirm);
  - fields: name, key, description, domain select, and audience checkboxes;
  - a `data-controller="journey-builder"` list of `StepRowComponent`, plus a `<template>` holding a blank row.
- **`Journeys::StepRowComponent.new(step:, index:, pages:, earlier_steps:)`:**
  - a row with `data-journey-builder-target="row"` and `data-kind`;
  - the shared row contains a hidden `steps[][key]` input (`step_<n>` when new) and a kind select (`changeKind`);
  - kind-specific blocks are shown with `group` / `group-data-[kind=relate]:block hidden`:
    - all working steps: page select with `steps[][page_id]`, options `pages`;
    - relate: input-from select with `steps[][input_from]`, options `earlier_steps`, and a repeat checkbox;
    - finish: finish kind (record or page), plus the finish step or finish page;
  - also a label input and up/down/remove buttons.

Every row is `grid grid-cols-1 gap-3 md:grid-cols-12`.

- [ ] **Step 4: Run the tests**

  Run `bundle exec rspec spec/requests/admin/maintenance/journeys_spec.rb spec/requests/admin/maintenance/journey_generations_spec.rb spec/components/journeys && npx vitest run --coverage`. Expected: all pass, and `journey_builder_controller.js` is at 100%.

- [ ] **Step 5: Checkpoint.**

---

### Task 14: Domain Journeys tab and "Used in journeys"

**Files:**
- Create:
  - `app/controllers/admin/domains/journeys_controller.rb`
  - `app/views/admin/domains/journeys/index.html.erb`
  - `app/components/page_builder/journey_usage_component.{rb,html.erb}`
- Modify:
  - **`config/routes.rb` L282–284:** add `resources :journeys, only: :index, module: :domains` inside `resources :domains`.
  - **`app/components/admin/domains/browse_component.rb`:**
    - `TABS = %i[entities pages journeys].freeze`;
    - `tabs` appends `{ id: :journeys, label: t("admin_misc.domains.tabs.journeys"), count: journey_count, path: helpers.admin_domain_journeys_path(customer_id, section.key), active: tab == :journeys }`, only when `JourneyVisibility.allowed?(helpers.current_user)` and `!section.ungrouped?`.
  - **`app/views/admin/maintenance/pages/_editor.html.erb`:** where `FlowsSectionComponent` used to render, add `<%= render PageBuilder::JourneyUsageComponent.new(page: @page, customer_id: current_customer.id) if JourneyVisibility.allowed?(current_user) %>`.
  - **`config/locales/admin_misc.{en,zh-CN}.yml`:** `admin_misc.domains.tabs.journeys` is "Journeys" / "引导流程".
- Test:
  - `spec/requests/admin/domains/journeys_spec.rb`
  - Extend `spec/requests/admin/domains_spec.rb`: the tab is visible to the owner and absent for an admin.
  - `spec/components/page_builder/journey_usage_component_spec.rb`

**Interfaces:**
- Consumes: `DomainBrowsing#load_domain_sections` and `#find_domain_section`; `Journeys::ListComponent`.

- [ ] **Step 1: Write the failing tests.** They check:
  - **Owner:** sees `a[data-section-nav-tab='journeys']` with the count, and the tab lists the domain's journeys with "New journey" (`new_admin_maintenance_journey_path(domain_id:)`) and "Generate journey" (`generate_admin_maintenance_journeys_path(domain_id:)`).
  - **Admin:** has no tab, and `GET /domains/:id/journeys` returns 403 or 404.
  - **Foreign domain:** 404.
  - **Usage component:** lists the journeys whose definition contains the page's action key, and shows `usage.empty` otherwise.

- [ ] **Step 2: Run them and confirm they fail.**

- [ ] **Step 3: Implement**

```ruby
# app/controllers/admin/domains/journeys_controller.rb
# frozen_string_literal: true

module Admin
  module Domains
    # A domain's journeys (owner only; gated by JourneyVisibility).
    class JourneysController < ApplicationController
      include Admin::DomainBrowsing

      def index
        load_domain_sections
        @section = find_domain_section(params[:domain_id])
        raise ActiveRecord::RecordNotFound if @section.ungrouped?

        @journeys = Journey.for_customer(current_customer.id).where(entity_domain_id: @section.domain.id).by_name
      end
    end
  end
end
```

The view renders `Admin::Domains::BrowseComponent.new(sections: @sections, section: @section, customer_id: current_customer.id, tab: :journeys)`, with `Journeys::ListComponent` inside it plus the two action buttons. `JourneyUsageComponent` queries `Journey.for_customer(customer_id).select { |journey| journey.steps_definition.action_keys.include?(@page.action_key) }` and returns nothing when the page has no action key.

- [ ] **Step 4: Run the specs**

  Run `bundle exec rspec spec/requests/admin/domains spec/requests/admin/domains_spec.rb spec/components/page_builder spec/components/admin/domains`. Expected: all pass.

- [ ] **Step 5: Checkpoint.**

---

### Task 15: Verification, release and review

**Files:** none. This task only runs things (`anysys-release-engineer`, then `anysys-tech-lead` and `anysys-code-reviewer` in parallel).

- [ ] **Step 1: Full suite** (cross-cutting, auth and tenant changes):

  `bin/rails parallel:prepare && bin/rails parallel:spec`

  Expected: 0 failures. Paste the summary line.

- [ ] **Step 2: JavaScript coverage**

  `npx vitest run --coverage`

  Expected: every file under `app/javascript/**` is at 100% lines and branches.

- [ ] **Step 3: Locale parity**

  `bundle exec rspec spec/i18n*` (or the repo's parity spec)

  Expected: the `en` and `zh-CN` key sets match.

- [ ] **Step 4: Dev server**

  `rm -f public/assets/.manifest.json && SKIP_AUTH=1 bin/rails server -b 0.0.0.0 -p 3000`

  If digested assets shadow the sources, run `bin/rails assets:clobber && bin/rails tailwindcss:build` first.

- [ ] **Step 5: Smoke test on customer 81721200, domain #5**
  1. Open `/81721200/admin/domains/5/journeys` and click "Generate journey". Pick Student.
  2. Confirm two launched pages exist: Student (`student_new`) and "Add Course for Student" (with the student locked input). Confirm a draft journey exists.
  3. Launch it from the builder.
  4. Go to `/81721200/admin/entities/99/entries/new`, create a student, and land on "Add Course for Student" with the student card showing and the progress at "Step 2 of 2".
  5. Use "Save and add another" twice, then Continue. You should land on the student's detail page with both enrolments.
  6. Repeat the run with `?locale=zh-CN` and check the Chinese strings.
  7. Check the narrow (mobile) layout of the bridge page, the journey builder and the domain tab.

- [ ] **Step 6: Update `AGENTS.md`** (requested by the user).
  - Rewrite the "Flowcharts — platform owner only" section: form pages no longer bind a flowchart (`form_settings.flowchart_id` is gone). Pages save through `Entries::Save`; a launched, customer-owned flowchart with a `trigger_timing` (`before_save` / `after_save` / `after_commit`) runs as a record automation from every writer. Customers still never see the editor or the word "flowchart".
  - Add a short "Linked Pages & Journeys" section: page `form_settings.modes` / `inputs` (locked, server-enforced) / `after_submit` (`message` / `page` / `handoff`); `JourneyRun` (DB row, SHA-256 token digest, session-pinned for anonymous visitors); `Journey` (customer-owned, built only by the platform owner via `JourneyVisibility` in `OwnerOnlySurfaces`, steps reference action keys, kinds `create` / `relate` / `finish`); the public start URL `/:cid/journeys/:key`; tenant admins run journeys but cannot build them.
  - Touch no other section.

- [ ] **Step 7: Parallel review.** Dispatch `anysys-tech-lead` (conventions: roles, URL areas, owner gate, i18n, ViewComponent/Tailwind/Stimulus purity) and `anysys-code-reviewer` (tenant scoping of `JourneyRun`/`InputBindings`, forged-input handling, transaction and rollback behaviour, N+1 in `Starter`/`LaunchChecks`) in one message. Fix what they find and re-run the affected specs.

- [ ] **Step 8: Final checkpoint.** Report the results to the user. Don't commit.

---

## Self-review

- **Coverage against the agreed design:**

  | Agreed item | Task |
  |---|---|
  | One record writer | 3, 4 |
  | Automations with timing, condition and position | 1, 2, 8 |
  | Pages without flowcharts | 4, 5 |
  | Locked inputs | 6, 7 |
  | "After submit" message and "go to page" | 6, 7 |
  | Journeys stored in the database (`journey_runs`) | 6, 9 |
  | Repeatable relate step | 10 |
  | Planner and "Generate journey" | 12 |
  | Manual building by the owner in the page builder and journey builder | 7, 13 |
  | Owner-only Journeys tab and "Used in journeys" | 14 |
  | Tenant admins run journeys from "New entry" | 10, through `Starter.for_page` |
  | Launch rules | 11 |

  Deferred to Phase 3, as agreed: branching, update and module steps, public registration continuing as a member, and the assistant operation.
- **Placeholders:** two spots ask the implementer to adapt to real names: the `let` names in the association fixtures, and the `Billing` job-spec pattern for queued-job assertions. Both name the exact file to read, and no step is left vague.
- **Name consistency:** these names are used identically across tasks: `Entries::Save::Result`, `Automations::Dispatcher::Result`, `JourneyRun#bindings_for` / `#record!` / `#records`, `Journey#steps_definition`, `Journeys::Definition::Step#display_label`, `Page#page_inputs` / `#input_slugs` / `#serves?` / `#after_submit_mode` / `#next_page_config`.


## Decisions (confirmed by the user, 2026-11-12)

1. **Execution mode:** subagent-driven. A fresh `anysys-*` subagent per task (model inherited), a task review after each, and the parallel tech-lead and code-reviewer pass at the end.
2. **`AGENTS.md`:** update the "Flowcharts — platform owner only" section and add a short "Linked Pages & Journeys" section (Task 15, Step 6).
3. **Salesforce-style related-list "Add" with the parent locked in:** not added. The plan stays as written.
4. **Commits:** none. A task that passes review is staged with `git add`, so the next task's review covers only its unstaged changes.
