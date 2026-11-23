# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartRuntime::Backoff do
  describe ".delay_for" do
    it "returns the base delay for the fixed strategy on every attempt" do
      expect(described_class.delay_for(1, strategy: "fixed", initial_delay: 2)).to eq(2.0)
      expect(described_class.delay_for(4, strategy: "fixed", initial_delay: 2)).to eq(2.0)
    end

    it "scales linearly with the attempt number" do
      expect(described_class.delay_for(3, strategy: "linear", initial_delay: 2)).to eq(6.0)
    end

    it "doubles on each attempt for the exponential strategy" do
      expect(described_class.delay_for(1, strategy: "exponential", initial_delay: 1)).to eq(1.0)
      expect(described_class.delay_for(4, strategy: "exponential", initial_delay: 1)).to eq(8.0)
    end

    it "keeps decorrelated jitter between the base delay and three times the previous delay" do
      delay = described_class.delay_for(2, strategy: "decorrelated_jitter", initial_delay: 1, previous_delay: 4)
      expect(delay).to be >= 1.0
      expect(delay).to be <= 12.0
    end

    it "clamps an explosive exponential delay to the caller ceiling" do
      expect(described_class.delay_for(20, strategy: "exponential", initial_delay: 1, max_delay: 30)).to eq(30.0)
    end

    it "never exceeds the module maximum even when the ceiling does" do
      expect(described_class.delay_for(20, strategy: "exponential", initial_delay: 10, max_delay: 60))
        .to eq(described_class::MAX_DELAY_SECONDS.to_f)
    end

    it "adds at most jitter_percent of the delay" do
      delays = Array.new(30) do
        described_class.delay_for(1, strategy: "fixed", initial_delay: 10, jitter_percent: 50)
      end
      expect(delays.min).to be >= 10.0
      expect(delays.max).to be <= 15.0
    end

    it "returns the unjittered delay when jitter_percent is zero" do
      expect(described_class.delay_for(2, strategy: "linear", initial_delay: 3, jitter_percent: 0)).to eq(6.0)
    end

    it "rejects a non-positive attempt" do
      expect { described_class.delay_for(0, strategy: "fixed", initial_delay: 1) }
        .to raise_error(described_class::Error, /attempt/)
    end

    it "rejects an attempt beyond the maximum" do
      expect { described_class.delay_for(51, strategy: "fixed", initial_delay: 1) }
        .to raise_error(described_class::Error, /maximum/)
    end

    it "rejects an unknown strategy" do
      expect { described_class.delay_for(1, strategy: "warp", initial_delay: 1) }
        .to raise_error(described_class::Error, /unsupported backoff strategy/)
    end

    it "rejects a negative initial delay" do
      expect { described_class.delay_for(1, strategy: "fixed", initial_delay: -1) }
        .to raise_error(described_class::Error, /initial_delay/)
    end

    it "rejects an initial delay beyond the maximum" do
      expect { described_class.delay_for(1, strategy: "fixed", initial_delay: 601) }
        .to raise_error(described_class::Error, /maximum/)
    end

    it "rejects an out-of-range jitter percentage" do
      expect { described_class.delay_for(1, strategy: "fixed", initial_delay: 1, jitter_percent: 101) }
        .to raise_error(described_class::Error, /jitter_percent/)
      expect { described_class.delay_for(1, strategy: "fixed", initial_delay: 1, jitter_percent: "x") }
        .to raise_error(described_class::Error, /jitter_percent/)
    end

    it "rejects a negative previous delay" do
      expect { described_class.delay_for(2, strategy: "decorrelated_jitter", initial_delay: 1, previous_delay: -5) }
        .to raise_error(described_class::Error, /previous_delay/)
    end
  end

  describe ".total_delay" do
    it "sums the per-attempt delays of a policy" do
      expect(described_class.total_delay(3, strategy: "linear", initial_delay: 1)).to eq(6.0)
    end

    it "stays bounded for a pathological policy" do
      total = described_class.total_delay(described_class::MAX_ATTEMPTS, strategy: "exponential", initial_delay: 60)
      expect(total).to eq(described_class::MAX_ATTEMPTS * described_class::MAX_DELAY_SECONDS.to_f)
    end
  end
end
