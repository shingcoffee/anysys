# frozen_string_literal: true

require "rails_helper"

RSpec.describe "admin/settings/billing/one_time_payments", type: :request do
  include_context "admin records"

  let!(:subscription) { create(:billing_subscription, customer: customer) }
  let!(:invoice) { create(:billing_invoice, :open, customer: customer, subscription: subscription) }
  let!(:other) { create(:customer) }
  let!(:other_admin) { create(:user, :admin, customer: other) }
  let!(:foreign_invoice) do
    create(:billing_invoice, :open, customer: other, subscription: create(:billing_subscription, customer: other))
  end
  let(:tampered_params) do
    {
      provider: "stripe",
      openid: nil,
      amount: "1.00",
      amount_cents: 1,
      currency: "USD",
      customer_id: other.id,
      merchant_account_id: 99,
      payment_method_id: "pm_forged",
      save_card: true,
      return_url: "https://attacker.example/"
    }
  end

  before do
    %w[StartOneTimePayment ConfirmOneTimePayment PrepareSubscriptionOneTimeInvoice].each do |name|
      Billing::Activities.const_get(name)
    rescue NameError
      stub_const("Billing::Activities::#{name}", Class.new)
    end
    begin
      Billing::OneTimePaymentAction
    rescue NameError
      stub_const("Billing::OneTimePaymentAction", Module.new do
        def self.for(invoice:); end
      end)
    end
  end

  def expect_start_ignores_client_money(expected_invoice:, provider: "stripe", openid: nil)
    expect(Billing::Activities::StartOneTimePayment).to receive(:call) { |**kwargs|
      expect(kwargs.keys).to contain_exactly(:invoice, :provider, :openid, :request)
      expect(kwargs[:invoice]).to eq(expected_invoice)
      expect(kwargs[:provider]).to eq(provider)
      expect(kwargs[:openid]).to eq(openid)
      expect(kwargs[:request]).to be_a(ActionDispatch::Request)
      Billing::Result.new(status: :pending)
    }
  end

  describe "GET show" do
    let(:guard_path) { admin_settings_billing_invoice_one_time_payment_path(customer.id, invoice) }

    it_behaves_like "an admin-guarded GET"

    it "lets the tenant admin reach the URL customer's invoice" do
      sign_in admin
      get guard_path
      expect(response).to have_http_status(:ok).or have_http_status(:see_other)
    end

    it "forbids a cross-tenant admin" do
      sign_in other_admin
      get admin_settings_billing_invoice_one_time_payment_path(customer.id, invoice), as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it "lets the platform owner reach the URL customer's own invoice" do
      sign_in find_or_create_platform_owner
      get guard_path
      expect(response).to have_http_status(:ok).or have_http_status(:see_other)
    end

    it "returns 404 for a foreign invoice id to the tenant admin" do
      sign_in admin
      expect(Billing::Activities::ConfirmOneTimePayment).not_to receive(:call)
      expect(Billing::Activities::StartOneTimePayment).not_to receive(:call)
      get admin_settings_billing_invoice_one_time_payment_path(customer.id, foreign_invoice)
      expect(response).to have_http_status(:not_found)
    end

    it "returns 404 for a foreign invoice id even to an owner on a tenant path" do
      sign_in find_or_create_platform_owner
      expect(Billing::Activities::ConfirmOneTimePayment).not_to receive(:call)
      expect(Billing::Activities::StartOneTimePayment).not_to receive(:call)
      get admin_settings_billing_invoice_one_time_payment_path(customer.id, foreign_invoice)
      expect(response).to have_http_status(:not_found)
    end

    it "does not start or confirm payment on GET even with forged redirect hints" do
      paid = create(:billing_invoice, :paid, customer: customer, subscription: subscription)
      sign_in admin
      expect(Billing::Activities::ConfirmOneTimePayment).not_to receive(:call)
      expect(Billing::Activities::StartOneTimePayment).not_to receive(:call)
      get admin_settings_billing_invoice_one_time_payment_path(customer.id, paid),
          params: { redirect_status: "succeeded", payment_intent: "pi_forged" }
      expect(response).to have_http_status(:see_other)
      expect(response).to redirect_to(admin_settings_billing_invoice_path(customer.id, paid))
      expect(response.headers["Cache-Control"]).to include("no-store")
    end
  end

  describe "POST create" do
    let(:guard_path) { admin_settings_billing_invoice_one_time_payment_path(customer.id, invoice) }

    it_behaves_like "an admin-guarded request", :post

    it "lets the tenant admin start a one-time payment" do
      sign_in admin
      allow(Billing::Activities::StartOneTimePayment).to receive(:call)
        .and_return(Billing::Result.new(status: :pending))
      post guard_path, as: :json
      expect(response).to have_http_status(:accepted)
    end

    it "forbids a cross-tenant admin" do
      sign_in other_admin
      expect(Billing::Activities::StartOneTimePayment).not_to receive(:call)
      post admin_settings_billing_invoice_one_time_payment_path(customer.id, invoice), as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it "lets the platform owner start payment for the URL customer's invoice" do
      sign_in find_or_create_platform_owner
      allow(Billing::Activities::StartOneTimePayment).to receive(:call)
        .and_return(Billing::Result.new(status: :succeeded))
      post guard_path, as: :json
      expect(response).to have_http_status(:ok)
    end

    it "returns 404 for a foreign invoice id to the tenant admin" do
      sign_in admin
      expect(Billing::Activities::StartOneTimePayment).not_to receive(:call)
      post admin_settings_billing_invoice_one_time_payment_path(customer.id, foreign_invoice), as: :json
      expect(response).to have_http_status(:not_found)
    end

    it "returns 404 for a foreign invoice id even to an owner on a tenant path" do
      sign_in find_or_create_platform_owner
      expect(Billing::Activities::StartOneTimePayment).not_to receive(:call)
      post admin_settings_billing_invoice_one_time_payment_path(customer.id, foreign_invoice), as: :json
      expect(response).to have_http_status(:not_found)
    end

    it "ignores forged amount, currency, customer, account, method, and save_card" do
      sign_in admin
      expect_start_ignores_client_money(expected_invoice: invoice)
      post guard_path, params: { one_time_payment: tampered_params }, as: :json
      expect(response).to have_http_status(:accepted)
    end

    it "ignores the same forged fields when posted at the top level" do
      sign_in admin
      expect_start_ignores_client_money(expected_invoice: invoice)
      post guard_path, params: tampered_params, as: :json
      expect(response).to have_http_status(:accepted)
    end
  end

  describe "GET status" do
    let(:guard_path) { status_admin_settings_billing_invoice_one_time_payment_path(customer.id, invoice) }

    it_behaves_like "an admin-guarded GET"

    it "lets the tenant admin poll the URL customer's invoice" do
      sign_in admin
      allow(Billing::Activities::ConfirmOneTimePayment).to receive(:call)
        .and_return(Billing::Result.new(status: :pending))
      get guard_path
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include("status" => "pending", "invoice_status" => invoice.status)
    end

    it "forbids a cross-tenant admin" do
      sign_in other_admin
      expect(Billing::Activities::ConfirmOneTimePayment).not_to receive(:call)
      get status_admin_settings_billing_invoice_one_time_payment_path(customer.id, invoice), as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it "lets the platform owner poll the URL customer's own invoice" do
      sign_in find_or_create_platform_owner
      allow(Billing::Activities::ConfirmOneTimePayment).to receive(:call)
        .and_return(Billing::Result.new(status: :pending))
      get guard_path, as: :json
      expect(response).to have_http_status(:ok)
    end

    it "returns 404 for a foreign invoice id to the tenant admin" do
      sign_in admin
      expect(Billing::Activities::ConfirmOneTimePayment).not_to receive(:call)
      get status_admin_settings_billing_invoice_one_time_payment_path(customer.id, foreign_invoice)
      expect(response).to have_http_status(:not_found)
    end

    it "returns 404 for a foreign invoice id even to an owner on a tenant path" do
      sign_in find_or_create_platform_owner
      expect(Billing::Activities::ConfirmOneTimePayment).not_to receive(:call)
      get status_admin_settings_billing_invoice_one_time_payment_path(customer.id, foreign_invoice)
      expect(response).to have_http_status(:not_found)
    end

    it "returns 404 when confirmation reports payment_not_found" do
      sign_in admin
      allow(Billing::Activities::ConfirmOneTimePayment).to receive(:call)
        .and_return(Billing::Result.new(status: :invalid, reason: :payment_not_found))
      get guard_path
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST confirm" do
    let(:guard_path) { confirm_admin_settings_billing_invoice_one_time_payment_path(customer.id, invoice) }

    it_behaves_like "an admin-guarded request", :post

    it "lets the tenant admin confirm the URL customer's invoice" do
      sign_in admin
      expect(Billing::Activities::ConfirmOneTimePayment).to receive(:call).with(invoice: invoice)
        .and_return(Billing::Result.new(status: :succeeded))
      post guard_path, params: { redirect_status: "succeeded", payment_intent: "pi_forged" }, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include("status" => "succeeded", "invoice_id" => invoice.id)
    end

    it "forbids a cross-tenant admin" do
      sign_in other_admin
      expect(Billing::Activities::ConfirmOneTimePayment).not_to receive(:call)
      post confirm_admin_settings_billing_invoice_one_time_payment_path(customer.id, invoice), as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it "lets the platform owner confirm the URL customer's own invoice" do
      sign_in find_or_create_platform_owner
      allow(Billing::Activities::ConfirmOneTimePayment).to receive(:call)
        .and_return(Billing::Result.new(status: :pending))
      post guard_path, as: :json
      expect(response).to have_http_status(:accepted)
    end

    it "returns 404 for a foreign invoice id to the tenant admin" do
      sign_in admin
      expect(Billing::Activities::ConfirmOneTimePayment).not_to receive(:call)
      post confirm_admin_settings_billing_invoice_one_time_payment_path(customer.id, foreign_invoice), as: :json
      expect(response).to have_http_status(:not_found)
    end

    it "returns 404 for a foreign invoice id even to an owner on a tenant path" do
      sign_in find_or_create_platform_owner
      expect(Billing::Activities::ConfirmOneTimePayment).not_to receive(:call)
      post confirm_admin_settings_billing_invoice_one_time_payment_path(customer.id, foreign_invoice), as: :json
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST subscription/one_time_payment" do
    let(:guard_path) { admin_settings_billing_subscription_one_time_payment_path(customer.id) }

    it_behaves_like "an admin-guarded request", :post

    it "lets the tenant admin start a subscription one-time payment" do
      sign_in admin
      allow(Billing::Activities::PrepareSubscriptionOneTimeInvoice).to receive(:call)
        .and_return(Billing::Result.new(status: :ready, invoice: invoice))
      allow(Billing::Activities::StartOneTimePayment).to receive(:call)
        .and_return(Billing::Result.new(status: :pending))
      post guard_path
      expect(response).to have_http_status(:see_other)
    end

    it "forbids a cross-tenant admin" do
      sign_in other_admin
      expect(Billing::Activities::PrepareSubscriptionOneTimeInvoice).not_to receive(:call)
      post admin_settings_billing_subscription_one_time_payment_path(customer.id), as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it "lets the platform owner pay the URL customer's invoice" do
      sign_in find_or_create_platform_owner
      allow(Billing::Activities::PrepareSubscriptionOneTimeInvoice).to receive(:call)
        .and_return(Billing::Result.new(status: :succeeded, invoice: invoice))
      expect(Billing::Activities::StartOneTimePayment).not_to receive(:call)
      post guard_path
      expect(response).to have_http_status(:see_other)
      expect(response).to redirect_to(admin_settings_billing_invoice_path(customer.id, invoice))
    end

    it "returns 404 for a foreign invoice id to the tenant admin" do
      sign_in admin
      expect(Billing::Activities::PrepareSubscriptionOneTimeInvoice).not_to receive(:call)
      expect(Billing::Activities::StartOneTimePayment).not_to receive(:call)
      post guard_path, params: { one_time_payment: { provider: "stripe", invoice_id: foreign_invoice.id } }, as: :json
      expect(response).to have_http_status(:not_found)
    end

    it "returns 404 for a foreign invoice id even to an owner on a tenant path" do
      sign_in find_or_create_platform_owner
      expect(Billing::Activities::PrepareSubscriptionOneTimeInvoice).not_to receive(:call)
      expect(Billing::Activities::StartOneTimePayment).not_to receive(:call)
      post guard_path, params: { one_time_payment: { provider: "stripe", invoice_id: foreign_invoice.id } }, as: :json
      expect(response).to have_http_status(:not_found)
    end

    it "ignores forged amount, currency, customer, account, method, and save_card" do
      sign_in admin
      expect(Billing::Activities::PrepareSubscriptionOneTimeInvoice).to receive(:call) { |**kwargs|
        expect(kwargs[:customer]).to eq(customer)
        expect(kwargs[:subscription]).to eq(subscription)
        expect(kwargs[:invoice_id].to_s).to eq(invoice.id.to_s)
        Billing::Result.new(status: :ready, invoice: invoice)
      }
      expect_start_ignores_client_money(expected_invoice: invoice)
      post guard_path, params: { one_time_payment: tampered_params.merge(invoice_id: invoice.id) }
      expect(response).to have_http_status(:see_other)
    end
  end
end
