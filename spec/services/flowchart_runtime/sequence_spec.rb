# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartRuntime::Sequence do
  let(:customer) { create(:customer) }
  let(:other) { create(:customer) }
  let(:ctx) { { customer_id: customer.id } }

  it "allocates a padded number with prefix and starts at 1" do
    expect(described_class.next(ctx, name: "order", period: "never", prefix: "INV-", padding: 6))
      .to eq("INV-000001")
    expect(described_class.next(ctx, name: "order", period: "never", prefix: "INV-", padding: 6))
      .to eq("INV-000002")
  end

  it "keeps the same name independent across tenants" do
    expect(described_class.next(ctx, name: "order", period: "never", prefix: "", padding: 3)).to eq("001")
    expect(described_class.next({ customer_id: other.id }, name: "order", period: "never", prefix: "", padding: 3))
      .to eq("001")
  end

  it "uses a year or month period bucket" do
    travel_to Time.zone.local(2026, 10, 19, 12) do
      expect(described_class.next(ctx, name: "order", period: "year", prefix: "", padding: 2)).to eq("01")
      expect(FlowchartSequence.find_by!(customer_id: customer.id, name: "order", period: "2026").last_value).to eq(1)
      expect(described_class.next(ctx, name: "order", period: "month", prefix: "", padding: 2)).to eq("01")
      expect(FlowchartSequence.find_by!(customer_id: customer.id, name: "order", period: "2026-10").last_value).to eq(1)
    end
  end

  it "uses day, week and quarter period buckets" do
    travel_to Time.zone.local(2026, 11, 16, 12) do
      expect(described_class.next(ctx, name: "daily", period: "day", prefix: "", padding: 2)).to eq("01")
      expect(FlowchartSequence.find_by!(customer_id: customer.id, name: "daily", period: "2026-11-16").last_value).to eq(1)
      expect(described_class.next(ctx, name: "weekly", period: "week", prefix: "", padding: 2)).to eq("01")
      expect(FlowchartSequence.find_by!(customer_id: customer.id, name: "weekly", period: "2026-W47").last_value).to eq(1)
      expect(described_class.next(ctx, name: "quarterly", period: "quarter", prefix: "", padding: 2)).to eq("01")
      expect(FlowchartSequence.find_by!(customer_id: customer.id, name: "quarterly", period: "2026-Q4").last_value).to eq(1)
    end
  end

  it "formats start_at, step, suffix and a year date segment" do
    travel_to Time.zone.local(2026, 3, 1, 12) do
      expect(described_class.next(ctx, name: "invoice", period: "never", prefix: "INV-", padding: 6,
                                       suffix: "-CN", start_at: 100, step: 5, date_segment: "year"))
        .to eq("INV-2026-000100-CN")
      expect(described_class.next(ctx, name: "invoice", period: "never", prefix: "INV-", padding: 6,
                                       suffix: "-CN", start_at: 100, step: 5, date_segment: "year"))
        .to eq("INV-2026-000105-CN")
    end
  end

  it "rolls the number back with the surrounding transaction" do
    described_class.next(ctx, name: "order", period: "never", prefix: "", padding: 1)
    FlowchartSequence.transaction do
      expect(described_class.next(ctx, name: "order", period: "never", prefix: "", padding: 1)).to eq("2")
      raise ActiveRecord::Rollback
    end
    expect(described_class.next(ctx, name: "order", period: "never", prefix: "", padding: 1)).to eq("2")
  end

  it "raises when customer_id is missing" do
    expect { described_class.next({}, name: "order", period: "never") }
      .to raise_error(FlowchartRuntime::Sequence::Error, /customer_id/)
  end

  describe "20 concurrent increments" do
    self.use_transactional_tests = false

    it "returns 20 distinct consecutive values" do
      raise "Committed fixtures required" if ApplicationRecord.connection.transaction_open?

      customer = create(:customer)
      ctx = { customer_id: customer.id }
      values = Queue.new
      threads = 20.times.map do
        Thread.new do
          ApplicationRecord.connection_pool.with_connection do
            values << described_class.next(ctx, name: "order", period: "never", prefix: "", padding: 6)
          ensure
            Current.reset
          end
        end.tap { |thread| thread.report_on_exception = false }
      end
      threads.each do |thread|
        raise "increment thread timed out" unless thread.join(30)
      end
      allocated = 20.times.map { values.pop }
      numbers = allocated.map(&:to_i).sort
      expect(allocated.uniq.size).to eq(20)
      expect(numbers).to eq((1..20).to_a)
    ensure
      FlowchartSequence.where(customer_id: customer&.id).delete_all
      customer&.destroy!
    end
  end
end
