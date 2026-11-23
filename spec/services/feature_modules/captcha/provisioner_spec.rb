# frozen_string_literal: true

require "rails_helper"

RSpec.describe FeatureModules::Captcha::Provisioner do
  let_it_be(:customer) { create(:customer) }

  describe ".call" do
    it "is a no-op (returns nil)" do
      expect(described_class.call(customer)).to be_nil
    end
  end

  describe ".deprovision" do
    it "strips the captcha key from each Page#configuration_json for the customer" do
      page1 = create(:page, customer: customer)
      page1.configuration_json = page1.configuration_json.merge(
        "captcha" => { "enabled" => true }
      )
      page1.save!(validate: false)

      described_class.deprovision(customer)

      expect(page1.reload.configuration_json["captcha"]).to be_nil
    end
  end
end
