# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Payments::Admin::Disputes", type: :request do
  let_it_be(:customer) { create(:customer) }
  let!(:payment_module) { enable_module!("payment", customer, name: "Payments") }
  let(:owner) { create(:user, :admin, customer: customer, password: "password123") }
  let(:admin) { owner }
  let(:index_path) { "/#{customer.id}/admin/modules/payments/disputes" }
  let(:guard_path) { index_path }

  it_behaves_like "an admin-guarded GET"

  def dispute_for(cust, ref:, dispute_id:, reason: "fraudulent", status: "lost")
    Current.customer = cust
    order = create(:payment_order, customer: cust, external_ref: ref, amount: 5.00, subject: "s", currency: "USD")
    payment = create(:payment, customer: cust, payment_order: order, provider: "stripe", flow: "card",
                     out_trade_no: "#{ref}-ot", amount: 5.00, status: "succeeded")
    create(:payment_dispute, customer: cust, payment: payment, provider: "stripe", psp_dispute_id: dispute_id,
           reason: reason, status: status, amount: 5.00, opened_at: Time.current)
  end

  before do
    Current.customer = customer
    sign_in owner
  end

  it "denies an admin from a DIFFERENT tenant visiting this tenant's disputes URL" do
    sign_out owner
    other_customer = create(:customer)
    other_admin = create(:user, :admin, customer: other_customer)
    sign_in other_admin

    get index_path

    expect([302, 403, 404]).to include(response.status)
    expect(response.status).not_to eq(200)
  end

  it "GET index renders the tenant's disputes" do
    dispute_for(customer, ref: "d1", dispute_id: "dp_visible", reason: "fraudulent")
    Current.customer = customer

    get index_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("dp_visible")
    expect(response.body).to include(I18n.t("comp_payments.dispute_table.reasons.fraudulent"))
    expect(response.body).to include("Credit / Debit Card (Stripe)")
    expect(response.body).to include(I18n.t("comp_payments.dispute_table.statuses.lost"))
  end

  it "does not leak another tenant's disputes" do
    other = create(:customer)
    dispute_for(other, ref: "leak", dispute_id: "dp_leaked", reason: "leaked_reason")
    Current.customer = customer

    get index_path
    expect(response.body).not_to include("dp_leaked")
    expect(response.body).not_to include("leaked_reason")
  end

  it "caps the listing at 100 rows, matching TransactionsController's cap" do
    101.times { |i| dispute_for(customer, ref: "cap-#{i}", dispute_id: "dp_cap_#{i}") }
    Current.customer = customer

    get index_path
    expect(response).to have_http_status(:ok)
    expect(response.body.scan('class="table-row"').count).to eq(100)
  end
end
