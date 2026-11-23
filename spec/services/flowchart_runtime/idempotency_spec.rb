# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartRuntime::Idempotency do
  let(:ctx) { { customer_id: 42 } }
  let(:cache) { ActiveSupport::Cache::MemoryStore.new }

  before { allow(Rails).to receive(:cache).and_return(cache) }

  describe ".claim" do
    it "claims a key once per tenant and reports a duplicate afterwards" do
      expect(described_class.claim(ctx, "order-1", ttl: 60)).to eq(:claimed)
      expect(described_class.claim(ctx, "order-1", ttl: 60)).to eq(:duplicate)
      expect(described_class.claim({ customer_id: 99 }, "order-1", ttl: 60)).to eq(:claimed)
    end

    it "writes under a tenant-scoped cache key" do
      described_class.claim(ctx, "order-1", ttl: 30)

      expect(cache.read(FlowchartRuntime::CacheKey.scoped(42, "idempotency", "order-1"))).to be_present
    end

    it "scopes keys by user without sharing across users of the same tenant" do
      alice = { customer_id: 42, current_user_id: 7, errors: [] }
      bob = { customer_id: 42, current_user_id: 8, errors: [] }

      expect(described_class.claim(alice, "order-1", ttl: 30, scope: "user")).to eq(:claimed)
      expect(described_class.claim(bob, "order-1", ttl: 30, scope: "user")).to eq(:claimed)
      expect(described_class.claim(alice, "order-1", ttl: 30, scope: "user")).to eq(:duplicate)
    end

    it "fails when user scope is selected and no user is signed in" do
      unsigned = { customer_id: 42, errors: [] }
      expect(described_class.claim(unsigned, "order-1", ttl: 30, scope: "user")).to be(false)
      expect(unsigned[:errors]).to eq([I18n.t("flowchart_runtime.errors.idempotency_user_required")])
    end

    it "digests params stably so the same payload hashes the same" do
      first = described_class.digest_inputs({ "a" => 1, "b" => 2 })
      second = described_class.digest_inputs({ "a" => 1, "b" => 2 })

      expect(first).to eq(second)
      expect(first).to match(/\A[0-9a-f]{64}\z/)
    end

    it "rejects a blank key" do
      expect { described_class.claim(ctx, "  ", ttl: 30) }
        .to raise_error(described_class::Error, /key/)
    end
  end
end
