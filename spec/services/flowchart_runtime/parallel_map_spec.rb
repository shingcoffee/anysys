# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartRuntime::ParallelMap do
  describe ".map" do
    it "maps a collection in parallel" do
      result = described_class.map([1, 2, 3], in_threads: 2) { |n| n * 2 }
      expect(result).to eq([2, 4, 6])
    end

    it "does not swallow an unexpected block failure" do
      expect do
        described_class.map([1], in_threads: 1) { raise "boom" }
      end.to raise_error(RuntimeError, "boom")
    end

    it "wraps parallel worker failures" do
      allow(Parallel).to receive(:map).and_raise(Parallel::DeadWorker, "worker died")

      expect { described_class.map([1], in_threads: 1) { |value| value } }
        .to raise_error(FlowchartRuntime::ParallelMap::Error, "worker died")
    end
  end

  describe ".each" do
    it "iterates a collection in parallel" do
      seen = []
      described_class.each([1, 2], in_threads: 2) { |n| seen << n }
      expect(seen.sort).to eq([1, 2])
    end
  end

  it "rejects in_threads above MAX_THREADS" do
    expect {
      described_class.map([1, 2], in_threads: FlowchartRuntime::ParallelMap::MAX_THREADS + 1) { |x| x }
    }.to raise_error(FlowchartRuntime::ParallelMap::Error, /exceeds maximum/)
  end
end
