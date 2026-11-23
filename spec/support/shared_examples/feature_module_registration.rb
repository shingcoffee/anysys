# frozen_string_literal: true

# Identity shared by every FeatureModules::*::Registration spec.
#
#   it_behaves_like "a feature module registration",
#     key: "email", name: "Email"
#   it_behaves_like "a feature module registration",
#     key: "captcha", name: "Captcha", inactive: true, required: false
RSpec.shared_examples "a feature module registration" do |key:, name:, inactive: nil, required: nil|
  it "declares module metadata" do
    expect(described_class.module_key).to eq(key)
    expect(described_class.module_name).to eq(name)
  end

  it "registers a FeatureModules::Module row" do
    described_class.register!
    record = FeatureModules::Module.find_by(key: key)
    expect(record).to be_present
    expect(record.name).to eq(name)
    expect(record).to be_inactive if inactive
    expect(record.required).to eq(required) unless required.nil?
  end
end
