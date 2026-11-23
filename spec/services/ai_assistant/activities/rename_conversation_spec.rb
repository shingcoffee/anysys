# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiAssistant::Activities::RenameConversation do
  let_it_be(:customer) { create(:customer) }
  let_it_be(:user) { create(:user, :admin, customer: customer) }
  let(:conversation) { create(:ai_assistant_conversation, customer: customer, user: user) }

  def rename(id:, title:, actor: user, tenant: customer)
    described_class.call(customer: tenant, user: actor, conversation_id: id, title: title)
  end

  before do
    Current.customer = customer
    enable_ai_assistant_module!(customer)
    allow(AiAssistant::Stream).to receive(:broadcast_conversations)
  end

  it "renames the thread and refreshes the sidebar" do
    result = rename(id: conversation.id, title: "Quarterly review")

    expect(result).to be_success
    expect(result.http_status).to eq(200)
    expect(conversation.reload.title).to eq("Quarterly review")
    expect(AiAssistant::Stream).to have_received(:broadcast_conversations).with(
      customer: customer, user: user, current_id: conversation.id
    )
  end

  it "collapses whitespace so a padded title cannot exceed the column" do
    rename(id: conversation.id, title: "  Budget\n\n  review  ")

    expect(conversation.reload.title).to eq("Budget review")
  end

  it "stops the thread borrowing its first prompt once it is named" do
    rename(id: conversation.id, title: "Named by hand")
    conversation.reload.adopt_title_from("A prompt that would have become the title")

    expect(conversation.reload.title).to eq("Named by hand")
  end

  it "rejects a blank title" do
    result = rename(id: conversation.id, title: "   ")

    expect(result).not_to be_success
    expect(result.http_status).to eq(422)
    expect(result.errors.join).to include(I18n.t("ai_assistant.errors.title_blank"))
    expect(conversation.reload.title).to be_nil
  end

  it "rejects a title over the limit" do
    result = rename(id: conversation.id, title: "x" * (AiAssistant::Conversation::TITLE_LIMIT + 1))

    expect(result.http_status).to eq(422)
    expect(result.errors.join).to include(I18n.t("ai_assistant.errors.title_too_long"))
    expect(conversation.reload.title).to be_nil
  end

  it "accepts a title exactly at the limit" do
    title = "y" * AiAssistant::Conversation::TITLE_LIMIT

    expect(rename(id: conversation.id, title: title)).to be_success
    expect(conversation.reload.title).to eq(title)
  end

  it "refuses a blank id rather than renaming the current thread" do
    result = rename(id: "", title: "Sneaky")

    expect(result.http_status).to eq(404)
    expect(result.errors).to include(I18n.t("ai_assistant.errors.conversation_not_found"))
    expect(conversation.reload.title).to be_nil
  end

  it "returns 404 for an id that does not exist" do
    expect(rename(id: 999_999, title: "Nope").http_status).to eq(404)
  end

  it "returns 404 for another user's thread in the same tenant" do
    other = create(:user, :admin, customer: customer)
    foreign = create(:ai_assistant_conversation, customer: customer, user: other, title: "Theirs")

    result = rename(id: foreign.id, title: "Mine now")

    expect(result.http_status).to eq(404)
    expect(foreign.reload.title).to eq("Theirs")
  end

  it "returns 404 for the same user's thread in another tenant" do
    other_tenant = create(:customer)
    cross = create(:user, :admin, customer: other_tenant)
    foreign = create(:ai_assistant_conversation, customer: other_tenant, user: cross, title: "Theirs")

    result = rename(id: foreign.id, title: "Mine now")

    expect(result.http_status).to eq(404)
    expect(foreign.reload.title).to eq("Theirs")
  end

  it "refuses when the module is not enabled for the tenant" do
    conversation
    fm = FeatureModules::Module.find_by!(key: "ai_assistant")
    FeatureModules::CustomerAssignment.where(customer: customer, feature_module: fm).delete_all

    result = rename(id: conversation.id, title: "Nope")

    expect(result.http_status).to eq(403)
    expect(conversation.reload.title).to be_nil
  end
end
