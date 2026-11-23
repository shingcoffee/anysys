# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiAssistant::Activities::Preflight do
  # Isolate the shared paid-request primitive from DB/vendor work, so real
  # concurrent hits exercise the same limiter used by both enqueue activities.
  let(:consumer_class) do
    Class.new do
      include AiAssistant::Activities::Preflight
      const_set(:Result, AiAssistant::Activities::Preflight::Result)
      attr_reader :customer, :user

      def initialize(customer:, user:)
        @customer, @user = customer, user
      end

      def rate_scope = "paid-spec"
      def call = rate_limited_failure
    end
  end

  before { Authentication::Throttle.store = ActiveSupport::Cache::MemoryStore.new }
  after { Authentication::Throttle.reset_store! }

  it "allows only the burst budget under simultaneous paid attempts" do
    tenant = Struct.new(:id).new(100)
    actor = Struct.new(:id).new(200)
    ready, start = Queue.new, Queue.new
    count = AiAssistant::Limits::BURST.limit + 5
    now = Time.current.utc.to_i
    allow(Time).to receive(:current).and_return(Time.at(now - now % 3600 + 100).utc)
    consumer = consumer_class
    workers = Array.new(count) do
      Thread.new do
        ready << true
        start.pop
        consumer.new(customer: tenant, user: actor).call
      end
    end
    count.times { ready.pop }
    count.times { start << true }
    results = workers.map(&:value)
    expect(results.count(nil)).to eq(AiAssistant::Limits::BURST.limit)
    expect(results.compact.map(&:http_status)).to all(eq(429))
  ensure
    count&.times { start << true } if start
    workers&.each { |worker| worker.join }
  end

  it "buckets the paid budget by tenant as well as user" do
    actor = Struct.new(:id).new(200)
    first = consumer_class.new(customer: Struct.new(:id).new(100), user: actor)
    AiAssistant::Limits::BURST.limit.times { expect(first.call).to be_nil }
    expect(first.call.http_status).to eq(429)
    second = consumer_class.new(customer: Struct.new(:id).new(101), user: actor)
    expect(second.call).to be_nil
  end
end
