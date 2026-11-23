# frozen_string_literal: true

require "rails_helper"

RSpec.describe FeatureModules::Authentication::Registration, ".enforce_mfa!", type: :request do
  let_it_be(:customer) { create(:customer) }
  let(:auth_module) { FeatureModules::Module.find_by!(key: "authentication") }

  before do
    ensure_customer_feature_module(customer, auth_module,
                                   configuration: { "mfa_enabled" => true }.to_json)
  end

  context "with customer-wide MFA on" do
    it "does NOT force a member into MFA setup" do
      member = create(:user, :member, customer: customer)
      sign_in member

      get "/#{customer.id}/member/security"
      expect(response).to have_http_status(:ok)
    end

    it "DOES force an admin into MFA setup" do
      admin = create(:user, :admin, customer: customer)
      sign_in admin

      get "/#{customer.id}/admin/dashboard"
      expect(response).to redirect_to("/#{customer.id}/auth/mfa/setup")
    end
  end
end
