# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::Admin::PaymentMethodComponent, type: :component do
  it "forwards setup descriptors and the stable request key rather than advertising arbitrary registered gateways" do
    render_inline described_class.new(payment_methods: [], available_providers: %w[alipay wechat_pay], customer_id: 12345678,
      provider_options: [{ key: "alipay", setup_kind: :redirect }], currency: "CNY", request_key: "request-identity")
    expect(page).to have_button("Set up Alipay (China)")
    expect(page).not_to have_text("WeChat")
    expect(page).to have_css('input[name="billing_payment_method[request_key]"][value="request-identity"]', visible: :all)
  end
end
