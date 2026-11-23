# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiAssistant::Assistant::ReplyWriter do
  let(:customer) { create(:customer) }
  let(:user) { create(:user, :admin, customer: customer) }
  let(:conversation) do
    create(:ai_assistant_conversation, customer: customer, user: user)
  end
  let(:user_message) do
    create(:ai_assistant_message, customer: customer, conversation: conversation)
  end
  let(:generation) do
    AiAssistant::Assistant::GenerationLifecycle.start!(
      conversation: conversation,
      user_message: user_message
    ).tap { |record| AiAssistant::Assistant::GenerationLifecycle.claim!(record) }
  end
  let(:write_guard) do
    AiAssistant::Assistant::GenerationWriteGuard.new(generation: generation)
  end

  before do
    allow(AiAssistant::Stream).to receive(:broadcast_message)
    allow(AiAssistant::Stream).to receive(:broadcast_artifact)
  end

  it "persists, broadcasts, and pins a tenant-owned artifact" do
    entity = create(:entity, customer: customer)
    finalized = AiAssistant::Assistant::Finalizer::Result.new(
      body: "Done",
      status: "complete",
      metadata: { "changes" => [] },
      artifact: entity,
      artifact_kind: "entity"
    )

    message = described_class.call(conversation: conversation, finalized: finalized)

    expect(message).to be_persisted
    expect(message.body).to eq("Done")
    expect(conversation.reload.artifact_id).to eq(entity.id)
    expect(AiAssistant::Stream).to have_received(:broadcast_message).with(message)
    expect(AiAssistant::Stream).to have_received(:broadcast_artifact).with(conversation)
  end

  it "rolls back the assistant message when artifact persistence fails" do
    entity = create(:entity, customer: customer)
    finalized = AiAssistant::Assistant::Finalizer::Result.new(
      body: "Done",
      status: "complete",
      metadata: { "changes" => [] },
      artifact: entity,
      artifact_kind: "entity"
    )
    allow(AiAssistant::Assistant::Artifact).to receive(:assign_record!)
      .and_raise(ActiveRecord::StatementInvalid, "artifact write failed")
    message_count = conversation.messages.where(role: "assistant").count

    expect {
      described_class.call(conversation: conversation, finalized: finalized)
    }.to raise_error(ActiveRecord::StatementInvalid, "artifact write failed")
    expect(conversation.messages.where(role: "assistant").count).to eq(message_count)
  end

  it "publishes only after the generation write fence transaction closes" do
    entity = create(:entity, customer: customer)
    finalized = AiAssistant::Assistant::Finalizer::Result.new(
      body: "Done",
      status: "complete",
      metadata: { "changes" => [] },
      artifact: entity,
      artifact_kind: "entity"
    )
    transaction_states = []
    allow(AiAssistant::Stream).to receive(:broadcast_message) do
      transaction_states << ActiveRecord::Base.connection.open_transactions
    end
    allow(AiAssistant::Stream).to receive(:broadcast_artifact) do
      transaction_states << ActiveRecord::Base.connection.open_transactions
    end
    baseline_transactions = ActiveRecord::Base.connection.open_transactions

    described_class.call(
      conversation: conversation,
      finalized: finalized,
      write_guard: write_guard
    )

    expect(transaction_states).to eq([baseline_transactions, baseline_transactions])
  end

  def proposal_result(body: "Review these changes.")
    AiAssistant::Assistant::Finalizer::Result.new(
      body: body,
      status: "complete",
      metadata: {
        "pending_confirmation" => {
          "kind" => "entity",
          "customer_id" => customer.id,
          "document" => { "entities" => [{ "name" => "Teacher" }] },
          "targets" => [{ "id" => 1, "name" => "Teacher", "version_id" => 1 }]
        }
      }
    )
  end

  it "retires an older pending proposal in the same transaction that parks a new one" do
    older = create(
      :ai_assistant_message, :assistant,
      conversation: conversation, customer: customer,
      metadata: {
        "pending_confirmation" => {
          "kind" => "entity",
          "customer_id" => customer.id,
          "document" => { "entities" => [{ "name" => "Student" }] },
          "targets" => [{ "id" => 2, "name" => "Student", "version_id" => 1 }]
        }
      }
    )

    described_class.call(conversation: conversation, finalized: proposal_result)

    metadata = older.reload.metadata_json
    expect(metadata).not_to have_key("pending_confirmation")
    expect(metadata).to have_key("superseded_proposal")
    expect(conversation.messages.with_pending_proposal.count).to eq(1)
  end

  it "does not retire an older proposal when the new message cannot be saved" do
    older = create(
      :ai_assistant_message, :assistant,
      conversation: conversation, customer: customer,
      metadata: {
        "pending_confirmation" => {
          "kind" => "entity",
          "customer_id" => customer.id,
          "document" => { "entities" => [{ "name" => "Student" }] },
          "targets" => [{ "id" => 2, "name" => "Student", "version_id" => 1 }]
        }
      }
    )

    expect {
      described_class.call(conversation: conversation, finalized: proposal_result(body: ""))
    }.to raise_error(ActiveRecord::RecordInvalid)

    expect(older.reload.metadata_json).to have_key("pending_confirmation")
    expect(older.metadata_json).not_to have_key("superseded_proposal")
  end
end
