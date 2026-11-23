# frozen_string_literal: true

require "rails_helper"

RSpec.describe Sms::OptOut do
  let_it_be(:customer_a) { create(:customer) }
  let_it_be(:customer_b) { create(:customer) }

  it "is valid with a phone_e164" do
    expect(build(:sms_opt_out)).to be_valid
  end

  it "requires phone_e164" do
    o = build(:sms_opt_out, phone_e164: nil)
    expect(o).not_to be_valid
    expect(o.errors[:phone_e164]).to include("can't be blank")
  end

  describe ".opted_out?" do
    it "is false when no matching row exists" do
      expect(described_class.opted_out?(customer_id: customer_a.id, phone_e164: "+8613800138000")).to be(false)
    end

    it "is true when a GLOBAL (customer_id nil) row matches, for ANY tenant" do
      described_class.record_global!(phone_e164: "+8613800138000", provider: "twilio", reason: "inbound:STOP")

      expect(described_class.opted_out?(customer_id: customer_a.id, phone_e164: "+8613800138000")).to be(true)
      expect(described_class.opted_out?(customer_id: customer_b.id, phone_e164: "+8613800138000")).to be(true)
    end

    it "is true when a tenant-scoped row matches that tenant only" do
      described_class.record_for_customer!(customer_id: customer_a.id, phone_e164: "+8613800138000")

      expect(described_class.opted_out?(customer_id: customer_a.id, phone_e164: "+8613800138000")).to be(true)
      expect(described_class.opted_out?(customer_id: customer_b.id, phone_e164: "+8613800138000")).to be(false)
    end

    it "does not match a different phone number" do
      described_class.record_global!(phone_e164: "+8613800138000")
      expect(described_class.opted_out?(customer_id: customer_a.id, phone_e164: "+8613800139999")).to be(false)
    end
  end

  describe ".record_global!" do
    it "creates a customer_id-nil row" do
      row = described_class.record_global!(phone_e164: "+8613800138000", provider: "twilio", reason: "inbound:STOP")
      expect(row.customer_id).to be_nil
      expect(row.provider).to eq("twilio")
      expect(row.reason).to eq("inbound:STOP")
    end

    it "is idempotent — a second call for the same phone does not raise or duplicate" do
      described_class.record_global!(phone_e164: "+8613800138000")
      expect {
        described_class.record_global!(phone_e164: "+8613800138000")
      }.not_to change(described_class, :count)
    end

    it "is race-safe against a concurrent insert (RecordNotUnique)" do
      allow(described_class).to receive(:find_or_create_by!).and_raise(ActiveRecord::RecordNotUnique)
      existing = described_class.create!(customer_id: nil, phone_e164: "+8613800138000")

      result = described_class.record_global!(phone_e164: "+8613800138000")
      expect(result).to eq(existing)
    end
  end

  describe ".record_for_customer!" do
    it "creates a customer_id-scoped row" do
      row = described_class.record_for_customer!(customer_id: customer_a.id, phone_e164: "+8613800138000",
                                                  reason: "manual")
      expect(row.customer_id).to eq(customer_a.id)
      expect(row.reason).to eq("manual")
    end

    it "canonicalizes writes and reads through the same phone helper" do
      row = described_class.record_for_customer!(customer_id: customer_a.id, phone_e164: "00 86 138-0013-8000")
      expect(row.phone_e164).to eq("+8613800138000")
      expect(described_class.opted_out?(customer_id: customer_a.id, phone_e164: "13800138000")).to be(true)
      expect(described_class.opted_out?(customer_id: customer_b.id, phone_e164: "+86 138 0013 8000")).to be(false)
    end

    it "rejects invalid writes and does not query invalid suppression keys" do
      expect { described_class.record_global!(phone_e164: "call 13800138000") }.to raise_error(ArgumentError)
      expect(described_class).not_to receive(:where)
      expect(described_class.opted_out?(customer_id: customer_a.id, phone_e164: ["13800138000"])).to be(false)
    end
  end

  describe ".for_customer scope" do
    it "returns global rows and this tenant's rows, excluding other tenants'" do
      global = described_class.record_global!(phone_e164: "+8613800138000")
      mine   = described_class.record_for_customer!(customer_id: customer_a.id, phone_e164: "+8613800139999")
      described_class.record_for_customer!(customer_id: customer_b.id, phone_e164: "+8613800137777")

      result = described_class.for_customer(customer_a.id)
      expect(result).to contain_exactly(global, mine)
    end
  end

  it "is NOT TenantScoped (no default customer scope leaks through .all)" do
    described_class.record_for_customer!(customer_id: customer_a.id, phone_e164: "+8613800138000")
    described_class.record_for_customer!(customer_id: customer_b.id, phone_e164: "+8613800139999")

    expect(described_class.count).to eq(2)
  end
end
