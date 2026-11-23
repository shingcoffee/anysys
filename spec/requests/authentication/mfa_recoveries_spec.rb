# frozen_string_literal: true

require "rails_helper"

RSpec.describe "MFA Recovery", type: :request do
  let_it_be(:customer) { create(:customer) }
  let(:member)   { create(:user, :member, :with_mfa, customer: customer, email: "alice@example.com") }
  let(:admin)    { create(:user, :admin, :with_mfa, customer: customer, email: "bob@example.com") }
  let(:cid)      { customer.id }

  def expect_secret_response_headers
    expect(response.headers["Cache-Control"]).to include("private", "no-store")
    expect(response.headers["Referrer-Policy"]).to eq("no-referrer")
    expect(response.headers["Pragma"]).to eq("no-cache")
  end

  describe "GET /:cid/auth/mfa_recovery/new" do
    it "is publicly accessible" do
      get "/#{cid}/auth/mfa_recovery/new"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("email")
      expect(response.body).to include(I18n.t("auth.sessions.email_placeholder"))
    end
  end

  describe "POST /:cid/auth/mfa_recovery" do
    before { ActionMailer::Base.deliveries.clear }

    it "renders the same generic confirmation regardless of email outcome" do
      post "/#{cid}/auth/mfa_recovery", params: { email: member.email }
      member_body = response.body

      ActionMailer::Base.deliveries.clear
      post "/#{cid}/auth/mfa_recovery", params: { email: admin.email }
      admin_body = response.body

      ActionMailer::Base.deliveries.clear
      post "/#{cid}/auth/mfa_recovery", params: { email: "ghost@example.com" }
      missing_body = response.body

      expect(member_body).to eq(admin_body)
      expect(member_body).to eq(missing_body)
    end

    it "delivers an email only for member matches" do
      expect {
        perform_enqueued_jobs do
          post "/#{cid}/auth/mfa_recovery", params: { email: member.email }
        end
      }.to change { ActionMailer::Base.deliveries.size }.by(1)
    end

    it "does not email admins" do
      expect {
        perform_enqueued_jobs do
          post "/#{cid}/auth/mfa_recovery", params: { email: admin.email }
        end
      }.not_to change { ActionMailer::Base.deliveries.size }
    end
  end

  describe "GET /:cid/auth/mfa_recovery/consume" do
    it "does not disable MFA on GET so a mail scanner cannot consume the link" do
      token = Member::Mfa::ResetToken.generate(member)

      get "/#{cid}/auth/mfa_recovery/consume", params: { token: token }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Disable two-factor authentication")
      expect(member.reload.mfa_required?).to be(true)
      expect_secret_response_headers
    end

    it "answers HEAD without consuming the token" do
      token = Member::Mfa::ResetToken.generate(member)

      head "/#{cid}/auth/mfa_recovery/consume", params: { token: token }
      expect(response).to have_http_status(:ok)
      expect(member.reload.mfa_required?).to be(true)
      expect_secret_response_headers
    end

    it "hardens a missing-token redirect as well as the confirmation page" do
      get "/#{cid}/auth/mfa_recovery/consume"

      expect(response).to redirect_to(new_user_session_path)
      expect_secret_response_headers
    end

    it "hardens a tenant-lookup error before the consume action runs" do
      missing_id = Customer.maximum(:id) + 1
      get "/#{missing_id}/auth/mfa_recovery/consume", params: { token: "invalid-token" }

      expect(response).to have_http_status(:not_found)
      expect_secret_response_headers
    end
  end

  describe "POST /:cid/auth/mfa_recovery/consume" do
    it "disables MFA on a valid token and redirects to sign-in" do
      token = Member::Mfa::ResetToken.generate(member)

      post "/#{cid}/auth/mfa_recovery/consume", params: { token: token }
      expect(response).to redirect_to("/auth/sign_in")
      expect(flash[:notice]).to match(/disabled/i)
      expect(member.reload.mfa_required?).to be(false)
      expect_secret_response_headers
    end

    it "shows a generic flash on an admin-targeted token without modifying the admin" do
      token = Member::Mfa::ResetToken.generate(admin)

      post "/#{cid}/auth/mfa_recovery/consume", params: { token: token }
      expect(response).to redirect_to("/auth/sign_in")
      expect(flash[:alert]).to match(/invalid|expired/i)
      expect(admin.reload.mfa_required?).to be(true)
      expect_secret_response_headers
    end

    it "shows a generic flash on an expired token" do
      token = Member::Mfa::ResetToken.generate(member)

      travel_to(20.minutes.from_now) do
        post "/#{cid}/auth/mfa_recovery/consume", params: { token: token }
        expect(flash[:alert]).to match(/invalid|expired/i)
        expect_secret_response_headers
      end
    end

    it "hardens an invalid-token redirect and does not emit a successful mutation event" do
      expect {
        post "/#{cid}/auth/mfa_recovery/consume", params: { token: "invalid-token" }
      }.not_to change { Authentication::Event.where(event: "mfa_disabled").count }

      expect(response).to redirect_to(new_user_session_path)
      expect_secret_response_headers
    end

    it "records one recovery disable with outcome facts and no token or secret" do
      secret = member.otp_secret
      token = Member::Mfa::ResetToken.generate(member)

      expect {
        post "/#{cid}/auth/mfa_recovery/consume", params: { token: token }
      }.to change { Authentication::Event.where(event: "mfa_disabled", user_id: member.id).count }.by(1)

      event = Authentication::Event.where(event: "mfa_disabled", user_id: member.id).last
      expect(event.customer_id).to eq(customer.id)
      expect(event.metadata).to include(
        "source" => "recovery", "outcome" => "success",
        "before" => { "required" => true, "configured" => true },
        "after" => { "required" => false, "configured" => false }
      )
      expect(event.metadata.to_json).not_to include(secret, token)

      expect {
        post "/#{cid}/auth/mfa_recovery/consume", params: { token: token }
      }.not_to change { Authentication::Event.where(event: "mfa_disabled", user_id: member.id).count }
    end
  end
end
