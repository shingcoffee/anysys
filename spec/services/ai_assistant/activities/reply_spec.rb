# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiAssistant::Activities::Reply do
  let_it_be(:customer) { create(:customer) }
  let_it_be(:user) { create(:user, :admin, customer: customer) }
  let!(:settings) { create(:ai_assistant_provider_settings) }
  let(:conversation) { create(:ai_assistant_conversation, customer: customer, user: user) }
  let(:user_message) do
    create(:ai_assistant_message, customer: customer, conversation: conversation, role: "user", body: "Hello")
  end
  let(:generation) do
    AiAssistant::Assistant::GenerationLifecycle.start!(
      conversation: conversation,
      user_message: user_message
    )
  end

  around { |example| Current.set(customer: customer) { example.run } }

  before do
    enable_ai_assistant_module!(customer)
    allow(Turbo::StreamsChannel).to receive(:broadcast_append_to)
    allow(Turbo::StreamsChannel).to receive(:broadcast_remove_to)
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
    allow(Turbo::StreamsChannel).to receive(:broadcast_update_to)
  end

  def chat_payload(reply, entities: [])
    { intent: "chat", reply: reply, entities: entities }.to_json
  end

  let_it_be(:domain) { create(:entity_domain, customer: customer, name: "Academics") }

  def create_entity_tool(name, attributes: [{ "name" => "Title" }])
    { "tool" => "create_entity", "arguments" => { "domain" => domain.name, "entities" => [{ "name" => name, "attributes" => attributes }] } }.to_json
  end

  def update_entity_tool(name, changes: [{ "op" => "add_attribute", "attribute" => { "name" => "Notes", "html_type" => "textarea" } }])
    { "tool" => "update_entity", "arguments" => { "updates" => [{ "entity" => name, "changes" => changes }] } }.to_json
  end

  def envelope_payload(reply, intent: "chat")
    { "intent" => intent, "reply" => reply }.to_json
  end

  def clarify_payload(reply, entities: [])
    { intent: "clarify", reply: reply, entities: entities }.to_json
  end

  def flowchart_chat_payload(reply = "")
    { intent: "chat", reply: reply, flowchart: nil }.to_json
  end

  def stub_vendor_chat(*texts)
    queue = texts.dup
    allow_any_instance_of(AiAssistant::Providers::OpenaiWhisper).to receive(:chat) do
      text = queue.shift || { intent: "chat", reply: "" }.to_json
      { outcome: :success, text: text, raw: {} }
    end
  end

  def run_reply
    described_class.call(generation: generation)
  end

  it "persists an assistant message from a successful chat outcome" do
    stub_vendor_chat(chat_payload("Hi!"), flowchart_chat_payload)
    run_reply
    reply = conversation.messages.where(role: "assistant").last
    expect(reply.body).to eq("Hi!")
    expect(reply.status).to eq("complete")
    expect(Turbo::StreamsChannel).to have_received(:broadcast_append_to)
  end

  it "passes native tools on the first OpenAI chat and not on the flowchart follow-on" do
    seen = []
    allow_any_instance_of(AiAssistant::Providers::OpenaiWhisper).to receive(:chat) do |**kwargs|
      seen << kwargs[:tools]
      text = seen.size == 1 ? chat_payload("Hi!") : flowchart_chat_payload
      { outcome: :success, text: text, raw: {} }
    end
    run_reply
    expect(Array(seen.first).map(&:name)).to include(
      "list_catalog", "generate_page", "verify_artifact",
      "create_domain", "create_entity", "update_entity", "get_entity"
    )
    expect(seen[1]).to be_nil
  end

  it "persists a failed assistant turn when the vendor is down" do
    allow_any_instance_of(AiAssistant::Providers::OpenaiWhisper).to receive(:chat)
      .and_return(outcome: :unreachable, text: nil, raw: {})
    run_reply
    reply = conversation.messages.where(role: "assistant").last
    expect(reply.status).to eq("failed")
    expect(reply.body).to eq(I18n.t("ai_assistant.assistant.reply_failed"))
  end

  # Regression: a spent per-turn call budget is an operational condition, not a
  # vendor outage. It used to be reported with the generic "try again" copy,
  # which is the wrong advice — repeating the request spends the same budget.
  describe "when the per-turn vendor call budget is spent" do
    before { stub_const("AiAssistant::Limits::MAX_VENDOR_CALLS", 0) }

    it "tells the reader to break the request up instead of retrying" do
      expect_any_instance_of(AiAssistant::Providers::OpenaiWhisper).not_to receive(:chat)

      run_reply

      reply = conversation.messages.where(role: "assistant").last
      expect(reply.status).to eq("failed")
      expect(reply.body).to eq(I18n.t("ai_assistant.assistant.budget_exceeded"))
      expect(reply.body).not_to eq(I18n.t("ai_assistant.assistant.reply_failed"))
    end

    it "records the budget as its own failure code" do
      run_reply

      expect(generation.reload).to have_attributes(status: "failed", failure_code: "vendor_call_budget")
    end
  end

  it "still uses the generic copy for a vendor outage" do
    allow_any_instance_of(AiAssistant::Providers::OpenaiWhisper).to receive(:chat)
      .and_return(outcome: :unreachable, text: nil, raw: {})

    run_reply

    expect(conversation.messages.where(role: "assistant").last.body)
      .to eq(I18n.t("ai_assistant.assistant.reply_failed"))
    expect(generation.reload.failure_code).to be_nil
  end

  it "still uses the generic copy for an empty vendor reply" do
    allow_any_instance_of(AiAssistant::Providers::OpenaiWhisper).to receive(:chat)
      .and_return(outcome: :success, text: "   ", raw: {})

    run_reply

    expect(conversation.messages.where(role: "assistant").last.body)
      .to eq(I18n.t("ai_assistant.assistant.reply_failed"))
    expect(generation.reload.failure_code).to be_nil
  end

  it "persists a cancelled assistant turn when the generation was cancelled" do
    AiAssistant::Assistant::GenerationLifecycle.cancel!(conversation: generation.conversation)
    run_reply
    reply = conversation.messages.where(role: "assistant").last
    expect(reply.status).to eq("cancelled")
    expect(reply.body).to eq(I18n.t("ai_assistant.assistant.cancelled"))
    expect(generation.reload.status).to eq("cancelled")
    expect(conversation.reload.current_generation_id).to be_nil
  end

  it "does not persist a cancellation turn for a cancelled predecessor" do
    cancelled = generation
    AiAssistant::Assistant::GenerationLifecycle.cancel!(conversation: conversation)
    replacement_message = create(
      :ai_assistant_message,
      customer: customer,
      conversation: conversation,
      role: "user",
      body: "Replacement"
    )
    replacement = AiAssistant::Assistant::GenerationLifecycle.start!(
      conversation: conversation,
      user_message: replacement_message
    )

    described_class.call(generation: cancelled)

    expect(conversation.messages.where(role: "assistant")).to be_empty
    expect(conversation.reload.current_generation).to eq(replacement)
  end

  it "does not run or clear state for a superseded generation" do
    old_generation = generation
    newer_message = create(
      :ai_assistant_message,
      customer: customer,
      conversation: conversation,
      role: "user",
      body: "Newer"
    )
    newer_generation = AiAssistant::Assistant::GenerationLifecycle.start!(
      conversation: conversation,
      user_message: newer_message
    )

    expect_any_instance_of(AiAssistant::Providers::OpenaiWhisper).not_to receive(:chat)

    described_class.call(generation: old_generation)

    expect(old_generation.reload.status).to eq("superseded")
    expect(newer_generation.reload.status).to eq("queued")
    expect(conversation.reload.current_generation_id).to eq(newer_generation.id)
    expect(conversation.messages.where(role: "assistant")).to be_empty
  end

  it "is idempotent when the same completed generation job is delivered again" do
    stub_vendor_chat(chat_payload("Hi!"), flowchart_chat_payload)
    run_reply
    assistant_ids = conversation.messages.where(role: "assistant").pluck(:id)

    expect_any_instance_of(AiAssistant::Providers::OpenaiWhisper).not_to receive(:chat)

    described_class.call(generation: generation)

    expect(generation.reload.status).to eq("completed")
    expect(conversation.messages.where(role: "assistant").pluck(:id)).to eq(assistant_ids)
    expect(conversation.reload.current_generation).to be_nil
  end

  it "rechecks authorization after enqueue and before provider invocation" do
    queued_generation = generation
    user.users_roles.delete_all

    expect_any_instance_of(AiAssistant::Providers::OpenaiWhisper).not_to receive(:chat)

    described_class.call(generation: queued_generation)

    expect(queued_generation.reload).to have_attributes(
      status: "failed",
      failure_code: "unauthorized"
    )
    expect(conversation.messages.where(role: "assistant").last.status).to eq("failed")
  end

  it "rechecks module availability after enqueue and before provider invocation" do
    queued_generation = generation
    FeatureModules::CustomerAssignment.where(customer: customer).delete_all

    expect_any_instance_of(AiAssistant::Providers::OpenaiWhisper).not_to receive(:chat)

    described_class.call(generation: queued_generation)

    expect(queued_generation.reload).to have_attributes(
      status: "failed",
      failure_code: "module_disabled"
    )
    expect(conversation.messages.where(role: "assistant").last.status).to eq("failed")
  end

  it "prevents a superseded generation from persisting artifacts during processing" do
    stub_vendor_chat(
      create_entity_tool("StaleEntity"),
      envelope_payload("Done"),
      flowchart_chat_payload
    )
    original_call = AiAssistant::Assistant::Tools::Session.instance_method(:call)
    newer_generation = nil

    allow_any_instance_of(AiAssistant::Assistant::Tools::Session).to receive(:call) do |session, name, arguments = {}|
      if name.to_s == "create_entity" && newer_generation.nil?
        newer_message = create(
          :ai_assistant_message,
          customer: customer,
          conversation: conversation,
          role: "user",
          body: "Newer"
        )
        newer_generation = AiAssistant::Assistant::GenerationLifecycle.start!(
          conversation: conversation,
          user_message: newer_message
        )
      end
      original_call.bind(session).call(name, arguments)
    end

    run_reply

    expect(Entity.find_by(customer_id: customer.id, name: "StaleEntity")).to be_nil
    expect(generation.reload.status).to eq("superseded")
    expect(conversation.reload.current_generation).to eq(newer_generation)
    expect(conversation.messages.where(role: "assistant")).to be_empty
  end

  it "honors cancellation immediately before a guarded entity mutation" do
    stub_vendor_chat(
      create_entity_tool("CancelledEntity"),
      envelope_payload("Done")
    )
    original_call = AiAssistant::Assistant::Tools::Session.instance_method(:call)

    allow_any_instance_of(AiAssistant::Assistant::Tools::Session).to receive(:call) do |session, name, arguments = {}|
      if name.to_s == "create_entity"
        AiAssistant::Assistant::GenerationLifecycle.cancel!(conversation: conversation)
      end
      original_call.bind(session).call(name, arguments)
    end

    run_reply

    expect(Entity.find_by(customer_id: customer.id, name: "CancelledEntity")).to be_nil
    expect(generation.reload.status).to eq("cancelled")
    expect(conversation.messages.where(role: "assistant").last).to have_attributes(
      status: "cancelled",
      body: I18n.t("ai_assistant.assistant.cancelled")
    )
  end

  it "does not broadcast an idle state when a newer generation takes over during finish" do
    stub_vendor_chat(chat_payload("Hi!"), flowchart_chat_payload)
    original_finish = AiAssistant::Assistant::GenerationLifecycle.method(:finish!)
    newer_generation = nil

    allow(AiAssistant::Assistant::GenerationLifecycle).to receive(:finish!) do |finished, status:, failure_code: nil, &block|
      newer_message = create(
        :ai_assistant_message,
        customer: customer,
        conversation: conversation,
        role: "user",
        body: "Newer"
      )
      newer_generation = AiAssistant::Assistant::GenerationLifecycle.start!(
        conversation: conversation,
        user_message: newer_message
      )
      original_finish.call(finished, status: status, failure_code: failure_code, &block)
    end

    run_reply

    expect(conversation.reload.current_generation).to eq(newer_generation)
    expect(Turbo::StreamsChannel).not_to have_received(:broadcast_replace_to)
      .with(
        anything,
        hash_including(
          target: AiAssistant::Stream::RUNNING_ID,
          html: include('data-running="false"')
        )
      )
  end

  it "persists a failed assistant turn when no generation assignee is configured" do
    settings.deactivate_for!(:generation)
    run_reply
    expect(conversation.messages.where(role: "assistant").last.status).to eq("failed")
  end

  it "does not construct OpenAI::Client when the provider is stubbed" do
    stub_vendor_chat(chat_payload("ok"), flowchart_chat_payload)
    expect(OpenAI::Client).not_to receive(:new)
    run_reply
  end

  it "uses the generation assignee even when transcribe is a different vendor" do
    settings.deactivate_for!(:transcribe)
    create(:ai_assistant_provider_settings,
           provider: "aliyun",
           api_key: "secret",
           transcribe_active: true,
           generation_active: false,
           config: { access_key_id: "AKID", app_key: "app-1" }.to_json)
    stub_vendor_chat(chat_payload("Hi!"), flowchart_chat_payload)
    run_reply
    expect(conversation.messages.where(role: "assistant").last.body).to eq("Hi!")
  end

  it "fail-closes assistant replies when only a transcription-only vendor is assigned" do
    settings.deactivate_for!(:transcribe)
    settings.deactivate_for!(:generation)
    create(:ai_assistant_provider_settings,
           provider: "aliyun",
           api_key: "secret",
           transcribe_active: true,
           generation_active: false,
           config: { access_key_id: "AKID", app_key: "app-1" }.to_json)

    run_reply
    reply = conversation.messages.where(role: "assistant").last
    expect(reply.status).to eq("failed")
    expect(reply.body).to eq(I18n.t("ai_assistant.assistant.reply_failed"))
  end

  describe "prompt construction" do
    # Regression: a failed assistant row's body IS the localized "could not
    # reply" string, so including it fed the model its own error text as context.
    it "excludes failed assistant turns from the prompt" do
      create(:ai_assistant_message, :assistant, customer: customer, conversation: conversation,
             body: I18n.t("ai_assistant.assistant.reply_failed"), status: "failed")
      user_message

      sent = nil
      allow_any_instance_of(AiAssistant::Providers::OpenaiWhisper).to receive(:chat) do |**kwargs|
        sent ||= kwargs[:messages]
        { outcome: :success, text: chat_payload("ok"), raw: {} }
      end

      run_reply

      bodies = sent.map { |m| m[:content] }
      expect(bodies).to include("Hello")
      expect(bodies).not_to include(I18n.t("ai_assistant.assistant.reply_failed"))
    end

    it "sends the system prompt plus at most HISTORY_LIMIT recent turns" do
      (AiAssistant::Assistant::PromptBuilder::HISTORY_LIMIT + 5).times do |i|
        create(:ai_assistant_message, customer: customer, conversation: conversation, body: "turn #{i}")
      end
      user_message

      sent = nil
      allow_any_instance_of(AiAssistant::Providers::OpenaiWhisper).to receive(:chat) do |**kwargs|
        sent ||= kwargs[:messages]
        { outcome: :success, text: chat_payload("ok"), raw: {} }
      end

      run_reply

      expect(sent.length).to eq(AiAssistant::Assistant::PromptBuilder::HISTORY_LIMIT + 1)
      expect(sent.first[:role]).to eq("system")
      expect(sent.last[:content]).to eq("Hello")
    end

    it "forwards attached user images to the generation vendor" do
      user_message.images.attach(
        io: StringIO.new("\x89PNG\r\n\x1A\n"),
        filename: "shot.png",
        content_type: "image/png"
      )

      sent = nil
      allow_any_instance_of(AiAssistant::Providers::OpenaiWhisper).to receive(:chat) do |**kwargs|
        sent ||= kwargs[:messages]
        { outcome: :success, text: chat_payload("ok"), raw: {} }
      end

      run_reply

      user_turn = sent.find { |row| row[:content] == "Hello" }
      expect(user_turn[:images]).to contain_exactly(user_message.images.first.blob)
    end
  end

  it "maps an escaped provider transport error to a failed assistant turn" do
    allow_any_instance_of(AiAssistant::Providers::OpenaiWhisper).to receive(:chat)
      .and_raise(Faraday::TimeoutError, "provider timed out")
    allow(Rails.logger).to receive(:error)

    expect { run_reply }.not_to raise_error

    expect(Rails.logger).to have_received(:error).with(
      /provider call failed.*Faraday::TimeoutError: provider timed out/
    )
    expect(conversation.messages.where(role: "assistant").last.status).to eq("failed")
  end

  it "terminalizes and re-raises an application failure from a native provider tool" do
    allow_any_instance_of(AiAssistant::Providers::OpenaiWhisper).to receive(:chat)
      .and_raise(ActiveRecord::StatementInvalid, "tool write failed")

    expect { run_reply }
      .to raise_error(ActiveRecord::StatementInvalid, "tool write failed")

    expect(generation.reload.status).to eq("failed")
    expect(conversation.reload.current_generation).to be_nil
  end

  it "terminalizes and re-raises an unexpected persistence failure" do
    stub_vendor_chat(chat_payload("Hi!"), flowchart_chat_payload)
    allow(AiAssistant::Assistant::ReplyWriter).to receive(:call)
      .and_raise(ActiveRecord::StatementInvalid, "write failed")

    expect { run_reply }
      .to raise_error(ActiveRecord::StatementInvalid, "write failed")

    expect(generation.reload.status).to eq("failed")
    expect(conversation.reload.current_generation).to be_nil
  end

  it "does not swallow a lifecycle finalization failure" do
    stub_vendor_chat(chat_payload("Hi!"), flowchart_chat_payload)
    allow(AiAssistant::Assistant::GenerationLifecycle).to receive(:finish!)
      .and_raise(ActiveRecord::StatementInvalid, "finish failed")

    expect { run_reply }
      .to raise_error(ActiveRecord::StatementInvalid, "finish failed")
  end

  # The admin can delete the thread while a reply is in flight. The turns and
  # the generation go with it, so the job's next reload finds nothing to write
  # to and has to stop without raising into the job runner.
  #
  # The rows are emptied rather than the conversation destroyed so the example
  # can still read the row back and assert what the job did (and did not) do.
  describe "the thread is emptied mid-flight" do
    def reset_during_chat(payload)
      allow_any_instance_of(AiAssistant::Providers::OpenaiWhisper).to receive(:chat) do
        conversation.update!(current_generation: nil, artifact_kind: nil, artifact_id: nil)
        conversation.generations.destroy_all
        conversation.messages.destroy_all
        { outcome: :success, text: payload, raw: {} }
      end
    end

    it "stops quietly when the generation is gone" do
      reset_during_chat(chat_payload("Hi!"))
      allow(Rails.logger).to receive(:error)

      expect { run_reply }.not_to raise_error
      expect(conversation.reload.messages).to be_empty
      expect(conversation.generations).to be_empty
      expect(Rails.logger).to have_received(:error).with(/generation no longer exists/)
    end

    it "writes no entities for a persist document it can no longer own" do
      reset_during_chat(create_entity_tool("Student"))

      expect { run_reply }.not_to raise_error
      expect(Entity.where(customer_id: customer.id).count).to eq(0)
    end
  end

  it "keeps the persisted reply complete when broadcasting fails" do
    stub_vendor_chat(chat_payload("Hi!"), flowchart_chat_payload)
    allow(Turbo::StreamsChannel).to receive(:broadcast_append_to).and_raise(RuntimeError, "no redis")
    allow(Rails.logger).to receive(:error)

    expect { run_reply }.not_to raise_error
    expect(Rails.logger).to have_received(:error).with(/message broadcast failed.*RuntimeError: no redis/)
    expect(conversation.messages.where(role: "assistant").last.status).to eq("complete")
  end

  it "does not persist entities for a chat document" do
    stub_vendor_chat(chat_payload("Just chatting"), flowchart_chat_payload)
    expect { run_reply }.not_to change(Entity, :count)
  end

  it "persists entities from a create_entity tool call" do
    stub_vendor_chat(create_entity_tool("Cohort"), envelope_payload("Done"), flowchart_chat_payload)
    run_reply
    expect(Entity.find_by!(customer_id: customer.id, name: "Cohort")).to be_active
    reply = conversation.messages.where(role: "assistant").last
    expect(reply.status).to eq("complete")
    expect(reply.body).to include("Done")
    expect(reply.body).to include("Cohort")
    expect(conversation.reload.artifact_kind).to eq("page")
    expect(Page.find(conversation.artifact_id).entity).to eq(Entity.find_by(customer_id: customer.id, name: "Cohort"))
  end

  describe "a sub-system build in the conversation" do
    include ActiveJob::TestHelper

    it "hands the message to a build waiting for answers without calling the vendor" do
      build = AiAssistant::SubsystemBuild.create!(customer_id: customer.id, conversation: conversation, user: user,
                                                  status: "waiting_for_answers", blueprint: { "domain" => "Academics" })
      expect_any_instance_of(AiAssistant::Providers::OpenaiWhisper).not_to receive(:chat)

      expect { run_reply }.to have_enqueued_job(AiAssistant::SubsystemBuildJob).with(build.id)

      reply = conversation.messages.where(role: "assistant").last
      expect(reply.body).to eq(I18n.t("ai_assistant.subsystems.answers.received", name: "Academics"))
      expect(reply.metadata_json).to include("subsystem_build" => { "id" => build.id }, "changes" => [])
      expect(build.reload.status).to eq("running")
      expect(generation.reload.status).to eq("completed")
    end

    it "marks the reply that started a build so it can show the build" do
      conversation.update!(user: find_or_create_platform_owner)
      brief = venue_brief("domain" => { "name" => "Academics", "description" => "Courses and students." }, "values" => [])
      start = { "tool" => "start_subsystem_build", "arguments" => brief }.to_json
      stub_vendor_chat(start, envelope_payload("The build has started."), flowchart_chat_payload)

      run_reply

      build = AiAssistant::SubsystemBuild.sole
      reply = conversation.messages.where(role: "assistant").last
      expect(reply.metadata_json["subsystem_build"]).to eq("id" => build.id)
      expect(reply.metadata_json["changes"]).not_to include(hash_including("kind" => "subsystem_build"))
    end
  end

  it "fail-closes on a retired apply_entities document and writes no entities" do
    allow_any_instance_of(AiAssistant::Providers::OpenaiWhisper).to receive(:chat)
      .and_return(outcome: :success, text: { intent: "apply_entities", reply: "Nope" }.to_json, raw: {})
    expect { run_reply }.not_to change(Entity, :count)
    reply = conversation.messages.where(role: "assistant").last
    expect(reply.status).to eq("failed")
    expect(reply.body).to eq(I18n.t("ai_assistant.assistant.extraction_invalid"))
  end

  it "pins apply writes to the conversation customer when Current.customer differs" do
    other = create(:customer)
    Current.customer = other
    stub_vendor_chat(create_entity_tool("PinnedCohort"), envelope_payload("Done"), flowchart_chat_payload)
    run_reply
    expect(Entity.find_by(customer_id: customer.id, name: "PinnedCohort")).to be_present
    expect(Entity.find_by(customer_id: other.id, name: "PinnedCohort")).to be_nil
  end

  it "returns apply validation errors to the model and writes no entities" do
    stub_vendor_chat(
      create_entity_tool("Student", attributes: [{ "name" => "X", "html_type" => "javascript" }]),
      envelope_payload("I could not use that field type.")
    )
    expect { run_reply }.not_to change(Entity, :count)
    reply = conversation.messages.where(role: "assistant").last
    expect(reply.status).to eq("complete")
    expect(reply.body).to include("I could not use that field type.")
  end

  it "does not persist entities for a clarify document" do
    allow_any_instance_of(AiAssistant::Providers::OpenaiWhisper).to receive(:chat)
      .and_return(outcome: :success, text: clarify_payload("What should it be called?", entities: [{ "name" => "Maybe" }]), raw: {})
    expect { run_reply }.not_to change(Entity, :count)
    expect(conversation.messages.where(role: "assistant").last.body).to eq("What should it be called?")
  end

  it "asks before adding an attribute to an existing entity, and parks the plan" do
    create(:entity, customer: customer, name: "Student")
    stub_vendor_chat(
      update_entity_tool("Student"),
      envelope_payload("I'll add Notes to Student.")
    )

    run_reply

    expect(Entity.find_by!(customer_id: customer.id, name: "Student").property_schema_json).to eq([])
    reply = conversation.messages.where(role: "assistant").last
    expect(reply.body).to include("I'll add Notes to Student.")
    expect(reply.body).to include(I18n.t("ai_assistant.assistant.update_needs_confirmation"))
    proposal = reply.metadata_json.fetch("pending_confirmation")
    expect(proposal).to include("kind" => "operation", "operation" => "update_entity", "customer_id" => customer.id)
    expect(proposal["invocation_id"]).to be_present
    expect(proposal.fetch("plan").flat_map { |entry| entry["rows"] }).to include(
      hash_including("kind" => "attribute", "action" => "added", "name" => "Notes")
    )
  end

  it "does not park a proposal for a read-only get_entity call" do
    existing = create(
      :entity,
      customer: customer,
      name: "Student",
      property_schema: [{ "name" => "Email", "name_slug" => "email", "html_type" => "email" }].to_json
    )
    stub_vendor_chat(
      { "tool" => "get_entity", "arguments" => { "entity" => "Student" } }.to_json,
      envelope_payload("Student already has an Email field."),
      flowchart_chat_payload
    )

    run_reply

    expect(existing.reload.property_schema_json.map { |attr| attr["name"] }).to eq(["Email"])
    reply = conversation.messages.where(role: "assistant").last
    expect(reply.body).not_to include(I18n.t("ai_assistant.assistant.update_needs_confirmation"))
    expect(reply.metadata_json).not_to have_key("pending_confirmation")
  end

  # Security: the parked plan is display only. A plan rewritten in the message
  # metadata must not change what the confirmation applies — the apply path
  # replays the pinned `document`, not the plan.
  it "applies only the pinned document when the parked plan has been tampered with" do
    existing = create(
      :entity,
      customer: customer,
      name: "Student",
      property_schema: [{ "name" => "Name", "name_slug" => "name", "html_type" => "text" }].to_json
    )
    stub_vendor_chat(
      update_entity_tool("Student"),
      envelope_payload("Adding Notes.")
    )

    run_reply

    proposal_message = conversation.messages.where(role: "assistant").last
    metadata = proposal_message.metadata_json.deep_dup
    metadata["pending_confirmation"]["plan"] = [{
      "name" => "Student",
      "rows" => [{ "kind" => "identity", "action" => "modified", "field" => "name_slug",
                   "before" => "student", "after" => "hijacked", "breaking" => true }]
    }]
    proposal_message.update!(metadata: metadata)

    confirmation = create(
      :ai_assistant_message,
      customer: customer,
      conversation: conversation,
      role: "user",
      body: "Yes"
    )
    described_class.call(
      generation: AiAssistant::Assistant::GenerationLifecycle.start!(
        conversation: conversation,
        user_message: confirmation
      )
    )

    existing.reload
    expect(existing.property_schema_json.map { |attr| attr["name_slug"] }).to eq(%w[name notes])
  end

  it "does not apply a breaking change to an existing entity until the user confirms" do
    create(
      :entity,
      customer: customer,
      name: "Student",
      property_schema: [{ "name" => "Enrolled", "name_slug" => "enrolled", "html_type" => "date" }].to_json
    )
    stub_vendor_chat(
      update_entity_tool(
        "Student",
        changes: [{ "op" => "update_attribute", "slug" => "enrolled", "set" => { "html_type" => "datetime-local" } }]
      ),
      envelope_payload("Switching Enrolled to date and time. Proceed?")
    )

    run_reply

    expect(Entity.find_by!(customer_id: customer.id, name: "Student").property_schema_json.first["html_type"])
      .to eq("date")
    expect(conversation.messages.where(role: "assistant").last.body).to include("Proceed?")
    expect(conversation.messages.where(role: "assistant").last.body).to include(I18n.t("ai_assistant.assistant.update_needs_confirmation"))
  end

  it "applies a breaking change only after a later explicit confirmation" do
    existing = create(
      :entity,
      customer: customer,
      name: "Student",
      property_schema: [
        { "name" => "Name", "name_slug" => "name", "html_type" => "text" },
        { "name" => "Status", "name_slug" => "status", "html_type" => "text" }
      ].to_json
    )
    calls = 0
    allow_any_instance_of(AiAssistant::Providers::OpenaiWhisper).to receive(:chat) do
      calls += 1
      raise "confirmation must not call the model" if calls > 2

      text = if calls == 1
        update_entity_tool(
          "Student",
          changes: [{
            "op" => "update_attribute",
            "slug" => "status",
            "set" => { "html_type" => "select", "options" => { "source" => "static", "values" => %w[Open Closed] } }
          }]
        )
      else
        envelope_payload("Updating Student")
      end
      { outcome: :success, text: text, raw: {} }
    end

    run_reply
    expect(existing.reload.property_schema_json.map { |attr| attr["html_type"] }).to eq(%w[text text])
    proposal_message = conversation.messages.where(role: "assistant").last
    expect(proposal_message.metadata_json["pending_confirmation"]).to be_present

    confirmation = create(
      :ai_assistant_message,
      customer: customer,
      conversation: conversation,
      role: "user",
      body: "Yes"
    )
    confirmation_generation = AiAssistant::Assistant::GenerationLifecycle.start!(
      conversation: conversation,
      user_message: confirmation
    )
    described_class.call(generation: confirmation_generation)

    existing.reload
    expect(existing.property_schema_json.map { |attr| attr["html_type"] }).to eq(%w[text select])
    expect(conversation.messages.where(role: "assistant").last.body).to include("Student")
    expect(proposal_message.reload.metadata_json).not_to have_key("pending_confirmation")
    expect(
      proposal_message.metadata_json["confirmation_consumed_by_generation_id"]
    ).to eq(confirmation_generation.id)
    expect(calls).to eq(2)
  end

  it "returns schema errors as a complete turn and writes no entities" do
    stub_vendor_chat(
      create_entity_tool("Student", attributes: [{ "name" => "X", "html_type" => "javascript" }]),
      envelope_payload("That field type is not supported.")
    )
    expect { run_reply }.not_to change(Entity, :count)
    reply = conversation.messages.where(role: "assistant").last
    expect(reply.status).to eq("complete")
    expect(reply.body).to include("That field type is not supported.")
  end

  it "persists a flowchart after a successful entity create for the platform owner" do
    conversation.update!(user: find_or_create_platform_owner)
    flowchart = {
      "name" => "Create Cohort",
      "elements" => [
        { "id" => "start_1", "type" => "start", "label" => "Start" },
        { "id" => "p1", "type" => "process", "label" => "New Model", "steps" => [{ "action" => "new_model" }] },
        { "id" => "p2", "type" => "process", "label" => "Build Contract", "steps" => [{ "action" => "build_contract" }] },
        { "id" => "p3", "type" => "process", "label" => "Validate", "steps" => [{ "action" => "validate_contract" }] },
        { "id" => "p4", "type" => "process", "label" => "Save Model", "steps" => [{ "action" => "save_model" }] },
        { "id" => "end_1", "type" => "end", "label" => "End" }
      ],
      "connections" => [
        { "from" => "start_1", "to" => "p1" },
        { "from" => "p1", "to" => "p2" },
        { "from" => "p2", "to" => "p3" },
        { "from" => "p3", "to" => "p4" },
        { "from" => "p4", "to" => "end_1" }
      ]
    }
    stub_vendor_chat(
      create_entity_tool("Cohort"),
      envelope_payload("Done"),
      { intent: "apply_flowchart", reply: "Creating Create Cohort.", flowchart: flowchart }.to_json
    )
    run_reply
    expect(Entity.find_by(customer_id: customer.id, name: "Cohort")).to be_present
    record = Flowchart.find_by(customer_id: customer.id, name: "Create Cohort")
    expect(record).to be_present
    expect(record).to be_launched
    expect(conversation.messages.where(role: "assistant").last.body).to include("Create Cohort")
    expect(conversation.reload.artifact_kind).to eq("page")
    expect(Page.find(conversation.artifact_id).entity.name).to eq("Cohort")
  end

  it "generates a page and pins it after an entity create" do
    stub_vendor_chat(create_entity_tool("Cohort"), envelope_payload("Done"), flowchart_chat_payload)
    run_reply
    page = Page.find_by(customer_id: customer.id, name: "Cohort")
    expect(page).to be_present
    expect(page).to have_attributes(launched: true, status: "active")
    expect(page.visible_audiences).to eq(%w[admin])
    expect(page.entity).to be_active
    expect(conversation.reload.artifact_kind).to eq("page")
    expect(conversation.artifact_id).to eq(page.id)
    expect(conversation.messages.where(role: "assistant").last.body).to include(
      I18n.t("ai_assistant.assistant.apply_page_created", names: "Cohort")
    )
    expect(conversation.messages.where(role: "assistant").last.metadata_json.fetch("changes")).to include(
      { "kind" => "entity", "action" => "created", "name" => "Cohort" },
      { "kind" => "page", "action" => "created", "name" => "Cohort" }
    )
  end

  it "keeps related entities and their bridge active while launching their generated forms" do
    payload = {
      "tool" => "create_entity",
      "arguments" => { "domain" => domain.name, "entities" => [
        { "name" => "Course", "attributes" => [{ "name" => "Title" }] },
        {
          "name" => "Student", "attributes" => [{ "name" => "Name" }],
          "associations" => [{
            "related_entity" => "Course", "display_field" => "title",
            "bridge_attributes" => [{ "name" => "Grade" }]
          }]
        }
      ] }
    }
    stub_vendor_chat(payload.to_json, envelope_payload("Done"))

    run_reply

    records = Entity.where(customer_id: customer.id, name: %w[Course Student assoc_student_course])
    expect(records.map(&:name)).to match_array(%w[Course Student assoc_student_course])
    expect(records).to all(be_active)
    expect(records.find_by!(name: "assoc_student_course")).to be_bridge_entity
    pages = Page.where(customer_id: customer.id)
    expect(pages.map(&:name)).to match_array(%w[Course Student])
    expect(pages).to all(have_attributes(launched: true))
    expect(pages.map(&:visible_audiences)).to all(eq(%w[admin]))
    student_page = pages.find_by!(name: "Student")
    expect(student_page.fields.map { |field| field["property_slug"] }).to include("name")
    bridge = records.find_by!(name: "assoc_student_course")
    expect(Array(bridge.property_schema_json).map { |attribute| attribute["name_slug"] }).to include("grade")
    expect(conversation.reload).to have_attributes(artifact_kind: "page", artifact_id: student_page.id)
    expect(generation.reload.status).to eq("completed")
  end

  it "keeps the entity write complete when automatic form launch fails and does not report a created page" do
    stub_vendor_chat(create_entity_tool("Empty Cohort", attributes: []), envelope_payload("Done"))

    expect { run_reply }.not_to change { [Page.with_deleted.count, PageVersion.count] }

    entity = Entity.find_by!(customer_id: customer.id, name: "Empty Cohort")
    expect(entity).to be_active
    expect(conversation.reload).to have_attributes(artifact_kind: "entity", artifact_id: entity.id)
    reply = conversation.messages.where(role: "assistant").last
    expect(reply).to have_attributes(status: "complete")
    expect(reply.body).to include(I18n.t("maint_core.errors.page_launch.no_fields"))
    expect(reply.metadata_json.fetch("changes")).not_to include(hash_including("kind" => "page"))
    expect(generation.reload.status).to eq("completed")
  end

  it "persists a flowchart after a chat turn with no entity write for the platform owner" do
    conversation.update!(user: find_or_create_platform_owner)
    flowchart = {
      "name" => "Create Student",
      "elements" => [
        { "id" => "start_1", "type" => "start", "label" => "Start" },
        { "id" => "p1", "type" => "process", "label" => "New Model", "steps" => [{ "action" => "new_model" }] },
        { "id" => "p2", "type" => "process", "label" => "Build Contract", "steps" => [{ "action" => "build_contract" }] },
        { "id" => "p3", "type" => "process", "label" => "Validate", "steps" => [{ "action" => "validate_contract" }] },
        { "id" => "p4", "type" => "process", "label" => "Save Model", "steps" => [{ "action" => "save_model" }] },
        { "id" => "end_1", "type" => "end", "label" => "End" }
      ],
      "connections" => [
        { "from" => "start_1", "to" => "p1" },
        { "from" => "p1", "to" => "p2" },
        { "from" => "p2", "to" => "p3" },
        { "from" => "p3", "to" => "p4" },
        { "from" => "p4", "to" => "end_1" }
      ]
    }
    create(:entity, customer: customer, name: "Student")
    stub_vendor_chat(
      { intent: "chat", reply: "I'll create a Create Student flowchart.", flowchart: true }.to_json,
      { intent: "apply_flowchart", reply: "Creating Create Student.", flowchart: flowchart }.to_json
    )
    run_reply
    expect(Flowchart.find_by(customer_id: customer.id, name: "Create Student")).to be_present
    reply = conversation.messages.where(role: "assistant").last
    expect(reply.status).to eq("complete")
    expect(reply.body).to include("I'll create a Create Student flowchart.")
    expect(reply.body).to include("Create Student")
  end

  it "answers the platform owner's greeting in one vendor call and designs nothing" do
    conversation.update!(user: find_or_create_platform_owner)
    calls = 0
    allow_any_instance_of(AiAssistant::Providers::OpenaiWhisper).to receive(:chat) do
      calls += 1
      text = calls == 1 ? chat_payload("Hi! What would you like to work on?") : { intent: "apply_flowchart" }.to_json
      { outcome: :success, text: text, raw: {} }
    end

    expect { run_reply }.not_to change(Flowchart, :count)
    expect(calls).to eq(1)
    expect(conversation.messages.where(role: "assistant").last.body).to eq("Hi! What would you like to work on?")
  end

  it "keeps a successful Q&A chat complete when the flowchart turn fails" do
    calls = 0
    allow_any_instance_of(AiAssistant::Providers::OpenaiWhisper).to receive(:chat) do
      calls += 1
      if calls == 1
        { outcome: :success, text: chat_payload("Pages live under Maintenance."), raw: {} }
      else
        { outcome: :unreachable, text: nil, raw: {} }
      end
    end
    run_reply
    reply = conversation.messages.where(role: "assistant").last
    expect(reply.status).to eq("complete")
    expect(reply.body).to eq("Pages live under Maintenance.")
    expect(reply.body).not_to include(I18n.t("ai_assistant.assistant.flowchart_reply_failed"))
  end

  it "keeps an entity create complete without a flowchart follow-on for a tenant admin" do
    stub_vendor_chat(create_entity_tool("Cohort"), envelope_payload("Done"), flowchart_chat_payload)
    run_reply
    expect(Entity.find_by(customer_id: customer.id, name: "Cohort")).to be_present
    reply = conversation.messages.where(role: "assistant").last
    expect(reply.status).to eq("complete")
    expect(reply.body).to include("Done")
    expect(reply.body).not_to include(I18n.t("ai_assistant.assistant.flowchart_reply_failed"))
  end

  it "keeps an entity create complete when the flowchart turn fails for the platform owner" do
    conversation.update!(user: find_or_create_platform_owner)
    calls = 0
    allow_any_instance_of(AiAssistant::Providers::OpenaiWhisper).to receive(:chat) do
      calls += 1
      text = case calls
      when 1 then create_entity_tool("Cohort")
      when 2 then envelope_payload("Done")
      end
      if text
        { outcome: :success, text: text, raw: {} }
      else
        { outcome: :unreachable, text: nil, raw: {} }
      end
    end
    run_reply
    expect(Entity.find_by(customer_id: customer.id, name: "Cohort")).to be_present
    reply = conversation.messages.where(role: "assistant").last
    expect(reply.status).to eq("complete")
    expect(reply.body).to include("Done")
    expect(reply.body).to include(I18n.t("ai_assistant.assistant.flowchart_reply_failed"))
  end

  it "does not run a flowchart turn after a clarify document" do
    calls = 0
    allow_any_instance_of(AiAssistant::Providers::OpenaiWhisper).to receive(:chat) do
      calls += 1
      { outcome: :success, text: clarify_payload("What should it be called?"), raw: {} }
    end
    run_reply
    expect(calls).to eq(1)
    expect(conversation.messages.where(role: "assistant").last.body).to eq("What should it be called?")
  end

  # The user is a tenant admin, so no flowchart pass follows, and a website
  # document skips the entity pass: one vendor call per turn plus one per
  # repair round.
  describe "website generation" do
    def website_payload(pages, reply: "Built your About page.")
      { intent: "apply_website", reply: reply, pages: pages }.to_json
    end

    def website_t(key, **options)
      I18n.t("ai_assistant.assistant.website.#{key}", **options)
    end

    # Queues vendor replies like stub_vendor_chat and records what each call sent.
    def record_vendor_chat(*texts)
      queue = texts.dup
      sent = []
      allow_any_instance_of(AiAssistant::Providers::OpenaiWhisper).to receive(:chat) do |**kwargs|
        sent << kwargs[:messages]
        { outcome: :success, text: queue.shift || chat_payload(""), raw: {} }
      end
      sent
    end

    def attach_images(message, *filenames)
      Current.set(customer: message.customer) do
        filenames.each do |filename|
          message.images.attach(
            io: File.open(Rails.root.join("spec/fixtures/files/test.png")),
            filename: filename,
            content_type: "image/png"
          )
        end
      end
      Websites::Assistant::Uploads.ordered(message.reload)
    end

    def token(attachment)
      Websites::Assistant::Uploads.token_for(attachment)
    end

    def hero(attachment)
      { "type" => "hero_split", "props" => { "headline" => "Fresh bread every morning", "visual_url" => token(attachment) } }
    end

    def gallery(attachment)
      {
        "type" => "gallery",
        "props" => { "heading" => "From our ovens", "items" => [{ "image_url" => token(attachment), "caption" => "Pastries" }] }
      }
    end

    def statement
      { "type" => "statement", "props" => { "headline" => "Baked daily since 1998" } }
    end

    def site_media_copy(url, owner: customer)
      expect(url).to match(%r{\A/#{owner.id}/site/media/[^/]+\z})
      ActiveStorage::Blob.find_signed(url.split("/").last)
    end

    def website_pages(owner = customer)
      WebsitePage.where(customer_id: owner.id)
    end

    def assistant_reply
      conversation.messages.where(role: "assistant").last
    end

    context "with the Website module on" do
      let!(:website) { create(:website, customer: customer) }

      before do
        create(:website_page, :home, website: website, customer: customer)
        enable_module!("website", customer)
      end

      it "builds a draft page, places both attached photos, and pins the page" do
        storefront, pastries = attach_images(user_message, "storefront.png", "pastries.png")
        sent = record_vendor_chat(website_payload([
          { "title" => "About us", "slug" => "about-us", "sections" => [hero(storefront), gallery(pastries)] }
        ]))

        expect { run_reply }.to change { website_pages.count }.by(1)

        expect(sent.size).to eq(1)
        user_turn = sent.first.find { |row| row[:content].to_s.start_with?("Hello") }
        expect(user_turn[:content]).to include(
          Websites::Assistant::Uploads.manifest_line(Websites::Assistant::Uploads.ordered(user_message.reload))
        )
        expect(user_turn[:images]).to eq([storefront.blob, pastries.blob])

        page = website_pages.find_by!(title: "About us")
        expect(page).to have_attributes(published: false, home: false, slug: "about-us", website_id: website.id)
        expect(page.sections.to_json).not_to include("upload:")
        placed = {
          storefront => page.sections.find { |row| row["type"] == "hero_split" }.dig("props", "visual_url"),
          pastries => page.sections.find { |row| row["type"] == "gallery" }.dig("props", "items", 0, "image_url")
        }
        placed.each do |attachment, url|
          copy = site_media_copy(url)
          expect(copy.id).not_to eq(attachment.blob_id)
          expect(copy.customer_id).to eq(customer.id)
          expect(copy.metadata).to include("website_media" => true, "assistant_source_blob_id" => attachment.blob_id)
        end

        expect(assistant_reply).to have_attributes(
          status: "complete",
          body: ["Built your About page.", website_t("apply_created", names: "About us"), website_t("drafts_note")].join(" ")
        )
        expect(assistant_reply.metadata_json["changes"]).to include(
          { "kind" => "website_page", "action" => "created", "name" => "About us" }
        )
        expect(conversation.reload).to have_attributes(artifact_kind: "website_page", artifact_id: page.id)
        expect(generation.reload.status).to eq("completed")
        expect(Turbo::StreamsChannel).to have_received(:broadcast_replace_to).with(
          anything,
          hash_including(
            target: AiAssistant::Stream::ARTIFACT_ID,
            html: include(
              Rails.application.routes.url_helpers.edit_admin_modules_website_page_path(customer.id, page),
              I18n.t("ai_assistant.assistant.artifact.website_draft")
            )
          )
        )
        expect(Websites::Assistant::Undo.state(assistant_reply)).to eq(:available)
      end

      it "keeps the pages a stopped turn already wrote listed and undoable" do
        record_vendor_chat(website_payload([ { "title" => "About us", "slug" => "about-us", "sections" => [ statement ] } ]))
        allow(Websites::Assistant::Processor).to receive(:call).and_wrap_original do |original, **args|
          original.call(**args).tap { AiAssistant::Assistant::GenerationLifecycle.cancel!(conversation: conversation) }
        end

        run_reply

        expect(website_pages.find_by(title: "About us")).to be_present
        expect(assistant_reply).to have_attributes(status: "cancelled")
        expect(assistant_reply.metadata_json["changes"]).to include(
          { "kind" => "website_page", "action" => "created", "name" => "About us" }
        )
        expect(Websites::Assistant::Undo.state(assistant_reply)).to eq(:available)
      end

      it "retains committed website effects and undo after supersession without changing the newer generation" do
        record_vendor_chat(website_payload([{ "title" => "About us", "slug" => "about-us", "sections" => [statement] }]))
        replacement = nil
        allow(Websites::Assistant::Processor).to receive(:call).and_wrap_original do |original, **args|
          original.call(**args).tap do
            next_turn = create(:ai_assistant_message, conversation: conversation, customer: customer, body: "Next request")
            replacement = AiAssistant::Assistant::GenerationLifecycle.start!(conversation: conversation, user_message: next_turn)
          end
        end

        run_reply
        receipt = assistant_reply
        expect(generation.reload.status).to eq("superseded")
        expect(conversation.reload.current_generation_id).to eq(replacement.id)
        expect(receipt).to have_attributes(status: "cancelled")
        expect(receipt.metadata_json).to include("generation_id" => generation.id, "superseded" => true)
        expect(receipt.metadata_json["changes"]).to include(
          { "kind" => "website_page", "action" => "created", "name" => "About us" }
        )
        expect(Websites::Assistant::Undo.state(receipt)).to eq(:available)
        expect { run_reply }.not_to change { conversation.messages.where(role: "assistant").count }
        expect(conversation.reload.current_generation_id).to eq(replacement.id)
      end

      it "asks the clarifying questions and writes nothing" do
        questions = "Before I build it:\n1. What is the bakery called? (default: \"Your bakery\")\n" \
                    "2. Which phone number should visitors call? (default: [Your phone number])"
        sent = record_vendor_chat(clarify_payload(questions))

        expect { run_reply }.not_to change { website_pages.count }

        expect(sent.size).to eq(1)
        expect(assistant_reply).to have_attributes(status: "complete", body: questions)
        expect(assistant_reply.metadata_json["changes"]).to eq([])
        expect(conversation.reload.artifact_kind).to be_nil
      end

      it "repairs an invalid document and writes exactly one page" do
        sent = record_vendor_chat(
          website_payload([{ "title" => "Menu", "sections" => [{ "type" => "carousel", "props" => {} }] }]),
          website_payload([{ "title" => "Menu", "slug" => "menu", "sections" => [statement] }])
        )

        expect { run_reply }.to change { website_pages.count }.by(1)

        expect(sent.size).to eq(2)
        expect(sent.last.last[:content]).to include(
          AiAssistant::Assistant::Prompt::Document.read("website_repair"),
          website_t("errors.unknown_section", title: "Menu", index: 1, type: "carousel")
        )
        expect(website_pages.find_by!(title: "Menu").sections.map { |row| row["type"] }).to eq(["statement"])
        expect(assistant_reply.status).to eq("complete")
        expect(assistant_reply.body).to include(website_t("apply_created", names: "Menu"))
      end

      it "writes the page and its photo for the conversation customer when Current names another tenant" do
        other = create(:customer)
        enable_module!("website", other)
        storefront, = attach_images(user_message, "storefront.png")
        Current.customer = other
        record_vendor_chat(website_payload([{ "title" => "About us", "sections" => [hero(storefront)] }]))

        run_reply

        page = website_pages.find_by!(title: "About us")
        expect(site_media_copy(page.sections.first.dig("props", "visual_url")).customer_id).to eq(customer.id)
        expect(Website.where(customer_id: other.id)).to be_empty
        expect(website_pages(other)).to be_empty
        expect(ActiveStorage::Blob.where(customer_id: other.id)).to be_empty
      end
    end

    it "answers with the module-disabled copy and writes nothing when the Website module is off" do
      storefront, = attach_images(user_message, "storefront.png")
      sent = record_vendor_chat(website_payload([{ "title" => "About us", "sections" => [hero(storefront)] }]))

      expect { run_reply }.not_to change(ActiveStorage::Blob, :count)

      expect(sent.size).to eq(1)
      expect(assistant_reply).to have_attributes(
        status: "complete",
        body: I18n.t("ai_assistant.assistant.website.module_disabled")
      )
      expect(Website.where(customer_id: customer.id)).to be_empty
      expect(website_pages).to be_empty
      expect(conversation.reload.artifact_kind).to be_nil
    end
  end
end
