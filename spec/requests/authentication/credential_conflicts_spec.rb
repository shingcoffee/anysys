# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Authentication credential mutation conflicts", type: :request do
  let(:customer) { create(:customer) }
  let(:auth_module) { FeatureModules::Module.find_by!(key: "authentication") }
  let(:admin) { create(:user, :admin, customer: customer, password: "Password123!") }
  let(:member) { create(:user, :member, customer: customer, password: "Password123!") }

  before do
    ensure_customer_feature_module(customer, auth_module, status: :active)
    Authentication::Throttle.reset_store!
  end

  after { Authentication::Throttle.reset_store! }

  def expect_credential_conflict(locale: :en)
    expect(response).to have_http_status(:conflict)
    expect(response.body).to eq(I18n.t("auth.errors.credentials_changed", locale: locale))
    expect(response.headers["Cache-Control"]).to include("no-store")
    expect(response.headers["Referrer-Policy"]).to eq("no-referrer")
  end

  def rotate_before_mfa_mutation(user, required:)
    secret = ROTP::Base32.random
    rotated = false
    # Simulate the winner before the audited write takes its account lock.
    allow(Authentication::MutationAudit).to receive(:mfa).and_wrap_original do |method, **options, &block|
      if options[:user].id == user.id && !rotated
        rotated = true
        Authentication::User.find(user.id).update!(otp_secret: secret, otp_required_for_login: required)
      end
      method.call(**options, &block)
    end
    secret
  end

  it "returns a controlled conflict when an account password changes after current-password verification" do
    sign_in member
    rotated = false
    allow_any_instance_of(Authentication::User).to receive(:update).and_wrap_original do |method, *args|
      if method.receiver.id == member.id && !rotated
        rotated = true
        Authentication::User.find(member.id).update!(
          password: "WinningPassword1!", password_confirmation: "WinningPassword1!"
        )
      end
      method.call(*args)
    end

    patch user_registration_path, params: {
      user: { current_password: "Password123!", password: "RejectedPassword1!",
              password_confirmation: "RejectedPassword1!" }
    }

    expect_credential_conflict
    expect(member.reload.valid_password?("WinningPassword1!")).to be(true)
    expect(member.valid_password?("RejectedPassword1!")).to be(false)
  end

  it "returns a controlled conflict when a reset request holds a credential snapshot replaced by another reset" do
    token = member.send(:set_reset_password_token)
    rotated = false
    allow_any_instance_of(Authentication::User).to receive(:reset_password).and_wrap_original do |method, *args|
      if method.receiver.id == member.id && !rotated
        rotated = true
        Authentication::User.find(member.id).update!(
          password: "WinningPassword1!", password_confirmation: "WinningPassword1!"
        )
      end
      method.call(*args)
    end

    expect {
      patch user_password_path, params: {
        user: { reset_password_token: token, password: "RejectedPassword1!",
                password_confirmation: "RejectedPassword1!" }
      }
    }.not_to change { Authentication::Event.where(event: "password_reset_completed", user_id: member.id).count }

    expect_credential_conflict
    expect(member.reload.valid_password?("WinningPassword1!")).to be(true)
    expect(member.valid_password?("RejectedPassword1!")).to be(false)
    expect(controller.user_signed_in?).to be(false)
  end

  [:en, :"zh-CN"].each do |locale|
    it "returns the #{locale} conflict response when a member profile save has a stale email snapshot" do
      sign_in member
      changed = false
      allow_any_instance_of(Member::Profiles::UpdateContract).to receive(:save).and_wrap_original do |method|
        unless changed
          changed = true
          Authentication::User.find(member.id).update!(email: "winning-profile@example.com")
        end
        method.call
      end

      patch member_profile_path(customer.id), params: {
        locale: locale,
        member_profiles_update_contract: {
          first_name: "RejectedName", last_name: member.last_name,
          email: "rejected-profile@example.com", current_password: "Password123!"
        }
      }

      expect_credential_conflict(locale: locale)
      expect(member.reload.email).to eq("winning-profile@example.com")
      expect(member.first_name).not_to eq("RejectedName")
    end
  end

  it "returns structured JSON for a member credential conflict" do
    sign_in member
    allow_any_instance_of(Member::Profiles::UpdateContract).to receive(:save) do |contract|
      raise ActiveRecord::StaleObjectError.new(contract.model, "update")
    end

    patch member_profile_path(customer.id), params: {
      locale: "zh-CN",
      member_profiles_update_contract: {
        first_name: member.first_name, last_name: member.last_name,
        email: "rejected-json@example.com", current_password: "Password123!"
      }
    }, as: :json

    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body).to eq(
      "error" => "stale_credentials",
      "message" => I18n.t("auth.errors.credentials_changed", locale: :"zh-CN")
    )
    expect(member.reload.email).not_to eq("rejected-json@example.com")
    expect(response.headers["Cache-Control"]).to include("no-store")
  end

  it "keeps a newer credential and rolls back the requested role on an admin user update conflict" do
    sign_in admin
    target_id = member.id
    allow_any_instance_of(Admin::Modules::Authentication::UsersController).to receive(:find_user).and_wrap_original do |method|
      method.call
      Authentication::User.find(target_id).update!(
        password: "WinningPassword1!", password_confirmation: "WinningPassword1!"
      )
    end

    patch admin_modules_authentication_user_path(customer.id, member), params: {
      authentication_user: { role: "admin", password: "RejectedPassword1!",
                             password_confirmation: "RejectedPassword1!" }
    }

    expect_credential_conflict
    expect(member.reload.valid_password?("WinningPassword1!")).to be(true)
    expect(member.valid_password?("RejectedPassword1!")).to be(false)
    expect(member.member?).to be(true)
    expect(member.admin?).to be(false)
  end

  it "does not enable a newly rotated secret after verifying the old auth-enrollment secret" do
    member.update!(otp_secret: ROTP::Base32.random, otp_required_for_login: false)
    sign_in member
    code = ROTP::TOTP.new(member.otp_secret).now
    winning_secret = rotate_before_mfa_mutation(member, required: false)

    expect {
      post mfa_setup_path(customer.id), params: { otp_code: code }
    }.not_to change { Authentication::Event.where(event: "mfa_enabled", user_id: member.id).count }

    expect_credential_conflict
    expect(member.reload.otp_secret).to eq(winning_secret)
    expect(member.otp_required_for_login).to be(false)
    expect(session[:mfa_verified]).not_to be(true)
  end

  it "does not enable a newly rotated secret through member enrollment either" do
    member.update!(otp_secret: ROTP::Base32.random, otp_required_for_login: false)
    sign_in member
    code = ROTP::TOTP.new(member.otp_secret).now
    winning_secret = rotate_before_mfa_mutation(member, required: false)

    post "/#{customer.id}/member/security/mfa/setup", params: { code: code }

    expect_credential_conflict
    expect(member.reload.otp_secret).to eq(winning_secret)
    expect(member.otp_required_for_login).to be(false)
    expect(session[:mfa_verified]).not_to be(true)
  end

  it "does not disable a rotated secret after auth password re-authentication" do
    member.update!(otp_secret: ROTP::Base32.random, otp_required_for_login: true)
    sign_in member
    post mfa_session_path(customer.id), params: { otp_code: ROTP::TOTP.new(member.otp_secret).now }
    expect(response).to be_redirect
    winning_secret = rotate_before_mfa_mutation(member, required: true)

    expect {
      delete mfa_path(customer.id), params: { current_password: "Password123!" }
    }.not_to change { Authentication::Event.where(event: "mfa_disabled", user_id: member.id).count }

    expect_credential_conflict
    expect(member.reload.otp_secret).to eq(winning_secret)
    expect(member.otp_required_for_login).to be(true)
  end

  it "does not let an admin MFA reset clear a secret rotated after target lookup" do
    member.update!(otp_secret: ROTP::Base32.random, otp_required_for_login: true)
    sign_in admin
    winning_secret = ROTP::Base32.random
    target_id = member.id
    allow_any_instance_of(Admin::Modules::Authentication::UserMfaResetsController).to receive(:find_user).and_wrap_original do |method|
      method.call
      Authentication::User.find(target_id).update!(otp_secret: winning_secret)
    end

    post admin_modules_authentication_user_mfa_reset_path(customer.id, member)

    expect_credential_conflict
    expect(member.reload.otp_secret).to eq(winning_secret)
    expect(member.otp_required_for_login).to be(true)
  end
end
