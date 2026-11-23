# frozen_string_literal: true

require "rails_helper"

RSpec.describe Emails::Suppression, type: :model do
  let_it_be(:customer_a) { create(:customer) }
  let_it_be(:customer_b) { create(:customer) }

  describe "validations" do
    it "requires an email" do
      expect(described_class.new(email: nil)).not_to be_valid
    end

    it "is valid with just an email (customer_id nullable = global)" do
      expect(described_class.new(email: "a@b.com")).to be_valid
    end
  end

  describe ".normalize" do
    it "lowercases and strips the email" do
      expect(described_class.normalize("  Foo@Example.COM  ")).to eq("foo@example.com")
    end
  end

  describe ".suppressed?" do
    it "matches a global (customer_id nil) suppression regardless of the querying tenant" do
      described_class.record_global!(email: "bounced@example.com", reason: "hard_bounce")

      expect(described_class.suppressed?(customer_id: customer_a.id, email: "bounced@example.com")).to be true
      expect(described_class.suppressed?(customer_id: customer_b.id, email: "bounced@example.com")).to be true
    end

    it "matches a tenant-scoped suppression only for that tenant" do
      described_class.record_for_customer!(customer_id: customer_a.id, email: "manual@example.com", reason: "manual")

      expect(described_class.suppressed?(customer_id: customer_a.id, email: "manual@example.com")).to be true
      expect(described_class.suppressed?(customer_id: customer_b.id, email: "manual@example.com")).to be false
    end

    it "is case-insensitive" do
      described_class.record_global!(email: "Bounced@Example.com", reason: "hard_bounce")
      expect(described_class.suppressed?(customer_id: customer_a.id, email: "bounced@example.com")).to be true
    end

    it "returns false when no matching row exists" do
      expect(described_class.suppressed?(customer_id: customer_a.id, email: "clean@example.com")).to be false
    end
  end

  describe ".record_global!" do
    it "creates a customer_id-nil row with the normalized email" do
      row = described_class.record_global!(email: "Bounce@Example.com", reason: "hard_bounce", provider: "ses")
      expect(row.customer_id).to be_nil
      expect(row.email).to eq("bounce@example.com")
      expect(row.reason).to eq("hard_bounce")
      expect(row.provider).to eq("ses")
    end

    it "is idempotent under a race (RecordNotUnique returns the existing row)" do
      first = described_class.record_global!(email: "dup@example.com", reason: "hard_bounce")
      allow(described_class).to receive(:find_or_create_by!).and_raise(ActiveRecord::RecordNotUnique)

      second = described_class.record_global!(email: "dup@example.com", reason: "complaint")
      expect(second.id).to eq(first.id)
    end
  end

  describe ".record_for_customer!" do
    it "creates a tenant-scoped row" do
      row = described_class.record_for_customer!(customer_id: customer_a.id, email: "a@b.com", reason: "manual")
      expect(row.customer_id).to eq(customer_a.id)
    end
  end

  describe ".for_customer scope" do
    it "returns only tenant-scoped rows, excluding global and other tenant rows" do
      described_class.record_global!(email: "global@example.com", reason: "hard_bounce")
      own_row    = described_class.record_for_customer!(customer_id: customer_a.id, email: "own@example.com", reason: "manual")
      other_row  = described_class.record_for_customer!(customer_id: customer_b.id, email: "other@example.com", reason: "manual")

      result = described_class.for_customer(customer_a.id)
      expect(result).to include(own_row)
      expect(result).not_to include(other_row)
      expect(result.pluck(:customer_id)).not_to include(nil)
    end
  end

  describe "uniqueness of (customer_id, email)" do
    it "does not create duplicate rows for the same (customer_id, email) pair" do
      described_class.record_for_customer!(customer_id: customer_a.id, email: "dup2@example.com", reason: "manual")
      expect {
        described_class.record_for_customer!(customer_id: customer_a.id, email: "dup2@example.com", reason: "hard_bounce")
      }.not_to change(described_class, :count)
    end
  end
end
