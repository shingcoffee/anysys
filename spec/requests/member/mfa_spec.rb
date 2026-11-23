# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Member MFA", type: :request do
  let(:customer)   { create(:customer) }
  let(:member)     { create(:user, :member, customer: customer) }
  let(:other_cust) { create(:customer) }
  let(:cid)        { customer.id }
  let(:setup_path) { "/#{cid}/member/security/mfa/setup" }
  let(:mfa_path)   { "/#{cid}/member/security/mfa" }

  before do
    [customer, other_cust].each { |c| enable_module!("authentication", c, name: "Authentication") }
  end

  describe "GET /:cid/member/security/mfa/setup" do
    context "anonymous" do
      it "redirects to sign-in" do
        get setup_path
        expect(response).to redirect_to("/auth/sign_in")
      end
    end

    context "admin (wrong role)" do
      let(:admin) { create(:user, :admin, customer: customer) }

      it "is rejected by the route gate" do
        sign_in admin
        get setup_path
        expect(response).to redirect_to("/#{cid}/admin/assistant")
      end
    end

    context "member" do
      before { sign_in member }

      it "does not seed an otp_secret when the browser prefetches setup" do
        get setup_path, headers: { "Purpose" => "prefetch" }

        expect(response).to have_http_status(:no_content)
        expect(member.reload.otp_secret).to be_nil
      end

      it "seeds an otp_secret on first visit and renders the QR" do
        expect { get setup_path }
          .to change { member.reload.otp_secret }.from(nil)

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("svg")               # QR svg
        expect(response.body).to include(member.otp_secret)   # plain secret
      end

      it "blocks cross-tenant access" do
        get "/#{other_cust.id}/member/security/mfa/setup"
        expect(response).to redirect_to("/#{cid}/member")
      end
    end

    context "member with MFA already enforced" do
      let(:member) { create(:user, :member, :with_mfa, customer: customer) }

      before do
        sign_in member
        post "/#{cid}/auth/mfa/session", params: { otp_code: ROTP::TOTP.new(member.otp_secret).now }
      end

      it "does not re-render the TOTP secret" do
        secret = member.otp_secret
        get setup_path

        expect(response).to redirect_to("/#{cid}/member/security")
        follow_redirect!
        expect(response.body).not_to include(secret)
      end

      it "does not re-render the TOTP secret on POST" do
        secret = member.otp_secret
        post setup_path, params: { code: "000000" }

        expect(response).to redirect_to("/#{cid}/member/security")
        expect(member.reload.otp_secret).to eq(secret)
      end
    end
  end

  describe "HEAD /:cid/member/security/mfa/setup" do
    around { |example| freeze_time { example.run } }

    before do
      sign_in member
      member.generate_otp_secret!
    end

    it "does not enable MFA or consume a valid TOTP during a read-only probe" do
      secret = member.otp_secret
      code = ROTP::TOTP.new(secret).now
      original_timecode = member.last_otp_at

      head setup_path, params: { code: code }

      expect(response).to have_http_status(:ok)
      expect(response.body).to be_empty
      expect(response.headers["Cache-Control"]).to include("no-store")
      expect(member.reload.otp_required_for_login).to be(false)
      expect(member.otp_secret).to eq(secret)
      expect(member.last_otp_at).to eq(original_timecode)

      post setup_path, params: { code: code }
      expect(response).to redirect_to("/#{cid}/member/security")
      expect(member.reload.mfa_required?).to be(true)
    end
  end

  describe "POST /:cid/member/security/mfa/setup" do
    before { sign_in member; member.generate_otp_secret! }

    let(:totp) { ROTP::TOTP.new(member.otp_secret) }

    it "enables MFA on a valid code" do
      secret = member.otp_secret
      code = totp.now
      expect { post setup_path, params: { code: code } }
        .to change { Authentication::Event.where(event: "mfa_enabled", user_id: member.id).count }.by(1)
      expect(response).to redirect_to("/#{cid}/member/security")
      expect(member.reload.mfa_required?).to be(true)
      event = Authentication::Event.where(event: "mfa_enabled", user_id: member.id).last
      expect(event.metadata).to include("actor_id" => member.id, "source" => "self_service", "outcome" => "success")
      expect(event.metadata.to_json).not_to include(secret, code)
    end

    it "filters bare TOTP codes from request logging while still verifying the submitted code" do
      code = totp.now
      post setup_path, params: { code: code, audit: { code: code, postal_code: "90210" } }

      expect(response).to redirect_to("/#{cid}/member/security")
      expect(member.reload.mfa_required?).to be(true)
      filtered = controller.request.filtered_parameters
      expect(filtered["code"]).to eq("[FILTERED]")
      expect(filtered.dig("audit", "code")).to eq("[FILTERED]")
      expect(filtered.dig("audit", "postal_code")).to eq("90210")
    end

    it "re-renders the form on a wrong code" do
      expect { post setup_path, params: { code: "invalid-code" } }
        .not_to change { Authentication::Event.where(event: "mfa_enabled", user_id: member.id).count }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(member.reload.mfa_required?).to be(false)
    end

    it "shows the throttled flash instead of invalid-code after too many attempts" do
      throttle = instance_double(Authentication::Throttle, exceeded?: true)
      allow(Authentication::Throttle).to receive(:new).and_return(throttle)

      post setup_path, params: { code: totp.now }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include(I18n.t("member.security.mfa.throttled"))
      expect(member.reload.mfa_required?).to be(false)
    end
  end

  describe "DELETE /:cid/member/security/mfa" do
    let(:member) { create(:user, :member, :with_mfa, customer: customer) }
    let(:totp)   { ROTP::TOTP.new(member.otp_secret) }

    before do
      sign_in member
      # Bypass MFA enforcement for these tests - the member is already MFA-enabled
      # and needs to pass verification before reaching the disable action
      allow_any_instance_of(ApplicationController).to receive(:enforce_mfa!)
    end

    it "disables MFA on a valid code" do
      expect { delete mfa_path, params: { code: totp.now } }
        .to change { Authentication::Event.where(event: "mfa_disabled", user_id: member.id).count }.by(1)
      expect(response).to redirect_to("/#{cid}/member/security")
      expect(member.reload.mfa_required?).to be(false)
      event = Authentication::Event.where(event: "mfa_disabled", user_id: member.id).last
      expect(event.metadata).to include(
        "actor_id" => member.id, "source" => "self_service", "outcome" => "success",
        "after" => { "required" => false, "configured" => false }
      )
    end

    it "leaves MFA on with a wrong code" do
      expect { delete mfa_path, params: { code: "invalid-code" } }
        .not_to change { Authentication::Event.where(event: "mfa_disabled", user_id: member.id).count }
      expect(member.reload.mfa_required?).to be(true)
    end

    it "shows the throttled flash instead of invalid-code after too many attempts" do
      throttle = instance_double(Authentication::Throttle, exceeded?: true)
      allow(Authentication::Throttle).to receive(:new).and_return(throttle)

      delete mfa_path, params: { code: totp.now }

      expect(response).to redirect_to("/#{cid}/member/security")
      expect(flash[:alert]).to eq(I18n.t("member.security.mfa.throttled"))
      expect(member.reload.mfa_required?).to be(true)
    end
  end
end
