# frozen_string_literal: true

require "rails_helper"

# Covers RefundsController#create failure-mapping: a RefundNotAllowed code is
# translated into an admin-facing flash (never the developer-oriented exception
# message), unexpected failures fall back to a generic translated message, and
# the happy path still submits the refund.
RSpec.describe "admin/modules/payments/refunds", type: :request do
  let_it_be(:customer) { create(:customer) }
  let!(:payment_module) { enable_module!("payment", customer, name: "Payments") }
  let(:admin_user) { create(:user, :admin, customer: customer, password: "password123") }
  let(:admin) { admin_user }

  let(:order) { create(:payment_order, external_ref: "or", amount: 5.00, subject: "s") }
  let(:payment) do
    create(:payment, payment_order: order, provider: "alipay", flow: "qr",
           out_trade_no: "otr-req-1", amount: 5.00, status: "succeeded")
  end
  let(:refund_url) { "/#{customer.id}/admin/modules/payments/transactions/#{payment.id}/refunds" }
  let(:guard_path) { refund_url }
  let(:transactions_url) { "/#{customer.id}/admin/modules/payments/transactions" }

  it_behaves_like "an admin-guarded request", :post

  before do
    Current.customer = customer
    sign_in admin_user
  end

  it "does not refund a billing collection" do
    billing_order = create(:payment_order, external_ref: "billing-inv-4", amount: 5.00, subject: "Invoice")
    billing_payment = create(:payment, payment_order: billing_order, provider: "alipay", flow: "qr",
                             out_trade_no: "otr-bill-1", amount: 5.00, status: "succeeded")

    post "/#{customer.id}/admin/modules/payments/transactions/#{billing_payment.id}/refunds",
         params: { amount: "1.00", reason: "invoice" }

    expect(response).to have_http_status(:not_found)
    expect(Payments::Refund.where(payment_id: billing_payment.id)).to be_empty
  end

  it "maps a crafted array amount to the not-positive flash instead of 500ing" do
    post refund_url, params: { amount: ["1.00"], reason: "ok" }

    expect(response).to redirect_to(transactions_url)
    expect(flash[:alert]).to eq(I18n.t("comp_payments.flash.refund_amount_not_positive"))
    expect(Payments::Refund.where(payment_id: payment.id)).to be_empty
  end

  it "maps a non-finite amount to the not-positive flash instead of creating a NaN refund" do
    post refund_url, params: { amount: "NaN", reason: "ok" }

    expect(response).to redirect_to(transactions_url)
    expect(flash[:alert]).to eq(I18n.t("comp_payments.flash.refund_amount_not_positive"))
    expect(Payments::Refund.where(payment_id: payment.id)).to be_empty
  end

  it "maps :exceeds_remainder to a translated flash with formatted amounts and never leaks the developer message" do
    # ¥6.00 requested against a ¥5.00 captured payment → over-refund.
    post refund_url, params: { amount: 6.00, reason: "too much" }

    expect(response).to redirect_to(transactions_url)
    expected = I18n.t("comp_payments.flash.refund_exceeds_remainder",
                      amount:    Billing::CurrencyResolver.format(600, "CNY"),
                      remainder: Billing::CurrencyResolver.format(500, "CNY"))
    expect(flash[:alert]).to eq(expected)
    expect(flash[:alert]).to include("¥6.00").and include("¥5.00")
    # The developer-oriented exception text must NOT reach the admin.
    expect(flash[:alert]).not_to include("refundable remainder")
    expect(flash[:alert]).not_to include(payment.out_trade_no)
    # Nothing was reserved — the ceiling check rejects before creating a row.
    expect(Payments::Refund.where(payment_id: payment.id)).to be_empty
  end

  it "rescales zero-decimal (JPY) amounts in the over-refund flash instead of inflating them 100x" do
    # Storage is always a major-unit decimal with two digits: a ¥5000 (yen)
    # captured payment is stored as amount 5000.00.
    jpy_order = create(:payment_order, external_ref: "or-jpy", amount: 5000.00,
                       subject: "s", currency: "JPY")
    jpy_payment = create(:payment, payment_order: jpy_order, provider: "alipay", flow: "qr",
                            out_trade_no: "otr-jpy-1", amount: 5000.00, status: "succeeded")
    jpy_url = "/#{customer.id}/admin/modules/payments/transactions/#{jpy_payment.id}/refunds"

    # ¥6000 requested against the ¥5000 captured payment.
    post jpy_url, params: { amount: 6000.00, reason: "too much" }

    expect(response).to redirect_to(transactions_url)
    amount_disp    = Billing::CurrencyResolver.format(Payments::Money.to_iso_minor_units(6000.00, "JPY"), "JPY")
    remainder_disp = Billing::CurrencyResolver.format(Payments::Money.to_iso_minor_units(5000.00, "JPY"), "JPY")
    expect(flash[:alert]).to eq(
      I18n.t("comp_payments.flash.refund_exceeds_remainder", amount: amount_disp, remainder: remainder_disp)
    )
    expect(flash[:alert]).to include("¥6000").and include("¥5000")
    # Regression guard: the old bug rendered the canonical major×100 values (¥600000 / ¥500000).
    expect(flash[:alert]).not_to include("600000")
    expect(flash[:alert]).not_to include("500000")
  end

  it "falls back to the generic translated flash for an ApiError without leaking the PSP message" do
    allow(Payments::Gateway).to receive(:refund)
      .and_raise(Payments::Errors::ApiError.new("card_declined: do not honor", code: 402, payload: {}))

    post refund_url, params: { amount: 1.00, reason: "ok" }

    expect(response).to redirect_to(transactions_url)
    expect(flash[:alert]).to eq(I18n.t("comp_payments.flash.refund_failed"))
    expect(flash[:alert]).not_to include("card_declined")
  end

  it "falls back to the generic translated flash for a TransportError instead of 500ing" do
    allow(Payments::Gateway).to receive(:refund)
      .and_raise(Payments::Errors::TransportError, "timeout")

    post refund_url, params: { amount: 1.00, reason: "ok" }

    expect(response).to redirect_to(transactions_url)
    expect(flash[:alert]).to eq(I18n.t("comp_payments.flash.refund_failed"))
    expect(flash[:alert]).not_to include("timeout")
  end

  it "submits the refund and renders the success flash on the happy path" do
    allow(Payments::Gateway).to receive(:refund)
      .and_return(status: :succeeded, psp_refund_id: "PR-1", raw: {})

    post refund_url, params: { amount: 2.00, reason: "ok" }

    expect(response).to redirect_to(transactions_url)
    expect(flash[:notice]).to eq(I18n.t("comp_payments.flash.refunded"))
    refund = Payments::Refund.where(payment_id: payment.id).sole
    expect(refund.status).to eq("succeeded")
    expect(refund.psp_refund_id).to eq("PR-1")
  end

  it "alerts when the PSP reports a failed refund instead of flashing success" do
    allow(Payments::Gateway).to receive(:refund)
      .and_return(status: :failed, raw: { "error" => "refund_declined" })

    post refund_url, params: { amount: 1.00, reason: "ok" }

    expect(response).to redirect_to(transactions_url)
    expect(flash[:alert]).to eq(I18n.t("comp_payments.flash.refund_failed"))
    expect(flash[:notice]).to be_nil
  end

  it "notices when the refund is still processing" do
    allow(Payments::Gateway).to receive(:refund)
      .and_return(status: :processing, psp_refund_id: "P-PENDING", raw: {})

    post refund_url, params: { amount: 1.00, reason: "ok" }

    expect(response).to redirect_to(transactions_url)
    expect(flash[:notice]).to eq(I18n.t("comp_payments.flash.refund_processing"))
  end
end
