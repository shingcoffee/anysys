# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::Contracts::OneTimePayment do
  def contract(attrs = {})
    described_class.new(OpenStruct.new({ provider: "stripe", invoice_id: 1, openid: nil }.merge(attrs)))
  end

  it "requires a provider" do
    form = contract(provider: "")
    expect(form.validate(provider: "", invoice_id: 1, openid: nil)).to be(false)
    expect(form.errors[:provider]).to be_present
  end

  it "accepts a provider with optional openid" do
    form = contract
    expect(form.validate(provider: "wechat_pay", invoice_id: 11, openid: "oABC")).to be(true)
  end

  it "does not persist client-supplied money or save_card fields" do
    form = contract
    form.validate(provider: "stripe", invoice_id: 11, amount_cents: 1, currency: "USD",
                  customer_id: 99, merchant_account_id: 4, save_card: true)
    expect(form.provider).to eq("stripe")
    expect(form.invoice_id).to eq(11)
    expect(form.class.definitions.keys.map(&:to_s)).to contain_exactly("provider", "invoice_id", "openid")
  end
end
