# frozen_string_literal: true

require "rails_helper"

RSpec.describe Authentication::Throttle do
  before { described_class.reset_store! }
  after  { described_class.reset_store! }

  let(:throttle) { described_class.new(key: "test:1", limit: 3, period: 15.minutes) }

  describe "#count" do
    it "is zero for a key with no recorded failures" do
      expect(throttle.count).to eq(0)
    end
  end

  describe "#record_failure" do
    it "increments the failure count" do
      expect { throttle.record_failure }.to change { throttle.count }.from(0).to(1)
    end

    it "accumulates across repeated calls" do
      3.times { throttle.record_failure }
      expect(throttle.count).to eq(3)
    end
  end

  describe "#exceeded?" do
    it "is false while under the limit" do
      2.times { throttle.record_failure }
      expect(throttle.exceeded?).to be false
    end

    it "is true once the count reaches the limit" do
      3.times { throttle.record_failure }
      expect(throttle.exceeded?).to be true
    end

    it "is true when the count is beyond the limit" do
      4.times { throttle.record_failure }
      expect(throttle.exceeded?).to be true
    end
  end

  # #hit! is for the count-every-attempt callers (sign-in, password reset,
  # email flood). It increments and compares in one step, because the
  # #exceeded?-then-#record_failure pair those callers used to run is not safe
  # under concurrency: N simultaneous requests all read the same under-limit
  # count and all pass, so the effective cap scaled with the attacker's
  # concurrency rather than holding at `limit`.
  describe "#hit!" do
    it "counts the attempt it is reporting on" do
      expect { throttle.hit! }.to change { throttle.count }.from(0).to(1)
    end

    it "allows exactly `limit` attempts through" do
      expect(Array.new(3) { throttle.hit! }).to all(be false)
    end

    it "reports a breach on the attempt after the limit" do
      3.times { throttle.hit! }
      expect(throttle.hit!).to be true
    end

    it "keeps reporting a breach for every subsequent attempt" do
      5.times { throttle.hit! }
      expect(throttle.hit!).to be true
    end

    it "does not share counts across keys" do
      other = described_class.new(key: "test:hit-other", limit: 3, period: 15.minutes)
      4.times { throttle.hit! }
      expect(other.hit!).to be false
    end

    it "lets attempts through again once the period elapses" do
      4.times { throttle.hit! }
      travel_to(20.minutes.from_now) do
        expect(throttle.hit!).to be false
      end
    end

    # The store's `increment` returns nil for a key that does not exist yet, so
    # the first attempt in a window has to seed the counter. Seeding must not
    # clobber a count another worker established in the same instant.
    it "does not lose a concurrent worker's count while seeding" do
      other = described_class.new(key: "test:1", limit: 3, period: 15.minutes)
      throttle.hit!
      other.hit!
      expect(throttle.count).to eq(2)
    end
  end

  describe ".mfa" do
    # Every second-factor surface — verify, enrol, disable, and the member
    # equivalents — shares one bucket per user, so attempts cannot be spread
    # across endpoints to multiply the brute-force budget.
    it "keys the bucket per user" do
      user  = create(:user)
      other = create(:user)

      described_class::MFA_LIMIT.times { described_class.mfa(user).record_failure }

      expect(described_class.mfa(user).exceeded?).to be true
      expect(described_class.mfa(other).exceeded?).to be false
    end

    it "returns an equivalent bucket for repeated calls with the same user" do
      user = create(:user)
      described_class.mfa(user).record_failure
      expect(described_class.mfa(user).count).to eq(1)
    end
  end

  describe "#clear" do
    it "resets the count back to zero" do
      3.times { throttle.record_failure }
      throttle.clear
      expect(throttle.count).to eq(0)
      expect(throttle.exceeded?).to be false
    end
  end

  describe "key isolation" do
    it "does not share counts across different keys" do
      other = described_class.new(key: "test:2", limit: 3, period: 15.minutes)
      3.times { throttle.record_failure }
      expect(other.count).to eq(0)
      expect(other.exceeded?).to be false
    end
  end

  describe "expiry" do
    it "resets the count after the period elapses" do
      throttle.record_failure
      travel_to(20.minutes.from_now) do
        expect(throttle.count).to eq(0)
      end
    end
  end

  describe ".store" do
    it "falls back to a MemoryStore because Rails.cache is a NullStore in test" do
      expect(Rails.cache).to be_a(ActiveSupport::Cache::NullStore)
      expect(described_class.store).to be_a(ActiveSupport::Cache::MemoryStore)
    end

    it "memoizes the fallback store across instances until reset_store!" do
      store1 = described_class.store
      store2 = described_class.store
      expect(store1).to equal(store2)
    end

    it "is overridable for specs" do
      custom = ActiveSupport::Cache::MemoryStore.new
      described_class.store = custom
      expect(described_class.store).to equal(custom)
    end
  end
end
