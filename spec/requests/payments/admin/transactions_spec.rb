# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Payments::Admin::Transactions", type: :request do
  let_it_be(:customer) { create(:customer) }
  let!(:payment_module) { enable_module!("payment", customer, name: "Payments") }
  let(:owner) { create(:user, :admin, customer: customer, password: "password123") }
  let(:admin) { owner }
  let(:order) { create(:payment_order, external_ref: "tx_ref1", amount: 5.00, subject: "tx") }
  let(:payment) do
    create(:payment, payment_order: order, provider: "alipay", flow: "qr",
           out_trade_no: "tx_ot1", amount: 5.00, status: "succeeded")
  end

  let(:index_path) { "/#{customer.id}/admin/modules/payments/transactions" }
  let(:guard_path) { index_path }

  it_behaves_like "an admin-guarded GET"

  describe "GET show — auth guards" do
    let(:guard_path) { "#{index_path}/#{payment.id}" }

    it_behaves_like "an admin-guarded GET"
  end

  describe "POST refund — auth guards" do
    let(:guard_path) { "#{index_path}/#{payment.id}/refunds" }

    it_behaves_like "an admin-guarded request", :post
  end

  before do
    Current.customer = customer
    sign_in owner
  end

  # Creates a payment owned by a freshly-created OTHER tenant, so isolation
  # examples can assert the current customer never sees it. Returns the payment.
  def other_tenant_payment(external_ref:, out_trade_no:)
    other_customer = create(:customer)
    Current.customer = other_customer
    order = create(:payment_order, customer: other_customer, external_ref: external_ref, amount: 0.99, subject: "x")
    payment = create(:payment, customer: other_customer, payment_order: order, provider: "alipay", flow: "qr",
                     out_trade_no: out_trade_no, amount: 0.99, status: "succeeded")
    Current.customer = customer
    payment
  end

  it "GET index renders the transaction table" do
    payment # create
    get index_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("tx_ref1")
    expect(response.body).to include("Alipay (China)")
    expect(response.body).to include(I18n.t("comp_payments.transaction_table.statuses.succeeded"))
    expect(response.body).to include("Refund")
  end

  it "GET show renders the refund dialog" do
    get "#{index_path}/#{payment.id}"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Refund Payment ##{payment.id}")
    expect(response.body).to include("Alipay (China)")
    expect(response.body).to include(I18n.t("comp_payments.transaction_table.statuses.succeeded"))
    expect(response.body).to include("Issue Refund")
  end

  it "POST refund invokes Refund activity and redirects" do
    refund = instance_double(Payments::Refund, status: "succeeded")
    expect(Payments::Activities::Refund).to receive(:call).with(
      customer: customer, payment: kind_of(Payments::Payment),
      amount: "2.5", reason: "duplicate"
    ).and_return(refund)

    post "#{index_path}/#{payment.id}/refunds", params: {
      amount: 2.50, reason: "duplicate"
    }
    expect(response).to redirect_to(admin_modules_payments_transactions_path(customer_id: customer.id))
  end

  it "flags a charged-back payment with a Chargeback badge in the index" do
    create(:payment_dispute, payment: payment, provider: "alipay", psp_dispute_id: "dp_cb",
           status: "lost", amount: 5.00, opened_at: Time.current)
    get index_path
    expect(response.body).to include("Chargeback")
  end

  it "index does not leak another tenant's payments" do
    other_tenant_payment(external_ref: "OTHER_REF", out_trade_no: "OTHER_OT")

    get index_path
    expect(response.body).not_to include("OTHER_REF")
  end

  it "show does not reveal another tenant's payment" do
    leak = other_tenant_payment(external_ref: "LEAK_REF", out_trade_no: "LEAK_OT")

    get "#{index_path}/#{leak.id}"
    expect(response).to have_http_status(:not_found)
  end
end
