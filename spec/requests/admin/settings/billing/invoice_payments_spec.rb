# frozen_string_literal: true

require "rails_helper"

RSpec.describe "admin/settings/billing/invoice_payments", type: :request do
  include_context "admin records"
  let!(:subscription) { create(:billing_subscription, customer: customer) }
  let!(:invoice) { create(:billing_invoice, :open, customer: customer, subscription: subscription) }
  let(:guard_path) { admin_settings_billing_invoice_payment_path(customer.id, invoice) }

  it_behaves_like "an admin-guarded request", :post

  it "uses the recovery trigger without passing client mode, amount, account, or token" do
    sign_in admin
    expect(Billing::Activities::AuthorizeInvoiceCollection).not_to receive(:call)
    expect(Billing::Activities::CollectInvoice).to receive(:call).with(invoice: invoice, trigger: :recovery)
      .and_return(Billing::Result.new(status: :pending, invoice: invoice))
    post guard_path, params: { collection: { mode: "gateway" }, amount_cents: 1, currency: "USD",
                              merchant_account_id: 1, payment_method_id: "pm_forged" }, as: :json
    expect(response).to have_http_status(:accepted)
    expect(response.parsed_body).to eq("invoice_id" => invoice.id, "status" => "pending",
                                      "invoice_url" => admin_settings_billing_invoice_url(customer.id, invoice))
  end

  it "does not label pending collection as paid on an HTML response" do
    sign_in admin
    allow(Billing::Activities::CollectInvoice).to receive(:call).and_return(Billing::Result.new(status: :requires_action))
    post guard_path
    expect(response).to have_http_status(:see_other)
    expect(flash[:notice]).to eq(I18n.t("admin_settings.flash.billing.collection.requires_action"))
  end

  it "returns conflict for exhausted debt instead of a success redirect" do
    sign_in admin
    allow(Billing::Activities::CollectInvoice).to receive(:call).and_return(Billing::Result.new(status: :exhausted))
    post guard_path, as: :json
    expect(response).to have_http_status(:conflict)
    expect(flash[:notice]).to be_nil
  end

  it "denies foreign record IDs even to an owner on a tenant path" do
    sign_in find_or_create_platform_owner
    other = create(:customer)
    foreign = create(:billing_invoice, :open, customer: other, subscription: create(:billing_subscription, customer: other))
    expect(Billing::Activities::CollectInvoice).not_to receive(:call)
    post admin_settings_billing_invoice_payment_path(customer.id, foreign), as: :json
    expect(response).to have_http_status(:not_found)
  end
end
