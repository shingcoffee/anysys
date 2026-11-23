# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Modules::Payments::Reconciliations download", type: :request do
  include_context "as admin"
  let!(:payment_module) { enable_module!("payment", customer, name: "Payments") }

  def create_bill(cust, with_file: true)
    bill = Payments::ReconciliationBill.create!(
      customer: cust, provider: "alipay", bill_date: Date.current,
      bill_type: "all", status: "reconciled"
    )
    if with_file
      bill.bill_file.attach(io: StringIO.new("date,amount\n2026-07-16,100"),
                            filename: "bill.csv", content_type: "text/csv")
    end
    bill
  end

  let(:bill) { create_bill(customer) }
  let(:guard_path) { "/#{customer.id}/admin/modules/payments/reconciliations/#{bill.id}/download" }

  it_behaves_like "an admin-guarded GET"

  it "streams the attached bill file as an attachment" do
    bill = create_bill(customer)
    get "/#{customer.id}/admin/modules/payments/reconciliations/#{bill.id}/download"

    expect(response).to have_http_status(:ok)
    expect(response.headers["Content-Disposition"]).to include("attachment")
    expect(response.body).to include("date,amount")
  end

  it "404s when the bill has no attached file" do
    bill = create_bill(customer, with_file: false)
    get "/#{customer.id}/admin/modules/payments/reconciliations/#{bill.id}/download"
    expect(response).to have_http_status(:not_found)
  end

  it "404s for a bill belonging to another tenant" do
    other = create(:customer)
    bill = create_bill(other)
    get "/#{customer.id}/admin/modules/payments/reconciliations/#{bill.id}/download"
    expect(response).to have_http_status(:not_found)
  end
end
