# frozen_string_literal: true

require "rails_helper"

RSpec.describe ExtendedModels::Attributes do
  describe ".allowed" do
    it "returns the extended model's columns except structural and sensitive ones" do
      allowed = described_class.allowed("Authentication::User")

      expect(allowed).to include("first_name", "last_name", "email", "locale")
      expect(allowed).not_to include("id", "customer_id", "created_at", "updated_at")
      expect(allowed & Authentication::User::SENSITIVE_COLUMNS).to be_empty
    end

    it "returns every non-structural column when the model declares none sensitive" do
      allowed = described_class.allowed("Customer")

      expect(allowed).to include("name")
      expect(allowed).not_to include("id", "created_at", "updated_at")
    end

    it "returns nothing for a name that is not an application record" do
      expect(described_class.allowed("String")).to eq([])
      expect(described_class.allowed("Missing::Model")).to eq([])
    end
  end

  describe ".link" do
    it "finds the entry association whose target is the extended model" do
      link = described_class.link("Authentication::User")

      expect(link.name).to eq(:user)
      expect(link.foreign_key).to eq("user_id")
      expect(link.klass.table_name).to eq("users")
    end

    it "returns nil when the entry has no association to that model" do
      expect(described_class.link("Page")).to be_nil
      expect(described_class.link("Missing::Model")).to be_nil
    end
  end
end
