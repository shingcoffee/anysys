# frozen_string_literal: true

require "rails_helper"

RSpec.describe AccessPoints::PlatformProvider do
  subject(:provider) { described_class.new }

  describe "#applicable?" do
    it "returns true only for the platform-owner customer (81_721_200)" do
      expect(provider.applicable?(customer_id: 81_721_200)).to be true
      expect(provider.applicable?(customer_id: 12_345_678)).to be false
    end
  end

  describe "#call" do
    it "yields platform-only descriptors" do
      results = provider.call(customer_id: 81_721_200)
      keys = results.map(&:subject_key)
      expect(keys).to include("customers", "module_settings", "industry_templates", "code_generators")
      results.each { |d| expect(d.subject_type).to eq("Platform") }
    end

    it "labels platform features through I18n rather than English constants" do
      customers = provider.call(customer_id: 81_721_200).find { |d| d.subject_key == "customers" }
      expect(customers.label).to eq("Platform: Customers")

      I18n.with_locale(:"zh-CN") do
        customers = provider.call(customer_id: 81_721_200).find { |d| d.subject_key == "customers" }
        expect(customers.label).to eq(I18n.t("admin_settings.access_points.platform.customers", locale: :"zh-CN"))
      end
    end
  end
end
