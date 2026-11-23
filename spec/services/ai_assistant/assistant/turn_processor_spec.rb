# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiAssistant::Assistant::TurnProcessor do
  let(:customer) { create(:customer) }
  let(:admin) { create(:user, :admin, customer: customer) }
  let(:conversation) { create(:ai_assistant_conversation, customer: customer, user: admin) }
  let(:owner_conversation) do
    create(:ai_assistant_conversation, customer: customer, user: find_or_create_platform_owner)
  end

  def session_for(convo)
    AiAssistant::Assistant::Tools::Session.new(
      customer: customer,
      viewer: convo.user,
      conversation: convo
    )
  end

  let!(:domain) { create(:entity_domain, customer: customer, name: "Academics") }

  def create_tool(name)
    { "tool" => "create_entity", "arguments" => { "domain" => domain.name, "entities" => [{ "name" => name, "attributes" => [{ "name" => "Title" }] }] } }.to_json
  end

  def update_tool(name)
    {
      "tool" => "update_entity",
      "arguments" => {
        "updates" => [
          {
            "entity" => name,
            "changes" => [{ "op" => "add_attribute", "attribute" => { "name" => "Notes", "html_type" => "textarea" } }]
          }
        ]
      }
    }.to_json
  end

  def envelope(reply, intent: "chat", flowchart: nil)
    { "intent" => intent, "reply" => reply, "flowchart" => flowchart }.compact.to_json
  end

  it "returns a complete chat turn without a flowchart follow-on for a tenant admin" do
    result = described_class.call(
      text: envelope("Pages live under Maintenance."),
      conversation: conversation,
      customer: customer,
      chat: ->(*) { raise "unused" }
    )

    expect(result.status).to eq("complete")
    expect(result.body).to eq("Pages live under Maintenance.")
    expect(result.entity_result).to be_present
    expect(result.flowchart_result).to be_nil
  end

  it "answers the platform owner's greeting without starting a flowchart design" do
    allow(FlowchartDefinitions::Assistant::Processor).to receive(:call)

    result = described_class.call(
      text: envelope("Hi! How can I help with your workspace today?"),
      conversation: owner_conversation,
      customer: customer,
      chat: ->(*) { raise "a greeting must not reach the flowchart pass" }
    )

    expect(result.status).to eq("complete")
    expect(result.body).to eq("Hi! How can I help with your workspace today?")
    expect(result.flowchart_result).to be_nil
    expect(FlowchartDefinitions::Assistant::Processor).not_to have_received(:call)
  end

  it "ignores a flowchart request that is not literally true" do
    result = described_class.call(
      text: { "intent" => "chat", "reply" => "Hello.", "flowchart" => "yes" }.to_json,
      conversation: owner_conversation,
      customer: customer,
      chat: ->(*) { raise "flowchart should not run" }
    )

    expect(result.flowchart_result).to be_nil
  end

  it "does not record a design step for a reply that wrote nothing" do
    progress = AiAssistant::Assistant::Progress.new(
      conversation: owner_conversation,
      publisher: class_double(AiAssistant::Stream, broadcast_progress: nil)
    )

    described_class.call(
      text: envelope("Hi!"),
      conversation: owner_conversation,
      customer: customer,
      chat: ->(*) { raise "unused" },
      progress: progress
    )

    expect(progress.steps).to be_empty
  end

  it "hides an optional flowchart failure for the platform owner" do
    result = described_class.call(
      text: envelope("I'll design that flowchart.", flowchart: true),
      conversation: owner_conversation,
      customer: customer,
      chat: ->(_messages, tools: nil) { { outcome: :unreachable, text: nil, raw: {} } }
    )

    expect(result.status).to eq("complete")
    expect(result.body).to eq("I'll design that flowchart.")
    expect(result.entity_result).to be_present
    expect(result.flowchart_result.status).to eq("failed")
  end

  it "does not repeat the reply when a requested flowchart pass also replies in chat" do
    flowchart_chat = { "intent" => "chat", "reply" => "Nothing to change in the flowchart." }.to_json
    result = described_class.call(
      text: envelope("I'll look at the Create Student flowchart.", flowchart: true),
      conversation: owner_conversation,
      customer: customer,
      chat: ->(_messages, tools: nil) { { outcome: :success, text: flowchart_chat, raw: {} } }
    )

    expect(result.status).to eq("complete")
    expect(result.body).to eq("I'll look at the Create Student flowchart.")
    expect(result.flowchart_result.intent).to eq("chat")
  end

  it "appends the flowchart pass's clarifying question for the platform owner" do
    flowchart_clarify = { "intent" => "clarify", "reply" => "Which trigger starts it?" }.to_json
    result = described_class.call(
      text: envelope("I can help build that flow.", flowchart: true),
      conversation: owner_conversation,
      customer: customer,
      chat: ->(_messages, tools: nil) { { outcome: :success, text: flowchart_clarify, raw: {} } }
    )

    expect(result.status).to eq("complete")
    expect(result.body).to eq("I can help build that flow.\n\nWhich trigger starts it?")
  end

  it "does not run a flowchart turn for a clarification" do
    result = described_class.call(
      text: envelope("Which fields?", intent: "clarify"),
      conversation: conversation,
      customer: customer,
      chat: ->(*) { raise "flowchart should not run" }
    )

    expect(result.status).to eq("complete")
    expect(result.body).to eq("Which fields?")
    expect(result.flowchart_result).to be_nil
  end

  it "copies sanitized questions and assumptions onto the result" do
    questions = [
      { "prompt" => "Which stages?", "type" => "multiple", "options" => %w[Qualification Proposal], "default" => %w[Qualification] }
    ]
    assumptions = ["Amount is in your reporting currency."]
    result = described_class.call(
      text: {
        "intent" => "clarify",
        "reply" => "Two lists are specific to your team.",
        "questions" => questions,
        "assumptions" => assumptions
      }.to_json,
      conversation: conversation,
      customer: customer,
      chat: ->(*) { raise "unused" }
    )

    expect(result.status).to eq("complete")
    expect(result.questions).to eq(AiAssistant::Assistant::Questions.sanitize(questions))
    expect(result.assumptions).to eq(assumptions)
    expect(result.entity_result.questions).to eq(result.questions)
    expect(result.entity_result.assumptions).to eq(result.assumptions)
  end

  it "does not run a flowchart follow-on when the envelope carries questions" do
    allow(FlowchartVisibility).to receive(:allowed?).and_return(true)
    allow(FlowchartDefinitions::Assistant::Processor).to receive(:call)

    result = described_class.call(
      text: {
        "intent" => "chat",
        "reply" => "Confirm the pipeline and I'll build Opportunity.",
        "questions" => [{ "prompt" => "Which stages?", "type" => "multiple", "options" => %w[A B] }]
      }.to_json,
      conversation: conversation,
      customer: customer,
      chat: ->(*) { raise "flowchart should not run" }
    )

    expect(result.status).to eq("complete")
    expect(result.questions).to be_present
    expect(result.entity_result.intent).to eq("clarify")
    expect(result.flowchart_result).to be_nil
    expect(FlowchartDefinitions::Assistant::Processor).not_to have_received(:call)
  end

  it "keeps assumptions on the result after the flowchart follow-on joins" do
    allow(FlowchartVisibility).to receive(:allowed?).and_return(true)
    allow(FlowchartDefinitions::Assistant::Processor).to receive(:call).and_return(
      FlowchartDefinitions::Assistant::Processor::Message.new(body: "No flowchart change.", status: "complete")
    )

    result = described_class.call(
      text: {
        "intent" => "chat",
        "reply" => "Created Student.",
        "assumptions" => ["Amount is in your reporting currency."],
        "flowchart" => true
      }.to_json,
      conversation: conversation,
      customer: customer,
      chat: ->(*) { raise "flowchart chat is stubbed" }
    )

    expect(result.assumptions).to eq(["Amount is in your reporting currency."])
    expect(result.flowchart_result).to be_present
    expect(FlowchartDefinitions::Assistant::Processor).to have_received(:call)
  end

  it "applies a create_entity tool call and synthesizes an applied entity result" do
    chat = ->(_messages) { { outcome: :success, text: envelope("Created Student."), raw: {} } }

    result = described_class.call(
      text: create_tool("Student"),
      conversation: conversation,
      customer: customer,
      chat: chat,
      tool_session: session_for(conversation)
    )

    expect(result.status).to eq("complete")
    expect(result.entity_result.applied).to eq(true)
    expect(result.entity_result.created).to include("Student")
    expect(result.pending_confirmation).to be_nil
    expect(Entity.find_by(customer_id: customer.id, name: "Student")).to be_present
    expect(result.body).to include("Created Student.")
    expect(result.body).to include(I18n.t("ai_assistant.assistant.apply_created", names: "Student"))
  end

  it "parks an update_entity proposal and skips the flowchart follow-on" do
    create(:entity, :with_name_status_schema, customer: customer, name: "Student")
    chat = ->(_messages) { { outcome: :success, text: envelope("I'll add Notes."), raw: {} } }

    result = described_class.call(
      text: update_tool("Student"),
      conversation: owner_conversation,
      customer: customer,
      chat: chat,
      tool_session: session_for(owner_conversation)
    )

    expect(result.status).to eq("complete")
    expect(result.entity_result.applied).to eq(false)
    expect(result.pending_confirmation).to include(
      "kind" => "operation",
      "operation" => "update_entity",
      "customer_id" => customer.id
    )
    expect(result.pending_confirmation["invocation_id"]).to be_present
    expect(result.flowchart_result).to be_nil
    expect(result.body).to include(I18n.t("ai_assistant.assistant.update_needs_confirmation"))
    expect(Entity.find_by!(customer_id: customer.id, name: "Student").property_schema_json.map { |row| row["name_slug"] })
      .not_to include("notes")
  end

  it "applies a parked operation proposal" do
    entity = create(:entity, :with_name_status_schema, customer: customer, name: "Student")
    tool_session = session_for(conversation)
    tool_session.call("update_entity", JSON.parse(update_tool("Student")).fetch("arguments"))
    proposal = tool_session.pending_proposal

    result = described_class.call(
      proposal: proposal,
      conversation: conversation,
      customer: customer,
      chat: ->(*) { raise "confirmation must not call the model" }
    )

    expect(result.confirmation_applied).to eq(true)
    expect(result.entity_result.applied).to eq(true)
    expect(result.entity_result.updated).to include("Student")
    expect(entity.reload.property_schema_json.map { |field| field["name_slug"] }).to include("notes")
    expect(result.body).to include(I18n.t("ai_assistant.assistant.apply_updated", names: "Student"))
  end

  it "returns a stale-proposal body when confirmation conflicts" do
    create(:entity, :with_name_status_schema, customer: customer, name: "Student")
    tool_session = session_for(conversation)
    tool_session.call("update_entity", JSON.parse(update_tool("Student")).fetch("arguments"))
    proposal = tool_session.pending_proposal
    Entity.find_by!(customer_id: customer.id, name: "Student").update!(description: "Changed after review")

    result = described_class.call(
      proposal: proposal,
      conversation: conversation,
      customer: customer,
      chat: ->(*) { raise "unused" }
    )

    expect(result.confirmation_applied).to eq(false)
    expect(result.status).to eq("complete")
    expect(result.body).to eq(I18n.t("ai_assistant.assistant.proposal_stale"))
  end

  describe "operations other than the entity ones" do
    it "does not report another operation's created records as entities" do
      tool_session = session_for(conversation)
      tool_session.operation_outcomes << Operations::Outcome.succeeded(
        operation: "create_flowchart", data: { "created" => [{ "name" => "Intake" }] }
      )

      result = described_class.call(
        text: envelope("Created the Intake flowchart."),
        conversation: conversation,
        customer: customer,
        chat: ->(_messages) { { outcome: :success, text: envelope("unused"), raw: {} } },
        tool_session: tool_session
      )

      expect(result.entity_result.applied).to eq(false)
      expect(result.entity_result.created).to be_empty
      expect(result.body).to eq("Created the Intake flowchart.")
    end

    def parked_proposal(operation)
      invocation = create(:operation_invocation, :awaiting_confirmation, customer: customer, user: admin,
                                                                         conversation_id: conversation.id, operation: operation)
      { "kind" => "operation", "operation" => operation, "invocation_id" => invocation.id,
        "customer_id" => customer.id, "plan" => [] }
    end

    def confirm_with(outcome)
      allow(Operations::Activities::Confirm).to receive(:call).and_return(outcome)
      described_class.call(proposal: parked_proposal(outcome.operation), conversation: conversation,
                           customer: customer, chat: ->(*) { raise "unused" })
    end

    it "replies generically when another operation's approval applies" do
      result = confirm_with(Operations::Outcome.succeeded(operation: "create_flowchart", data: { "updated" => [{ "name" => "Intake" }] }))

      expect(result.confirmation_applied).to eq(true)
      expect(result.entity_result.applied).to eq(false)
      expect(result.entity_result.updated).to be_empty
      expect(result.body).to eq(I18n.t("ai_assistant.assistant.operation_applied"))
    end

    it "replies generically when another operation's approval conflicts" do
      result = confirm_with(Operations::Outcome.conflict(operation: "create_flowchart", violations: []))

      expect(result.confirmation_applied).to eq(false)
      expect(result.body).to eq(I18n.t("ai_assistant.assistant.operation_stale"))
    end
  end

  it "fails confirmation when the invocation is no longer pending" do
    result = described_class.call(
      proposal: {
        "kind" => "operation",
        "operation" => "update_entity",
        "invocation_id" => 0,
        "customer_id" => customer.id,
        "plan" => []
      },
      conversation: conversation,
      customer: customer,
      chat: ->(*) { raise "unused" }
    )

    expect(result.status).to eq("failed")
    expect(result.confirmation_applied).to eq(false)
  end

  it "does not convert a flowchart application failure into an optional model result" do
    allow(FlowchartDefinitions::Assistant::Processor).to receive(:call)
      .and_raise(ActiveRecord::StatementInvalid, "flowchart query failed")

    expect {
      described_class.call(
        text: envelope("Checking flowcharts.", flowchart: true),
        conversation: owner_conversation,
        customer: customer,
        chat: ->(*) { raise "unused" }
      )
    }.to raise_error(ActiveRecord::StatementInvalid, "flowchart query failed")
  end

  it "leaves a started sub-system build's processing to the build instead of designing a flowchart" do
    allow(FlowchartDefinitions::Assistant::Processor).to receive(:call)
    session = session_for(owner_conversation)
    allow(session).to receive(:operation_outcomes).and_return(
      [
        Operations::Outcome.succeeded(operation: "create_entity", data: { "created" => [{ "name" => "Order" }] }),
        Operations::Outcome.succeeded(operation: "start_subsystem_build", data: { "build" => 1 })
      ]
    )

    result = described_class.call(
      text: envelope("Created Order and started the build.", flowchart: true),
      conversation: owner_conversation,
      customer: customer,
      chat: ->(*) { raise "flowchart should not run" },
      tool_session: session
    )

    expect(result.status).to eq("complete")
    expect(result.flowchart_result).to be_nil
    expect(FlowchartDefinitions::Assistant::Processor).not_to have_received(:call)
  end

  it "still designs a flowchart for the platform owner after a sub-system build was refused" do
    allow(FlowchartDefinitions::Assistant::Processor).to receive(:call).and_return(
      FlowchartDefinitions::Assistant::Processor::Message.new(body: "No flowchart change.", status: "complete")
    )
    session = session_for(owner_conversation)
    allow(session).to receive(:operation_outcomes).and_return(
      [Operations::Outcome.invalid(operation: "start_subsystem_build", violations: [Operations::Violation.new(code: "subsystem.build_active", resolution: "blocked")])]
    )

    described_class.call(
      text: envelope("I'll design that flowchart.", flowchart: true),
      conversation: owner_conversation,
      customer: customer,
      chat: ->(*) { raise "flowchart chat is stubbed" },
      tool_session: session
    )

    expect(FlowchartDefinitions::Assistant::Processor).to have_received(:call)
  end

  it "does not run the flowchart processor for a tenant admin" do
    allow(FlowchartDefinitions::Assistant::Processor).to receive(:call)
      .and_raise(ActiveRecord::StatementInvalid, "flowchart query failed")

    result = described_class.call(
      text: envelope("Checking flowcharts.", flowchart: true),
      conversation: conversation,
      customer: customer,
      chat: ->(*) { raise "unused" }
    )

    expect(result.status).to eq("complete")
    expect(result.flowchart_result).to be_nil
    expect(FlowchartDefinitions::Assistant::Processor).not_to have_received(:call)
  end

  it "maps a tool-loop provider failure to the existing failed assistant turn" do
    result = described_class.call(
      text: { "tool" => "list_catalog", "arguments" => {} }.to_json,
      conversation: conversation,
      customer: customer,
      chat: ->(_messages) { { outcome: :unreachable, text: nil, raw: {} } }
    )

    expect(result.status).to eq("failed")
    expect(result.body).to eq(I18n.t("ai_assistant.assistant.reply_failed"))
    expect(result.questions).to be_nil
    expect(result.assumptions).to be_nil
  end

  it "maps tool-loop exhaustion to the existing failed assistant turn" do
    tool_request = { "tool" => "list_catalog", "arguments" => {} }.to_json

    result = described_class.call(
      text: tool_request,
      conversation: conversation,
      customer: customer,
      chat: lambda do |_messages|
        { outcome: :success, text: tool_request, raw: {} }
      end
    )

    expect(result.status).to eq("failed")
    expect(result.body).to eq(I18n.t("ai_assistant.assistant.reply_failed"))
  end

  describe "website documents" do
    let(:document) do
      {
        intent: "apply_website",
        reply: "Here is a first draft of your home page.",
        pages: [
          {
            title: "Home",
            sections: [
              { type: "rich_text", props: { heading: "Fresh bread daily", body: "Baked before sunrise." } }
            ]
          }
        ]
      }.to_json
    end

    it "builds website pages without running the entity or flowchart passes" do
      enable_module!("website", customer)
      allow(FlowchartDefinitions::Assistant::Processor).to receive(:call)

      result = described_class.call(
        text: document,
        conversation: owner_conversation,
        customer: customer,
        chat: ->(*) { raise "a valid document must not call the model" }
      )

      expect(result.status).to eq("complete")
      expect(result.entity_result).to be_nil
      expect(result.flowchart_result).to be_nil
      expect(result.website_result.applied).to eq(true)
      page = result.website_result.pages.last
      expect(page).to have_attributes(customer_id: customer.id, title: "Home", published: false)
      expect(FlowchartDefinitions::Assistant::Processor).not_to have_received(:call)
    end

    it "reports the progress step for the website pass" do
      enable_module!("website", customer)
      progress = AiAssistant::Assistant::Progress.new(
        conversation: conversation,
        publisher: class_double(AiAssistant::Stream, broadcast_progress: nil)
      )

      described_class.call(
        text: document,
        conversation: conversation,
        customer: customer,
        chat: ->(*) { raise "unused" },
        progress: progress
      )

      expect(progress.steps.map(&:key)).to eq([:website])
    end

    it "writes nothing when the Website module is off" do
      result = described_class.call(
        text: document,
        conversation: conversation,
        customer: customer,
        chat: ->(*) { raise "unused" }
      )

      expect(result.body).to eq(I18n.t("ai_assistant.assistant.website.module_disabled"))
      expect(result.website_result.applied).to be_falsey
      expect(WebsitePage.where(customer_id: customer.id)).to be_empty
    end
  end

  it "rejects a stored flowchart proposal for a tenant admin" do
    allow(FlowchartDefinitions::Assistant::Processor).to receive(:call)
    proposal = {
      "kind" => "flowchart",
      "document" => { "intent" => "apply_flowchart", "reply" => "Creating flow." }
    }

    result = described_class.call(
      proposal: proposal,
      conversation: conversation,
      customer: customer,
      chat: ->(*) { raise "confirmation must not call the model" }
    )

    expect(result.status).to eq("failed")
    expect(result.body).to eq(I18n.t("ai_assistant.assistant.reply_failed"))
    expect(FlowchartDefinitions::Assistant::Processor).not_to have_received(:call)
  end
end
