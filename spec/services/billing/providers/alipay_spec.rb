# frozen_string_literal: true
require "rails_helper"
require_relative "../partition_b_helpers"

RSpec.describe Billing::Providers::Alipay do
  include BillingPartitionBHelpers

  it "produces a genuine RSA2 signed page form with the merchant external reference and CNY-only ceiling" do
    aggregate = billing_aggregate(currency: "CNY")
    Payments::PlatformGateway.for_provider("alipay").update!(available: true)
    account = create(:payment_merchant_account, :alipay, customer: aggregate.fetch(:platform))
    method = create(:billing_payment_method, customer: aggregate.fetch(:tenant), provider: "alipay", merchant_account: account, authorized_by_id: aggregate.fetch(:actor).id)
    mandate = create(:payment_subscription, customer: aggregate.fetch(:platform), provider: "alipay", currency: "cny", cycle: "monthly", amount: 123,
      managed_by: "billing", external_ref: "billing-pm-#{method.customer_id}-alipay-#{method.id}")
    method.update!(payments_subscription: mandate)
    # A page API must sign locally; WebMock fails any unexpected network call.
    action = described_class.new(method).setup(return_url: "https://example.test/#{method.customer_id}/admin/settings/billing/payment_methods")[:action]
    expect(action).to include(kind: :provider_form, action_url: Payments::Gateways::Alipay::BILLING_SANDBOX_GATEWAY, method: "post")
    fields = action.fetch(:fields)
    expect(fields.fetch("method")).to eq("alipay.user.agreement.page.sign")
    expect(fields).to all(satisfy { |key, value| key.is_a?(String) && value.is_a?(String) })
    biz = JSON.parse(fields.fetch("biz_content"))
    expect(biz.fetch("external_agreement_no")).to eq(mandate.external_ref)
    expect(biz).not_to have_key("agreement_no")
    expect(biz.fetch("period_rule_params")).to include("period_type" => "MONTH", "period" => 1, "single_amount" => "123.00")
    signed = fields.except("sign").sort.map { |key, value| "#{key}=#{value}" }.join("&")
    key = OpenSSL::PKey::RSA.new(account.credential(:platform_public_key_pem))
    expect(key.verify(OpenSSL::Digest::SHA256.new, Base64.decode64(fields.fetch("sign")), signed)).to be(true)
  end
end
