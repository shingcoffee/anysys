# frozen_string_literal: true

require "rails_helper"

RSpec.describe Role, type: :model do
  let_it_be(:customer) { create(:customer) }

  describe "validations" do
    it "requires key" do
      role = build(:role, key: nil)
      expect(role).not_to be_valid
      expect(role.errors[:key]).to be_present
    end

    it "requires name" do
      role = build(:role, name: nil)
      expect(role).not_to be_valid
      expect(role.errors[:name]).to be_present
    end

    it "enforces uniqueness of key per customer" do
      create(:role, customer: customer, key: "manager")
      dup = build(:role, customer: customer, key: "manager")
      expect(dup).not_to be_valid
      expect(dup.errors[:key]).to be_present
    end

    it "permits same key across different customers" do
      other = create(:customer)
      create(:role, customer: customer, key: "manager")
      expect(build(:role, customer: other, key: "manager")).to be_valid
    end
  end

  describe "scopes" do
    it ".system returns rows with system: true" do
      # Customer already has 3 reserved system roles from after_create callback
      reserved_roles = customer.roles.where(system: true).to_a
      expect(reserved_roles.count).to eq(3)
      sys = create(:role, customer: customer, key: "custom_system", system: true)
      _custom = create(:role, customer: customer, system: false)
      expect(described_class.where(customer: customer).system).to contain_exactly(sys, *reserved_roles)
    end

    it ".custom returns rows with system: false" do
      # Customer already has 3 reserved system roles from after_create callback
      custom = create(:role, customer: customer, system: false)
      expect(described_class.where(customer: customer).custom).to contain_exactly(custom)
    end
  end

  describe "#system?" do
    it "returns true when system: true and false when system: false" do
      aggregate_failures do
        expect(build(:role, system: true)).to be_system
        expect(build(:role, system: false)).not_to be_system
      end
    end
  end

  describe "#locked_grants?" do
    it "returns true when locked_grants: true and false when locked_grants: false" do
      aggregate_failures do
        expect(build(:role, locked_grants: true)).to be_locked_grants
        expect(build(:role, locked_grants: false)).not_to be_locked_grants
      end
    end
  end

  describe "#reserved?" do
    it "returns true for reserved keys" do
      expect(build(:role, customer: customer, key: "owner")).to be_reserved
      expect(build(:role, customer: customer, key: "admin")).to be_reserved
      expect(build(:role, customer: customer, key: "member")).to be_reserved
    end

    it "returns false for custom keys" do
      expect(build(:role, customer: customer, key: "manager")).not_to be_reserved
    end
  end

  describe "case-insensitive key uniqueness" do
    it "rejects duplicates with different case" do
      create(:role, customer: customer, key: "manager")
      dup = build(:role, customer: customer, key: "MANAGER")
      expect(dup).not_to be_valid
    end
  end
end
