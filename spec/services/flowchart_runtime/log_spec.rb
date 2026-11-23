# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartRuntime::Log do
  describe ".write" do
    it "writes through Rails.logger" do
      logger = instance_double(ActiveSupport::Logger)
      allow(Rails).to receive(:logger).and_return(logger)
      expect(logger).to receive(:info).with("hello")
      expect(described_class.write({ customer_id: 1 }, level: "info", logger: "rails",
                                 message: "hello")).to be(true)
    end

    it "writes to stdout" do
      expect { described_class.write({}, level: "info", logger: "stdout", message: "hi") }
        .to output("hi\n").to_stdout
    end

    it "writes a tenant-scoped file" do
      ctx = { customer_id: "81721200" }
      described_class.write(ctx, level: "info", logger: "file", message: "ln", file_path: "custom.log")
      path = FlowchartRuntime::LogFile.path_for("81721200", "custom.log")
      expect(File.read(path)).to include("ln")
    ensure
      FileUtils.rm_rf(Rails.root.join(FlowchartRuntime::LogFile::ROOT))
    end

    it "raises Error without a tenant on the file logger" do
      expect {
        described_class.write({}, level: "info", logger: "file", message: "ln", file_path: "a.log")
      }.to raise_error(described_class::Error, /tenant is required/)
    end

    it "redacts sensitive tag keys in structured output" do
      logger = instance_double(ActiveSupport::Logger)
      allow(Rails).to receive(:logger).and_return(logger)
      expect(logger).to receive(:info) do |payload|
        parsed = JSON.parse(payload)
        expect(parsed["tags"]["password"]).to eq("[FILTERED]")
        expect(parsed["message"]).to eq("hello")
      end
      described_class.write({ customer_id: 1 }, level: "info", logger: "rails",
                            message: "hello", tags: { "password" => "hunter2" }, structured: true)
    end
  end
end
