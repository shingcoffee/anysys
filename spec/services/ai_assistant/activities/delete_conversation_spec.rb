# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiAssistant::Activities::DeleteConversation do
  let_it_be(:customer) { create(:customer) }
  let_it_be(:user) { create(:user, :admin, customer: customer) }
  let(:conversation) { create(:ai_assistant_conversation, customer: customer, user: user) }

  def delete_it(id:, actor: user, tenant: customer)
    described_class.call(customer: tenant, user: actor, conversation_id: id)
  end

  before do
    Current.customer = customer
    enable_ai_assistant_module!(customer)
    allow(AiAssistant::Stream).to receive(:broadcast_conversations)
    allow(Turbo::StreamsChannel).to receive(:broadcast_update_to)
  end

  it "destroys the thread and its turns" do
    create(:ai_assistant_message, conversation: conversation, customer: customer)

    result = delete_it(id: conversation.id)

    expect(result).to be_success
    expect(result.http_status).to eq(200)
    expect(result.conversation.id).to eq(conversation.id)
    expect(AiAssistant::Conversation.find_by(id: conversation.id)).to be_nil
    expect(AiAssistant::Message.where(conversation_id: conversation.id)).to be_empty
  end

  it "cancels an in-flight generation before dropping the row" do
    message = create(:ai_assistant_message, conversation: conversation, customer: customer)
    generation = AiAssistant::Assistant::GenerationLifecycle.start!(
      conversation: conversation,
      user_message: message
    )

    delete_it(id: conversation.id)

    expect(AiAssistant::Generation.find_by(id: generation.id)).to be_nil
  end

  it "refreshes the sidebar with nothing highlighted" do
    delete_it(id: conversation.id)

    expect(AiAssistant::Stream).to have_received(:broadcast_conversations).with(
      customer: customer, user: user, current_id: nil
    )
  end

  it "refuses a blank id rather than destroying the current thread" do
    conversation

    result = nil
    expect { result = delete_it(id: nil) }.not_to change(AiAssistant::Conversation, :count)
    expect(result.http_status).to eq(404)
    expect(result.errors).to include(I18n.t("ai_assistant.errors.conversation_not_found"))
  end

  it "returns 404 for an id that does not exist" do
    expect(delete_it(id: 999_999).http_status).to eq(404)
  end

  it "returns 404 for another user's thread in the same tenant" do
    other = create(:user, :admin, customer: customer)
    foreign = create(:ai_assistant_conversation, customer: customer, user: other)

    result = delete_it(id: foreign.id)

    expect(result.http_status).to eq(404)
    expect(AiAssistant::Conversation.find_by(id: foreign.id)).to be_present
  end

  it "returns 404 for the same user's thread in another tenant" do
    other_tenant = create(:customer)
    cross = create(:user, :admin, customer: other_tenant)
    foreign = create(:ai_assistant_conversation, customer: other_tenant, user: cross)

    expect(delete_it(id: foreign.id).http_status).to eq(404)
    expect(AiAssistant::Conversation.find_by(id: foreign.id)).to be_present
  end

  it "leaves the caller's other threads alone" do
    keeper = create(:ai_assistant_conversation, customer: customer, user: user)

    delete_it(id: conversation.id)

    expect(AiAssistant::Conversation.find_by(id: keeper.id)).to eq(keeper)
  end

  it "refuses when the module is not enabled for the tenant" do
    conversation
    fm = FeatureModules::Module.find_by!(key: "ai_assistant")
    FeatureModules::CustomerAssignment.where(customer: customer, feature_module: fm).delete_all

    result = nil
    expect { result = delete_it(id: conversation.id) }.not_to change(AiAssistant::Conversation, :count)
    expect(result.http_status).to eq(403)
  end
end
