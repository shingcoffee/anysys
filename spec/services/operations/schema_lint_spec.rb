# frozen_string_literal: true

require "rails_helper"

RSpec.describe Operations::SchemaLint do
  let_it_be(:customer) { create(:customer) }
  let(:context) { Operations::Context.new(customer: customer, channel: "assistant") }

  it "returns no problems for a fully described operation" do
    expect(described_class.call(Operations::FakeLintClean, context)).to eq([])
  end

  it "does not mistake a property named type, or example data, for a schema" do
    expect(described_class.call(Operations::FakeLintTypeProperty, context)).to eq([])
  end

  it "reports each completeness rule on a dirty contract" do
    problems = described_class.call(Operations::FakeLintDirty, context)

    expect(problems).to include(a_string_matching(/title is missing/))
    expect(problems).to include(a_string_matching(/summary is missing/))
    expect(problems).to include(a_string_matching(/schema description is missing/))
    expect(problems).to include(a_string_matching(/missing a description/))
    expect(problems).to include(a_string_matching(/missing x-enum-descriptions/))
    expect(problems).to include(a_string_matching(/conditional is missing a description/))
    expect(problems).to include(a_string_matching(/additionalProperties: false/))
    expect(problems).to include(a_string_matching(/examples\[0\] is invalid/))
  end

  it "reports a projection that exceeds the size budget" do
    allow(Operations::SchemaProjection).to receive(:call).and_raise(Operations::SchemaProjection::TooLarge, "too big")

    expect(described_class.call(Operations::FakeLintClean, context)).to include("too big")
  end
end
