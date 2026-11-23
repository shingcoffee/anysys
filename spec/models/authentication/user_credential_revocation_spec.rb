# frozen_string_literal: true

require "rails_helper"

# Exercises the account-serialized credential lifecycle: revocation must fire
# on password/identity change and OTP-secret invalidation, but
# must not fire on first-time enrolment (nil → secret).
RSpec.describe Authentication::User, "credential grant revocation" do
  let(:customer) { create(:customer) }

  def issue_token(owner)
    Oauth::AccessToken.create_for(
      application: Oauth::DesktopClient.ensure!,
      resource_owner: owner,
      scopes: Oauth::Protocol::SCOPE,
      expires_in: Oauth::Protocol::ACCESS_TOKEN_TTL.to_i,
      use_refresh_token: true
    )
  end

  def issue_trusted_device(owner)
    Authentication::TrustedDevice.issue!(
      user: owner, ip: "203.0.113.10", user_agent: "RSpec"
    ).first
  end

  def issue_code(owner)
    Doorkeeper.config.access_grant_model.create!(
      application: Oauth::DesktopClient.ensure!, resource_owner_id: owner.id,
      expires_in: Oauth::Protocol::AUTHORIZATION_CODE_TTL.to_i,
      redirect_uri: "http://127.0.0.1/callback", scopes: Oauth::Protocol::SCOPE,
      code_challenge: "challenge", code_challenge_method: "S256"
    )
  end

  def issue_link(owner)
    raw, digest = Devise.token_generator.generate(described_class, :sign_in_token)
    owner.update_columns(sign_in_token: digest, sign_in_token_sent_at: Time.current)
    raw
  end

  describe "the complete credential lifecycle" do
    %i[password password_reset mfa_disable mfa_rotation email customer_id].each do |change|
      it "revokes codes, tokens, devices and sign-in links on #{change}" do
        account = create(:user, :with_mfa, customer: customer)
        token = issue_token(account)
        code = issue_code(account)
        device = issue_trusted_device(account)
        issue_link(account)

        case change
        when :password
          account.update!(password: "NewPassword1!", password_confirmation: "NewPassword1!")
        when :password_reset
          reset = account.send(:set_reset_password_token)
          result = described_class.reset_password_by_token(
            reset_password_token: reset, password: "NewPassword1!", password_confirmation: "NewPassword1!"
          )
          expect(result.errors).to be_empty
        when :mfa_disable then account.disable_mfa!
        when :mfa_rotation then account.generate_otp_secret!
        when :email then account.update!(email: "changed-#{account.id}@example.com")
        when :customer_id then account.update!(customer: create(:customer))
        end

        expect(token.reload).to be_revoked
        expect(code.reload).to be_revoked
        expect(Authentication::TrustedDevice.exists?(device.id)).to be(false)
        expect(account.reload.sign_in_token).to be_nil
        expect(account.sign_in_token_sent_at).to be_nil
      end
    end

    it "keeps pending codes and links during first-time enrollment and its completion" do
      account = create(:user, customer: customer)
      code = issue_code(account)
      raw = issue_link(account)

      account.generate_otp_secret!
      account.enable_mfa!

      expect(code.reload).not_to be_revoked
      expect(account.reload.sign_in_token).to eq(Devise.token_generator.digest(described_class, :sign_in_token, raw))
    end

    it "does not revoke another account's pending codes or sign-in links" do
      account = create(:user, customer: customer)
      other = create(:user, customer: create(:customer))
      code = issue_code(other)
      raw = issue_link(other)

      account.update!(email: "changed-#{account.id}@example.com")

      expect(code.reload).not_to be_revoked
      expect(other.reload.sign_in_token).to eq(Devise.token_generator.digest(described_class, :sign_in_token, raw))
    end

    it "rolls revocation back with the credential write" do
      account = create(:user, :with_mfa, customer: customer)
      token = issue_token(account)
      code = issue_code(account)
      device = issue_trusted_device(account)
      raw = issue_link(account)

      described_class.transaction(requires_new: true) do
        account.update!(password: "NewPassword1!", password_confirmation: "NewPassword1!")
        raise ActiveRecord::Rollback
      end

      expect(account.reload.valid_password?("password123")).to be(true)
      expect(token.reload).not_to be_revoked
      expect(code.reload).not_to be_revoked
      expect(Authentication::TrustedDevice.exists?(device.id)).to be(true)
      expect(account.sign_in_token).to eq(Devise.token_generator.digest(described_class, :sign_in_token, raw))
    end

    it "rejects a stale credential write without revoking grants minted after the replacement" do
      account = create(:user, :with_mfa, customer: customer)
      stale = described_class.find(account.id)
      account.update!(password: "NewPassword1!", password_confirmation: "NewPassword1!")
      token = issue_token(account)
      code = issue_code(account)
      device = issue_trusted_device(account)
      raw = issue_link(account)

      expect { stale.update!(otp_secret: ROTP::Base32.random) }
        .to raise_error(ActiveRecord::StaleObjectError)

      expect(account.reload.valid_password?("NewPassword1!")).to be(true)
      expect(token.reload).not_to be_revoked
      expect(code.reload).not_to be_revoked
      expect(Authentication::TrustedDevice.exists?(device.id)).to be(true)
      expect(account.sign_in_token).to eq(Devise.token_generator.digest(described_class, :sign_in_token, raw))
    end

    it "does not let an instance loaded before enrollment replace its newly installed secret" do
      account = create(:user, customer: customer)
      stale = described_class.find(account.id)
      account.generate_otp_secret!
      secret = account.otp_secret

      expect { stale.update!(otp_secret: ROTP::Base32.random) }
        .to raise_error(ActiveRecord::StaleObjectError)
      expect(account.reload.otp_secret).to eq(secret)
    end
  end

  describe "password change" do
    it "revokes the user's active Doorkeeper tokens and deletes trusted devices" do
      user = create(:user, customer: customer)
      token = issue_token(user)
      device = issue_trusted_device(user)

      user.update!(password: "NewPassword1!", password_confirmation: "NewPassword1!")

      expect(token.reload).to be_revoked
      expect(Authentication::TrustedDevice.exists?(device.id)).to be(false)
    end
  end

  describe "otp_secret invalidation" do
    it "revokes grants when a previously stored secret is rotated" do
      user = create(:user, :mfa_configured, customer: customer)
      token = issue_token(user)
      device = issue_trusted_device(user)
      previous_secret = user.otp_secret

      user.update!(otp_secret: ROTP::Base32.random)

      expect(user.otp_secret).not_to eq(previous_secret)
      expect(token.reload).to be_revoked
      expect(Authentication::TrustedDevice.exists?(device.id)).to be(false)
    end

    it "revokes grants when a previously stored secret is cleared" do
      user = create(:user, :with_mfa, customer: customer)
      token = issue_token(user)

      user.disable_mfa!

      expect(token.reload).to be_revoked
    end

    # First-time enrolment is not a credential invalidation. The user still
    # holds the same password; killing their desktop-client tokens as a side
    # effect of opening MFA setup would be a denial of service.
    it "does not revoke grants when otp_secret goes from nil to a value" do
      user = create(:user, customer: customer)
      expect(user.otp_secret).to be_blank
      token = issue_token(user)
      device = issue_trusted_device(user)

      user.generate_otp_secret!

      expect(user.otp_secret).to be_present
      expect(token.reload).not_to be_revoked
      expect(Authentication::TrustedDevice.exists?(device.id)).to be(true)
    end
  end

  describe "unrelated updates" do
    it "revokes nothing when a non-credential attribute changes" do
      user = create(:user, :mfa_configured, customer: customer)
      token = issue_token(user)
      device = issue_trusted_device(user)

      user.update!(first_name: "Ada")

      expect(token.reload).not_to be_revoked
      expect(Authentication::TrustedDevice.exists?(device.id)).to be(true)
    end
  end

  describe "tenant / owner isolation" do
    it "does not touch another user's tokens or trusted devices" do
      actor = create(:user, customer: customer)
      bystander = create(:user, customer: customer)
      bystander_token = issue_token(bystander)
      bystander_device = issue_trusted_device(bystander)

      actor.update!(password: "NewPassword1!", password_confirmation: "NewPassword1!")

      expect(bystander_token.reload).not_to be_revoked
      expect(Authentication::TrustedDevice.exists?(bystander_device.id)).to be(true)
    end
  end
end
