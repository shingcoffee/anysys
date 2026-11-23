# frozen_string_literal: true

require "rails_helper"

RSpec.describe FeatureModules::PageHandoff do
  let_it_be(:customer) { create(:customer) }
  let(:session) { {} }
  let(:entry) { instance_double(EntityEntry, id: 7) }
  let(:page) { instance_double(Page, id: 42) }

  def call(outcome: {})
    described_class.call(session: session, customer: customer, page: page, entity_entry: entry, outcome: outcome)
  end

  before { allow(FeatureModules::Invocation).to receive(:begin!).and_return("/entry") }

  it "does not hand off when the outcome has no handoff" do
    expect(call(outcome: { "preset" => "submitted" })).to be(false)
    expect(FeatureModules::Invocation).not_to have_received(:begin!)
  end

  it "begins a handoff from the outcome's already-resolved input" do
    expect(call(outcome: {
      "handoff" => { "module_key" => "email", "input" => { "to" => "a@b.test" }, "exit_target" => { "kind" => "route" } }
    })).to be(true)

    expect(FeatureModules::Invocation).to have_received(:begin!).with(
      session: session, customer: customer, triggering_page: page, entity_entry: entry,
      module_key: "email", input: { "to" => "a@b.test" }, exit_target: { "kind" => "route" },
      on_success: nil, audience: nil
    )
  end

  it "carries what to change once the module succeeds and who started it" do
    plan = { "entity_id" => 3, "entry_id" => 7, "fields" => { "status" => "Paid" } }
    described_class.call(session: session, customer: customer, page: page, entity_entry: entry, audience: "member",
                         outcome: { "handoff" => { "module_key" => "payment", "input" => {}, "on_success" => plan } })

    expect(FeatureModules::Invocation).to have_received(:begin!)
      .with(hash_including(module_key: "payment", on_success: plan, audience: "member"))
  end

  it "ignores a malformed outcome handoff" do
    expect(call(outcome: { "handoff" => { "module_key" => "", "input" => "x" } })).to be(false)
    expect(call(outcome: { "handoff" => "payment" })).to be(false)
    expect(FeatureModules::Invocation).not_to have_received(:begin!)
  end

  it "passes an empty input when the outcome handoff input is not a hash" do
    call(outcome: { handoff: { module_key: "email", input: "x" } })
    expect(FeatureModules::Invocation).to have_received(:begin!).with(hash_including(module_key: "email", input: {}))
  end
end
