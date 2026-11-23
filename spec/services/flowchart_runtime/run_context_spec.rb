# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartRuntime::RunContext do
  after { described_class.reset }

  describe ".remaining" do
    it "returns the full execution cap when no deadline is set" do
      expect(described_class.remaining).to eq(ActivityTracer::EXECUTION_TIMEOUT_SECONDS)
      expect(described_class.deadline).to be_nil
    end
  end

  describe ".with_deadline" do
    it "exposes a shrinking remaining budget and restores the previous deadline" do
      described_class.with_deadline(2) do
        expect(described_class.deadline).to be_a(Float)
        expect(described_class.remaining).to be > 0
        expect(described_class.remaining).to be <= 2

        described_class.with_deadline(0.2) do
          expect(described_class.remaining).to be <= 0.2
        end

        expect(described_class.remaining).to be > 0.2
      end

      expect(described_class.deadline).to be_nil
      expect(described_class.remaining).to eq(ActivityTracer::EXECUTION_TIMEOUT_SECONDS)
    end

    it "is isolated across threads" do
      inner = Queue.new
      thread = Thread.new do
        described_class.with_deadline(1) { inner << described_class.remaining }
      end
      thread.join

      expect(described_class.deadline).to be_nil
      expect(inner.pop).to be <= 1
    end

    it "rejects a non-positive budget" do
      expect { described_class.with_deadline(0) { } }
        .to raise_error(described_class::Error, /deadline/)
    end
  end
end
