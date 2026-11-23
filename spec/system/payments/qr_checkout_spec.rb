# frozen_string_literal: true

require "rails_helper"

# Desktop UA → FlowSelector returns :qr → CheckoutsController renders
# Payments::QrCodeComponent, which wires the payments--qr-poll Stimulus
# controller. This exercises the full controller → component render path;
# client-side polling behaviour is covered by the Stimulus unit tests.
RSpec.describe "QR checkout", type: :system do
  # The project's rails_helper includes ViewComponent::SystemTestHelpers into
  # `type: :system` groups which shadows Capybara's `page` with a
  # `Capybara::Node::Simple`. That breaks `visit` here, so we explicitly
  # route through `Capybara.current_session` for this full-request system spec.
  def page
    Capybara.current_session
  end

  let(:customer) { create(:customer) }
  let(:owner)    { ::Authentication::User.find_by(customer: customer, role: :owner) }

  before do
    Current.customer = customer
    enable_module!("payment", customer, name: "Payments")
    # Checkout only offers gateways the platform owner has made available.
    Payments::PlatformGateway.for_provider("wechat_pay").update!(available: true)
    create(:payment_merchant_account, :wechat_pay, merchant_id: "wx_m")
    stub_request(:post, %r{/v3/pay/transactions/native})
      .to_return(
        status:  200,
        body:    File.read("spec/fixtures/payments/wechat/native_prepay.json"),
        headers: { "Content-Type" => "application/json" }
      )
  end

  after { Current.customer = nil }

  it "renders QR after choosing WeChat Pay (desktop UA)" do
    # Orders are created server-side (e.g. by subscription cron) — the
    # public checkout no longer accepts amount/subject from the query
    # string because that allowed any anonymous visitor to pick the
    # price they paid. Pre-create the order, then visit the checkout.
    create(:payment_order, external_ref: "R1", amount: 1.00, subject: "Test")
    page.visit "/#{customer.id}/payments/checkout?ref=R1"

    expect(page).to have_button("WeChat Pay (China)")

    # rack_test default UA is "rack_test", which FlowSelector treats as :qr
    page.click_button "WeChat Pay (China)"

    expect(page).to have_css("[data-controller~='payments--qr-poll']")

    # The poll must hit the status endpoint by out_trade_no — CheckoutsController#status
    # 404s an integer primary-key lookup for anonymous shoppers, so polling by
    # payment.id would strand the shopper before they ever reach the result page.
    payment = Payments::Payment.order(:id).last
    poll = page.find("[data-controller~='payments--qr-poll']")
    status_url = poll["data-payments--qr-poll-status-url-value"]
    expect(status_url).to include(payment.out_trade_no)
    expect(status_url).not_to match(%r{/#{payment.id}/status\z})
  end
end
