# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartRuntime::RateLimiter do
  let(:ctx) { { customer_id: 42 } }

  before { ::Authentication::Throttle.store = ActiveSupport::Cache::MemoryStore.new }
  after { ::Authentication::Throttle.reset_store! }

  describe ".check" do
    it "admits up to capacity requests inside the window and then denies" do
      expect(described_class.check(ctx, "signup", capacity: 2, window: 60)[:allowed]).to be(true)
      expect(described_class.check(ctx, "signup", capacity: 2, window: 60)[:allowed]).to be(true)
      denied = described_class.check(ctx, "signup", capacity: 2, window: 60)
      expect(denied[:allowed]).to be(false)
      expect(denied[:retry_after]).to be > 0
    end

    it "returns retry_after 0 when the run is admitted" do
      expect(described_class.check(ctx, "signup", capacity: 1, window: 60)[:retry_after]).to eq(0)
    end

    it "admits again once the next window starts" do
      travel_to(Time.zone.at(6_000)) do
        expect(described_class.check(ctx, "signup", capacity: 1, window: 60)[:allowed]).to be(true)
        expect(described_class.check(ctx, "signup", capacity: 1, window: 60)[:allowed]).to be(false)
      end
      travel_to(Time.zone.at(6_060)) do
        expect(described_class.check(ctx, "signup", capacity: 1, window: 60)[:allowed]).to be(true)
      end
    end

    it "does not share buckets across tenants, users, IPs or window lengths" do
      expect(described_class.allow?(ctx, "signup", capacity: 1, window: 60)).to be(true)
      expect(described_class.allow?({ customer_id: 99 }, "signup", capacity: 1, window: 60)).to be(true)
      expect(described_class.allow?(ctx, "signup", capacity: 1, window: 3600)).to be(true)
      expect(described_class.allow?(
        { customer_id: 42, current_user_id: 1 }, "signup", capacity: 1, window: 60, scope: "user"
      )).to be(true)
      expect(described_class.allow?(
        { customer_id: 42, current_user_id: 2 }, "signup", capacity: 1, window: 60, scope: "user"
      )).to be(true)
      expect(described_class.allow?(
        { customer_id: 42, request_ip: "1.1.1.1" }, "signup", capacity: 1, window: 60, scope: "ip"
      )).to be(true)
    end

    it "weights a run by cost in one increment" do
      store = ::Authentication::Throttle.store
      allow(store).to receive(:increment).and_call_original
      expect(described_class.allow?(ctx, "weighted", capacity: 3, window: 60, cost: 3)).to be(true)
      expect(store).to have_received(:increment).with(anything, 3, anything).at_least(:once)
      expect(described_class.allow?(ctx, "weighted", capacity: 3, window: 60, cost: 1)).to be(false)
    end

    it "never sleeps" do
      expect(described_class).not_to receive(:sleep)
      expect(Kernel).not_to receive(:sleep)

      described_class.check(ctx, "signup", capacity: 1, window: 60)
      described_class.check(ctx, "signup", capacity: 1, window: 60)
    end

    it "rejects a blank name" do
      expect { described_class.check(ctx, " ", capacity: 1, window: 60) }
        .to raise_error(described_class::Error, /name/)
    end

    it "rejects a non-positive capacity, window or cost" do
      expect { described_class.check(ctx, "signup", capacity: 0, window: 60) }
        .to raise_error(described_class::Error, /capacity/)
      expect { described_class.check(ctx, "signup", capacity: 1, window: "x") }
        .to raise_error(described_class::Error, /window/)
      expect { described_class.check(ctx, "signup", capacity: 1, window: 60, cost: 0) }
        .to raise_error(described_class::Error, /cost/)
    end
  end

  describe ".allow?" do
    it "returns the allowed flag from check" do
      expect(described_class.allow?(ctx, "signup", capacity: 1, window: 60)).to be(true)
      expect(described_class.allow?(ctx, "signup", capacity: 1, window: 60)).to be(false)
    end
  end
end
