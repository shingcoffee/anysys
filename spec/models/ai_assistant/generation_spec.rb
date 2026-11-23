# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiAssistant::Generation do
  let(:customer) { create(:customer) }
  let(:user) { create(:user, :admin, customer: customer) }
  let(:conversation) { create(:ai_assistant_conversation, customer: customer, user: user) }
  let(:user_message) do
    create(:ai_assistant_message, customer: customer, conversation: conversation)
  end

  it "persists a tenant-scoped queued generation for its source user message" do
    generation = described_class.create!(
      customer: customer,
      conversation: conversation,
      user_message: user_message,
      token: "generation-token"
    )

    expect(generation).to have_attributes(
      customer: customer,
      conversation: conversation,
      user_message: user_message,
      status: "queued",
      started_at: nil,
      finished_at: nil,
      cancelled_at: nil,
      failure_code: nil
    )
    expect(described_class.for_customer(customer.id)).to contain_exactly(generation)
  end

  it "rejects an unsupported lifecycle status" do
    generation = described_class.new(
      customer: customer,
      conversation: conversation,
      user_message: user_message,
      token: "generation-token",
      status: "unknown"
    )

    expect(generation).not_to be_valid
    expect(generation.errors[:status]).to be_present
  end

  it "rejects a user message from another conversation" do
    other_user = create(:user, :admin, customer: customer)
    other_conversation = create(
      :ai_assistant_conversation,
      customer: customer,
      user: other_user
    )
    other_message = create(
      :ai_assistant_message,
      customer: customer,
      conversation: other_conversation
    )
    generation = described_class.new(
      customer: customer,
      conversation: conversation,
      user_message: other_message,
      token: "generation-token"
    )

    expect(generation).not_to be_valid
    expect(generation.errors[:user_message]).to be_present
  end

  it "rejects a user message whose customer differs from the conversation" do
    other_customer = create(:customer)
    other_customer_message = create(
      :ai_assistant_message,
      customer: other_customer,
      conversation: conversation
    )
    generation = described_class.new(
      customer: customer,
      conversation: conversation,
      user_message: other_customer_message,
      token: "generation-token"
    )

    expect(generation).not_to be_valid
    expect(generation.errors[:user_message]).to be_present
  end
end
