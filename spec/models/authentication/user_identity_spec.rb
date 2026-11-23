# frozen_string_literal: true

require "rails_helper"

RSpec.describe Authentication::User, "pinned owner identity and password confirmation" do
  describe "owner pin" do
    let(:owner) { find_or_create_platform_owner }

    it "rejects changing the persisted owner's email" do
      expect(owner.update(email: "replacement@example.com")).to be(false)
      expect(owner.errors[:email]).to include(I18n.t("admin_settings.errors.validations.role_owner_reserved"))
      expect(owner.reload.email).to eq(described_class::PLATFORM_OWNER_EMAIL)
    end

    it "rejects moving the persisted owner to another customer" do
      original_customer = owner.customer_id
      expect(owner.update(customer: create(:customer))).to be(false)
      expect(owner.reload.customer_id).to eq(original_customer)
    end

    it "protects the pin even when the role association was loaded as empty" do
      owner.users_roles.delete_all # Fixture a provisioning-time identity before its join exists.
      stale = described_class.find(owner.id)
      expect(stale.owner?).to be(false)
      owner.users_roles.create!(role: owner.customer.roles.system.find_by!(key: "owner"))

      expect(stale.update(email: "replacement@example.com")).to be(false)
      expect(owner.reload.email).to eq(described_class::PLATFORM_OWNER_EMAIL)
    end

    it "allows name and password updates without changing owner identity" do
      expect(owner.update(first_name: "Renamed", password: "NewPassword1!", password_confirmation: "NewPassword1!"))
        .to be(true)
      expect(owner.reload).to be_platform_owner
    end

    it "never grants platform access to an owner predicate with the wrong identity" do
      account = build(:user, customer: owner.customer, email: "other@example.com")
      allow(account).to receive(:owner?).and_return(true)
      expect(account).not_to be_platform_owner
    end
  end

  describe "password confirmation" do
    let(:account) { create(:user, customer: create(:customer)) }

    it "rejects a mismatched confirmation when creating a passworded account" do
      account = build(:user, password: "NewPassword1!", password_confirmation: "DifferentPassword1!")
      expect(account).not_to be_valid
      expect(account.errors[:password_confirmation]).to be_present
    end

    it "does not change a persisted password on a confirmation mismatch" do
      expect(account.update(password: "NewPassword1!", password_confirmation: "DifferentPassword1!"))
        .to be(false)
      expect(account.reload.valid_password?("password123")).to be(true)
    end

    it "leaves a reset token usable after a mismatched reset, then accepts a matching reset" do
      raw = account.send(:set_reset_password_token)
      rejected = described_class.reset_password_by_token(
        reset_password_token: raw, password: "NewPassword1!", password_confirmation: "DifferentPassword1!"
      )
      expect(rejected.errors[:password_confirmation]).to be_present
      expect(account.reload.reset_password_token).to be_present
      expect(account.valid_password?("password123")).to be(true)

      accepted = described_class.reset_password_by_token(
        reset_password_token: raw, password: "NewPassword1!", password_confirmation: "NewPassword1!"
      )
      expect(accepted.errors).to be_empty
      expect(account.reload.valid_password?("NewPassword1!")).to be(true)
    end

    it "preserves passwordless creation and name-only updates" do
      passwordless = build(:user, customer: account.customer, password: nil, allow_blank_password: true)
      expect(passwordless).to be_valid
      expect(account.update(first_name: "Renamed")).to be(true)
    end
  end
end
