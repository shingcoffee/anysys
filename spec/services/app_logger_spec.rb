# frozen_string_literal: true

require "rails_helper"

RSpec.describe AppLogger do
  let(:logger) { ActiveSupport::TaggedLogging.new(ActiveSupport::Logger.new(StringIO.new)) }

  before do
    allow(Rails).to receive(:logger).and_return(logger)
  end

  describe ".info" do
    it "logs at info level" do
      expect(logger).to receive(:info).with("hello").and_call_original
      described_class.info("hello", source: "Test")
    end
  end

  describe ".warn" do
    it "logs at warn level" do
      expect(logger).to receive(:warn).with("warning").and_call_original
      described_class.warn("warning", source: "Test")
    end
  end

  describe ".error" do
    it "logs at error level" do
      expect(logger).to receive(:error).with("bad").and_call_original
      described_class.error("bad", source: "Test")
    end
  end

  describe ".debug" do
    it "logs at debug level" do
      expect(logger).to receive(:debug).with("trace").and_call_original
      described_class.debug("trace", source: "Test")
    end
  end

  describe "tagging" do
    let(:output) { StringIO.new }
    let(:logger) { ActiveSupport::TaggedLogging.new(ActiveSupport::Logger.new(output)) }

    it "tags with source when provided" do
      described_class.info("msg", source: "MyService")
      expect(output.string).to include("[MyService]")
    end

    it "tags with customer ID when Current.customer is set" do
      customer = create(:customer)
      Current.customer = customer

      described_class.info("msg", source: "MyService")
      expect(output.string).to include("[customer:#{customer.id}]")
      expect(output.string).to include("[MyService]")
    end

    it "omits customer tag when no current customer" do
      Current.customer = nil
      described_class.info("msg", source: "MyService")
      expect(output.string).not_to include("[customer:")
    end

    it "works with no source and no customer" do
      Current.customer = nil
      described_class.info("bare message")
      expect(output.string).to include("bare message")
      expect(output.string).not_to include("[]")
    end
  end
end
