# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Operations API assistant clarification" do
  let(:customer) { create(:customer) }
  let(:admin) { create(:user, :admin, customer: customer) }
  let(:conversation) { create(:ai_assistant_conversation, customer: customer, user: admin) }
  let(:user_message) do
    create(:ai_assistant_message, customer: customer, conversation: conversation, role: "user", body: "Build Opportunity.")
  end
  let(:generation) do
    AiAssistant::Assistant::GenerationLifecycle.start!(
      conversation: conversation,
      user_message: user_message
    )
  end
  let(:vendor) { { calls: 0, messages: [] } }
  let(:broadcast_html) { [] }

  around { |example| Current.set(customer: customer) { example.run } }

  before do
    enable_ai_assistant_module!(customer)
    create(:ai_assistant_provider_settings)
    allow(Turbo::StreamsChannel).to receive(:broadcast_append_to) do |*_args, **kwargs|
      broadcast_html << kwargs[:html].to_s
    end
    allow(Turbo::StreamsChannel).to receive(:broadcast_remove_to)
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
    allow(Turbo::StreamsChannel).to receive(:broadcast_update_to)
  end

  def envelope(reply, intent: "chat", **extra)
    { "intent" => intent, "reply" => reply }.merge(extra).to_json
  end

  let!(:domain) { create(:entity_domain, customer: customer, name: "Academics") }

  def create_tool(name)
    {
      "tool" => "create_entity",
      "arguments" => {
        "domain" => domain.name,
        "entities" => [{ "name" => name, "attributes" => [{ "name" => "Title" }] }]
      }
    }.to_json
  end

  def stub_vendor_chat(*texts)
    queue = texts.dup
    allow_any_instance_of(AiAssistant::Providers::OpenaiWhisper).to receive(:chat) do |*args, **kwargs|
      vendor[:calls] += 1
      vendor[:messages] << (kwargs[:messages] || args.find { |arg| arg.is_a?(Array) })
      text = queue.shift || envelope("Done.")
      { outcome: :success, text: text, raw: {} }
    end
  end

  def reset_vendor_capture
    vendor[:calls] = 0
    vendor[:messages] = []
  end

  def run_reply(for_generation = generation)
    AiAssistant::Activities::Reply.call(generation: for_generation)
  end

  def user_turn!(body, metadata: {})
    message = create(
      :ai_assistant_message,
      customer: customer,
      conversation: conversation,
      role: "user",
      body: body,
      metadata: metadata
    )
    next_generation = AiAssistant::Assistant::GenerationLifecycle.start!(
      conversation: conversation,
      user_message: message
    )
    reset_vendor_capture
    run_reply(next_generation)
    { message: message, generation: next_generation }
  end

  def last_assistant
    conversation.messages.where(role: "assistant").order(:id).last
  end

  def history_text_for(messages)
    Array(messages).drop(1).map { |message| message[:content] || message["content"] }.join("\n")
  end

  def message_html(message)
    ApplicationController.render(AiAssistant::MessageComponent.new(message: message), layout: false)
  end

  it "sanitizes clarify questions and assumptions, writes no entity, and renders the question card" do
    long_option = "O" * (AiAssistant::Assistant::Questions::MAX_OPTION_LENGTH + 1)
    raw_questions = [
      {
        "prompt" => "Which stages does your pipeline use?",
        "type" => "multiple",
        "options" => ["Qualification", "Won", long_option, "Proposal"],
        "default" => ["Qualification", "Won"]
      },
      {
        "prompt" => "Opening hours",
        "type" => "text",
        "default" => "Mon–Sat 8:00–18:00"
      },
      "not-a-hash",
      { "prompt" => "Third?", "type" => "text", "default" => "A3" },
      { "prompt" => "Fourth?", "type" => "text", "default" => "A4" },
      { "prompt" => "Fifth?", "type" => "text", "default" => "A5" },
      { "prompt" => "Sixth extra?", "type" => "text", "default" => "A6" },
      { "prompt" => "Seventh extra?", "type" => "text", "default" => "A7" }
    ]
    raw_assumptions = [
      "Amount is in your reporting currency.",
      "  Amount is in your reporting currency.  ",
      "Statuses are team-specific."
    ]
    sanitized = AiAssistant::Assistant::Questions.sanitize(raw_questions)
    assumptions = AiAssistant::Assistant::Questions.sanitize_assumptions(raw_assumptions)

    stub_vendor_chat(
      envelope(
        "Two lists are specific to your team.",
        intent: "clarify",
        "questions" => raw_questions,
        "assumptions" => raw_assumptions
      )
    )

    expect { run_reply }.not_to change(Entity, :count)

    reply = last_assistant
    expect(reply.status).to eq("complete")
    expect(reply.metadata_json["questions"]).to eq(sanitized)
    expect(reply.metadata_json["questions"].map { |row| row["id"] }).to eq(%w[q1 q2 q3 q4 q5])
    expect(reply.metadata_json["questions"].size).to eq(AiAssistant::Assistant::Questions::MAX_QUESTIONS)
    expect(reply.metadata_json["questions"][0]["options"]).not_to include(long_option)
    expect(reply.metadata_json["assumptions"]).to eq(assumptions)
    expect(sanitized.map { |row| row["prompt"] }).not_to include("Seventh extra?")

    html = broadcast_html.join + message_html(reply)
    expect(html).to include('data-controller="ai-assistant-questions"')
  end

  it "replays the questions note and treats a composed card answer as an ordinary create turn" do
    questions = [
      {
        "prompt" => "Which stages?",
        "type" => "multiple",
        "options" => ["Qualification", "Won", "Lost"],
        "default" => ["Qualification"]
      },
      {
        "prompt" => "Opening hours",
        "type" => "text",
        "default" => "Mon–Sat 8:00–18:00"
      }
    ]
    stub_vendor_chat(
      envelope(
        "Confirm the pipeline.",
        intent: "clarify",
        "questions" => questions,
        "assumptions" => ["Amount is in your reporting currency."]
      )
    )
    run_reply

    stub_vendor_chat(create_tool("Opportunity"), envelope("Created Opportunity."))
    user_turn!("Which stages?\nQualification, Won")

    expect(vendor[:calls]).to eq(2)
    history = history_text_for(vendor[:messages].first)
    expect(history).to include("You asked these questions")
    expect(history).to include("Which stages?")
    expect(Entity.find_by(customer_id: customer.id, name: "Opportunity")).to be_present
  end

  it "stores a chat envelope that carries questions as clarify and skips the flowchart follow-on" do
    allow(FlowchartVisibility).to receive(:allowed?).and_return(true)
    expect(FlowchartDefinitions::Assistant::Processor).not_to receive(:call)

    stub_vendor_chat(
      envelope(
        "A few details first.",
        intent: "chat",
        "questions" => [{
          "prompt" => "Name of the entity?",
          "type" => "text",
          "default" => "Student"
        }]
      )
    )
    run_reply

    reply = last_assistant
    expect(reply.status).to eq("complete")
    expect(reply.metadata_json["questions"]).to eq(
      AiAssistant::Assistant::Questions.sanitize([
        { "prompt" => "Name of the entity?", "type" => "text", "default" => "Student" }
      ])
    )
    expect(Entity.where(customer_id: customer.id)).to be_empty
  end

  it "persists the zh-CN declined body when a zh-CN admin types no through ReplyJob" do
    zh_admin = create(:user, :admin, customer: customer, locale: "zh-CN")
    zh_conversation = create(:ai_assistant_conversation, customer: customer, user: zh_admin)
    create(:entity, :with_name_status_schema, customer: customer, name: "Student")
    park_message = create(
      :ai_assistant_message,
      customer: customer,
      conversation: zh_conversation,
      role: "user",
      body: "Add notes to Student."
    )
    park_generation = AiAssistant::Assistant::GenerationLifecycle.start!(
      conversation: zh_conversation,
      user_message: park_message
    )
    stub_vendor_chat(
      {
        "tool" => "update_entity",
        "arguments" => {
          "updates" => [{
            "entity" => "Student",
            "changes" => [{ "op" => "add_attribute", "attribute" => { "name" => "Notes", "html_type" => "textarea" } }]
          }]
        }
      }.to_json,
      envelope("I'll add Notes.")
    )
    run_reply(park_generation)

    decline_message = create(
      :ai_assistant_message,
      customer: customer,
      conversation: zh_conversation,
      role: "user",
      body: "no"
    )
    decline_generation = AiAssistant::Assistant::GenerationLifecycle.start!(
      conversation: zh_conversation,
      user_message: decline_message
    )
    reset_vendor_capture
    allow_any_instance_of(AiAssistant::Providers::OpenaiWhisper).to receive(:chat) do
      vendor[:calls] += 1
      raise "vendor must not be called"
    end

    AiAssistant::ReplyJob.perform_now(decline_generation.id)

    reply = zh_conversation.messages.where(role: "assistant").order(:id).last
    expect(vendor[:calls]).to eq(0)
    expect(reply.body).to eq(I18n.t("ai_assistant.assistant.plan.declined", locale: :"zh-CN"))
    expect(reply.body).not_to eq(I18n.t("ai_assistant.assistant.plan.declined", locale: :en))
  end
end
