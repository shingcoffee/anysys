# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiAssistant::Assistant::GenerationWriteGuard do
  let(:customer) { create(:customer) }
  let(:user) { create(:user, :admin, customer: customer) }
  let(:conversation) { create(:ai_assistant_conversation, customer: customer, user: user) }
  let(:message) do
    create(:ai_assistant_message, customer: customer, conversation: conversation)
  end
  let(:generation) do
    AiAssistant::Assistant::GenerationLifecycle.start!(
      conversation: conversation,
      user_message: message
    ).tap { |record| AiAssistant::Assistant::GenerationLifecycle.claim!(record) }
  end

  it "allows a write only while the generation is current and running" do
    value = described_class.new(generation: generation).call { "written" }

    expect(value).to eq("written")
  end

  describe ".wrap" do
    it "runs the write through the guard when there is one" do
      guard = described_class.new(generation: generation)
      allow(guard).to receive(:call).and_call_original

      expect(described_class.wrap(guard) { "written" }).to eq("written")
      expect(guard).to have_received(:call)
    end

    # A confirmation replay deliberately has no guard: it already runs inside
    # the conversation lock held by PendingConfirmation.
    it "runs the write directly when there is none" do
      expect(described_class.wrap(nil) { "written" }).to eq("written")
    end

    it "lets a rejection reach the caller" do
      guard = described_class.new(generation: generation)
      AiAssistant::Assistant::GenerationLifecycle.cancel!(conversation: conversation)

      expect { described_class.wrap(guard) { "written" } }
        .to raise_error(described_class::Rejected)
    end
  end

  it "rejects a generation after a newer turn supersedes it" do
    guard = described_class.new(generation: generation)
    newer_message = create(
      :ai_assistant_message,
      customer: customer,
      conversation: conversation,
      body: "Newer"
    )
    AiAssistant::Assistant::GenerationLifecycle.start!(
      conversation: conversation,
      user_message: newer_message
    )

    expect { guard.call { raise "must not run" } }
      .to raise_error(described_class::Rejected) { |error| expect(error.state).to eq(:superseded) }
  end

  it "allows a cancellation reply only while the cancelled generation is current" do
    guard = described_class.new(generation: generation)
    AiAssistant::Assistant::GenerationLifecycle.cancel!(conversation: conversation)

    value = guard.call(required_status: "cancelled") { "stopped" }

    expect(value).to eq("stopped")
  end

  it "rejects a cancelled predecessor after a newer generation becomes current" do
    guard = described_class.new(generation: generation)
    AiAssistant::Assistant::GenerationLifecycle.cancel!(conversation: conversation)
    newer_message = create(
      :ai_assistant_message,
      customer: customer,
      conversation: conversation,
      body: "Newer"
    )
    AiAssistant::Assistant::GenerationLifecycle.start!(
      conversation: conversation,
      user_message: newer_message
    )

    expect { guard.call(required_status: "cancelled") { raise "must not run" } }
      .to raise_error(described_class::Rejected) { |error| expect(error.state).to eq(:stale) }
  end
end
