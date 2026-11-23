# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::Admin::OneTimePaymentComponent, type: :component do
  let(:invoice) do
    double(
      "invoice",
      id: 11,
      to_param: "11",
      number: "INV-12345678-00011",
      status: "open",
      currency: "USD",
      total_cents: 4950,
      period_start: Time.zone.local(2026, 6, 1),
      period_end: Time.zone.local(2026, 7, 1),
      due_at: Time.zone.local(2026, 6, 15)
    )
  end
  let(:providers) { [{ key: "stripe" }, { key: "paypal" }, { key: "alipay" }] }
  let(:urls) do
    {
      post_url: "/12345678/admin/settings/billing/invoices/11/one_time_payment",
      status_url: "/12345678/admin/settings/billing/invoices/11/one_time_payment/status",
      confirm_url: "/12345678/admin/settings/billing/invoices/11/one_time_payment/confirm",
      result_url: "/12345678/admin/settings/billing/invoices/11",
      back_url: "/12345678/admin/settings/billing/invoices/11"
    }
  end

  def render_checkout(**options)
    render_inline described_class.new(invoice: invoice, customer_id: 12345678, providers: providers, **urls, **options)
  end

  it "summarizes the invoice and offers provider tiles before a payment starts" do
    render_checkout
    expect(page).to have_text("Invoice INV-12345678-00011")
    expect(page).to have_text("One-time")
    expect(page).to have_text("$49.50 USD")
    expect(page).to have_text("This payment settles only this invoice once")
    expect(page).to have_link("Back to invoice", href: urls[:back_url])
    expect(page).to have_text("Preferred payment provider")
    expect(page).to have_css('input[name="one_time_payment[provider]"][value="stripe"]', visible: :all)
    expect(page).not_to have_text("Complete payment")
    expect(page).not_to have_css('[data-controller="payments--stripe-card"]')
    expect(page).not_to have_css('[data-payments--stripe-card-billing-setup-value]')
  end

  it "mounts Stripe PaymentIntent checkout without billing setup or save-card" do
    render_checkout(payment_action: {
      kind: :stripe_card, provider: "stripe", publishable_key: "pk_test", client_secret: "pi_secret"
    })
    expect(page).to have_css('[data-controller="payments--stripe-card"]')
    expect(page).to have_css('[data-payments--stripe-card-publishable-key-value="pk_test"]')
    expect(page).to have_css('[data-payments--stripe-card-client-secret-value="pi_secret"]')
    expect(page).to have_css('[data-payments--stripe-card-result-url-value="/12345678/admin/settings/billing/invoices/11"]')
    expect(page).to have_css('[data-payments--stripe-card-target="element"]')
    expect(page).to have_css('[data-payments--stripe-card-target="error"][role="alert"][aria-live="polite"]', visible: :all)
    expect(page).to have_css('[data-action="click->payments--stripe-card#submit"]', text: "Pay $49.50 USD")
    expect(page).not_to have_css('[data-payments--stripe-card-billing-setup-value]')
    expect(page).not_to have_text("Save this card")
    expect(page).not_to have_field("save_card")
    expect(page).to have_button("Verify payment status")
    expect(page).to have_link("Refresh status", href: urls[:post_url])
  end

  it "mounts PayPal Smart Buttons with capture URLs and localized SDK copy" do
    render_checkout(payment_action: {
      kind: :paypal_buttons, provider: "paypal", client_id: "client_abc", paypal_order_id: "ORDER-1"
    })
    expect(page).to have_css('[data-controller="payments--paypal-buttons"]')
    expect(page).to have_css('[data-payments--paypal-buttons-client-id-value="client_abc"]')
    expect(page).to have_css('[data-payments--paypal-buttons-paypal-order-id-value="ORDER-1"]')
    expect(page).to have_css('[data-payments--paypal-buttons-currency-value="USD"]')
    expect(page).to have_css('[data-payments--paypal-buttons-status-url-value="/12345678/admin/settings/billing/invoices/11/one_time_payment/status"]')
    expect(page).to have_css('[data-payments--paypal-buttons-result-url-value="/12345678/admin/settings/billing/invoices/11"]')
    expect(page).to have_css("[data-payments--paypal-buttons-sdk-error-value]")
    expect(page).to have_css("[data-payments--paypal-buttons-cancelled-text-value]")
    expect(page).to have_css("[data-payments--paypal-buttons-error-text-value]")
    expect(page).to have_css('[data-payments--paypal-buttons-target="element"]')
    expect(page).to have_css('[data-payments--paypal-buttons-target="error"][role="alert"]', visible: :all)
    expect(page).to have_text("Secured by PayPal")
  end

  it "renders a server-side QR SVG and wires status polling" do
    render_checkout(payment_action: {
      kind: :qr, provider: "alipay", code_url: "weixin://wxpay/bizpayurl?pr=abc"
    })
    expect(page).to have_css('[data-controller="payments--qr-poll"]')
    expect(page).to have_css('[data-payments--qr-poll-status-url-value="/12345678/admin/settings/billing/invoices/11/one_time_payment/status"]')
    expect(page).to have_css('[data-payments--qr-poll-result-url-value="/12345678/admin/settings/billing/invoices/11"]')
    expect(page).to have_css("[data-payments--qr-poll-status-prefix-value]")
    expect(page).to have_css("[data-payments--qr-poll-status-labels-value]")
    expect(page).to have_text("Scan to pay")
    expect(page).to have_text("Use Alipay (China) to scan the code below")
    expect(page).to have_css("svg")
    expect(page).to have_css('[data-payments--qr-poll-target="status"]', text: "Waiting for payment")
    expect(page.native.to_html).not_to include("api.qrserver.com")
  end

  it "mounts an H5 redirect with a tap-to-continue fallback" do
    render_checkout(payment_action: { kind: :h5, provider: "alipay", url: "https://m.alipay.com/pay" })
    expect(page).to have_css('[data-controller="payments--h5-redirect"][data-payments--h5-redirect-url-value="https://m.alipay.com/pay"]')
    expect(page).to have_text("Redirecting to your payment app")
    expect(page).to have_link("Tap to continue", href: "https://m.alipay.com/pay")
  end

  it "mounts JSAPI completion with provider params" do
    render_checkout(payment_action: {
      kind: :jsapi, provider: "wechat_pay", params: { trade_no: "wx-9" }
    })
    expect(page).to have_css('[data-controller="payments--jsapi-invoker"]')
    expect(page).to have_css('[data-payments--jsapi-invoker-provider-value="wechat_pay"]')
    expect(page).to have_css('[data-payments--jsapi-invoker-result-url-value="/12345678/admin/settings/billing/invoices/11"]')
    expect(page.find("[data-payments--jsapi-invoker-params-value]", visible: :all)["data-payments--jsapi-invoker-params-value"]).to include("trade_no")
    expect(page).to have_css(".size-2\\.5.animate-pulse.rounded-full.bg-accent")
    expect(page).to have_text("Completing payment")
  end

  it "shows the empty provider state on the selector card" do
    render_checkout(providers: [])
    expect(page).to have_text("No one-time payment provider is available")
    expect(page).not_to have_css("form")
  end

  it "keeps a provider switcher under an in-flight payment" do
    render_checkout(payment_action: { kind: :stripe_card, provider: "stripe", publishable_key: "pk", client_secret: "pi" })
    expect(page).to have_text("Pay with a different provider")
    expect(page).to have_css(".border-accent.ring-accent", text: "Credit / Debit Card (Stripe)")
    expect(page).to have_css('input[name="one_time_payment[provider]"][value="paypal"]', visible: :all)
    expect(page).to have_text("Complete payment with your selected provider")
  end

  it "renders an error alert above the checkout" do
    render_checkout(error_message: "That charge could not be started.")
    expect(page).to have_css('[role="alert"]', text: "That charge could not be started.")
  end

  it "localizes the checkout in zh-CN" do
    I18n.with_locale(:"zh-CN") do
      render_checkout
      expect(page).to have_text("单次付款")
      expect(page).to have_text("返回账单详情")
      expect(page).to have_text("选择支付服务商")
      expect(page).not_to have_css(".translation_missing")
    end
  end
end
