# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartRuntime::CircuitBreaker do
  let(:tenant) { "81721200" }
  let(:name)   { "payment_api" }
  let(:cache)  { ActiveSupport::Cache::MemoryStore.new }

  before do
    allow(Rails).to receive(:cache).and_return(cache)
    described_class.reset(tenant, name)
  end

  def evaluate(outcome, **opts)
    described_class.evaluate(tenant, name, outcome: outcome, **opts)
  end

  describe ".cache_key" do
    it "namespaces breaker state per tenant" do
      expect(described_class.cache_key(tenant, name))
        .to eq("flowchart:81721200:breaker:payment_api")
    end

    it "never shares state between two tenants" do
      expect(described_class.cache_key("1", name)).not_to eq(described_class.cache_key("2", name))
    end

    it "rejects a blank breaker name" do
      expect { described_class.cache_key(tenant, "  ") }.to raise_error(described_class::Error, /name/)
    end

    it "rejects a blank tenant" do
      expect { described_class.cache_key("", name) }.to raise_error(described_class::Error, /tenant/)
    end
  end

  describe ".evaluate" do
    it "allows traffic while closed" do
      expect(evaluate("none")).to include(state: "closed", allowed: true)
    end

    it "stays closed below the failure threshold" do
      evaluate("failure", failure_threshold: 3)
      expect(evaluate("failure", failure_threshold: 3)).to include(state: "closed", allowed: true)
    end

    it "opens once the failure threshold is reached inside the window" do
      3.times { evaluate("failure", failure_threshold: 3) }
      result = evaluate("none", failure_threshold: 3)
      expect(result[:state]).to eq("open")
      expect(result[:allowed]).to be(false)
      expect(result[:retry_after]).to be > 0
    end

    it "honors a higher failure threshold" do
      3.times { evaluate("failure", failure_threshold: 10) }
      expect(evaluate("none", failure_threshold: 10)).to include(state: "closed", allowed: true)
    end

    it "forgets failures that fall outside the rolling window" do
      2.times { evaluate("failure", failure_threshold: 3, window_size: 60) }
      travel_to(Time.current + 120.seconds) do
        expect(evaluate("failure", failure_threshold: 3, window_size: 60))
          .to include(state: "closed", allowed: true)
      end
    end

    it "moves to half_open after the reset timeout and admits a trial request" do
      2.times { evaluate("failure", failure_threshold: 2, reset_timeout: 30) }
      travel_to(Time.current + 31.seconds) do
        expect(evaluate("none", failure_threshold: 2, reset_timeout: 30))
          .to include(state: "half_open", allowed: true)
      end
    end

    it "admits at most half_open_trials trial requests" do
      2.times { evaluate("failure", failure_threshold: 2, reset_timeout: 30) }
      travel_to(Time.current + 31.seconds) do
        opts = { failure_threshold: 2, reset_timeout: 30, half_open_trials: 2 }
        expect(evaluate("none", **opts)[:allowed]).to be(true)
        expect(evaluate("none", **opts)[:allowed]).to be(true)
        expect(evaluate("none", **opts)[:allowed]).to be(false)
      end
    end

    it "closes after success_threshold successes in half_open" do
      2.times { evaluate("failure", failure_threshold: 2, reset_timeout: 30) }
      travel_to(Time.current + 31.seconds) do
        opts = { failure_threshold: 2, reset_timeout: 30, half_open_trials: 5, success_threshold: 2 }
        evaluate("none", **opts)
        evaluate("success", **opts)
        expect(evaluate("success", **opts)).to include(state: "closed", allowed: true)
      end
    end

    it "re-opens immediately on a failure while half_open" do
      2.times { evaluate("failure", failure_threshold: 2, reset_timeout: 30) }
      travel_to(Time.current + 31.seconds) do
        opts = { failure_threshold: 2, reset_timeout: 30 }
        evaluate("none", **opts)
        expect(evaluate("failure", **opts)).to include(state: "open", allowed: false)
      end
    end

    it "extends the wait when jitter is enabled" do
      allow(described_class).to receive(:rand).and_return(1.0)
      expect(described_class.effective_timeout(60, true)).to be > 60
      expect(described_class.effective_timeout(60, false)).to eq(60.0)
    end

    it "rejects an unknown outcome" do
      expect { evaluate("maybe") }.to raise_error(described_class::Error, /unsupported outcome/)
    end

    it "rejects a non-positive threshold" do
      expect { evaluate("none", failure_threshold: 0) }
        .to raise_error(described_class::Error, /failure_threshold/)
    end

    it "rejects a window beyond the maximum" do
      expect { evaluate("none", window_size: described_class::MAX_WINDOW_SECONDS + 1) }
        .to raise_error(described_class::Error, /maximum/)
    end

    it "rejects a reset timeout beyond the maximum" do
      expect { evaluate("none", reset_timeout: described_class::MAX_TIMEOUT_SECONDS + 1) }
        .to raise_error(described_class::Error, /maximum/)
    end

    it "rejects trial counts beyond the maximum" do
      expect { evaluate("none", half_open_trials: described_class::MAX_TRIALS + 1) }
        .to raise_error(described_class::Error, /maximum/)
    end

    it "ignores corrupt cached state instead of trusting it" do
      Rails.cache.write(described_class.cache_key(tenant, name), "not-a-hash")
      expect(evaluate("none")).to include(state: "closed", allowed: true)
    end

    it "falls back to closed for an unrecognized stored state" do
      Rails.cache.write(described_class.cache_key(tenant, name), { state: "molten", failures: [] })
      expect(evaluate("none")).to include(state: "closed", allowed: true)
    end
  end

  describe ".reset" do
    it "clears recorded failures" do
      3.times { evaluate("failure", failure_threshold: 3) }
      described_class.reset(tenant, name)
      expect(evaluate("none", failure_threshold: 3)).to include(state: "closed", allowed: true)
    end
  end
end
