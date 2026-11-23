# frozen_string_literal: true

require "rails_helper"

RSpec.describe FeatureModules::Authentication::Provisioner do
  let(:customer) { create(:customer, name: "Acme Corp", contact: "admin@acme.com") }
  let(:provisioned_user) { Authentication::User.find_by(customer: customer) }

  describe ".call" do
    it "auto-provisions exactly one user on customer creation" do
      expect(Authentication::User.where(customer: customer).count).to eq(1)
    end

    it "assigns the admin role (not owner) to the provisioned user" do
      expect(provisioned_user.admin?).to be true
      expect(provisioned_user.owner?).to be false
      expect(provisioned_user.reserved_role_keys).to eq(["admin"])
    end

    context "when provisioning the platform owner customer" do
      let(:platform_customer) do
        Customer.find_or_create_by!(id: ::Authentication::User::PLATFORM_CUSTOMER_ID) do |c|
          c.name = "Platform"
          c.industry = :technology
          c.tier = :basic
          c.contact = nil
        end
      end

      it "creates the pinned platform owner account with owner role" do
        Authentication::User.where(customer: platform_customer).destroy_all
        described_class.call(platform_customer)
        user = Authentication::User.find_by(customer: platform_customer)
        expect(user.email).to eq(::Authentication::User::PLATFORM_OWNER_EMAIL)
        expect(user.owner?).to be true
        expect(user.reserved_role_keys).to eq(["owner"])
      end
    end

    it "uses the customer contact as the email when one is present" do
      expect(provisioned_user.email).to eq("admin@acme.com")
    end

    it "generates a fallback email from the customer name when contact is blank" do
      # Re-provision from scratch so the fallback (not the seeded contact) is exercised
      Authentication::User.where(customer: customer).destroy_all
      customer.update_column(:contact, nil)
      described_class.call(customer)
      expect(provisioned_user.email).to include("@acme-corp.local")
    end

    it "is idempotent" do
      # Ensure a user exists first (auto-provisioned on customer creation)
      described_class.call(customer)
      expect {
        described_class.call(customer)
      }.not_to change(Authentication::User, :count)
    end

    it "does not leave an account behind when provisioning its reserved join fails" do
      Authentication::User.where(customer: customer).destroy_all
      allow_any_instance_of(UsersRole).to receive(:save!) do |record|
        record.errors.add(:base, I18n.t("auth.errors.reserved_role_required"))
        raise ActiveRecord::RecordInvalid.new(record)
      end

      expect { described_class.call(customer) }.to raise_error(ActiveRecord::RecordInvalid)
      expect(Authentication::User.where(customer: customer)).to be_empty
    end

    it "suffixes the provisioned email when that address already exists on another tenant" do
      customer
      other = create(:customer, name: "Other Org", contact: "admin@acme.com")
      expect(Authentication::User.find_by(customer: other).email).to eq("admin+#{other.id}@acme.com")
    end
  end
end
