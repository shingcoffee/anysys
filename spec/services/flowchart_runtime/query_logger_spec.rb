# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartRuntime::QueryLogger do
  describe ".capture" do
    it "returns block result and captured queries" do
      customer = create(:customer)

      result, queries = described_class.capture do
        Customer.find(customer.id)
      end

      expect(result).to eq(customer)
      expect(queries).to be_an(Array)
      expect(queries.size).to be >= 1
      expect(queries.first).to have_key(:sql)
      expect(queries.first).to have_key(:duration_ms)
      expect(queries.first).to have_key(:name)
    end

    it "excludes SCHEMA queries" do
      _result, queries = described_class.capture do
        Customer.count
      end

      schema_queries = queries.select { |q| q[:name] == "SCHEMA" }
      expect(schema_queries).to be_empty
    end

    it "excludes SQL emitted by other threads during capture" do
      other_thread = nil

      _result, queries = described_class.capture do
        Customer.count
        # A concurrent request on another thread (e.g. another tenant) emits
        # sql.active_record on that thread; it must not leak into this capture.
        other_thread = Thread.new do
          ActiveSupport::Notifications.instrument(
            "sql.active_record",
            sql: "SELECT 'leaked-from-other-thread'",
            name: "Other Tenant Load",
            duration: 1.0
          )
        end
        other_thread.join
      end

      expect(queries).not_to be_empty
      expect(queries.map { |q| q[:sql] }).not_to include("SELECT 'leaked-from-other-thread'")
      expect(queries.map { |q| q[:name] }).not_to include("Other Tenant Load")
    end

    it "cleans up subscriber after block completes" do
      initial_count = ActiveSupport::Notifications.notifier.listeners_for("sql.active_record").size

      described_class.capture { Customer.count }

      final_count = ActiveSupport::Notifications.notifier.listeners_for("sql.active_record").size
      expect(final_count).to eq(initial_count)
    end

    it "cleans up subscriber even when block raises" do
      initial_count = ActiveSupport::Notifications.notifier.listeners_for("sql.active_record").size

      expect {
        described_class.capture { raise "boom" }
      }.to raise_error("boom")

      final_count = ActiveSupport::Notifications.notifier.listeners_for("sql.active_record").size
      expect(final_count).to eq(initial_count)
    end
  end
end
