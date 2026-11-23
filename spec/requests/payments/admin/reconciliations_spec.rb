# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Payments::Admin::Reconciliations", type: :request do
  let_it_be(:customer) { create(:customer) }
  let!(:payment_module) { enable_module!("payment", customer, name: "Payments") }
  let(:owner) { create(:user, :admin, customer: customer, password: "password123") }
  let(:admin) { owner }
  let(:index_path) { "/#{customer.id}/admin/modules/payments/reconciliations" }
  let(:guard_path) { index_path }

  it_behaves_like "an admin-guarded GET"

  describe "GET show — auth guards" do
    let(:guard_path) { "#{index_path}/#{bill.id}" }

    it_behaves_like "an admin-guarded GET"
  end

  let(:bill) do
    Payments::ReconciliationBill.create!(provider: "alipay", bill_type: "all",
                                      bill_date: Date.new(2026, 4, 1),
                                      status: "parsed")
  end

  def create_bill(bill_date:, provider: "wechat_pay", bill_type: "all", status: "parsed")
    Payments::ReconciliationBill.create!(provider: provider, bill_type: bill_type,
                                         bill_date: bill_date, status: status)
  end

  before do
    Current.customer = customer
    sign_in owner
  end

  it "GET index renders the reconciliation table" do
    bill
    get index_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(I18n.l(Date.new(2026, 4, 1), format: :long))
    expect(response.body).to include("Alipay (China)")
    expect(response.body).to include(I18n.t("comp_payments.reconciliation.bill_types.all"))
    expect(response.body).to include(I18n.t("comp_payments.reconciliation.statuses.parsed"))
  end

  it "GET show renders the bill row" do
    get "#{index_path}/#{bill.id}"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(I18n.l(Date.new(2026, 4, 1), format: :long))
    expect(response.body).to include(I18n.t("comp_payments.reconciliation.statuses.parsed"))
  end

  it "index does not leak another tenant's bills" do
    other = create(:customer)
    Current.customer = other
    create_bill(bill_date: Date.new(2020, 1, 1))
    Current.customer = customer

    get index_path
    expect(response.body).not_to include("2020-01-01")
  end

  it "show does not reveal another tenant's bill" do
    other = create(:customer)
    Current.customer = other
    leak = create_bill(bill_date: Date.new(2020, 1, 1))
    Current.customer = customer

    get "#{index_path}/#{leak.id}"
    expect(response).to have_http_status(:not_found)
  end
end
