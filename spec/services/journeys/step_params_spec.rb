# frozen_string_literal: true

require "rails_helper"

RSpec.describe Journeys::StepParams do
  let(:customer) { create(:customer) }

  include JourneyPageHelpers
  include_context "student course association"

  def page(**attributes)
    Current.set(customer: attributes[:customer] || customer) do
      create(:page, { customer: customer, entity: student_entity }.merge(attributes))
    end
  end

  def shared_page(**attributes)
    Current.set(customer: customer) { create(:page, :shared, **attributes) }
  end

  def to_definition(rows) = described_class.to_definition(rows, customer_id: customer.id)

  let(:relate_page) do
    Current.set(customer: customer) do
      create(:page, customer: customer, entity: bridge_entity, name: "Add course", action_key: "student_add_course",
                    configuration: { form_settings: { inputs: [{ field: "student", entity_id: student_entity.id }] },
                                     pages: [{ id: "page_1", fields: [] }] }.to_json)
    end
  end

  it "maps builder rows to steps, ending in the finish row" do
    start = page(name: "Student New")
    rows = [
      { "key" => "start", "page_id" => start.id.to_s, "label" => " Register ", "optional" => "1", "repeat" => "1",
        "inputs" => { "student" => "start" } },
      { "page_id" => relate_page.id.to_s, "inputs" => { "student" => " start ", "ignored" => "x" },
        "repeat" => "1", "optional" => "1" },
      { "finish_kind" => "record", "finish_step" => "start", "finish_message" => " Thanks " }
    ]

    expect(to_definition(rows)).to eq("steps" => [
      { "key" => "start", "kind" => "create", "action_key" => "student_new_#{start.id}", "label" => "Register",
        "inputs" => {}, "repeat" => false, "optional" => false },
      { "key" => "step_2", "kind" => "relate", "action_key" => "student_add_course",
        "inputs" => { "student" => "start" }, "repeat" => true, "optional" => true },
      { "key" => "step_3", "kind" => "finish", "target" => { "kind" => "record", "step" => "start", "message" => "Thanks" } }
    ])
    expect(start.reload.action_key).to eq("student_new_#{start.id}")
  end

  describe "a start from an existing record" do
    let(:rows) do
      [{ "key" => "courses", "page_id" => relate_page.id.to_s, "inputs" => { "student" => "record" }, "repeat" => "1", "optional" => "1" },
       { "finish_kind" => "record", "finish_step" => "record" }]
    end

    it "opens with a record step and lets the first row fill, repeat and be skipped" do
      start = ActionController::Parameters.new(kind: "record", entity_id: " #{student_entity.id} ", key: "").permit!
      definition = described_class.to_definition(rows, customer_id: customer.id, start: start)

      expect(definition["steps"].first(2)).to eq([
        { "key" => "record", "kind" => "record", "entity_id" => student_entity.id.to_s },
        { "key" => "courses", "kind" => "relate", "action_key" => "student_add_course",
          "inputs" => { "student" => "record" }, "repeat" => true, "optional" => true }
      ])
      expect(Journeys::Definition.new(definition)).to be_valid
    end

    it "keeps a posted record key, and ignores a start that creates or is missing" do
      keyed = described_class.to_definition(rows, customer_id: customer.id, start: { "kind" => "record", "entity_id" => "7", "key" => "learner" })
      expect(keyed["steps"].first).to eq("key" => "learner", "kind" => "record", "entity_id" => "7")

      [{ "kind" => "create", "entity_id" => "7" }, nil, "record"].each do |start|
        first = described_class.to_definition(rows, customer_id: customer.id, start: start)["steps"].first
        expect(first).to include("key" => "courses", "kind" => "create", "inputs" => {}, "repeat" => false, "optional" => false)
      end
    end

    it "carries the start condition's field and its stripped, unique values" do
      start = ActionController::Parameters.new(kind: "record", entity_id: "7", key: "",
                                               when: { field: " status ", in: [" Submitted ", "", "Submitted", "Approved"] }).permit!

      first = described_class.to_definition(rows, customer_id: customer.id, start: start)["steps"].first
      expect(first).to eq("key" => "record", "kind" => "record", "entity_id" => "7",
                          "when" => { "field" => "status", "in" => %w[Submitted Approved] })
    end

    it "drops a condition without a field, and keeps one without values so the definition asks for them" do
      [{ "field" => " ", "in" => ["Submitted"] }, "junk", nil].each do |condition|
        start = { "kind" => "record", "entity_id" => "7", "when" => condition }
        expect(described_class.to_definition(rows, customer_id: customer.id, start: start)["steps"].first).not_to have_key("when")
      end

      definition = described_class.to_definition(rows, customer_id: customer.id,
                                                       start: { "kind" => "record", "entity_id" => "7", "when" => { "field" => "status" } })
      expect(definition["steps"].first["when"]).to eq("field" => "status", "in" => [])
      expect(Journeys::Definition.new(definition).errors)
        .to include(I18n.t("journeys.definition.errors.when_values_invalid", step: "record"))
    end

    it "lets the first row edit the start record" do
      review = page(name: "Student Review")
      definition = described_class.to_definition(
        [{ "key" => "review", "kind" => "update", "page_id" => review.id.to_s, "record" => "record" },
         { "finish_kind" => "record", "finish_step" => "record" }],
        customer_id: customer.id, start: { "kind" => "record", "entity_id" => student_entity.id.to_s }
      )

      expect(definition["steps"].second).to eq("key" => "review", "kind" => "update", "action_key" => "student_review_#{review.id}",
                                                "record" => "record", "optional" => false)
      expect(Journeys::Definition.new(definition)).to be_valid
    end
  end

  describe "a row set to edit a record" do
    it "updates the earlier step's record it names, never repeating, and may be skipped" do
      start = page(name: "Student New")
      rows = [
        { "key" => "start", "page_id" => start.id.to_s },
        { "key" => "review", "kind" => "update", "page_id" => start.id.to_s, "label" => " Review ", "record" => " start ",
          "inputs" => { "student" => "start" }, "repeat" => "1", "optional" => "1" },
        { "key" => "again", "kind" => "update", "page_id" => start.id.to_s, "record" => " " },
        { "finish_kind" => "record", "finish_step" => "start" }
      ]

      steps = to_definition(rows)["steps"]
      expect(steps.second).to eq("key" => "review", "kind" => "update", "action_key" => "student_new_#{start.id}",
                                 "label" => "Review", "record" => "start", "optional" => true)
      expect(steps.third).to eq("key" => "again", "kind" => "update", "action_key" => "student_new_#{start.id}", "optional" => false)
      expect(Journeys::Definition.new("steps" => steps.values_at(0, 1, 3))).to be_valid
    end

    it "never makes the lead row edit" do
      start = page(name: "Student New")
      first = to_definition([{ "key" => "start", "kind" => "update", "page_id" => start.id.to_s, "record" => "start" },
                             { "finish_kind" => "record", "finish_step" => "start" }])["steps"].first

      expect(first).to eq("key" => "start", "kind" => "create", "action_key" => "student_new_#{start.id}",
                          "inputs" => {}, "repeat" => false, "optional" => false)
    end
  end

  it "marks a later row an earlier step's processing may leave out, never the lead row" do
    start = page(name: "Student New")
    rows = [
      { "key" => "start", "page_id" => start.id.to_s, "conditional" => "1" },
      { "key" => "course", "page_id" => relate_page.id.to_s, "inputs" => { "student" => "start" }, "conditional" => "1" },
      { "key" => "review", "kind" => "update", "page_id" => start.id.to_s, "record" => "start", "conditional" => "1" },
      { "key" => "plain", "page_id" => start.id.to_s, "conditional" => "0" },
      { "finish_kind" => "record", "finish_step" => "start" }
    ]

    steps = to_definition(rows)["steps"]
    expect(steps.map { |step| step["conditional"] }).to eq([nil, true, true, nil, nil])
    expect(Journeys::Definition.new("steps" => steps)).to be_valid

    started = described_class.to_definition(rows, customer_id: customer.id, start: { "kind" => "record", "entity_id" => student_entity.id.to_s })
    expect(started["steps"].map { |step| step["conditional"] }).to eq([nil, nil, true, true, nil, nil])
  end

  describe "a start that creates a user account" do
    let(:start_page) { page(name: "Student New") }
    let(:rows) do
      [{ "key" => "start", "page_id" => start_page.id.to_s, "inputs" => { "student" => "user" }, "repeat" => "1", "optional" => "1" },
       { "finish_kind" => "record", "finish_step" => "start" }]
    end

    it "opens with a user step, and the first row creates with nothing to fill, repeat or skip" do
      start = ActionController::Parameters.new(kind: "user", entity_id: "9", key: "").permit!
      definition = described_class.to_definition(rows, customer_id: customer.id, start: start)

      expect(definition["steps"].first(2)).to eq([
        { "key" => "user", "kind" => "user" },
        { "key" => "start", "kind" => "create", "action_key" => "student_new_#{start_page.id}",
          "inputs" => {}, "repeat" => false, "optional" => false }
      ])
      expect(Journeys::Definition.new(definition)).to be_valid
    end

    it "keeps a posted key" do
      definition = described_class.to_definition(rows, customer_id: customer.id, start: { "kind" => "user", "key" => "account" })

      expect(definition["steps"].first).to eq("key" => "account", "kind" => "user")
    end
  end

  it "accepts index-keyed rows and a page finish, keying the finish page too" do
    thanks = page(name: "Thanks")
    definition = to_definition("0" => { "page_id" => relate_page.id },
                               "1" => { "finish_kind" => "page", "finish_page_id" => thanks.id.to_s,
                                        "finish_message" => "  " })

    expect(definition["steps"].last["target"]).to eq("kind" => "page", "action_key" => "thanks_#{thanks.id}")
    expect(to_definition([{}, { "finish_kind" => "elsewhere" }])["steps"].last["target"]).to be_nil
    expect(to_definition([])).to eq("steps" => [])
  end

  it "reads row and input hashes from Parameters" do
    start = page(name: "Student New")
    rows = ActionController::Parameters.new(
      "0" => { "key" => "start", "page_id" => start.id.to_s },
      "1" => { "page_id" => relate_page.id.to_s, "inputs" => { "student" => "start" }, "repeat" => "1" },
      "2" => { "finish_kind" => "record", "finish_step" => "start", "finish_message" => "Done" }
    ).permit!

    steps = to_definition(rows)["steps"]
    expect(steps.map { |step| step["kind"] }).to eq(%w[create relate finish])
    expect(steps.second).to include("inputs" => { "student" => "start" }, "repeat" => true)
    expect(steps.last["target"]).to include("message" => "Done")
  end

  it "keeps generated keys valid, bounded and unique across the tenant and shared pages" do
    unnamed = page(name: "学生登记")
    numbered = page(name: "2026 Intake")
    long = page(name: "x" * 90)
    clash = page(name: "Clash")
    page(name: "Taken", action_key: "clash_#{clash.id}")
    shared_page(name: "Shared", action_key: "clash_#{clash.id}_2")

    keys = to_definition([unnamed, numbered, long, clash, {}].map { |item| item.is_a?(Page) ? { "page_id" => item.id } : item })["steps"]
           .filter_map { |step| step["action_key"] }

    expect(keys).to eq(["page_#{unnamed.id}", "page_2026_intake_#{numbered.id}", "#{'x' * (62 - long.id.to_s.length)}_#{long.id}",
                        "clash_#{clash.id}_3"])
    expect(keys).to all(match(PageVisibility::ACTION_KEY))
    expect(keys.map(&:length).max).to eq(63)
  end

  it "uses a shared page's key but never writes one onto a shared or another tenant's page" do
    keyed_shared = shared_page(name: "Shared keyed", action_key: "shared_signup")
    unkeyed_shared = shared_page(name: "Shared unkeyed")
    foreign = page(name: "Foreign", customer: create(:customer), entity: create(:entity))

    steps = to_definition([keyed_shared, unkeyed_shared, foreign, {}].map { |item| item.is_a?(Page) ? { "page_id" => item.id } : item })["steps"]

    expect(steps.first(3).map { |step| step["action_key"] }).to eq(["shared_signup", nil, nil])
    expect(Page.unscoped.find(unkeyed_shared.id).action_key).to be_nil
    expect(Page.unscoped.find(foreign.id).action_key).to be_nil
  end

  it "treats a page that locks nothing as a create, even in the middle" do
    plain = page(name: "Plain")
    step = to_definition([{ "key" => "start" }, { "page_id" => plain.id, "inputs" => { "student" => "start" },
                                                   "repeat" => "1", "optional" => "1" }, {}])["steps"].second

    expect(step).to include("kind" => "create", "inputs" => {}, "repeat" => false, "optional" => true)
  end

  it "drops blank input values and fields the page does not lock" do
    step = to_definition([
      { "key" => "start" },
      { "page_id" => relate_page.id, "inputs" => { "student" => "  ", "course" => "start" } },
      {}
    ])["steps"].second

    expect(step).to include("kind" => "relate", "inputs" => {})
  end

  it "truncates the finish message" do
    message = "x" * (described_class::MESSAGE_LENGTH + 10)
    target = to_definition([{ "key" => "start" }, { "finish_kind" => "record", "finish_step" => "start",
                                                    "finish_message" => message }])["steps"].last["target"]

    expect(target["message"]).to eq("x" * described_class::MESSAGE_LENGTH)
  end

  it "takes kind from whether the page locks records, never from the post, so the first row keeps no input, repeat or optional" do
    start = page(name: "Student New")
    rows = [
      { "key" => "start", "kind" => "relate", "page_id" => relate_page.id.to_s, "inputs" => { "student" => "start" },
        "repeat" => "1", "optional" => "1" },
      { "key" => "courses", "kind" => "finish", "page_id" => relate_page.id.to_s, "inputs" => { "student" => "start" } },
      { "key" => "more", "kind" => "create", "page_id" => start.id.to_s, "repeat" => "1", "optional" => "1" },
      { "key" => "done", "kind" => "relate", "finish_kind" => "record", "finish_step" => "start" }
    ]

    steps = to_definition(rows)["steps"]
    expect(steps.map { |step| step["kind"] }).to eq(%w[create relate create finish])
    expect(steps.first).to include("inputs" => {}, "repeat" => false, "optional" => false)
    expect(steps.second).to include("inputs" => { "student" => "start" }, "repeat" => false, "optional" => false)
    expect(steps.third).to include("inputs" => {}, "repeat" => false, "optional" => true)
  end
end
