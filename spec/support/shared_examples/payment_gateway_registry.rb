# frozen_string_literal: true

# Registry lookup shared by every payment gateway spec.
# Host keeps credential_fields, JSAPI UA, flows, and capabilities.
#
#   it_behaves_like "a registered payment gateway", key: "stripe"
RSpec.shared_examples "a registered payment gateway" do |key:|
  it "registers under its vendor key" do
    expect(Payments::Gateways.keys.map(&:to_s)).to include(key.to_s)
    expect(Payments::Gateways.for(key.to_s)).to eq(described_class)
  end
end
