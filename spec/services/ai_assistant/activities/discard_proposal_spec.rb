# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiAssistant::Activities::DiscardProposal do
  let_it_be(:customer) { create(:customer) }
  let_it_be(:user) { create(:user, :admin, customer: customer) }
  let(:conversation) { create(:ai_assistant_conversation, customer: customer, user: user) }

  def park_invocation!(overrides = {})
    create(
      :operation_invocation,
      :awaiting_confirmation,
      customer: customer,
      user: user,
      operation: "update_entity",
      conversation_id: conversation.id,
      **overrides
    )
  end

  def proposal(invocation)
    {
      "kind" => "operation",
      "operation" => "update_entity",
      "invocation_id" => invocation.id,
      "customer_id" => customer.id,
      "plan" => []
    }
  end

  def park!(pending)
    create(
      :ai_assistant_message,
      :assistant,
      conversation: conversation,
      customer: customer,
      metadata: { "pending_confirmation" => pending }
    )
  end

  def call(user: self.user, customer: self.customer, message_id:)
    described_class.call(customer: customer, user: user, message_id: message_id)
  end

  before do
    enable_ai_assistant!(customer)
    allow(AiAssistant::Stream).to receive(:broadcast_message_replace)
  end

  it "declines the proposal, redraws the message, and spends no turn" do
    invocation = park_invocation!
    parked = proposal(invocation)
    message = park!(parked)
    message_count = AiAssistant::Message.count
    generation_count = AiAssistant::Generation.count

    result = call(message_id: message.id)

    expect(result).to have_attributes(success?: true, http_status: 200, message: message)
    expect(AiAssistant::Message.count).to eq(message_count)
    expect(AiAssistant::Generation.count).to eq(generation_count)
    metadata = message.reload.metadata_json
    expect(metadata).not_to have_key("pending_confirmation")
    expect(metadata.fetch("declined_proposal")).to eq(parked)
    expect(invocation.reload).to be_declined
    expect(invocation.confirmed_by).to eq(user)
    expect(invocation.confirmed_at).to be_present
    expect(AiAssistant::Stream).to have_received(:broadcast_message_replace).with(message)
  end

  it "declines under the conversation's lock" do
    message = park!(proposal(park_invocation!))
    expect_any_instance_of(AiAssistant::Conversation).to receive(:with_lock).and_call_original

    expect(call(message_id: message.id).success?).to be(true)
  end

  it "reports the committed decline even when the redraw fails" do
    invocation = park_invocation!
    message = park!(proposal(invocation))
    allow(AiAssistant::Stream).to receive(:broadcast_message_replace).and_raise("cable down")
    allow(Rails.logger).to receive(:error)

    expect(call(message_id: message.id)).to have_attributes(success?: true, http_status: 200)
    expect(message.reload.metadata_json).to have_key("declined_proposal")
    expect(invocation.reload).to be_declined
    expect(Rails.logger).to have_received(:error).with(a_string_including("cable down"))
  end

  it "returns 422 with the message when nothing is pending" do
    message = create(
      :ai_assistant_message, :assistant,
      conversation: conversation, customer: customer,
      metadata: {}
    )

    result = call(message_id: message.id)

    expect(result).to have_attributes(success?: false, http_status: 422, message: message)
    expect(result.errors).to eq([ I18n.t("ai_assistant.assistant.proposal_not_pending") ])
    expect(AiAssistant::Stream).not_to have_received(:broadcast_message_replace)
  end

  it "does not reach a reply in another admin's conversation" do
    other = create(:user, :admin, customer: customer)
    invocation = park_invocation!
    message = park!(proposal(invocation))

    result = call(user: other, message_id: message.id)

    expect(result).to have_attributes(success?: false, http_status: 404, message: nil)
    expect(result.errors).to include(I18n.t("ai_assistant.errors.conversation_not_found"))
    expect(message.reload.metadata_json).to have_key("pending_confirmation")
    expect(invocation.reload).to be_awaiting_confirmation
  end

  it "does not reach a reply from another tenant" do
    other_customer = create(:customer)
    other_admin = create(:user, :admin, customer: other_customer)
    enable_ai_assistant_module!(other_customer)
    invocation = park_invocation!
    message = park!(proposal(invocation))

    result = call(user: other_admin, customer: other_customer, message_id: message.id)

    expect(result).to have_attributes(http_status: 404, message: nil)
    expect(result.errors).to include(I18n.t("ai_assistant.errors.conversation_not_found"))
    expect(message.reload.metadata_json).to have_key("pending_confirmation")
    expect(invocation.reload).to be_awaiting_confirmation
  end

  it "does not discard a user message" do
    user_message = create(:ai_assistant_message, conversation: conversation, customer: customer)

    expect(call(message_id: user_message.id)).to have_attributes(
      http_status: 404, message: nil
    )
  end

  it "refuses while the module is off" do
    invocation = park_invocation!
    message = park!(proposal(invocation))
    fm = FeatureModules::Module.find_by!(key: "ai_assistant")
    FeatureModules::CustomerAssignment.where(customer: customer, feature_module: fm).delete_all

    expect(call(message_id: message.id)).to have_attributes(success?: false, http_status: 403)
    expect(message.reload.metadata_json).to have_key("pending_confirmation")
    expect(invocation.reload).to be_awaiting_confirmation
  end
end
