# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiAssistant::ReplyJob do
  let_it_be(:customer) { create(:customer) }
  let_it_be(:user) { create(:user, customer: customer) }
  let(:conversation) { create(:ai_assistant_conversation, customer: customer, user: user) }
  let(:message) { create(:ai_assistant_message, customer: customer, conversation: conversation) }
  let(:generation) do
    AiAssistant::Assistant::GenerationLifecycle.start!(
      conversation: conversation,
      user_message: message
    )
  end

  it "loads the generation, sets Current.customer, and calls Reply" do
    without_partial_double_verification do
      expect(AiAssistant::Activities::Reply).to receive(:call) do |generation:|
        expect(generation).to eq(self.generation)
        expect(Current.customer).to eq(customer)
      end
    end
    described_class.new.perform(generation.id)
  end

  it "is a no-op when the generation is gone" do
    expect(AiAssistant::Activities::Reply).not_to receive(:call)
    expect { described_class.new.perform(-1) }.not_to raise_error
  end

  it "runs Reply in the conversation user's locale" do
    zh_user = create(:user, customer: customer, locale: "zh-CN")
    zh_conversation = create(:ai_assistant_conversation, customer: customer, user: zh_user)
    zh_message = create(:ai_assistant_message, customer: customer, conversation: zh_conversation)
    zh_generation = AiAssistant::Assistant::GenerationLifecycle.start!(
      conversation: zh_conversation,
      user_message: zh_message
    )
    without_partial_double_verification do
      expect(AiAssistant::Activities::Reply).to receive(:call) do |generation:|
        expect(generation).to eq(zh_generation)
        expect(I18n.locale).to eq(:"zh-CN")
      end
    end
    described_class.new.perform(zh_generation.id)
  end

  it "clears tenant context when reply execution raises" do
    allow(AiAssistant::Activities::Reply).to receive(:call)
      .with(generation: generation)
      .and_raise(ActiveRecord::StatementInvalid, "write failed")

    expect {
      described_class.new.perform(generation.id)
    }.to raise_error(ActiveRecord::StatementInvalid, "write failed")
    expect(Current.customer).to be_nil
  end
end
