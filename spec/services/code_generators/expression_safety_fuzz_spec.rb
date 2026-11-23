# frozen_string_literal: true

require "rails_helper"
require "prism"

RSpec.describe "expression safety fuzz" do
  UNSAFE_EXPRESSION_PAYLOADS = [
    "ctx[:a]; Kernel.exit!(1)",
    "ctx[:a]\nKernel.exit!(1)",
    "ctx[:a] == ("
  ].freeze

  # Config fields that splice a ctx[...] value into emitted Ruby unchanged,
  # plus string_manipulate.pattern and api_call.cookies.
  PASSTHROUGH_FIELDS = [
    ["api_call", "url"],
    ["send_template_email", "cc"],
    ["send_template_email", "bcc"],
    ["send_template_email", "replyTo"],
    ["template_render", "variables"],
    ["cache_fetch", "fallbackExpression"]
  ].freeze

  QUOTE_INJECTION_PAYLOADS = [
    '"x"); Kernel.exit!(1); %("',
    "'x'); Kernel.exit!(1); %('"
  ].freeze

  def generator_for(action)
    CodeGenerators::GeneratorRegistry.find_step_action(action)
  end

  def instance_for(klass, config)
    klass.new({ "config" => config }, {})
  end

  describe "CodeGenerators::Shared::ExpressionSafety#safe_single_expression?" do
    let(:host) do
      Object.new.extend(CodeGenerators::Shared::ExpressionSafety)
    end

    it "accepts a single ctx read" do
      expect(host.safe_single_expression?("ctx[:a]")).to be(true)
    end

    it "rejects a statement list joined by semicolon" do
      expect(host.safe_single_expression?("ctx[:a]; Kernel.exit!(1)")).to be(false)
    end

    it "rejects a second statement after a newline" do
      expect(host.safe_single_expression?("ctx[:a]\nKernel.exit!(1)")).to be(false)
    end

    it "rejects an unbalanced expression" do
      expect(host.safe_single_expression?("ctx[:a] == (")).to be(false)
    end
  end

  PASSTHROUGH_FIELDS.each do |action, field|
    describe "#{action}.#{field}" do
      let(:klass) { generator_for(action) }
      let(:sample) { klass.sample_input }

      UNSAFE_EXPRESSION_PAYLOADS.each do |payload|
        it "rejects #{payload.inspect} at validate_config" do
          config = sample.merge(field => payload)
          generator = instance_for(klass, config)
          expect(generator.validate_config(config)).not_to be_empty
        end
      end

      it "still accepts the original sample and emits parseable Ruby" do
        generator = instance_for(klass, sample)
        expect(generator.validate_config(sample)).to be_empty
        expect(Prism.parse(generator.generate_body).success?).to be(true)
      end
    end
  end

  describe "api_call header/query quote injection" do
    let(:klass) { generator_for("api_call") }
    let(:sample) { klass.sample_input }

    def kernel_exit_call_nodes(source)
      result = Prism.parse(source)
      nodes = []
      queue = [result.value]
      until queue.empty?
        node = queue.shift
        next unless node.is_a?(Prism::Node)

        nodes << node if node.is_a?(Prism::CallNode) && node.name == :exit!
        node.compact_child_nodes.each { |child| queue << child }
      end
      nodes
    end

    %w[headers queryParams].each do |field|
      QUOTE_INJECTION_PAYLOADS.each do |payload|
        it "emits #{payload.inspect} in #{field} via inspect, not as Ruby" do
          config = sample.merge(field => [{ "key" => "H", "value" => payload }])
          body = instance_for(klass, config).generate_body
          expect(Prism.parse(body).success?).to be(true)
          expect(kernel_exit_call_nodes(body)).to be_empty
        end
      end
    end
  end
end
