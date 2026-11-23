# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::Utility::AuditLogGenerator do
  let(:element) { { "config" => {} } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  def generate(config = described_class.sample_input)
    described_class.new({ "config" => config }, {})
  end

  def body(config = described_class.sample_input)
    generate(config).generate_body
  end

  def errors(config)
    generate(config).validate_config(config)
  end

  def execute(config, ctx)
    CodeGenerators::TestRunner.execute(described_class, config: config, ctx: ctx)
  end

  it "has only required errors on schema defaults" do
    defaults = described_class._config_schema.defaults
    unexpected = errors(defaults).reject { |error| error.respond_to?(:code) && error.code == :required }
    expect(unexpected).to eq([])
  end

  it "accepts sample_input and compiles" do
    sample = described_class.sample_input
    expect(errors(sample)).to eq([])
    expect { RubyVM::InstructionSequence.compile(generate(sample).generate_step_method) }.not_to raise_error
    result = CodeGenerators::BodyLint.check(body(sample), outputs: [])
    expect(result.ok?).to be(true), result.violations.inspect
  end

  it "generates the sample step" do
    expect(generated_step).to eq(<<~RUBY.chomp)
      def test_step(ctx, **)
        FlowchartRuntime::Audit.write(
          ctx,
          event_type: "record_updated",
          actor_id: ctx[:current_user_id],
          ip_address: ctx[:request_ip],
          user_agent: ctx[:user_agent]
        )
      end
    RUBY
  end

  it "emits metadata input paths and a non-default severity" do
    code = generated_step(
      described_class.sample_input.merge(
        "severity" => "error",
        "metadata" => [{ "key" => "sku", "value" => "sku" }]
      )
    )
    expect(code).to include('"sku" => ctx[:sku]')
    expect(code).to include('severity: "error"')
  end

  described_class::SEVERITIES.each do |severity|
    it "emits a BodyLint-clean body for severity #{severity}" do
      config = described_class.sample_input.merge("severity" => severity)
      expect(body(config)).to include("FlowchartRuntime::Audit.write")
      expect(body(config)).not_to include("persistTo")
      expect(CodeGenerators::BodyLint.check(body(config), outputs: []).ok?).to be(true)
    end
  end

  it "does not emit persistTo" do
    expect(body).not_to include("persistTo")
    expect(body).not_to include("AppLogger")
  end

  describe "behaviour" do
    it "writes a JSON audit line to the logger" do
      allow(Rails.logger).to receive(:info)

      result = execute(
        described_class.sample_input.merge("metadata" => [{ "key" => "sku", "value" => "sku" }]),
        { current_user_id: 7, request_ip: "1.1.1.1", user_agent: "rspec", sku: "ABC" }
      )
      expect(result[:outcome]).to be(true)
      expect(Rails.logger).to have_received(:info).with(a_string_including("[AUDIT]", "record_updated", "7"))
    end

    it "inserts a flowchart_audit_events row for the run's customer" do
      allow(Rails.logger).to receive(:info)
      customer = create(:customer)

      result = execute(
        described_class.sample_input.merge("metadata" => [{ "key" => "sku", "value" => "sku" }]),
        {
          customer_id: customer.id, flowchart_id: 9, current_user_id: 7,
          request_ip: "1.1.1.1", user_agent: "rspec", sku: "ABC"
        }
      )
      expect(result[:outcome]).to be(true)
      row = FlowchartAuditEvent.find_by!(customer_id: customer.id, event_type: "record_updated")
      expect(row.flowchart_id).to eq(9)
      expect(row.actor_user_id).to eq(7)
      expect(row.metadata).to eq("sku" => "ABC", "outcome" => "success")
    end

    it "stores outcome and a changes hash in metadata" do
      allow(Rails.logger).to receive(:error)
      customer = create(:customer)
      diff = { "name" => { "from" => "a", "to" => "b" } }

      result = execute(
        described_class.sample_input.merge("outcome" => "failure", "changesVariable" => "diff"),
        { customer_id: customer.id, current_user_id: 7, request_ip: "1.1.1.1", user_agent: "rspec", diff: diff }
      )
      expect(result[:outcome]).to be(true)
      row = FlowchartAuditEvent.find_by!(customer_id: customer.id, event_type: "record_updated")
      expect(row.metadata["outcome"]).to eq("failure")
      expect(row.metadata["changes"]).to eq("name" => { "from" => "a", "to" => "b" })
    end
  end

end
