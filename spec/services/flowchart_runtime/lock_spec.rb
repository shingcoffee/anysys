# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartRuntime::Lock do
  class AtomicLockCache < ActiveSupport::Cache::MemoryStore
    def compare_and_delete(name, expected)
      @monitor.synchronize do
        return false unless read(name) == expected

        delete(name)
      end
    end
  end

  let(:cache) { AtomicLockCache.new }

  before { allow(Rails).to receive(:cache).and_return(cache) }

  describe ".acquire" do
    it "returns true on first successful write" do
      expect(described_class.acquire("tenant-1", "job", "tok-a", ttl: 30)).to be(true)
    end

    it "returns false when the lock is already held and never waits" do
      described_class.acquire("tenant-1", "job", "tok-a", ttl: 30)
      expect(described_class).not_to receive(:sleep)
      expect(described_class.acquire("tenant-1", "job", "tok-b", ttl: 30)).to be(false)
    end

    it "has no wait or retry options" do
      expect { described_class.acquire("tenant-1", "job", "tok-a", ttl: 30, retry_count: 5) }
        .to raise_error(ArgumentError, /retry_count/)
    end

    it "wraps Solid Cache Active Record failures" do
      allow(cache).to receive(:write).and_raise(ActiveRecord::ConnectionNotEstablished, "offline")

      expect { described_class.acquire("tenant-1", "job", "tok", ttl: 30) }
        .to raise_error(FlowchartRuntime::Lock::Error, "offline")
    end

    it "requires a tenant namespace" do
      expect { described_class.acquire(nil, "job", "tok", ttl: 30) }
        .to raise_error(described_class::Error, "tenant namespace is required")
    end

    it "isolates identical keys by tenant namespace" do
      expect(described_class.acquire("tenant-1", "job", "tok-a", ttl: 30)).to be(true)
      expect(described_class.acquire("tenant-2", "job", "tok-b", ttl: 30)).to be(true)
    end

    it "stores the lock under CacheKey.scoped" do
      described_class.acquire("tenant-1", "job", "tok-a", ttl: 30)
      expect(cache.read(FlowchartRuntime::CacheKey.scoped("tenant-1", "lock", "job"))).to eq("tok-a")
    end
  end

  describe ".release" do
    it "deletes the lock when the token matches" do
      described_class.acquire("tenant-1", "job", "tok-a", ttl: 30)
      expect(described_class.release("tenant-1", "job", "tok-a")).to be(true)
      expect(described_class.acquire("tenant-1", "job", "tok-b", ttl: 30)).to be(true)
    end

    it "returns false when the token does not match" do
      described_class.acquire("tenant-1", "job", "tok-a", ttl: 30)
      expect(described_class.release("tenant-1", "job", "wrong")).to be(false)
    end

    it "uses one atomic compare-and-delete operation" do
      described_class.acquire("tenant-1", "job", "tok-a", ttl: 30)
      key = FlowchartRuntime::CacheKey.scoped("tenant-1", "lock", "job")
      expect(cache).to receive(:compare_and_delete).with(key, "tok-a").and_call_original

      expect(described_class.release("tenant-1", "job", "tok-a")).to be(true)
    end

    it "rejects cache stores without atomic compare-and-delete support" do
      allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::NullStore.new)

      expect { described_class.release("tenant-1", "job", "tok-a") }
        .to raise_error(described_class::Error, /atomic compare-and-delete/)
    end

    it "supports the development MemoryStore atomically" do
      memory_cache = ActiveSupport::Cache::MemoryStore.new
      allow(Rails).to receive(:cache).and_return(memory_cache)
      described_class.acquire("tenant-1", "job", "tok-a", ttl: 30)

      expect(described_class.release("tenant-1", "job", "tok-a")).to be(true)
      expect(memory_cache.read(FlowchartRuntime::CacheKey.scoped("tenant-1", "lock", "job"))).to be_nil
    end
  end

  it "rejects ttl above MAX_TTL_SECONDS" do
    expect {
      described_class.acquire("tenant", "k", "t", ttl: FlowchartRuntime::Lock::MAX_TTL_SECONDS + 1)
    }.to raise_error(FlowchartRuntime::Lock::Error, /exceeds maximum/)
  end
end
