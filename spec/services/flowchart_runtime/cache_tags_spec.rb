# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartRuntime::CacheTags do
  let(:store) { ActiveSupport::Cache::MemoryStore.new }

  before { allow(Rails).to receive(:cache).and_return(store) }

  def scoped(tenant, key)
    FlowchartRuntime::CacheKey.scoped(tenant, key)
  end

  it "invalidates every key tagged under a tenant" do
    a = scoped("42", "user:1")
    b = scoped("42", "user:2")
    store.write(a, 1)
    store.write(b, 2)
    described_class.tag("42", a, ["people"])
    described_class.tag("42", b, ["people"])

    expect(described_class.invalidate("42", "people")).to eq(2)
    expect(store.read(a)).to be_nil
    expect(store.read(b)).to be_nil
  end

  it "does not touch another tenant's identically tagged keys" do
    mine = scoped("42", "user:1")
    theirs = scoped("99", "user:1")
    store.write(mine, 1)
    store.write(theirs, 2)
    described_class.tag("42", mine, ["people"])
    described_class.tag("99", theirs, ["people"])

    described_class.invalidate("42", "people")

    expect(store.read(theirs)).to eq(2)
  end

  # The previous read-modify-write index lost entries when writers interleaved.
  # Marker keys are disjoint, so no interleaving can drop a member.
  it "keeps every member when writers interleave" do
    keys = 25.times.map { |i| scoped("42", "user:#{i}") }
    keys.each { |key| store.write(key, key) }

    keys.map { |key| Thread.new { described_class.tag("42", key, ["people"]) } }.each(&:join)

    expect(described_class.invalidate("42", "people")).to eq(25)
    expect(keys.map { |key| store.read(key) }.compact).to be_empty
  end

  it "supports key_value_list rows and ignores blank tags" do
    key = scoped("42", "user:1")
    store.write(key, 1)

    expect(described_class.tag("42", key, [{ "key" => "people" }, { "key" => "  " }], expires_in: 60)).to eq(1)
    expect(described_class.invalidate("42", "people")).to eq(1)
  end

  it "returns zero when there are no tags" do
    expect(described_class.tag("42", scoped("42", "k"), [])).to eq(0)
  end

  it "refuses a blank tag on invalidate" do
    expect { described_class.invalidate("42", " ") }.to raise_error(described_class::Error, /tag is required/)
  end

  it "refuses a blank cache key" do
    expect { described_class.tag("42", "", ["people"]) }.to raise_error(described_class::Error, /cache key/)
  end

  it "strips glob metacharacters so a tag cannot widen the invalidation" do
    expect { described_class.invalidate("42", "*") }
      .to raise_error(described_class::Error, /tag is required/)
  end
end
