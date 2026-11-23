# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::Admin::PaymentAuthorizationComponent, type: :component do
  def render_authorization(**options)
    render_inline described_class.new(available_providers: [], customer_id: 12345678, **options)
  end

  it "renders the controlled Alipay vendor form without sending a Rails CSRF token to the provider" do
    render_authorization(authorization: { kind: :provider_form, action_url: "https://openapi.alipay.com/gateway.do",
      method: "post", fields: { "sign" => "signed", "biz_content" => '<script>bad</script>' } })
    expect(page).to have_css('form[action="https://openapi.alipay.com/gateway.do"][data-turbo="false"]')
    expect(page).to have_css('input[name="sign"][value="signed"]', visible: :all)
    expect(page).not_to have_css('input[name="authenticity_token"], script', visible: :all)
  end

  it "renders the validated redirect and truthful pending verification explanation" do
    render_authorization(authorization: { kind: :redirect, url: "https://openapi.alipay.com/gateway.do?sign=signed" })
    expect(page).to have_link("Continue", href: "https://openapi.alipay.com/gateway.do?sign=signed")
    expect(page).to have_text("Provider confirmation is pending")
  end

  it "mounts the existing SetupIntent mode with method-scoped confirmation, not PaymentIntent mode" do
    render_authorization(authorization: { kind: :stripe_setup, publishable_key: "pk_test", client_secret: "seti_secret",
      confirmation_url: "/12345678/admin/settings/billing/payment_methods/9/confirmation" })
    expect(page).to have_css('[data-controller="payments--stripe-card"][data-payments--stripe-card-billing-setup-value="true"]')
    expect(page).to have_css('[data-payments--stripe-card-setup-client-secret-value="seti_secret"]')
    expect(page).not_to have_css('[data-payments--stripe-card-client-secret-value]')
    expect(page).to have_css('[data-payments--stripe-card-target="error"][role="alert"]', visible: :all)
  end

  it "keeps disabled currency/provider options explanatory rather than actionable" do
    render_authorization(currency: "USD", provider_options: [{ key: "alipay", enabled: false,
      reason_key: "settings_billing.payment_methods.currency_incompatible" }])
    expect(page).to have_text("cannot collect invoices in USD")
    expect(page).not_to have_css("form")
  end

  it "names the redirect provider from the pending payment method" do
    method = double(id: 9, to_param: "9", provider: "wechat_pay", status: "pending")
    render_authorization(payment_method: method, authorization: {
      kind: :redirect, url: "https://pay.weixin.qq.com/authorize", confirmation_url: "/12345678/admin/settings/billing/payment_methods/9/confirmation"
    })
    expect(page).to have_text("Continue to WeChat Pay (China) to authorize recurring subscription charges.")
    expect(page).not_to have_text("Alipay (China)")
  end

  it "posts Verify authorization only while the method is pending" do
    pending_method = double(id: 9, to_param: "9", provider: "stripe", status: "pending")
    render_authorization(payment_method: pending_method, authorization: {
      kind: :redirect, url: "https://checkout.stripe.com/authorize",
      confirmation_url: "/12345678/admin/settings/billing/payment_methods/9/confirmation"
    })
    expect(page).to have_button("Verify authorization")
    expect(page).to have_css('form[action="/12345678/admin/settings/billing/payment_methods/9/confirmation"]')

    active_method = double(id: 9, to_param: "9", provider: "stripe", status: "active")
    render_authorization(payment_method: active_method, authorization: {
      kind: :redirect, url: "https://checkout.stripe.com/authorize",
      confirmation_url: "/12345678/admin/settings/billing/payment_methods/9/confirmation"
    })
    expect(page).not_to have_button("Verify authorization")
  end
end
