# frozen_string_literal: true
require "rails_helper"

RSpec.describe Billing::Contracts::ChangePlan do
  it "accepts both cadences and rejects malformed request identities" do
    monthly = create(:billing_plan)
    yearly = create(:billing_plan, :yearly)
    [monthly, yearly].each do |plan|
      form = described_class.new(OpenStruct.new)
      expect(form.validate(plan_code: plan.code, request_key: SecureRandom.uuid)).to be(true)
    end
    form = described_class.new(OpenStruct.new)
    expect(form.validate(plan_code: yearly.code, request_key: "price-override")).to be(false)
    expect(form.request_key).to eq("price-override")
    expect(form.errors[:request_key]).to be_present
  end

  it "does not accept archived plans for new requests" do
    plan = create(:billing_plan, active: false, archived_at: Time.current)
    form = described_class.new(OpenStruct.new)
    expect(form.validate(plan_code: plan.code, request_key: SecureRandom.uuid)).to be(false)
  end
end
