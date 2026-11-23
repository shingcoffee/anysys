# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartRuntime::CacheScope do
  let(:store) { ActiveSupport::Cache::MemoryStore.new }

  before { allow(Rails).to receive(:cache).and_return(store) }

  def write(tenant, key)
    store.write(FlowchartRuntime::CacheKey.scoped(tenant, key), key)
  end

  describe ".tenant_prefix" do
    it "namespaces by tenant" do
      expect(described_class.tenant_prefix("42")).to eq("flowchart:42:")
    end

    it "refuses a blank tenant" do
      expect { described_class.tenant_prefix(" ") }.to raise_error(described_class::Error, /tenant/)
    end
  end

  describe ".matching_keys" do
    it "returns only this tenant's keys matching the glob" do
      write("42", "user:1")
      write("42", "user:2")
      write("42", "order:1")
      write("99", "user:1")

      expect(described_class.matching_keys("42", "user:*"))
        .to contain_exactly("flowchart:42:user:1", "flowchart:42:user:2")
    end
  end

  describe ".delete_matched" do
    it "does not treat tenant 42 as a prefix of tenant 420" do
      write("42", "user:1")
      write("420", "user:1")

      expect(described_class.delete_matched("42", "*")).to eq(1)
      expect(store.read("flowchart:420:user:1")).to eq("user:1")
    end

    it "deletes matching keys and leaves other tenants untouched" do
      write("42", "user:1")
      write("99", "user:1")

      expect(described_class.delete_matched("42", "user:*")).to eq(1)
      expect(store.read("flowchart:42:user:1")).to be_nil
      expect(store.read("flowchart:99:user:1")).to eq("user:1")
    end

    it "refuses a confirmed delete at or above the limit" do
      3.times { |i| write("42", "user:#{i}") }

      expect { described_class.delete_matched("42", "user:*", max_keys: 3) }
        .to raise_error(described_class::Error, /at or above the confirmed limit/)
      expect(store.read("flowchart:42:user:0")).to eq("user:0")
    end

    it "performs a confirmed delete below the limit" do
      3.times { |i| write("42", "user:#{i}") }

      expect(described_class.delete_matched("42", "user:*", max_keys: 10)).to eq(3)
    end

    it "raises when the store cannot count keys and confirmation was requested" do
      allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::FileStore.new(Rails.root.join("tmp/cache_scope_spec")))

      expect { described_class.delete_matched("42", "user:*", max_keys: 10) }
        .to raise_error(described_class::Error, /confirmation is unavailable/)
    end
  end

  describe ".clear" do
    it "clears only the calling tenant's entries" do
      write("42", "a")
      write("42", "b")
      write("99", "a")

      expect(described_class.clear("42")).to eq(2)
      expect(store.read("flowchart:99:a")).to eq("a")
    end
  end

  describe "null store" do
    it "enumerates nothing rather than raising" do
      allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::NullStore.new)

      expect(described_class.matching_keys("42", "*")).to eq([])
      expect(described_class.clear("42")).to eq(0)
    end
  end
end
