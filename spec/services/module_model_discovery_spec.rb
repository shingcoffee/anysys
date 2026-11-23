# frozen_string_literal: true

require "rails_helper"

RSpec.describe ModuleModelDiscovery do
  describe ".call" do
    context "with authentication module" do
      let(:results)    { described_class.call("authentication") }
      let(:names)      { results.map { |r| r[:name] } }
      let(:user_entry) { results.find { |r| r[:name] == "Authentication::User" } }

      it "discovers Authentication::User model" do
        expect(results).to be_an(Array)
        expect(results.length).to be >= 1

        expect(user_entry).to be_present
        expect(user_entry[:table_name]).to eq("users")
        expect(user_entry[:columns_count]).to be > 0
      end

      it "discovers all authentication models including Roles" do
        expect(names).to include("Authentication::User", "Authentication::Event", "Authentication::TrustedDevice", "Role", "RolePermission", "UsersRole")
      end

      it "includes column details for each model" do
        expect(user_entry[:columns]).to be_an(Array)
        expect(user_entry[:columns].first).to include(:name, :type)
      end

      it "omits credential columns from Authentication::User" do
        names = user_entry[:columns].map { |c| c[:name] }
        expect(names).not_to include(
          "otp_secret", "encrypted_password", "sign_in_token",
          "reset_password_token", "confirmation_token", "unlock_token"
        )
        expect(names).to include("email", "first_name")
      end

      it "includes association details for each model" do
        expect(user_entry[:associations]).to be_an(Array)
        customer_assoc = user_entry[:associations].find { |a| a[:name] == "customer" }
        expect(customer_assoc).to be_present
        expect(customer_assoc[:macro]).to eq("belongs_to")
        expect(customer_assoc[:target_class]).to eq("Customer")
      end
    end

    context "with email module" do
      let(:results) { described_class.call("email") }
      let(:names)   { results.map { |r| r[:name] } }

      it "discovers email models from Emails namespace" do
        expect(names).to include("Emails::Credential", "Emails::Message", "Emails::Template", "Emails::TemplateToken")
      end
    end

    context "with payment module" do
      let(:results) { described_class.call("payment") }
      let(:names)   { results.map { |r| r[:name] } }

      it "discovers payment models from Payments namespace" do
        expect(names).to include("Payments::Payment", "Payments::MerchantAccount", "Payments::Order")
      end
    end

    context "with sms module" do
      let(:results) { described_class.call("sms") }
      let(:names)   { results.map { |r| r[:name] } }

      it "discovers sms models" do
        expect(names).to include("Sms::Credential", "Sms::Message", "Sms::Template")
      end
    end

    context "with captcha module" do
      let(:results) { described_class.call("captcha") }
      let(:names)   { results.map { |r| r[:name] } }

      it "discovers captcha models" do
        expect(names).to include("Captcha::ProviderSettings", "Captcha::UrlThrottle")
      end
    end

    context "with nonexistent module" do
      it "returns empty array" do
        expect(described_class.call("nonexistent")).to eq([])
      end
    end
  end
end
