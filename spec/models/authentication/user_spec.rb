# frozen_string_literal: true

require "rails_helper"

RSpec.describe Authentication::User, type: :model do
  let_it_be(:customer) { create(:customer) }

  # The platform-owner customer (81721200) is a fixed, seedable singleton.
  def platform_customer
    Customer.find_by(id: 81_721_200) || create(:customer, id: 81_721_200)
  end

  describe "validations" do
    it "is valid with valid attributes" do
      user = build(:user, customer: customer)
      expect(user).to be_valid
    end

    it "requires email" do
      user = build(:user, customer: customer, email: nil)
      expect(user).not_to be_valid
      expect(user.errors[:email]).to be_present
    end

    it "requires valid email format" do
      user = build(:user, customer: customer, email: "invalid")
      expect(user).not_to be_valid
    end

    it "requires email uniqueness globally" do
      create(:user, customer: customer, email: "dup@example.com")
      user = build(:user, customer: customer, email: "dup@example.com")
      expect(user).not_to be_valid
    end

    it "rejects the same email on a different customer" do
      other_customer = create(:customer)
      create(:user, customer: customer, email: "same@example.com")
      user = build(:user, customer: other_customer, email: "same@example.com")
      expect(user).not_to be_valid
    end

    it "requires first_name" do
      user = build(:user, customer: customer, first_name: nil)
      expect(user).not_to be_valid
    end

    it "requires last_name" do
      user = build(:user, customer: customer, last_name: nil)
      expect(user).not_to be_valid
    end

    it "requires password on create" do
      user = build(:user, customer: customer, password: nil)
      expect(user).not_to be_valid
    end

    it "allows a blank password on create when allow_blank_password is set" do
      user = build(:user, customer: customer, password: nil, allow_blank_password: true)
      expect(user).to be_valid
      expect(user.password_set?).to be(false)
    end

    it "requires password minimum 8 characters" do
      user = build(:user, customer: customer, password: "short")
      expect(user).not_to be_valid
    end

    it "requires customer_id" do
      user = described_class.new(email: "test@example.com", first_name: "A", last_name: "B",
                       password: "password123", customer_id: nil)
      expect(user).not_to be_valid
    end
  end

  describe "enums" do
    it "has status enum" do
      expect(described_class.statuses).to eq("active" => 0, "inactive" => 1, "trashed" => 2)
    end
  end

  describe "scopes" do
    it ".active returns only active users" do
      # Scope assertions to this example's own (fresh) customer so the result is
      # not polluted by users other specs may leave behind in a full-suite run.
      active = create(:user, customer: customer, status: :active)
      inactive = create(:user, customer: customer, status: :inactive)
      result = described_class.where(customer: customer).active
      expect(result).to include(active)
      expect(result).not_to include(inactive)
    end

    it ".by_role returns users with specified role" do
      admin = create(:user, customer: customer, role: :admin)
      member = create(:user, customer: customer, role: :member)
      result = described_class.where(customer: customer).by_role(:admin)
      expect(result).to include(admin)
      expect(result).not_to include(member)
    end
  end

  describe "#active_for_authentication? (per-request activation gate, S3)" do
    it "is true for a confirmed active user" do
      user = create(:user, customer: customer, status: :active)
      expect(user.active_for_authentication?).to be(true)
    end

    it "is false once the user is deactivated" do
      user = create(:user, customer: customer, status: :active)
      user.update!(status: :inactive)
      expect(user.active_for_authentication?).to be(false)
    end

    it "reports the :deactivated inactive_message when inactive" do
      user = create(:user, customer: customer, status: :inactive)
      expect(user.inactive_message).to eq(:deactivated)
    end
  end

  describe ".find_for_database_authentication" do
    it "finds user by email" do
      user = create(:user, customer: customer, email: "auth@example.com")
      found = described_class.find_for_database_authentication(
        email: "auth@example.com"
      )
      expect(found).to eq(user)
    end

    it "is case insensitive for email" do
      user = create(:user, customer: customer, email: "auth@example.com")
      found = described_class.find_for_database_authentication(
        email: "AUTH@EXAMPLE.COM"
      )
      expect(found).to eq(user)
    end

    it "finds the user even when a leftover customer_id is passed" do
      user = create(:user, customer: customer, email: "auth@example.com")
      other = create(:customer)
      found = described_class.find_for_database_authentication(
        email: "auth@example.com", customer_id: other.id
      )
      expect(found).to eq(user)
    end

    it "excludes inactive users" do
      create(:user, customer: customer, email: "auth@example.com", status: :inactive)
      found = described_class.find_for_database_authentication(
        email: "auth@example.com"
      )
      expect(found).to be_nil
    end

    it "returns nil without email" do
      create(:user, customer: customer, email: "auth@example.com")
      found = described_class.find_for_database_authentication(email: nil)
      expect(found).to be_nil
    end
  end

  describe "2FA / MFA" do
    describe "otp_secret encryption at rest" do
      it "does not store the plaintext otp_secret in the database column" do
        user = create(:user, customer: customer)
        user.generate_otp_secret!
        plaintext = user.otp_secret

        raw_column_value = described_class.connection.select_value(
          "SELECT otp_secret FROM users WHERE id = #{user.id}"
        )

        expect(raw_column_value).not_to eq(plaintext)
        expect(raw_column_value).to be_present
      end

      it "still round-trips transparently through the AR attribute reader" do
        user = create(:user, customer: customer)
        user.generate_otp_secret!
        plaintext = user.otp_secret

        expect(described_class.find(user.id).otp_secret).to eq(plaintext)
      end

      it "verify_otp still works against the encrypted-at-rest secret" do
        user = create(:user, :with_mfa, customer: customer)
        reloaded = described_class.find(user.id)
        code = ROTP::TOTP.new(reloaded.otp_secret).now

        expect(reloaded.verify_otp(code)).to be true
      end
    end

    describe "#generate_otp_secret!" do
      it "sets a new otp_secret" do
        user = create(:user, customer: customer)
        user.generate_otp_secret!
        expect(user.otp_secret).to be_present
        expect(user.otp_secret.length).to be >= 16
      end
    end

    describe "#verify_otp" do
      it "verifies a valid TOTP code" do
        user = create(:user, :with_mfa, customer: customer)
        totp = ROTP::TOTP.new(user.otp_secret)
        code = totp.now
        expect(user.verify_otp(code)).to be true
      end

      it "rejects an invalid code" do
        user = create(:user, :with_mfa, customer: customer)
        expect(user.verify_otp("000000")).to be false
      end

      it "returns false without otp_secret" do
        user = create(:user, customer: customer)
        expect(user.verify_otp("123456")).to be false
      end

      it "rejects a code more than ~30 seconds in the past" do
        user = create(:user, :with_mfa, customer: customer)
        totp = ROTP::TOTP.new(user.otp_secret)
        old_code = totp.at(Time.now - 90)
        expect(user.verify_otp(old_code)).to be false
      end

      it "rejects a code more than ~30 seconds in the future" do
        user = create(:user, :with_mfa, customer: customer)
        totp = ROTP::TOTP.new(user.otp_secret)
        future_code = totp.at(Time.now + 90)
        expect(user.verify_otp(future_code)).to be false
      end

      it "refuses to accept the same code twice (replay protection)" do
        user = create(:user, :with_mfa, customer: customer)
        code = ROTP::TOTP.new(user.otp_secret).now
        expect(user.verify_otp(code)).to be true
        expect(user.verify_otp(code)).to be false
      end

      # ROTP interprets drift_behind/drift_ahead as SECONDS (not steps), so
      # +/-15s tolerates minor clock skew within a single 30s step while
      # `after: last_otp_at` prevents replay and Authentication::Throttle caps
      # brute force. A code well outside that window (a couple of steps old) is
      # rejected.
      describe "clock-skew tolerance (+/-15s)" do
        it "rejects a code from well outside the +/-15s window" do
          user = create(:user, :with_mfa, customer: customer)
          totp = ROTP::TOTP.new(user.otp_secret)
          base = Time.at((Time.now.to_i / 30) * 30 + 5)

          travel_to(base) do
            stale_code = totp.at(base - 60) # ~55-65s old — outside +/-15s
            expect(user.verify_otp(stale_code)).to be false
          end
        end

        it "still verifies the current-step code at the same instant" do
          user = create(:user, :with_mfa, customer: customer)
          totp = ROTP::TOTP.new(user.otp_secret)
          base = Time.at((Time.now.to_i / 30) * 30 + 5)

          travel_to(base) do
            current_step_code = totp.at(base)
            expect(user.verify_otp(current_step_code)).to be true
          end
        end
      end
    end

    describe "#otp_provisioning_uri" do
      it "returns a provisioning URI" do
        user = create(:user, :with_mfa, customer: customer)
        uri = user.otp_provisioning_uri
        expect(uri).to include("otpauth://totp/")
        expect(uri).to include(ERB::Util.url_encode(user.email))
      end

      it "returns nil without otp_secret" do
        user = create(:user, customer: customer)
        expect(user.otp_provisioning_uri).to be_nil
      end
    end

    describe "#enable_mfa!" do
      it "enables MFA" do
        user = create(:user, :mfa_configured, customer: customer)
        user.enable_mfa!
        expect(user.otp_required_for_login).to be true
      end

      it "raises without otp_secret" do
        user = create(:user, customer: customer)
        expect { user.enable_mfa! }.to raise_error(RuntimeError, "OTP secret not set")
      end
    end

    describe "#disable_mfa!" do
      it "disables MFA and clears secret" do
        user = create(:user, :with_mfa, customer: customer)
        user.disable_mfa!
        expect(user.otp_required_for_login).to be false
        expect(user.otp_secret).to be_nil
      end
    end

    describe "#mfa_configured?" do
      it "returns true when otp_secret is set" do
        user = build(:user, :mfa_configured)
        expect(user.mfa_configured?).to be true
      end

      it "returns false when otp_secret is not set" do
        user = build(:user)
        expect(user.mfa_configured?).to be false
      end
    end

    describe "#mfa_required?" do
      it "returns true when both otp_required_for_login and otp_secret are set" do
        user = build(:user, :with_mfa)
        expect(user.mfa_required?).to be true
      end

      it "returns false when otp_required_for_login is false" do
        user = build(:user, :mfa_configured)
        expect(user.mfa_required?).to be false
      end
    end
  end

  describe "display helpers" do
    it "#full_name returns first and last name" do
      user = build(:user, first_name: "John", last_name: "Doe")
      expect(user.full_name).to eq("John Doe")
    end

    it "#display_name returns full name when present" do
      user = build(:user, first_name: "John", last_name: "Doe")
      expect(user.display_name).to eq("John Doe")
    end
  end

  describe "associations" do
    it "belongs to customer" do
      user = create(:user, customer: customer)
      expect(user.customer).to eq(customer)
    end

    it "has many person_entries and hands their identity back on destroy" do
      user = create(:user, customer: customer, first_name: "Ada", last_name: "Lovelace", email: "ada@example.com")
      entity = create(:entity, customer: customer)
      entry = create(:entity_entry, entity: entity, customer: customer, user: user)

      expect(user.person_entries).to contain_exactly(entry)
      user.destroy!
      entry.reload
      expect(entry.user_id).to be_nil
      expect(entry.data_json).to include("first_name" => "Ada", "last_name" => "Lovelace", "email" => "ada@example.com")
    end
  end

  describe "RBAC associations" do
    let(:user) { create(:user, customer: customer) }
    let(:role) { create(:role, customer: customer) }

    it "has many users_roles and roles" do
      user.users_roles.create!(role: role)
      expect(user.reload.roles).to contain_exactly(role)
    end
  end

  describe "#has_reserved_role?" do
    let(:user) { create(:user, customer: customer) }

    it "returns true when user holds a system role with the given key" do
      admin = create(:user, customer: customer, role: :admin)
      expect(admin.has_reserved_role?(:admin)).to be true
    end

    it "returns false when user holds only a custom role with that key" do
      role = create(:role, customer: customer, key: "custom_owner", system: false)
      user.users_roles.create!(role: role)
      expect(user.has_reserved_role?(:owner)).to be false
    end

    it "returns false when user holds no such role" do
      expect(user.has_reserved_role?(:owner)).to be false
    end
  end

  describe "Devise 5.0 resource-level overrides" do
    describe ".password_length" do
      it "returns the global Devise.password_length range by default" do
        expect(described_class.password_length).to eq(Devise.password_length)
      end

      it "drives the password length validation at runtime (seam wired through validation)" do
        allow(described_class).to receive(:password_length).and_return(20..128)
        user = build(:user, customer: customer, password: "tooshort1", password_confirmation: "tooshort1")
        expect(user).not_to be_valid
        expect(user.errors[:password].join).to match(/too short/i)
      end
    end

    describe ".sign_in_after_change_password" do
      it "is inherited from :registerable and returns Devise's global flag by default" do
        expect(described_class.sign_in_after_change_password)
          .to eq(Devise.sign_in_after_change_password)
      end
    end

    describe ".sign_in_after_reset_password" do
      it "is inherited from :recoverable and returns Devise's global flag by default" do
        expect(described_class.sign_in_after_reset_password)
          .to eq(Devise.sign_in_after_reset_password)
      end
    end
  end

  describe ".send_confirmation_instructions" do
    before do
      allow_any_instance_of(described_class).to receive(:send_devise_notification)
      allow(FeatureModules::Module).to receive(:enabled?).and_return(true)
      allow(Authentication::Settings).to receive(:for).and_return(
        instance_double(Authentication::Settings, signup_enabled?: true, password_reset_enabled?: true)
      )
    end

    it "looks up the user by email globally and sets a confirmation token" do
      user = create(:user, :unconfirmed, customer: customer, email: "shared@example.com")

      result = described_class.send_confirmation_instructions(email: "shared@example.com")

      expect(result).to eq(user)
      expect(user.reload.confirmation_token).to be_present
    end

    it "does not send when signup is disabled for the user's tenant" do
      user = create(:user, :unconfirmed, customer: customer, email: "shared@example.com")
      allow(Authentication::Settings).to receive(:for).and_return(
        instance_double(Authentication::Settings, signup_enabled?: false, password_reset_enabled?: true)
      )

      expect_any_instance_of(described_class).not_to receive(:send_confirmation_instructions)
      result = described_class.send_confirmation_instructions(email: "shared@example.com")
      expect(result).to eq(user)
    end
  end

  describe ".send_reset_password_instructions" do
    before do
      allow_any_instance_of(described_class).to receive(:send_devise_notification)
      allow(FeatureModules::Module).to receive(:enabled?).and_return(true)
      allow(Authentication::Settings).to receive(:for).and_return(
        instance_double(Authentication::Settings, signup_enabled?: true, password_reset_enabled?: true)
      )
    end

    it "returns a new (blank) user when email is unknown" do
      result = described_class.send_reset_password_instructions(email: "x@x.com")
      expect(result).to be_new_record
    end

    it "returns a new user with email not_found error when email does not match any user" do
      result = described_class.send_reset_password_instructions(email: "nobody@x.com")
      expect(result).to be_new_record
      expect(result.errors[:email]).to be_present
    end

    it "returns the found user and triggers reset instructions" do
      u = create(:user, customer: customer, email: "reset@example.com")
      expect_any_instance_of(described_class).to receive(:send_reset_password_instructions).and_call_original
      result = described_class.send_reset_password_instructions(email: "reset@example.com")
      expect(result).to eq(u)
    end

    it "accepts ActionController::Parameters (normalize_recovery_attributes branch)" do
      params = ActionController::Parameters.new(email: "p@x.com")
      result = described_class.send_reset_password_instructions(params)
      expect(result).to be_new_record
      expect(result.errors[:email]).to be_present
    end
  end

  describe ".send_unlock_instructions" do
    before do
      allow_any_instance_of(described_class).to receive(:send_devise_notification)
      allow(FeatureModules::Module).to receive(:enabled?).and_return(true)
    end

    it "returns a new user when email is unknown" do
      result = described_class.send_unlock_instructions(email: "x@x.com")
      expect(result).to be_new_record
    end

    it "returns a new user with error when email is not found" do
      result = described_class.send_unlock_instructions(email: "nope@x.com")
      expect(result).to be_new_record
      expect(result.errors[:email]).to be_present
    end

    it "calls send_unlock_instructions on found user" do
      create(:user, customer: customer, email: "unlock@example.com")
      expect_any_instance_of(described_class).to receive(:send_unlock_instructions).and_call_original
      described_class.send_unlock_instructions(email: "unlock@example.com")
    end
  end

  describe ".find_for_database_authentication — nil email guard" do
    let(:cust) { create(:customer) }

    it "returns nil when email is nil" do
      result = described_class.find_for_database_authentication(
        customer_id: cust.id, email: nil
      )
      expect(result).to be_nil
    end
  end

  describe "#display_name" do
    let(:cust) { create(:customer) }

    it "falls back to email when full_name is blank" do
      u = build(:user, customer: cust, first_name: " ", last_name: " ",
                email: "fallback@example.com")
      expect(u.display_name).to eq("fallback@example.com")
    end

    it "returns full_name when present" do
      u = build(:user, customer: cust, first_name: "Ada", last_name: "Lovelace")
      expect(u.display_name).to eq("Ada Lovelace")
    end
  end

  describe "#platform_owner?" do
    it "returns true only for owner on platform customer 81721200" do
      platform_cust = platform_customer
      # Use build + stub roles to avoid uniqueness collision with a pre-seeded owner user
      u = build(:user, customer: platform_cust, email: "lingercoffee@gmail.com")
      allow(u).to receive(:owner?).and_return(true)
      expect(u.platform_owner?).to be true
    end

    it "returns false for admin on a regular customer" do
      cust = create(:customer)
      u = create(:user, customer: cust, role: :admin)
      expect(u.platform_owner?).to be false
    end
  end

  describe "#eligible_for_owner_role?" do
    it "returns true for platform owner email under customer 81721200" do
      platform_cust = platform_customer
      u = build(:user, customer: platform_cust, email: "lingercoffee@gmail.com")
      expect(u.eligible_for_owner_role?).to be true
    end

    it "returns false for any other email under the platform customer" do
      platform_cust = platform_customer
      u = build(:user, customer: platform_cust, email: "other@example.com")
      expect(u.eligible_for_owner_role?).to be false
    end

    it "returns false for the owner email under a different customer" do
      cust = create(:customer)
      u = build(:user, customer: cust, email: "lingercoffee@gmail.com")
      expect(u.eligible_for_owner_role?).to be false
    end
  end

  describe "#primary_role_key fallback" do
    it "returns 'member' when user has no reserved roles assigned" do
      cust = create(:customer)
      u = create(:user, customer: cust)
      # No roles at all — reserved_role_keys is []
      expect(u.primary_role_key).to eq("member")
    end
  end

  describe "#role_display_name" do
    it "uses the reserved-role i18n label instead of capitalizing the key" do
      u = create(:user, :admin, customer: customer)
      expect(u.role_display_name).to eq("Admin")
      I18n.with_locale(:"zh-CN") do
        expect(u.role_display_name).to eq("管理员")
      end
    end
  end

  describe "#admin_or_owner?" do
    it "returns true for admin users" do
      cust = create(:customer)
      u = create(:user, customer: cust, role: :admin)
      expect(u.admin_or_owner?).to be true
    end

    it "returns false for member users" do
      cust = create(:customer)
      u = create(:user, customer: cust, role: :member)
      expect(u.admin_or_owner?).to be false
    end
  end

  describe "#revoke_trusted_devices! via after_update callback" do
    it "deletes trusted devices when password changes" do
      cust = create(:customer)
      u = create(:user, customer: cust)
      td = Authentication::TrustedDevice.new(user_id: u.id, customer_id: cust.id,
                                             user_agent: "UA", ip: "1.2.3.4",
                                             token_digest: "abc123",
                                             expires_at: 30.days.from_now)
      td.save!(validate: false)
      expect(u.trusted_devices.count).to eq(1)
      u.update!(password: "NewPassword1!", password_confirmation: "NewPassword1!")
      expect(u.trusted_devices.count).to eq(0)
    end
  end

  describe ".send_confirmation_instructions — user not found (nil &. branch)" do
    before do
      allow_any_instance_of(described_class).to receive(:send_devise_notification)
    end

    it "returns new user with email error when email is not found" do
      result = described_class.send_confirmation_instructions(email: "nobody@x.com")
      expect(result).to be_new_record
      expect(result.errors[:email]).to be_present
    end
  end

  describe ".find_by_normalized_email — blank email guard" do
    it "returns nil when email is blank" do
      result = described_class.send_reset_password_instructions(email: "")
      expect(result).to be_new_record
    end
  end

  # One case-insensitive lookup now backs Warden, password reset, unlock,
  # confirmation resend, and the sign-in link — there used to be three
  # hand-rolled `LOWER(email) = ?` copies that could drift apart.
  describe ".find_by_normalized_email" do
    let(:cust) { create(:customer) }

    it "matches regardless of case and surrounding whitespace" do
      user = create(:user, customer: cust, email: "canonical@example.com")

      expect(described_class.find_by_normalized_email(" CANONICAL@Example.COM ")).to eq(user)
    end

    it "returns nil for blank input" do
      expect(described_class.find_by_normalized_email(nil)).to be_nil
      expect(described_class.find_by_normalized_email("   ")).to be_nil
    end

    it "returns nil for an unknown address" do
      expect(described_class.find_by_normalized_email("nobody@example.com")).to be_nil
    end

    it "honours a scope it is chained onto" do
      create(:user, customer: cust, email: "off@example.com", status: :inactive)

      expect(described_class.find_by_normalized_email("off@example.com")).to be_present
      expect(described_class.active.find_by_normalized_email("off@example.com")).to be_nil
    end
  end

  describe "locale preference" do
    it "accepts a supported locale" do
      expect(build(:user, customer: customer, locale: "zh-CN")).to be_valid
    end

    it "treats blank/nil as 'follow the fallback chain'" do
      expect(build(:user, customer: customer, locale: nil)).to be_valid
      expect(build(:user, customer: customer, locale: "")).to be_valid
    end

    it "rejects a locale outside I18n.available_locales" do
      user = build(:user, customer: customer, locale: "fr")
      expect(user).not_to be_valid
      expect(user.errors[:locale]).to be_present
    end
  end

  # A password change or OTP-secret invalidation must kill every grant minted
  # under the old credential. First-time enrolment (nil → secret) is not an
  # invalidation — tearing down desktop-client tokens there would punish a
  # user for opening the MFA setup page.
  describe "credential-change grant revocation" do
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
        user: owner, ip: "1.2.3.4", user_agent: "RSpec"
      ).first
    end

    it "revokes the user's active access tokens and trusted devices on password change" do
      user = create(:user, customer: customer)
      token = issue_token(user)
      device = issue_trusted_device(user)

      user.update!(password: "NewPassword1!", password_confirmation: "NewPassword1!")

      expect(token.reload).to be_revoked
      expect(Authentication::TrustedDevice.find_by(id: device.id)).to be_nil
    end

    it "revokes grants when an existing otp_secret is rotated" do
      user = create(:user, :mfa_configured, customer: customer)
      token = issue_token(user)
      device = issue_trusted_device(user)

      user.update!(otp_secret: ROTP::Base32.random)

      expect(token.reload).to be_revoked
      expect(Authentication::TrustedDevice.find_by(id: device.id)).to be_nil
    end

    it "does not revoke grants on first-time OTP enrolment (nil → secret)" do
      user = create(:user, customer: customer)
      token = issue_token(user)
      device = issue_trusted_device(user)

      user.generate_otp_secret!

      expect(token.reload).not_to be_revoked
      expect(Authentication::TrustedDevice.find_by(id: device.id)).to eq(device)
    end

    it "does not revoke grants on an unrelated attribute update" do
      user = create(:user, :mfa_configured, customer: customer)
      token = issue_token(user)
      device = issue_trusted_device(user)

      user.update!(first_name: "Renamed")

      expect(token.reload).not_to be_revoked
      expect(Authentication::TrustedDevice.find_by(id: device.id)).to eq(device)
    end

    it "leaves another user's tokens and trusted devices untouched" do
      user = create(:user, customer: customer)
      other = create(:user, customer: customer)
      other_token = issue_token(other)
      other_device = issue_trusted_device(other)
      issue_token(user)
      issue_trusted_device(user)

      user.update!(password: "NewPassword1!", password_confirmation: "NewPassword1!")

      expect(other_token.reload).not_to be_revoked
      expect(Authentication::TrustedDevice.find_by(id: other_device.id)).to eq(other_device)
    end
  end
end
