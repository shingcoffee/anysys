# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiAssistant::Activities::ArchiveConversation do
  let_it_be(:customer) { create(:customer) }
  let_it_be(:user) { create(:user, :admin, customer: customer) }
  let(:conversation) { create(:ai_assistant_conversation, customer: customer, user: user) }

  def toggle(id:, archived:, actor: user, tenant: customer)
    described_class.call(customer: tenant, user: actor, conversation_id: id, archived: archived)
  end

  before do
    Current.customer = customer
    enable_ai_assistant_module!(customer)
    allow(AiAssistant::Stream).to receive(:broadcast_conversations)
  end

  it "archives an open thread" do
    result = toggle(id: conversation.id, archived: true)

    expect(result).to be_success
    expect(result.http_status).to eq(200)
    expect(conversation.reload).to be_archived
  end

  it "unarchives a filed thread" do
    filed = create(:ai_assistant_conversation, :archived, customer: customer, user: user)

    expect(toggle(id: filed.id, archived: false)).to be_success
    expect(filed.reload).not_to be_archived
  end

  it "takes an archived thread out of the running for the current one" do
    conversation
    toggle(id: conversation.id, archived: true)

    expect(AiAssistant::Conversation.current_for(customer: customer, user: user))
      .not_to eq(conversation)
  end

  it "keeps the thread's turns readable" do
    create(:ai_assistant_message, conversation: conversation, customer: customer, body: "kept")

    toggle(id: conversation.id, archived: true)

    expect(conversation.reload.messages.pluck(:body)).to eq([ "kept" ])
  end

  it "casts a string flag from a form post" do
    expect(toggle(id: conversation.id, archived: "true")).to be_success
    expect(conversation.reload).to be_archived

    expect(toggle(id: conversation.id, archived: "false")).to be_success
    expect(conversation.reload).not_to be_archived
  end

  it "highlights nothing in the sidebar after archiving" do
    toggle(id: conversation.id, archived: true)

    expect(AiAssistant::Stream).to have_received(:broadcast_conversations).with(
      customer: customer, user: user, current_id: nil
    )
  end

  it "highlights the restored thread after unarchiving" do
    filed = create(:ai_assistant_conversation, :archived, customer: customer, user: user)

    toggle(id: filed.id, archived: false)

    expect(AiAssistant::Stream).to have_received(:broadcast_conversations).with(
      customer: customer, user: user, current_id: filed.id
    )
  end

  it "refuses a blank id rather than archiving the current thread" do
    result = toggle(id: nil, archived: true)

    expect(result.http_status).to eq(404)
    expect(conversation.reload).not_to be_archived
  end

  it "returns 404 for another user's thread in the same tenant" do
    other = create(:user, :admin, customer: customer)
    foreign = create(:ai_assistant_conversation, customer: customer, user: other)

    result = toggle(id: foreign.id, archived: true)

    expect(result.http_status).to eq(404)
    expect(result.errors).to include(I18n.t("ai_assistant.errors.conversation_not_found"))
    expect(foreign.reload).not_to be_archived
  end

  it "returns 404 for the same user's thread in another tenant" do
    other_tenant = create(:customer)
    cross = create(:user, :admin, customer: other_tenant)
    foreign = create(:ai_assistant_conversation, customer: other_tenant, user: cross)

    expect(toggle(id: foreign.id, archived: true).http_status).to eq(404)
    expect(foreign.reload).not_to be_archived
  end

  # Regression: archiving used to leave a running turn streaming into a thread
  # the user had just put away, and its reply landed somewhere only the
  # archived disclosure could reach.
  describe "a thread with a turn still running" do
    def start_generation(on:)
      message = create(:ai_assistant_message, customer: customer, conversation: on, body: "Hello")
      AiAssistant::Assistant::GenerationLifecycle.start!(conversation: on, user_message: message)
    end

    before { allow(AiAssistant::Assistant::GenerationLifecycle).to receive(:cancel!).and_call_original }

    it "cancels the in-flight generation when archiving" do
      generation = start_generation(on: conversation)

      expect(toggle(id: conversation.id, archived: true)).to be_success

      expect(AiAssistant::Assistant::GenerationLifecycle)
        .to have_received(:cancel!).with(conversation: conversation)
      expect(generation.reload.status).to eq("cancelled")
      expect(conversation.reload).to be_archived
    end

    it "does not cancel anything when unarchiving" do
      filed = create(:ai_assistant_conversation, :archived, customer: customer, user: user)
      generation = start_generation(on: filed)

      expect(toggle(id: filed.id, archived: false)).to be_success

      expect(AiAssistant::Assistant::GenerationLifecycle).not_to have_received(:cancel!)
      expect(generation.reload.status).to eq("queued")
      expect(filed.reload).not_to be_archived
    end

    it "does not cancel another user's turn when its owner archives nothing" do
      other = create(:user, :admin, customer: customer)
      foreign = create(:ai_assistant_conversation, customer: customer, user: other)
      generation = start_generation(on: foreign)

      expect(toggle(id: foreign.id, archived: true).http_status).to eq(404)

      expect(AiAssistant::Assistant::GenerationLifecycle).not_to have_received(:cancel!)
      expect(generation.reload.status).to eq("queued")
    end
  end

  it "refuses when the module is not enabled for the tenant" do
    conversation
    fm = FeatureModules::Module.find_by!(key: "ai_assistant")
    FeatureModules::CustomerAssignment.where(customer: customer, feature_module: fm).delete_all

    expect(toggle(id: conversation.id, archived: true).http_status).to eq(403)
    expect(conversation.reload).not_to be_archived
  end
end
