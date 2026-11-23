# frozen_string_literal: true

require "rails_helper"

RSpec.describe Operations::Base do
  let_it_be(:customer) { create(:customer) }
  let(:context) { Operations::Context.new(customer: customer, channel: "assistant") }

  it "exposes the DSL readers, default hooks, and a tool definition" do
    expect(Operations::FakeEcho.key).to eq("fake_echo")
    expect(Operations::FakeEcho.version).to eq(1)
    expect(Operations::FakeEcho.confirmation).to eq(:never)
    expect(Operations::FakeUpdate.confirmation).to eq(:always)
    expect(Operations::FakeEcho.available?(context)).to be(true)

    instance = Operations::FakeEcho.new(context: context)
    expect(instance.validate({})).to eq([])
    expect(instance.plan({})).to be_nil
    expect(instance.snapshot({})).to be_nil
    expect(instance.stale?({})).to be(false)

    tool = Operations::FakeEcho.tool_definition(context)
    expect(tool[:name]).to eq("fake_echo")
    expect(tool[:description]).to eq(Operations::FakeEcho.summary)
    expect(tool[:parameters]).to be_a(Hash)
  end

  it "does not register fake operations on the global registry" do
    expect(Operations.all.map(&:key)).not_to include("fake_echo")
  end
end
