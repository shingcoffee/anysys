# frozen_string_literal: true

require "rails_helper"

RSpec.describe Email::Contracts::Send do
  subject(:contract) { described_class.new(described_class::Input.new) }

  let(:customer)  { create(:customer) }
  let!(:template) { create(:email_template, customer: customer, name: "welcome") }

  def validate_with(overrides = {})
    defaults = { customer_id: customer.id, to: "user@example.com",
                 template_id: template.id, vars: { first_name: "John" } }
    contract.validate(defaults.merge(overrides))
    contract
  end

  describe "validations" do
    it "is valid with correct inputs" do
      expect(validate_with.errors).to be_empty
    end

    it "exposes the resolved template on a valid form" do
      validate_with
      expect(contract.template).to eq(template)
    end

    it "is invalid when to is blank" do
      c = validate_with(to: "")
      expect(c.errors[:to]).to be_present
    end

    it "is invalid when to has a bad email format" do
      c = validate_with(to: "not-an-email")
      expect(c.errors[:to]).to include("is not a valid email")
    end

    it "is invalid for a non-existent template" do
      c = validate_with(template_id: -1)
      expect(c.errors[:template_id]).to include("is not a registered active template")
    end

    it "does not match vars against the template variables" do
      c = validate_with(vars: { unknown: "value" })
      expect(c.errors[:vars]).to be_empty
    end
  end
end
