# frozen_string_literal: true

require "rails_helper"

# S4 — the email-dispatching auth endpoints (MFA-recovery request, confirmation
# resend) must be rate-limited so they can't be used to flood a victim's inbox
# or burn the tenant's sender reputation. Backed by Authentication::Throttle
# (dual per-IP + per-email buckets), enumeration-safe.
RSpec.describe "Authentication: email-flood throttle", type: :request do
  let_it_be(:customer) { create(:customer) }
  let(:auth_module) { ::FeatureModules::Module.find_by!(key: "authentication") }

  before do
    ensure_customer_feature_module(customer, auth_module, status: :active)
    Authentication::Throttle.reset_store!
  end

  after { Authentication::Throttle.reset_store! }

  describe "POST /:cid/auth/mfa_recovery" do
    let!(:member) { create(:user, :member, customer: customer, email: "recover@example.com") }

    def request_recovery
      post "/#{customer.id}/auth/mfa_recovery", params: { email: member.email }
    end

    it "allows up to 5 requests within the window" do
      5.times { request_recovery }
      expect(response).to have_http_status(:success) # still rendering the generic page
    end

    it "throttles the 6th request with a redirect + generic alert" do
      5.times { request_recovery }
      request_recovery
      expect(response).to redirect_to(new_mfa_recovery_path(customer.id))
      follow_redirect!
      expect(response.body).to include(I18n.t("auth.flash.mfa_recovery.throttled"))
    end

    it "records a throttled audit event once the limit is exceeded" do
      5.times { request_recovery }
      expect { request_recovery }
        .to change { Authentication::Event.where(event: "throttled", customer_id: customer.id).count }.by(1)
    end
  end

  describe "POST /:cid/auth/confirmation" do
    let!(:unconfirmed) do
      create(:user, :member, customer: customer, email: "pending@example.com").tap do |u|
        u.update_columns(confirmed_at: nil)
      end
    end

    before { Authentication::Settings.for(customer.id) } # warm

    def request_confirmation
      post "/auth/confirmation", params: { user: { email: unconfirmed.email } }
    end

    it "throttles the 6th confirmation resend request" do
      # signup must be enabled for the resend endpoint to be reachable
      ensure_customer_feature_module(customer, auth_module, status: :active,
                                     configuration: { allow_registration: "true" }.to_json)

      5.times { request_confirmation }
      request_confirmation
      expect(response).to redirect_to(new_user_session_path)
      follow_redirect!
      expect(response.body).to include(I18n.t("auth.flash.confirmation.throttled"))
    end
  end

  describe "POST /auth/sign_in_link" do
    let!(:member) { create(:user, :member, customer: customer, email: "link@example.com") }

    def request_link
      post sign_in_links_path, params: { user: { email: member.email } }
    end

    it "throttles the 6th sign-in link request" do
      5.times { request_link }
      request_link
      expect(response).to redirect_to(new_user_session_path)
      follow_redirect!
      expect(response.body).to include(I18n.t("auth.flash.sign_in_link.throttled"))
    end
  end
end
