# frozen_string_literal: true

require "rails_helper"

RSpec.describe "communication semantic conformance" do
  def body(klass, config)
    result = CodeGenerators::TestRunner.run(klass, config: config)
    expect(result[:validation_errors]).to be_empty
    result[:body]
  end

  def errors(klass, config)
    CodeGenerators::TestRunner.run(klass, config: config)[:validation_errors]
  end

  describe CodeGenerators::ElementTypes::Process::Communication::ApiCallGenerator do
    it "honors bodyFormat" do
      sample = described_class.sample_input.merge("httpMethod" => "POST", "bodyTemplate" => "{ a: 1 }")
      expect(body(described_class, sample.merge("bodyFormat" => "json")))
        .not_to eq(body(described_class, sample.merge("bodyFormat" => "form")))
    end

    it "honors followRedirects" do
      sample = described_class.sample_input
      expect(body(described_class, sample.merge("followRedirects" => true)))
        .not_to eq(body(described_class, sample.merge("followRedirects" => false)))
    end

    it "honors failOnHttpError, statusVar and headersVar" do
      sample = described_class.sample_input
      expect(body(described_class, sample.merge("failOnHttpError" => true)))
        .not_to eq(body(described_class, sample.merge("failOnHttpError" => false)))
      expect(body(described_class, sample.merge("statusVar" => "http_status")))
        .not_to eq(body(described_class, sample.merge("statusVar" => "status_code")))
      expect(body(described_class, sample.merge("headersVar" => "http_headers")))
        .not_to eq(body(described_class, sample.merge("headersVar" => "response_headers")))
    end

    it "does not emit sleep or status-code retry" do
      src = body(described_class, described_class.sample_input)
      expect(src).not_to include("sleep")
      expect(src).not_to include("ctx[:_last_error]")
      expect(src).to include("FlowchartRuntime::Http.request")
    end

    it "rejects retry on a non-idempotent POST" do
      msgs = errors(described_class, described_class.sample_input.merge(
        "httpMethod" => "POST", "retryOnTransportError" => true
      ))
      expect(msgs.map { |error| error.respond_to?(:code) ? error.code : error }).to include(:retry_not_idempotent)
    end
  end

  describe CodeGenerators::ElementTypes::Process::Communication::SendWebhookGenerator do
    it "honors failOnHttpError and statusVar" do
      sample = described_class.sample_input
      expect(body(described_class, sample.merge("failOnHttpError" => false)))
        .not_to eq(body(described_class, sample.merge("failOnHttpError" => true)))
      expect(body(described_class, sample.merge("statusVar" => "hook_status")))
        .not_to eq(body(described_class, sample.merge("statusVar" => "webhook_status")))
    end

    it "fails closed through Step rather than _last_error" do
      src = body(described_class, described_class.sample_input)
      expect(src).to include("FlowchartRuntime::Http.request")
      expect(src).not_to include("ctx[:_last_error]")
      expect(src).not_to include("sleep")
    end
  end

  describe CodeGenerators::ElementTypes::Process::Communication::SendTemplateEmailGenerator do
    it "sends through the TemplateEmail runtime facade" do
      src = body(described_class, described_class.sample_input)
      expect(src).to include("FlowchartRuntime::TemplateEmail.deliver(ctx, ")
      expect(src).not_to include("ctx[:_last_error]")
    end

    it "honors locale" do
      sample = described_class.sample_input
      expect(body(described_class, sample.merge("locale" => '"zh-CN"')))
        .not_to eq(body(described_class, sample.merge("locale" => '"en"')))
    end
  end
end
