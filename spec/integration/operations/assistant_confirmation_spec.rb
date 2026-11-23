# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Operations API assistant confirmation" do
  let(:customer) { create(:customer) }
  let(:admin) { create(:user, :admin, customer: customer) }
  let(:conversation) { create(:ai_assistant_conversation, customer: customer, user: admin) }
  let(:user_message) do
    create(:ai_assistant_message, customer: customer, conversation: conversation, role: "user", body: "Add notes.")
  end
  let(:generation) do
    AiAssistant::Assistant::GenerationLifecycle.start!(
      conversation: conversation,
      user_message: user_message
    )
  end

  around { |example| Current.set(customer: customer) { example.run } }

  let(:vendor) { { calls: 0, messages: [] } }

  before do
    enable_ai_assistant_module!(customer)
    create(:ai_assistant_provider_settings)
    Authentication::Throttle.reset_store!
    allow(Turbo::StreamsChannel).to receive(:broadcast_append_to)
    allow(Turbo::StreamsChannel).to receive(:broadcast_remove_to)
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
    allow(Turbo::StreamsChannel).to receive(:broadcast_update_to)
  end

  after { Authentication::Throttle.reset_store! }

  def envelope(reply, intent: "chat", **extra)
    { "intent" => intent, "reply" => reply }.merge(extra).to_json
  end

  def update_tool(name)
    {
      "tool" => "update_entity",
      "arguments" => {
        "updates" => [{
          "entity" => name,
          "changes" => [{ "op" => "add_attribute", "attribute" => { "name" => "Notes", "html_type" => "textarea" } }]
        }]
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

  def stub_vendor_forbidden
    allow_any_instance_of(AiAssistant::Providers::OpenaiWhisper).to receive(:chat) do
      vendor[:calls] += 1
      raise "vendor must not be called"
    end
  end

  def reset_vendor_capture
    vendor[:calls] = 0
    vendor[:messages] = []
  end

  def run_reply(for_generation = generation)
    AiAssistant::Activities::Reply.call(generation: for_generation)
  end

  def confirm!(body: "Yes", metadata: {})
    confirmation = create(
      :ai_assistant_message,
      customer: customer,
      conversation: conversation,
      role: "user",
      body: body,
      metadata: metadata
    )
    next_generation = AiAssistant::Assistant::GenerationLifecycle.start!(
      conversation: conversation,
      user_message: confirmation
    )
    reset_vendor_capture
    run_reply(next_generation)
    next_generation
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

  def park_notes_proposal!(final_envelope: envelope("I'll add Notes."))
    create(:entity, :with_name_status_schema, customer: customer, name: "Student")
    reset_vendor_capture
    stub_vendor_chat(update_tool("Student"), final_envelope)
    run_reply
    conversation.messages.where(role: "assistant").last
  end

  def last_assistant
    conversation.messages.where(role: "assistant").order(:id).last
  end

  def system_prompt_for(messages)
    entry = Array(messages).find { |message| (message[:role] || message["role"]) == "system" } || Array(messages).first
    entry && (entry[:content] || entry["content"]).to_s
  end

  def history_text_for(messages)
    Array(messages).drop(1).map { |message| message[:content] || message["content"] }.join("\n")
  end

  def student_slugs
    Entity.find_by!(customer_id: customer.id, name: "Student").property_schema_json.map { |row| row["name_slug"] }
  end

  it "parks an update, applies it on a bare yes, and records confirmation on the invocation" do
    create(:entity, :with_name_status_schema, customer: customer, name: "Student")
    stub_vendor_chat(update_tool("Student"), envelope("I'll add Notes."))

    run_reply

    expect(student_slugs).not_to include("notes")
    proposal_message = conversation.messages.where(role: "assistant").last
    proposal = proposal_message.metadata_json.fetch("pending_confirmation")
    expect(proposal).to include(
      "kind" => "operation",
      "operation" => "update_entity",
      "customer_id" => customer.id
    )
    expect(proposal["invocation_id"]).to be_present
    expect(proposal["plan"]).to be_present
    invocation = OperationInvocation.find(proposal["invocation_id"])
    expect(invocation).to be_awaiting_confirmation
    expect(invocation.confirmed_by).to be_nil
    expect(Page.where(customer_id: customer.id)).to be_empty

    confirm!

    expect(student_slugs).to include("notes")
    reply = conversation.messages.where(role: "assistant").last
    expect(reply.body).to include(I18n.t("ai_assistant.assistant.apply_updated", names: "Student"))
    expect(proposal_message.reload.metadata_json).not_to have_key("pending_confirmation")
    expect(invocation.reload).to be_succeeded
    expect(invocation.confirmed_by).to eq(admin)
    expect(invocation.confirmed_at).to be_present
    student = Entity.find_by!(customer_id: customer.id, name: "Student")
    page = Page.find_by!(customer_id: customer.id, entity_version_id: student.current_version_id)
    expect(page).to have_attributes(launched: true, status: "active")
    expect(page.visible_audiences).to eq(%w[admin])
    expect(page.entity).to be_active
    expect(page.fields.map { |field| field["property_slug"] }).to include("notes")
    expect(conversation.reload).to have_attributes(artifact_kind: "page", artifact_id: page.id)
    expect(reply.metadata_json.fetch("changes")).to include(
      { "kind" => "page", "action" => "created", "name" => page.name }
    )
  end

  it "returns the localized stale-proposal body and marks the invocation conflict when the entity changed" do
    create(:entity, :with_name_status_schema, customer: customer, name: "Student")
    stub_vendor_chat(update_tool("Student"), envelope("I'll add Notes."))
    run_reply

    proposal_message = conversation.messages.where(role: "assistant").last
    invocation_id = proposal_message.metadata_json.dig("pending_confirmation", "invocation_id")
    EntityDefinitions::Persist.call(
      { customer: customer, entities: [{ "name" => "Student", "description" => "Changed outside" }], replace: false }
    )
    original_slugs = student_slugs

    confirm!

    reply = conversation.messages.where(role: "assistant").last
    expect(reply.body).to eq(I18n.t("ai_assistant.assistant.proposal_stale"))
    expect(student_slugs).to eq(original_slugs)
    expect(student_slugs).not_to include("notes")
    expect(OperationInvocation.find(invocation_id)).to be_conflict
    # The dead proposal no longer offers Apply.
    metadata = proposal_message.reload.metadata_json
    expect(metadata).not_to have_key("pending_confirmation")
    expect(metadata.dig("superseded_proposal", "invocation_id")).to eq(invocation_id)
  end

  it "does not apply a pending proposal whose invocation belongs to another conversation" do
    create(:entity, :with_name_status_schema, customer: customer, name: "Student")
    stub_vendor_chat(update_tool("Student"), envelope("I'll add Notes."), envelope("Ignored."))
    run_reply

    other = create(:ai_assistant_conversation, customer: customer, user: admin)
    foreign_invocation = create(
      :operation_invocation,
      :awaiting_confirmation,
      customer: customer,
      user: admin,
      operation: "update_entity",
      conversation_id: other.id
    )
    proposal_message = conversation.messages.where(role: "assistant").last
    metadata = proposal_message.metadata_json.deep_dup
    metadata["pending_confirmation"]["invocation_id"] = foreign_invocation.id
    proposal_message.update!(metadata: metadata)

    confirm!

    expect(student_slugs).not_to include("notes")
    expect(foreign_invocation.reload).to be_awaiting_confirmation
  end

  it "does not apply a pending proposal whose invocation belongs to another customer" do
    create(:entity, :with_name_status_schema, customer: customer, name: "Student")
    stub_vendor_chat(update_tool("Student"), envelope("I'll add Notes."), envelope("Ignored."))
    run_reply

    other_customer = create(:customer)
    foreign_invocation = create(
      :operation_invocation,
      :awaiting_confirmation,
      customer: other_customer,
      user: create(:user, :admin, customer: other_customer),
      operation: "update_entity"
    )
    proposal_message = conversation.messages.where(role: "assistant").last
    metadata = proposal_message.metadata_json.deep_dup
    metadata["pending_confirmation"]["invocation_id"] = foreign_invocation.id
    metadata["pending_confirmation"]["customer_id"] = other_customer.id
    proposal_message.update!(metadata: metadata)

    confirm!

    expect(student_slugs).not_to include("notes")
    expect(foreign_invocation.reload).to be_awaiting_confirmation
  end

  it "does not treat a typed yes after an intervening question as confirmation (F1)" do
    proposal_message = park_notes_proposal!
    invocation = OperationInvocation.find(proposal_message.metadata_json.dig("pending_confirmation", "invocation_id"))

    stub_vendor_chat(envelope("Do you also want a Phone field?"))
    user_turn!("What exactly does that change?")
    expect(vendor[:calls]).to eq(1)
    expect(last_assistant.body).to include("Do you also want a Phone field?")

    stub_vendor_chat(envelope("I'll add a Phone field too."))
    user_turn!("yes")

    expect(vendor[:calls]).to eq(1)
    expect(student_slugs).not_to include("notes")
    expect(proposal_message.reload.metadata_json).to have_key("pending_confirmation")
    expect(invocation.reload).to be_awaiting_confirmation
  end

  it "applies a pinned Apply after an intervening exchange with no vendor call" do
    proposal_message = park_notes_proposal!

    stub_vendor_chat(envelope("Do you also want a Phone field?"))
    user_turn!("What exactly does that change?")

    stub_vendor_forbidden
    confirm!(
      body: I18n.t("ai_assistant.assistant.plan.apply_reply"),
      metadata: { "confirms_message_id" => proposal_message.id }
    )

    expect(vendor[:calls]).to eq(0)
    expect(student_slugs).to include("notes")
    expect(proposal_message.reload.metadata_json).not_to have_key("pending_confirmation")
    expect(proposal_message.metadata_json).to have_key("applied_proposal")
    invocation = OperationInvocation.find(proposal_message.metadata_json.dig("applied_proposal", "invocation_id"))
    expect(invocation).to be_succeeded
    expect(invocation.confirmed_by).to eq(admin)
  end

  ["No, thanks", "算了"].each do |body|
    it "declines a pending proposal on typed #{body.inspect} with no vendor call" do
      proposal_message = park_notes_proposal!
      invocation_id = proposal_message.metadata_json.dig("pending_confirmation", "invocation_id")

      stub_vendor_forbidden
      confirm!(body: body)

      expect(vendor[:calls]).to eq(0)
      expect(last_assistant.body).to eq(I18n.t("ai_assistant.assistant.plan.declined"))
      expect(proposal_message.reload.metadata_json).not_to have_key("pending_confirmation")
      expect(proposal_message.metadata_json).to have_key("declined_proposal")
      invocation = OperationInvocation.find(invocation_id)
      expect(invocation).to be_declined
      expect(invocation.confirmed_by_id).to eq(admin.id)
      expect(invocation.confirmed_at).to be_present
      expect(student_slugs).not_to include("notes")
    end
  end

  it "does not apply a typed yes after Discard, and Discard itself creates no message or generation" do
    proposal_message = park_notes_proposal!
    message_count = conversation.messages.count
    generation_count = conversation.generations.count

    result = AiAssistant::Activities::DiscardProposal.call(
      customer: customer,
      user: admin,
      message_id: proposal_message.id
    )

    expect(result.http_status).to eq(200)
    expect(conversation.messages.count).to eq(message_count)
    expect(conversation.generations.count).to eq(generation_count)
    expect(proposal_message.reload.metadata_json).to have_key("declined_proposal")

    stub_vendor_forbidden
    confirm!(body: "yes")

    expect(vendor[:calls]).to eq(0)
    expect(last_assistant.body).to eq(I18n.t("ai_assistant.assistant.proposal_not_pending"))
    expect(student_slugs).not_to include("notes")
  end

  it "does not re-apply when regenerating a confirmation turn" do
    proposal_message = park_notes_proposal!
    confirm!(body: "yes")
    student = Entity.find_by!(customer_id: customer.id, name: "Student")
    invocation = OperationInvocation.find(proposal_message.reload.metadata_json.dig("applied_proposal", "invocation_id"))
    version_count = student.entity_versions.count
    confirmed_at = invocation.confirmed_at

    expect(student_slugs).to include("notes")
    expect(invocation).to be_succeeded

    stub_vendor_forbidden
    regenerate = AiAssistant::Activities::RegenerateLast.call(
      customer: customer,
      user: admin,
      conversation_id: conversation.id
    )
    expect(regenerate.success?).to eq(true)
    regen_generation = conversation.reload.current_generation
    expect(regen_generation).to be_present

    reset_vendor_capture
    run_reply(regen_generation)

    expect(vendor[:calls]).to eq(0)
    expect(last_assistant.body).to eq(I18n.t("ai_assistant.assistant.proposal_not_pending"))
    expect(student.reload.entity_versions.count).to eq(version_count)
    expect(student_slugs.count { |slug| slug == "notes" }).to eq(1)
    expect(invocation.reload).to be_succeeded
    expect(invocation.confirmed_at).to eq(confirmed_at)
    expect(invocation.confirmed_by).to eq(admin)
  end

  it "keeps a plan-plus-questions message pending on typed yes and applies it on pinned Apply" do
    questions = [{
      "prompt" => "Phone too?",
      "type" => "single",
      "options" => ["Yes", "No"],
      "default" => "No"
    }]
    proposal_message = park_notes_proposal!(
      final_envelope: envelope(
        "I'll add Notes. Phone too?",
        intent: "clarify",
        "questions" => questions
      )
    )

    expect(proposal_message.metadata_json).to have_key("pending_confirmation")
    expect(proposal_message.metadata_json["questions"]).to eq(
      AiAssistant::Assistant::Questions.sanitize(questions)
    )

    stub_vendor_chat(envelope("Waiting on the Phone question."))
    user_turn!("yes")

    expect(vendor[:calls]).to eq(1)
    expect(student_slugs).not_to include("notes")
    expect(proposal_message.reload.metadata_json).to have_key("pending_confirmation")

    stub_vendor_forbidden
    confirm!(
      body: I18n.t("ai_assistant.assistant.plan.apply_reply"),
      metadata: { "confirms_message_id" => proposal_message.id }
    )

    expect(vendor[:calls]).to eq(0)
    expect(student_slugs).to include("notes")
    expect(proposal_message.reload.metadata_json).to have_key("applied_proposal")
  end

  it "includes the parked proposal in the next non-confirmation prompt" do
    park_notes_proposal!

    stub_vendor_chat(envelope("The Notes field is a textarea on Student."))
    user_turn!("What exactly does that change?")

    prompt = system_prompt_for(vendor[:messages].first)
    history = history_text_for(vendor[:messages].first)
    expect(prompt).to include("Proposal waiting for approval")
    expect(prompt).to include("Notes")
    expect(history).to include(AiAssistant::Assistant::PromptBuilder::PENDING_NOTE)
  end

  it "omits the pending-proposal heading after a typed decline" do
    park_notes_proposal!

    stub_vendor_forbidden
    confirm!(body: "No, thanks")

    stub_vendor_chat(envelope("Hello."))
    user_turn!("Hello")

    later_prompt = system_prompt_for(vendor[:messages].first)
    later_history = history_text_for(vendor[:messages].first)
    expect(later_prompt).not_to include("Proposal waiting for approval")
    expect(later_history).to include(AiAssistant::Assistant::PromptBuilder::DECLINED_NOTE)
  end
end
