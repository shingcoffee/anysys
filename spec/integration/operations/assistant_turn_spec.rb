# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Operations API assistant turns" do
  let(:customer) { create(:customer) }
  let(:admin) { create(:user, :admin, customer: customer) }
  let(:conversation) { create(:ai_assistant_conversation, customer: customer, user: admin) }
  let(:user_message) do
    create(:ai_assistant_message, customer: customer, conversation: conversation, role: "user", body: "Please apply this.")
  end
  let(:generation) do
    AiAssistant::Assistant::GenerationLifecycle.start!(conversation: conversation, user_message: user_message)
  end

  around { |example| Current.set(customer: customer) { example.run } }

  def session
    @session ||= AiAssistant::Assistant::Tools::Session.new(
      customer: customer,
      viewer: admin,
      conversation: conversation,
      generation: generation
    )
  end

  def envelope(reply, intent: "chat")
    { "intent" => intent, "reply" => reply }.to_json
  end

  def tool_payload(name, arguments)
    { "tool" => name, "arguments" => arguments }.to_json
  end

  let!(:domain) { create(:entity_domain, customer: customer, name: "Academics") }

  def create_arguments
    {
      "domain" => domain.name,
      "entities" => [
        {
          "name" => "Course",
          "attributes" => [{ "name" => "Title", "html_type" => "text" }]
        },
        {
          "name" => "Student",
          "attribute_groups" => [
            { "key" => "basics", "name" => "Basics", "icon" => "folder", "color" => "indigo" }
          ],
          "attributes" => [
            {
              "name" => "Email",
              "html_type" => "email",
              "group" => "basics",
              "rules" => [{ "type" => "presence" }],
              "access" => { "visible_to" => { "admin" => true, "member" => true, "public" => false } }
            },
            {
              "name" => "Level",
              "html_type" => "select",
              "group" => "basics",
              "options" => { "source" => "static", "values" => %w[Beginner Advanced] }
            }
          ],
          "associations" => [{
            "related_entity" => "Course",
            "display_field" => "title",
            "bridge_attributes" => [{ "name" => "Enrolled On", "html_type" => "date" }]
          }]
        }
      ]
    }
  end

  def invalid_create_arguments
    {
      "domain" => domain.name,
      "entities" => [{
        "name" => "Student",
        "attributes" => [{ "name" => "Level", "html_type" => "select" }]
      }]
    }
  end

  def update_arguments(name, changes: nil)
    {
      "updates" => [{
        "entity" => name,
        "changes" => changes || [
          { "op" => "add_attribute", "attribute" => { "name" => "Notes", "html_type" => "textarea" } }
        ]
      }]
    }
  end

  def stub_chat(*texts)
    queue = texts.dup
    captured = []
    chat = lambda do |messages|
      captured << messages
      text = queue.shift || envelope("Done.")
      { outcome: :success, text: text, raw: {} }
    end
    [chat, captured]
  end

  def process_turn(text:, chat:)
    AiAssistant::Assistant::TurnProcessor.call(
      text: text,
      conversation: conversation,
      customer: customer,
      chat: chat,
      tool_session: session
    )
  end

  def last_tool_result(captured)
    payload = JSON.parse(captured.last.last[:content] || captured.last.last["content"])
    payload.fetch("tool_result")
  end

  it "creates a grouped entity with a select, rule, access flags, and a bridged association" do
    chat, = stub_chat(envelope("Created Student and Course."))

    result = process_turn(text: tool_payload("create_entity", create_arguments), chat: chat)

    expect(result.status).to eq("complete")
    expect(result.entity_result.applied).to eq(true)
    expect(result.entity_result.created).to include("Student", "Course")
    expect(result.entity_result.created).to eq(result.entity_result.created.uniq)
    expect(result.body).not_to match(/schema\.|attribute\.|entity\.not_found|attempts\.exhausted/)

    student = Entity.find_by!(customer_id: customer.id, name: "Student")
    course = Entity.find_by!(customer_id: customer.id, name: "Course")
    expect(Entity.where(customer_id: customer.id, category: :bridge).pluck(:name))
      .to include("assoc_student_course")

    by_slug = student.property_schema_json.index_by { |attr| attr["name_slug"] }
    expect(student.attribute_groups_json).to include(hash_including("id" => "basics", "name" => "Basics"))
    expect(by_slug["email"]).to include("html_type" => "email", "group_id" => "basics")
    expect(by_slug["email"]["validators"]).to include(hash_including("type" => "presence"))
    expect(by_slug["email"]["visibility"]).to include("public" => false)
    expect(by_slug["level"]["html_type"]).to eq("select")
    expect(by_slug["level"]["config"]).to include("source" => "manual")
    expect(by_slug["level"]["config"]["options"].map { |option| option["value"] }).to eq(%w[Beginner Advanced])
    expect(by_slug["level"]["validators"]).to include(
      hash_including("type" => "inclusion", "config" => { "values" => %w[Beginner Advanced] })
    )
    extras = student.associations_list.first.fetch("additional_attributes")
    expect(student.associations_list.first).to include("target_entity_name" => "Course")
    expect(extras.map { |attr| attr["name_slug"] }).to include("enrolled_on")
    expect(course.property_schema_json.map { |attr| attr["name_slug"] }).to include("title")

    invocation = OperationInvocation.find_by!(customer_id: customer.id, operation: "create_entity")
    expect(invocation).to have_attributes(
      status: "succeeded",
      channel: "assistant",
      generation_id: generation.id,
      conversation_id: conversation.id
    )

    finalized = AiAssistant::Assistant::Finalizer.call(turn: result, conversation: conversation)
    message = create(
      :ai_assistant_message,
      :assistant,
      customer: customer,
      conversation: conversation,
      body: finalized.body,
      metadata: finalized.metadata
    )
    expect(message.metadata_json.fetch("changes")).to include(
      { "kind" => "entity", "action" => "created", "name" => "Course" },
      { "kind" => "entity", "action" => "created", "name" => "Student" }
    )
  end

  it "self-corrects an invalid create and never shows violation codes to the admin" do
    chat, = stub_chat(
      tool_payload("create_entity", create_arguments),
      envelope("Created Student with a level list.")
    )

    result = process_turn(text: tool_payload("create_entity", invalid_create_arguments), chat: chat)

    expect(result.status).to eq("complete")
    expect(result.entity_result.applied).to eq(true)
    expect(result.entity_result.created).to include("Student")
    expect(result.body).to include("Created Student with a level list.")
    expect(result.body).not_to include("schema.required", "schema.invalid", "attempts.exhausted")
    expect(Entity.find_by(customer_id: customer.id, name: "Student")).to be_present
    expect(session.operation_outcomes.map(&:status)).to include("invalid", "succeeded")
  end

  it "exhausts three rejected calls for one operation and returns attempts.exhausted" do
    chat, captured = stub_chat(
      tool_payload("create_entity", invalid_create_arguments),
      tool_payload("create_entity", invalid_create_arguments),
      tool_payload("create_entity", invalid_create_arguments),
      envelope("I could not create that entity.")
    )

    result = process_turn(text: tool_payload("create_entity", invalid_create_arguments), chat: chat)

    expect(result.status).to eq("complete")
    expect(result.entity_result.applied).to eq(false)
    expect(Entity.find_by(customer_id: customer.id, name: "Student")).to be_nil
    expect(result.body).not_to include("attempts.exhausted")
    expect(last_tool_result(captured)).to include(
      "ok" => false,
      "status" => "invalid"
    )
    expect(last_tool_result(captured)["errors"]).to include(
      hash_including("code" => "attempts.exhausted", "resolution" => "blocked")
    )
  end

  it "clarifies when get_entity cannot resolve a name and has no close candidate" do
    chat, captured = stub_chat(envelope("Which record should I look up?", intent: "clarify"))

    result = process_turn(
      text: tool_payload("get_entity", "entity" => "UnicornFarm"),
      chat: chat
    )

    expect(result.status).to eq("complete")
    expect(result.entity_result.applied).to eq(false)
    expect(result.body).to eq("Which record should I look up?")
    expect(result.body).not_to include("entity.not_found")
    expect(JSON.parse(captured.first.last[:content] || captured.first.last["content"]).dig("tool_result", "errors"))
      .to include(hash_including("code" => "entity.not_found", "resolution" => "ask_user"))
  end

  it "clarifies when update_entity cannot resolve a name and has no close candidate" do
    chat, captured = stub_chat(envelope("I do not have an entity by that name. What should it be called?", intent: "clarify"))

    result = process_turn(
      text: tool_payload("update_entity", update_arguments("UnicornFarm")),
      chat: chat
    )

    expect(result.status).to eq("complete")
    expect(result.pending_confirmation).to be_nil
    expect(result.body).not_to include("entity.not_found")
    expect(JSON.parse(captured.first.last[:content] || captured.first.last["content"]).dig("tool_result", "errors"))
      .to include(hash_including("code" => "entity.not_found", "resolution" => "ask_user"))
  end

  it "parks one update proposal and rejects a second update in the same turn" do
    create(:entity, :with_name_status_schema, customer: customer, name: "Student")
    chat, captured = stub_chat(
      tool_payload("update_entity", update_arguments("Student", changes: [
        { "op" => "add_attribute", "attribute" => { "name" => "Phone", "html_type" => "tel" } }
      ])),
      envelope("I'll add Notes once you apply the plan.")
    )

    result = process_turn(text: tool_payload("update_entity", update_arguments("Student")), chat: chat)

    expect(result.status).to eq("complete")
    expect(result.entity_result.applied).to eq(false)
    expect(result.pending_confirmation).to include(
      "kind" => "operation",
      "operation" => "update_entity",
      "customer_id" => customer.id
    )
    expect(result.pending_confirmation["invocation_id"]).to be_present
    expect(result.pending_confirmation["plan"]).to be_present
    expect(Entity.find_by!(customer_id: customer.id, name: "Student").property_schema_json.map { |row| row["name_slug"] })
      .not_to include("notes", "phone")
    expect(last_tool_result(captured)["errors"]).to include(
      hash_including("code" => "proposal.already_pending")
    )
    expect(OperationInvocation.awaiting_confirmation.where(customer_id: customer.id).count).to eq(1)
  end

  it "replays an identical create in the same generation and lists the entity once" do
    chat, = stub_chat(
      tool_payload("create_entity", create_arguments),
      envelope("Created Student.")
    )

    result = process_turn(text: tool_payload("create_entity", create_arguments), chat: chat)

    expect(result.entity_result.applied).to eq(true)
    expect(result.entity_result.created).to eq(%w[Course Student])
    expect(Entity.where(customer_id: customer.id, name: %w[Course Student]).count).to eq(2)
    expect(OperationInvocation.where(customer_id: customer.id, operation: "create_entity").count).to eq(1)
    expect(session.operation_outcomes.map(&:replayed)).to include(true)
  end
end
