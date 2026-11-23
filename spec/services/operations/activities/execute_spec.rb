# frozen_string_literal: true

require "rails_helper"

RSpec.describe Operations::Activities::Execute do
  let_it_be(:customer) { create(:customer) }
  let_it_be(:admin) { create(:user, :admin, customer: customer) }
  let(:around_calls) { [] }
  let(:context) do
    Operations::Context.new(
      customer: customer,
      actor: admin,
      channel: "assistant",
      around_write: ->(&block) { around_calls << true; block.call }
    )
  end

  def run(operation:, input: { "name" => "Alpha" }, ctx: context)
    described_class.call(operation: operation, input: input, context: ctx)
  end

  it "turns an unknown key or non-operation class into operation.unknown" do
    allow(Operations).to receive(:keys).and_return(%i[fake_echo])
    allow(Operations).to receive(:for).and_call_original
    allow(Operations).to receive(:for).with("nope").and_raise(ArgumentError, "unknown operation: \"nope\"")

    unknown = run(operation: "nope")
    expect(unknown).not_to be_ok
    expect(unknown.violations.first.code).to eq("operation.unknown")
    expect(unknown.violations.first.details["available"]).to include("fake_echo")

    nil_key = run(operation: nil)
    expect(nil_key.violations.first.code).to eq("operation.unknown")

    not_an_operation = run(operation: String)
    expect(not_an_operation.violations.first.code).to eq("operation.unknown")
  end

  it "forbids members, inactive users, and unavailable operations" do
    member_ctx = Operations::Context.new(customer: customer, actor: create(:user, :member, customer: customer), channel: "assistant")
    expect(run(operation: Operations::FakeEcho, ctx: member_ctx).status).to eq("forbidden")

    unavailable = run(operation: Operations::FakeUnavailable)
    expect(unavailable.status).to eq("forbidden")
    expect(unavailable.violations.first.code).to eq("permission.denied")
  end

  it "replays a stored outcome for the same idempotency key and digest" do
    ctx = Operations::Context.new(customer: customer, actor: admin, channel: "assistant", idempotency_key: "gen-1")
    first = run(operation: Operations::FakeEcho, ctx: ctx)
    second = run(operation: Operations::FakeEcho, ctx: ctx)

    expect(first).to be_ok
    expect(second.replayed).to be(true)
    expect(second.status).to eq("succeeded")
    expect(OperationInvocation.where(customer_id: customer.id, idempotency_key: "gen-1").count).to eq(1)
  end

  it "re-runs a rejected call instead of replaying the rejection" do
    ctx = Operations::Context.new(customer: customer, actor: admin, channel: "assistant", idempotency_key: "gen-3")
    first = run(operation: Operations::FakeSemantic, ctx: ctx)
    second = run(operation: Operations::FakeSemantic, ctx: ctx)

    expect([first.status, second.status]).to eq(%w[invalid invalid])
    expect(second.replayed).to be(false)
    rows = OperationInvocation.where(customer_id: customer.id, operation: "fake_semantic")
    expect(rows.count).to eq(2)
    expect(rows.pluck(:idempotency_key)).to all(be_nil)
  end

  it "rejects reuse of an idempotency key with a different digest" do
    ctx = Operations::Context.new(customer: customer, actor: admin, channel: "assistant", idempotency_key: "gen-2")
    run(operation: Operations::FakeEcho, input: { "name" => "Alpha" }, ctx: ctx)
    reused = run(operation: Operations::FakeEcho, input: { "name" => "Beta" }, ctx: ctx)

    expect(reused.status).to eq("invalid")
    expect(reused.violations.first.code).to eq("idempotency.key_reused")
  end

  it "returns schema and semantic violations without writing" do
    schema = run(operation: Operations::FakeEcho, input: {})
    expect(schema.status).to eq("invalid")
    expect(schema.violations.map(&:code)).to include("schema.required")

    semantic = run(operation: Operations::FakeSemantic)
    expect(semantic.status).to eq("invalid")
    expect(OperationInvocation.where(operation: "fake_semantic").count).to eq(1)
  end

  it "turns an exception raised before perform into internal.error without leaking it" do
    outcome = run(operation: Operations::FakeValidateBoom)

    expect(outcome.status).to eq("failed")
    expect(outcome.violations.map(&:code)).to eq(["internal.error"])
    expect(JSON.generate(outcome.to_tool_payload)).not_to include("secret internals")
  end

  it "keeps the audit row when a concurrent call already holds the idempotency key" do
    ctx = Operations::Context.new(customer: customer, actor: admin, channel: "assistant", idempotency_key: "gen-race")
    calls = 0
    allow(OperationInvocation).to receive(:create!).and_wrap_original do |original, attrs|
      calls += 1
      raise ActiveRecord::RecordNotUnique, "duplicate key" if calls == 1

      original.call(attrs)
    end

    outcome = run(operation: Operations::FakeEcho, ctx: ctx)

    expect(outcome.status).to eq("succeeded")
    expect(outcome.invocation.idempotency_key).to be_nil
  end

  it "accepts a single Violation returned from validate" do
    outcome = run(operation: Operations::FakeSingleViolation)

    expect(outcome.status).to eq("invalid")
    expect(outcome.violations.map(&:code)).to eq(["schema.invalid"])
  end

  it "returns a dry_run plan without creating an invocation" do
    dry = Operations::Context.new(customer: customer, actor: admin, channel: "api", dry_run: true)
    outcome = run(operation: Operations::FakeUpdate, ctx: dry)

    expect(outcome.status).to eq("dry_run")
    expect(outcome.plan).to eq([{ "kind" => "echo", "name" => "Alpha" }])
    expect(OperationInvocation.count).to eq(0)
  end

  it "parks confirmation: :always calls as awaiting_confirmation" do
    outcome = run(operation: Operations::FakeUpdate)

    expect(outcome.status).to eq("confirmation_required")
    expect(outcome.invocation).to be_awaiting_confirmation
    expect(outcome.invocation.plan).to eq([{ "kind" => "echo", "name" => "Alpha" }])
    expect(around_calls).to be_empty
  end

  it "performs a write inside around_write and records the invocation" do
    outcome = run(operation: Operations::FakeEcho)

    expect(outcome.status).to eq("succeeded")
    expect(outcome.data["color"]).to eq("red")
    expect(around_calls).to eq([true])
    expect(outcome.invocation).to be_succeeded
    expect(outcome.invocation.duration_ms).to be >= 0
  end

  it "does not audit read-only operations" do
    run(operation: Operations::FakeRead)
    expect(OperationInvocation.count).to eq(0)
  end

  it "maps RecordInvalid to domain.invalid and other errors to internal.error" do
    domain = run(operation: Operations::FakeDomainError)
    expect(domain.status).to eq("invalid")
    expect(domain.violations.first.code).to eq("domain.invalid")
    expect(domain.violations.first.details["errors"]).to include(a_string_matching(/reserved/))

    boom = run(operation: Operations::FakeBoom)
    expect(boom.status).to eq("failed")
    expect(boom.violations.first.code).to eq("internal.error")
  end

  it "returns a non-ok outcome from perform as-is and rolls its writes back" do
    outcome = run(operation: Operations::FakeWriteThenFail)

    expect(outcome.status).to eq("invalid")
    expect(outcome.violations.first.code).to eq("schema.invalid")
    expect(OperationInvocation.where(operation: "partial_write")).to be_empty
  end

  it "rolls back even when the caller already holds a transaction" do
    ctx = Operations::Context.new(
      customer: customer,
      actor: admin,
      channel: "assistant",
      around_write: ->(&block) { customer.with_lock { block.call } }
    )

    expect(run(operation: Operations::FakeWriteThenFail, ctx: ctx).status).to eq("invalid")
    expect(OperationInvocation.where(operation: "partial_write")).to be_empty
  end

  it "lets exceptions raised by around_write itself propagate" do
    rejected = Class.new(StandardError)
    ctx = Operations::Context.new(
      customer: customer,
      actor: admin,
      channel: "assistant",
      around_write: ->(&) { raise rejected, "stale" }
    )

    expect { run(operation: Operations::FakeEcho, ctx: ctx) }.to raise_error(rejected, "stale")
  end
end
