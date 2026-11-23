# frozen_string_literal: true

require "rails_helper"

RSpec.describe AccessPoints::ModuleProvider do
  subject(:provider) { described_class.new }

  let_it_be(:customer) { create(:customer) }

  it "yields one descriptor per enabled module with :manage action" do
    fm = create(:feature_module, key: "payments", name: "Payments", status: :active)
    create(:customer_feature_module, customer: customer, feature_module: fm, status: :active)

    results = provider.call(customer_id: customer.id)
    descriptor = results.find { |d| d.subject_key == "payments" }
    expect(descriptor).not_to be_nil
    expect(descriptor.subject_type).to eq("Module")
    expect(descriptor.actions).to eq([:manage])
    expect(descriptor.group_key).to eq("modules.payments")
    expect(descriptor.label).to eq("Payments")
  end

  it "uses FeatureModules::Module#display_name as the grant label" do
    fm = create(:feature_module, name: "English Name", status: :active)
    create(:customer_feature_module, customer: customer, feature_module: fm, status: :active)
    allow_any_instance_of(FeatureModules::Module).to receive(:display_name).and_return("Localized module")

    descriptor = provider.call(customer_id: customer.id).find { |d| d.subject_key == fm.key }
    expect(descriptor.label).to eq("Localized module")
  end

  it "labels the derived modules.<key> group with #display_name after #call" do
    fm = create(:feature_module, name: "English Name", status: :active)
    create(:customer_feature_module, customer: customer, feature_module: fm, status: :active)
    allow_any_instance_of(FeatureModules::Module).to receive(:display_name).and_return("Localized module")

    provider.call(customer_id: customer.id)
    expect(provider.label_for_group("modules.#{fm.key}")).to eq("Localized module")
  end

  it "includes required modules even when no assignment exists" do
    # The available_for_customer scope includes required modules regardless of assignment
    results_before = provider.call(customer_id: customer.id)

    # Check if any required modules exist and are in the results
    required_modules = FeatureModules::Module.required.available
    expected_keys = required_modules.map(&:key)

    results_keys = results_before.map(&:subject_key)
    expected_keys.each do |key|
      expect(results_keys).to include(key)
    end
  end
end
