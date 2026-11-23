# frozen_string_literal: true

require "rails_helper"

RSpec.describe Loggable do
  let(:test_class) do
    Class.new do
      include Loggable

      def self.name
        "SomeModule::TestService"
      end

      def do_logging
        log_info "info message"
        log_warn "warn message"
        log_error "error message"
        log_debug "debug message"
      end
    end
  end

  let(:instance) { test_class.new }

  describe "log methods" do
    it "delegates log_info to AppLogger with auto-derived source" do
      expect(AppLogger).to receive(:info).with("info message", source: "TestService")
      instance.send(:log_info, "info message")
    end

    it "delegates log_warn to AppLogger" do
      expect(AppLogger).to receive(:warn).with("warn message", source: "TestService")
      instance.send(:log_warn, "warn message")
    end

    it "delegates log_error to AppLogger" do
      expect(AppLogger).to receive(:error).with("error message", source: "TestService")
      instance.send(:log_error, "error message")
    end

    it "delegates log_debug to AppLogger" do
      expect(AppLogger).to receive(:debug).with("debug message", source: "TestService")
      instance.send(:log_debug, "debug message")
    end
  end

  describe "#log_source" do
    it "demodulizes the class name" do
      expect(instance.send(:log_source)).to eq("TestService")
    end
  end
end
