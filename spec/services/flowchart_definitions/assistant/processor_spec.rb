# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartDefinitions::Assistant::Processor do
  let_it_be(:customer) { create(:customer) }
  let_it_be(:user) { create(:user, customer: customer) }
  let(:conversation) { create(:ai_assistant_conversation, customer: customer, user: user) }

  def apply_payload(reply, flowchart, updates_confirmed: false)
    { intent: "apply_flowchart", reply: reply, flowchart: flowchart, updates_confirmed: updates_confirmed }.to_json
  end

  def create_fill(extra_step: nil)
    actions = [
      ["p1", "new_model", { "resultVar" => "model" }],
      ["p2", "build_contract", nil],
      ["p3", "validate_contract", nil],
      ["p4", "save_model", nil]
    ]
    actions << ["p5", extra_step["action"], extra_step["config"]] if extra_step
    processes = actions.map do |id, step_action, config|
      step = { "action" => step_action }
      step["config"] = config if config
      { "id" => id, "type" => "process", "label" => step_action, "steps" => [step] }
    end
    ids = %w[start_1] + actions.map(&:first) + %w[end_1]
    {
      "name" => "Create Student",
      "elements" => [
        { "id" => "start_1", "type" => "start", "label" => "Start" },
        *processes,
        { "id" => "end_1", "type" => "end", "label" => "End" }
      ],
      "connections" => ids.each_cons(2).map { |from, to| { "from" => from, "to" => to } }
    }
  end

  def process_actions(record)
    record.elements.select { |el| el["type"] == "process" }.flat_map do |el|
      Array(el.dig("properties", "steps")).map { |step| step["action"] }
    end
  end

  def run(texts, confirmed: false)
    queue = Array(texts)
    described_class.call(
      conversation: conversation,
      customer: customer,
      confirmed: confirmed,
      chat: ->(_messages) { { outcome: :success, text: queue.shift, raw: {} } }
    )
  end

  it "returns a chat reply and does not persist" do
    expect {
      result = run([{ intent: "chat", reply: "", flowchart: nil }.to_json])
      expect(result.status).to eq("complete")
      expect(result.body).to eq("")
      expect(result.intent).to eq("chat")
    }.not_to change(Flowchart, :count)
  end

  it "reports the clarify intent of a reply that asks for flowchart details" do
    result = run([{ intent: "clarify", reply: "Which trigger starts it?", flowchart: nil }.to_json])

    expect(result.body).to eq("Which trigger starts it?")
    expect(result.intent).to eq("clarify")
  end

  it "persists a create" do
    result = run([apply_payload("Creating Create Student.", create_fill)])
    expect(result.status).to eq("complete")
    expect(result.body).to include("Create Student")
    expect(Flowchart.find_by!(customer_id: customer.id, name: "Create Student")).to be_launched
  end

  it "blocks an unconfirmed update" do
    run([apply_payload("Creating Create Student.", create_fill)])
    record = Flowchart.find_by!(customer_id: customer.id, name: "Create Student")
    original_head = record.current_version_id
    result = run([apply_payload("I can add a log step. Proceed?", create_fill(extra_step: { "action" => "log", "config" => { "messageTemplate" => "step", "includeBacktrace" => false, "structured" => false } }))])
    expect(result.body).to include(I18n.t("ai_assistant.assistant.flowchart_needs_confirmation"))
    expect(process_actions(record.reload)).not_to include("log")
    expect(record).to be_launched
    expect(record.current_version_id).to eq(original_head)
  end

  it "applies a confirmed update as a new version" do
    run([apply_payload("Creating Create Student.", create_fill)])
    record = Flowchart.find_by!(customer_id: customer.id, name: "Create Student")
    expect(record.flowchart_versions.count).to eq(1)
    result = run([apply_payload(
      "I can update Create Student. Proceed?",
      create_fill(extra_step: { "action" => "log", "config" => { "messageTemplate" => "step", "includeBacktrace" => false, "structured" => false } }),
      updates_confirmed: true
    )], confirmed: true)
    expect(result.body).to eq(
      I18n.t(
        "ai_assistant.assistant.apply_flowchart_updated",
        names: "Create Student"
      )
    )
    record.reload
    expect(record).to be_launched
    expect(process_actions(record)).to include("log")
    expect(record.flowchart_versions.count).to eq(2)
  end

  it "preserves an existing manual draft through a confirmed update" do
    record = create(:flowchart, :draft, customer: customer, name: "Create Student", configuration: FlowchartDefinitions::Normalizer.call(create_fill).configuration.to_json)
    result = run([apply_payload(
      "Updating Create Student.",
      create_fill(extra_step: { "action" => "log", "config" => { "messageTemplate" => "step", "includeBacktrace" => false, "structured" => false } })
    )], confirmed: true)

    expect(result.updated).to eq(record.name)
    expect(record.reload).to be_draft
    expect(process_actions(record)).to include("log")
    expect(record.flowchart_versions.count).to eq(2)
  end

  it "feeds launch-validation failures into repair before creating one launched version" do
    bad = create_fill(extra_step: {
      "action" => "api_call", "config" => { "url" => "ctx[:missing_api_url]", "method" => "GET" }
    })
    queue = [apply_payload("Creating.", bad), apply_payload("Repaired.", create_fill)]
    sent = []
    result = nil

    expect {
      result = described_class.call(
        conversation: conversation, customer: customer,
        chat: lambda do |messages|
          sent << messages
          if sent.size == 2
            expect(Flowchart.where(customer_id: customer.id)).to be_empty
            expect(FlowchartVersion.where(customer_id: customer.id)).to be_empty
          end
          { outcome: :success, text: queue.shift, raw: {} }
        end
      )
    }.to change(Flowchart, :count).by(1).and change(FlowchartVersion, :count).by(1)

    expect(sent.size).to eq(2)
    expect(sent.last.last[:content]).to include(
      I18n.t("maint_core.flowcharts.server_validation.missing_input", key: "missing_api_url")
    )
    expect(result.created).to eq("Create Student")
    expect(Flowchart.find_by!(customer_id: customer.id, name: "Create Student")).to be_launched
  end

  it "repairs an invalid action then persists" do
    bad = create_fill
    bad["elements"][1]["steps"] = [{ "action" => "not_a_real_action" }]
    result = run([
      apply_payload("Creating.", bad),
      apply_payload("Creating Create Student.", create_fill)
    ])
    expect(result.status).to eq("complete")
    expect(Flowchart.find_by(customer_id: customer.id, name: "Create Student")).to be_present
  end

  it "feeds screen errors into repair and persists the screened document" do
    logged = create_fill(extra_step: { "action" => "log", "config" => { "messageTemplate" => "step", "includeBacktrace" => false, "structured" => false } })
    screened = []
    queue = [apply_payload("Creating Create Student.", create_fill)]
    repair_errors = nil
    result = described_class.call(
      conversation: conversation,
      customer: customer,
      text: apply_payload("Creating.", logged),
      chat: lambda do |messages|
        repair_errors = messages.last[:content]
        { outcome: :success, text: queue.shift, raw: {} }
      end,
      screen: lambda do |normalized|
        actions = normalized.configuration["elements"].flat_map { |el| Array(el.dig("properties", "steps")).map { |step| step["action"] } }
        screened << actions
        actions.include?("log") ? ["Remove the log step."] : []
      end
    )

    expect(result.status).to eq("complete")
    expect(screened.size).to eq(2)
    expect(repair_errors).to include("Remove the log step.")
    record = Flowchart.find_by!(customer_id: customer.id, name: "Create Student")
    expect(process_actions(record)).not_to include("log")
  end

  it "does not let a repair overwrite an existing flowchart without confirmation" do
    run([apply_payload("Creating Create Student.", create_fill)])
    bad = create_fill
    bad["name"] = "Other Student"
    bad["elements"][1]["steps"] = [{ "action" => "not_a_real_action" }]
    hijack = create_fill(extra_step: { "action" => "log", "config" => { "messageTemplate" => "step", "includeBacktrace" => false, "structured" => false } })
    result = run([
      apply_payload("Creating Other Student.", bad),
      apply_payload("Updating Create Student.", hijack, updates_confirmed: true)
    ])
    expect(result.body).to include(I18n.t("ai_assistant.assistant.flowchart_needs_confirmation"))
    expect(Flowchart.find_by(customer_id: customer.id, name: "Other Student")).to be_nil
    record = Flowchart.find_by!(customer_id: customer.id, name: "Create Student")
    expect(process_actions(record)).not_to include("log")
  end

  it "never repairs or retargets a confirmed stored flowchart document" do
    flow_a = create_fill
    flow_a["name"] = "Flow A"
    flow_b = create_fill
    flow_b["name"] = "Flow B"
    run([apply_payload("Creating Flow A.", flow_a)])
    run([apply_payload("Creating Flow B.", flow_b)])

    invalid_flow_a = flow_a.deep_dup
    invalid_flow_a["elements"][1]["steps"] = [{ "action" => "not_a_real_action" }]
    retargeted_flow_b = create_fill(extra_step: { "action" => "log", "config" => { "messageTemplate" => "step", "includeBacktrace" => false, "structured" => false } })
    retargeted_flow_b["name"] = "Flow B"
    chat_calls = 0

    result = described_class.call(
      conversation: conversation,
      customer: customer,
      text: apply_payload("Updating Flow A.", invalid_flow_a),
      confirmed: true,
      chat: lambda do |_messages|
        chat_calls += 1
        {
          outcome: :success,
          text: apply_payload("Updating Flow B.", retargeted_flow_b),
          raw: {}
        }
      end
    )

    expect(chat_calls).to eq(0)
    expect(result.status).to eq("complete")
    flow_b_record = Flowchart.find_by!(customer_id: customer.id, name: "Flow B")
    expect(process_actions(flow_b_record)).not_to include("log")
  end

  it "fail-closes on unparseable text" do
    result = run(["not json"])
    expect(result.status).to eq("failed")
    expect(result.body).to eq(I18n.t("ai_assistant.assistant.extraction_invalid"))
  end

  it "does not swallow an unexpected exception from the chat boundary" do
    expect {
      described_class.call(
        conversation: conversation,
        customer: customer,
        chat: ->(_messages) { raise RuntimeError, "boom" }
      )
    }.to raise_error(RuntimeError, "boom")
  end

  it "persists Query Models config from the LLM fill" do
    flowchart = {
      "name" => "List Students",
      "elements" => [
        { "id" => "start_1", "type" => "start", "label" => "Start" },
        {
          "id" => "p1",
          "type" => "process",
          "label" => "Query Students",
          "steps" => [
            {
              "action" => "query_models",
              "config" => {
                "queryType" => "where",
                "conditions" => { "status" => "active" },
                "orderBy" => "email",
                "orderDirection" => "asc",
                "resultVar" => "models"
              }
            }
          ]
        },
        { "id" => "end_1", "type" => "end", "label" => "End" }
      ],
      "connections" => [
        { "from" => "start_1", "to" => "p1" },
        { "from" => "p1", "to" => "end_1" }
      ]
    }
    result = run([apply_payload("Creating List Students.", flowchart)])
    expect(result.status).to eq("complete")
    record = Flowchart.find_by!(customer_id: customer.id, name: "List Students")
    step = record.elements.find { |el| el["type"] == "process" }.dig("properties", "steps", 0)
    expect(step["config"]).to include(
      "queryType" => "where",
      "conditions" => { "status" => "active" },
      "orderBy" => "email"
    )
  end
end
