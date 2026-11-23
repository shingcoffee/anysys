# frozen_string_literal: true

require "rails_helper"

# Admin transactions index links succeeded rows to the refund review page.
# The actual refund POST is covered by the request spec.
RSpec.describe "Admin refund", type: :system do
  # rails_helper includes ViewComponent::SystemTestHelpers which shadows
  # Capybara's `page` helper — route through the Capybara session directly.
  def page
    Capybara.current_session
  end

  let(:customer) { create(:customer) }
  let(:owner) { create(:user, :admin, customer: customer, password: "password123") }
  let(:payment) { @payment }

  before do
    Current.customer = customer
    enable_module!("payment", customer, name: "Payments")
    sign_in owner
    order = create(:payment_order,
      external_ref: "ADM-REF-1",
      amount: 7.50,
      subject:      "Admin refund test"
    )
    @payment = create(:payment,
      payment_order: order,
      provider:      "alipay",
      flow:          "qr",
      out_trade_no:  "ot-admin-1",
      amount: 7.50,
      status:        "succeeded"
    )
  end

  after { Current.customer = nil }

  it "links each succeeded payment to the refund review page" do
    page.visit "/#{customer.id}/admin/modules/payments/transactions"

    expect(page).to have_text("ADM-REF-1")
    expect(page).to have_text("Alipay (China)")
    expect(page).to have_text(I18n.t("comp_payments.transaction_table.statuses.succeeded"))
    expect(page).to have_link(I18n.t("comp_payments.transaction_table.refund"),
                              href: "/#{customer.id}/admin/modules/payments/transactions/#{payment.id}")

    page.click_link I18n.t("comp_payments.transaction_table.refund")
    expect(page).to have_current_path("/#{customer.id}/admin/modules/payments/transactions/#{payment.id}")
    expect(page).to have_button(I18n.t("comp_payments.refund.submit"))
  end
end
