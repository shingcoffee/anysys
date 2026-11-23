# frozen_string_literal: true

require "rails_helper"

RSpec.describe "admin/settings/modules/payments/default_gateway", type: :request do
  let(:customer)       { create(:customer) }
  let(:other_customer) { create(:customer) }
  let(:admin_user)     { create(:user, :admin, customer: customer, password: "password123") }
  let(:admin)          { admin_user }
  let(:member_user)    { create(:user, customer: customer, password: "password123") }
  let(:other_admin)    { create(:user, :admin, customer: other_customer, password: "password123") }

  let(:url) { "/#{customer.id}/admin/settings/modules/payments/default_gateway" }
  let(:guard_path) { url }

  let!(:payment_module) { enable_module!("payment", customer, name: "Payments") }

  def make_eligible(provider)
    Payments::PlatformGateway.for_provider(provider).update!(available: true)
    a = Payments::MerchantAccount.unscoped_by_tenant.create!(
      customer_id: customer.id,
      provider:    provider,
      mode:        "sandbox",
      merchant_id: "M-#{provider}",
      status:      "active"
    )
    Payments::Gateways.for(provider).credential_fields.each { |f| a.write_credentials(f[:name] => "v") }
    a.save!
    a
  end

  # ===========================================================================
  # PATCH update — admin sets default to eligible provider
  # ===========================================================================
  describe "PATCH update" do
    it_behaves_like "an admin-guarded request", :patch

    it "forbids a member without changing the default" do
      sign_in member_user
      patch url, params: { provider: "alipay" }
      expect(Payments::DefaultGateway.provider_for(customer.id)).to be_nil
    end

    context "admin of a different customer (cross-tenant)" do
      before { sign_in other_admin }

      it "is blocked from another tenant's default_gateway endpoint" do
        patch url, params: { provider: "alipay" }
        expect(response).to have_http_status(:forbidden).or have_http_status(:redirect)
        expect(Payments::DefaultGateway.provider_for(customer.id)).to be_nil
      end
    end

    context "admin of the same customer" do
      before { sign_in admin_user }

      it "sets the default for an eligible provider and redirects to merchant_accounts index" do
        make_eligible("alipay")
        patch url, params: { provider: "alipay" }
        expect(Payments::DefaultGateway.provider_for(customer.id)).to eq("alipay")
        expect(response).to have_http_status(:redirect)
        expect(response.location).to include("merchant_accounts")
      end

      it "redirects with alert (no change) for an ineligible provider" do
        patch url, params: { provider: "stripe" }
        expect(Payments::DefaultGateway.provider_for(customer.id)).to be_nil
        expect(response).to have_http_status(:redirect)
        follow_redirect!
        expect(response.body).to match(/not an eligible/i).or match(/stripe/i)
      end

      it "does not affect another tenant's default when setting the provider" do
        make_eligible("alipay")
        patch url, params: { provider: "alipay" }
        expect(Payments::DefaultGateway.provider_for(other_customer.id)).to be_nil
      end
    end
  end
end
