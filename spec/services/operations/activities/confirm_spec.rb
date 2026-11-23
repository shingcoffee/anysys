# frozen_string_literal: true

require "rails_helper"

RSpec.describe Operations::Activities::Confirm do
  let_it_be(:customer) { create(:customer) }
  let_it_be(:other) { create(:customer) }
  let_it_be(:admin) { create(:user, :admin, customer: customer) }
  let(:context) { Operations::Context.new(customer: customer, actor: admin, channel: "assistant") }

  def parked(operation: "fake_update", **attrs)
    create(
      :operation_invocation,
      :awaiting_confirmation,
      customer: customer,
      user: admin,
      operation: operation,
      input: { "name" => "Alpha", "color" => "red", "count" => 1 },
      **attrs
    )
  end

  before do
    allow(Operations).to receive(:for).and_call_original
    allow(Operations).to receive(:for).with("fake_update").and_return(Operations::FakeUpdate)
    allow(Operations).to receive(:for).with("fake_stale").and_return(Operations::FakeStale)
    allow(Operations).to receive(:for).with("fake_echo").and_return(Operations::FakeEcho)
    allow(Operations).to receive(:for).with("fake_conflict_on_confirm").and_return(Operations::FakeConflictOnConfirm)
  end

  it "applies an invocation only from the conversation that parked it" do
    parked_in = create(:ai_assistant_conversation, customer: customer, user: admin)
    elsewhere = create(:ai_assistant_conversation, customer: customer, user: admin)
    invocation = parked(conversation_id: parked_in.id)

    other = described_class.call(
      invocation: invocation,
      context: Operations::Context.new(customer: customer, actor: admin, channel: "assistant", conversation: elsewhere)
    )
    expect(other.violations.map(&:code)).to eq(["proposal.not_pending"])
    expect(invocation.reload).to be_awaiting_confirmation

    same = described_class.call(
      invocation: invocation,
      context: Operations::Context.new(customer: customer, actor: admin, channel: "assistant", conversation: parked_in)
    )
    expect(same.status).to eq("succeeded")
  end

  it "returns conflict, not invalid, when re-validation reports a conflict" do
    invocation = parked(operation: "fake_conflict_on_confirm")
    outcome = described_class.call(invocation: invocation, context: context)

    expect(outcome.status).to eq("conflict")
    expect(outcome.violations.map(&:code)).to eq(["conflict.version_changed"])
    expect(invocation.reload).to be_conflict
  end

  it "applies a pending proposal and marks the row succeeded" do
    invocation = parked
    outcome = described_class.call(invocation: invocation, context: context)

    expect(outcome.status).to eq("succeeded")
    expect(invocation.reload).to be_succeeded
    expect(invocation.confirmed_by).to eq(admin)
    expect(invocation.confirmed_at).to be_present
  end

  it "returns conflict and marks the row when the snapshot is stale" do
    invocation = parked(operation: "fake_stale", snapshot: { "name" => "Alpha" })
    outcome = described_class.call(invocation: invocation, context: context)

    expect(outcome.status).to eq("conflict")
    expect(outcome.violations.first.code).to eq("conflict.version_changed")
    expect(invocation.reload).to be_conflict
  end

  it "rejects a proposal for another customer or a non-pending status" do
    foreign = create(:operation_invocation, :awaiting_confirmation, customer: other, user: create(:user, :admin, customer: other))
    expect(described_class.call(invocation: foreign, context: context).violations.first.code).to eq("proposal.not_pending")

    done = create(:operation_invocation, customer: customer, user: admin, status: "succeeded")
    expect(described_class.call(invocation: done, context: context).violations.first.code).to eq("proposal.not_pending")
  end

  it "rejects a parked proposal when the operation version changed" do
    invocation = parked(operation_version: 9)
    outcome = described_class.call(invocation: invocation, context: context)

    expect(outcome.violations.first.code).to eq("operation.version_changed")
  end

  it "supersedes a parked proposal" do
    invocation = parked
    described_class.supersede!(invocation)
    expect(invocation.reload).to be_superseded
  end

  it "declines a parked proposal and stamps the confirmer" do
    invocation = parked
    described_class.decline!(invocation, actor: admin)

    expect(invocation.reload).to be_declined
    expect(invocation.confirmed_by).to eq(admin)
    expect(invocation.confirmed_at).to be_present
  end
end
