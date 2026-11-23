# frozen_string_literal: true

# Class-level registry interface shared by every email vendor spec.
# Host keeps vendor-specific `.configured?` coverage (required fields differ).
#
#   it_behaves_like "an email provider class interface",
#     key: "ses", delivery_mechanism: :webhook,
#     config_fields: %i[access_key_id region from_email sns_topic_arn]
RSpec.shared_examples "an email provider class interface" do |key:, delivery_mechanism:, config_fields:|
  it ".key is the registered vendor key" do
    expect(described_class.key).to eq(key)
  end

  it ".delivery_mechanism matches the vendor" do
    expect(described_class.delivery_mechanism).to eq(delivery_mechanism)
  end

  it ".config_fields declare the vendor config blob keys" do
    names = described_class.config_fields.map { |field| field[:name] }
    expect(names).to match_array(config_fields)
  end
end
