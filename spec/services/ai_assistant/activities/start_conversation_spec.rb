# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiAssistant::Activities::StartConversation do
  let_it_be(:customer) { create(:customer) }
  let_it_be(:user) { create(:user, :admin, customer: customer) }

  def start(actor: user, tenant: customer)
    described_class.call(customer: tenant, user: actor)
  end

  # A started thread has to be written to before another may be started, so
  # every test that needs a second chat has to spend the first one.
  def use!(conversation)
    create(:ai_assistant_message, customer: conversation.customer, conversation: conversation)
    conversation
  end

  def used_conversation(**attrs)
    use!(create(:ai_assistant_conversation, customer: customer, user: user, **attrs))
  end

  before do
    Current.customer = customer
    enable_ai_assistant_module!(customer)
    allow(AiAssistant::Stream).to receive(:broadcast_conversations)
  end

  it "creates a thread owned by the caller and stamps its activity" do
    result = nil
    expect { result = start }.to change(AiAssistant::Conversation, :count).by(1)

    expect(result).to be_success
    expect(result.http_status).to eq(201)
    expect(result.conversation).to have_attributes(
      customer_id: customer.id,
      user_id: user.id,
      title: nil,
      archived_at: nil
    )
    expect(result.conversation.last_active_at).to be_within(5.seconds).of(Time.current)
  end

  it "becomes the thread the workspace opens next" do
    used_conversation(last_active_at: 1.day.ago)

    started = start.conversation

    expect(AiAssistant::Conversation.current_for(customer: customer, user: user)).to eq(started)
  end

  it "refreshes the sidebar with the new thread highlighted" do
    result = start

    expect(AiAssistant::Stream).to have_received(:broadcast_conversations).with(
      customer: customer, user: user, current_id: result.conversation.id
    )
  end

  it "keeps the caller's threads out of another user's list" do
    other = create(:user, :admin, customer: customer)
    started = start(actor: other).conversation

    expect(started.user_id).to eq(other.id)
    expect(AiAssistant::Conversation.owned_by(customer: customer, user: user)).to be_empty
  end

  it "refuses with a 429 quota failure at the per-user ceiling" do
    AiAssistant::Conversation::MAX_PER_USER.times do
      create(:ai_assistant_conversation, customer: customer, user: user)
    end

    result = nil
    expect { result = start }.not_to change(AiAssistant::Conversation, :count)

    expect(result).not_to be_success
    expect(result.http_status).to eq(429)
    expect(result.error_code).to eq("conversation_count_limit")
    expect(result.errors).to include(
      I18n.t("ai_assistant.errors.conversation_count_limit",
             count: AiAssistant::Conversation::MAX_PER_USER)
    )
  end

  it "counts the ceiling per user, not per tenant" do
    other = create(:user, :admin, customer: customer)
    AiAssistant::Conversation::MAX_PER_USER.times do
      create(:ai_assistant_conversation, customer: customer, user: other)
    end

    expect(start).to be_success
  end

  it "counts archived threads against the ceiling" do
    AiAssistant::Conversation::MAX_PER_USER.times do
      create(:ai_assistant_conversation, :archived, customer: customer, user: user)
    end

    expect(start.http_status).to eq(429)
  end

  it "refuses when the module is not enabled for the tenant" do
    fm = FeatureModules::Module.find_by!(key: "ai_assistant")
    FeatureModules::CustomerAssignment.where(customer: customer, feature_module: fm).delete_all

    result = nil
    expect { result = start }.not_to change(AiAssistant::Conversation, :count)

    expect(result.http_status).to eq(403)
    expect(result.errors).to include(I18n.t("ai_assistant.errors.module_disabled"))
  end

  it "does not spend the chat rate budget" do
    Authentication::Throttle.reset_store!

    (AiAssistant::Limits::BURST.limit + 2).times do
      result = start
      expect(result).to be_success
      use!(result.conversation)
    end
  ensure
    Authentication::Throttle.reset_store!
  end

  it "rechecks the user quota after preflight and before installing the thread" do
    allow_any_instance_of(described_class).to receive(:preflight_failure).and_wrap_original do |original|
      failure = original.call
      AiAssistant::Conversation::MAX_PER_USER.times do
        used_conversation
      end
      failure
    end
    result = start
    expect(result).to have_attributes(http_status: 429, error_code: "conversation_count_limit")
    expect(AiAssistant::Conversation.owned_by(customer: customer, user: user).count)
      .to eq(AiAssistant::Conversation::MAX_PER_USER)
  end

  it "does not create another empty thread after lazy workspace creation" do
    current = AiAssistant::Conversation.current_for(customer: customer, user: user)
    expect { expect(start.error_code).to eq("current_chat_empty") }.not_to change(AiAssistant::Conversation, :count)
    expect(AiAssistant::Conversation.current_for(customer: customer, user: user)).to eq(current)
  end

  describe "when the thread the workspace has open is still empty" do
    it "refuses with a 422 rather than minting a second blank thread" do
      existing = create(:ai_assistant_conversation, customer: customer, user: user)

      result = nil
      expect { result = start }.not_to change(AiAssistant::Conversation, :count)

      expect(result).not_to be_success
      expect(result.http_status).to eq(422)
      expect(result.error_code).to eq("current_chat_empty")
      expect(result.errors).to include(I18n.t("ai_assistant.errors.current_chat_empty"))
      expect(AiAssistant::Conversation.current_for(customer: customer, user: user)).to eq(existing)
    end

    it "allows it again once that thread has been written to" do
      use!(create(:ai_assistant_conversation, customer: customer, user: user))

      expect(start).to be_success
    end

    it "ignores an empty thread that has been archived out of the way" do
      create(:ai_assistant_conversation, :archived, customer: customer, user: user)

      expect(start).to be_success
    end

    it "only considers the caller's own empty thread" do
      other = create(:user, :admin, customer: customer)
      create(:ai_assistant_conversation, customer: customer, user: other)

      expect(start).to be_success
    end

    it "leaves the very first chat of a brand new user alone" do
      expect(AiAssistant::Conversation.owned_by(customer: customer, user: user)).to be_empty

      expect(start).to be_success
    end
  end
end
