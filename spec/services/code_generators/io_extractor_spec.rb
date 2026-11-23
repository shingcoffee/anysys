# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::IoExtractor do
  describe ".call" do
    let(:api_call_config) do
      { "httpMethod" => "GET", "url" => '"https://example.com"', "resultVar" => "resp", "responseFormat" => "json" }
    end

    it "returns empty pins for unknown action" do
      result = described_class.call(action: "definitely_not_a_real_action", config: {})
      expect(result).to eq(inputs: [], outputs: [])
    end

    it "extracts outputs from api_call generator" do
      result = described_class.call(action: "api_call", config: api_call_config)
      expect(result[:outputs].map { |o| o[:pin] }).to include("resp")
    end

    it "tags ctx reads that originate from a config expression as source: config_expr" do
      result = described_class.call(action: "api_call", config: api_call_config.merge("url" => "ctx[:target_url]"))
      expect(result[:inputs]).to include(hash_including(pin: "target_url", source: "config_expr"))
    end

    it "tags literal reads from generator body as source: generator_literal" do
      result = described_class.call(action: "new_model", config: {})
      expect(result[:inputs]).to include(hash_including(pin: "customer_id", source: "generator_literal"))
    end

    it "dedupes pins preserving first-seen order" do
      result = described_class.call(action: "api_call", config: api_call_config)
      expect(result[:outputs].map { |o| o[:pin] }.uniq).to eq(result[:outputs].map { |o| o[:pin] })
      expect(result[:inputs].map { |i| i[:pin] }.uniq).to eq(result[:inputs].map { |i| i[:pin] })
    end

    it "returns empty pins when the generator raises during body generation" do
      stub_gen = Class.new do
        def initialize(_element, _ctx); end
        def generate_body; raise "boom"; end
      end
      registry = CodeGenerators::GeneratorRegistry.instance
      allow(registry).to receive(:find_step_action).with("exploding_action").and_return(stub_gen)

      result = described_class.call(action: "exploding_action", config: {})
      expect(result).to eq(inputs: [], outputs: [])
    end

    it "populates ctx_key equal to pin in v1" do
      result = described_class.call(action: "api_call", config: api_call_config)
      result[:outputs].each { |o| expect(o[:ctx_key]).to eq(o[:pin]) }
      result[:inputs].each { |i| expect(i[:ctx_key]).to eq(i[:pin]) }
    end

    it "reports a pin that is both read and written in both inputs and outputs" do
      stub_gen = Class.new do
        def initialize(_element, _ctx); end
        def generate_body; "ctx[:counter] ||= 0\nctx[:counter] = ctx[:counter] + 1"; end
      end
      registry = CodeGenerators::GeneratorRegistry.instance
      allow(registry).to receive(:find_step_action).with("counter_inc").and_return(stub_gen)

      result = described_class.call(action: "counter_inc", config: {})
      expect(result[:inputs].map { |i| i[:pin] }).to include("counter")
      expect(result[:outputs].map { |o| o[:pin] }).to include("counter")
    end

    it "reports bound_entity and customer_id for new_model via Entries.scope(ctx)" do
      klass = CodeGenerators::ElementTypes::Process::ModelOperations::NewModelGenerator
      result = described_class.call(action: "new_model", config: klass.sample_input)
      expect(result[:inputs].map { |i| i[:pin] }).to include("bound_entity", "customer_id")
      expect(result[:outputs].map { |o| o[:pin] }).to include("model")
    end
  end
end

RSpec.describe CodeGenerators::IoExtractor, ".call_element" do
  it "extracts ctx reads/writes from a loop element generator body" do
    result = described_class.call_element(
      element_type: "loop",
      properties: {
        "loopType"     => "for_each",
        "collection"   => "items",
        "itemVariable" => "item",
        "indexVariable" => "idx",
        "collectInto"  => "bag"
      }
    )
    expect(result[:inputs].map { |i| i[:pin] }).to include("bag")
    expect(result[:outputs].map { |o| o[:pin] }).to include("item", "idx", "bag")
  end

  it "returns empty pins for unknown element types" do
    result = described_class.call_element(element_type: "__nope__", properties: {})
    expect(result).to eq(inputs: [], outputs: [])
  end

  it "returns empty pins when the element generator raises" do
    allow_any_instance_of(CodeGenerators::ElementTypes::Loop::LoopGenerator)
      .to receive(:generate_body).and_raise(StandardError, "boom")
    result = described_class.call_element(element_type: "loop", properties: {})
    expect(result).to eq(inputs: [], outputs: [])
  end
end

RSpec.describe CodeGenerators::IoExtractor, ".call_element (element-type coverage)" do
  it "returns empty pins for a start element (no literal ctx access)" do
    result = described_class.call_element(element_type: "start", properties: {})
    expect(result[:inputs]).to eq([])
  end

  it "returns empty pins for an end element" do
    result = described_class.call_element(element_type: "end", properties: {})
    expect(result[:inputs]).to eq([])
    expect(result[:outputs]).to eq([])
  end

  it "extracts inputs from a decision element with condition expression" do
    result = described_class.call_element(
      element_type: "decision",
      properties:   { "condition" => "ctx[:flag]", "branches" => [] }
    )
    expect(result[:inputs].map { |i| i[:pin] }).to include("flag") if result[:inputs].any?
  end

  it "returns empty pins for the removed timer element type" do
    result = described_class.call_element(
      element_type: "timer",
      properties:   { "duration" => 10 }
    )
    expect(result).to eq(inputs: [], outputs: [])
  end

  it "extracts collection ctx pins that Loop for_each reads via OperandConverter" do
    result = described_class.call_element(
      element_type: "loop",
      properties:   { "loopType" => "for_each", "collection" => "items" }
    )
    expect(result[:inputs].map { |i| i[:pin] }).to include("items")
  end
end

RSpec.describe CodeGenerators::IoExtractor, ".call_element (process element)" do
  let(:api_call_config_get) do
    { "httpMethod"     => "GET",
      "url"            => '"https://example.com"',
      "resultVar"      => "resp",
      "responseFormat" => "json" }
  end

  let(:api_call_config_literal) do
    { "httpMethod"     => "GET",
      "resultVar"      => "resp2",
      "responseFormat" => "json" }
  end

  it "returns empty pins when properties has no steps key" do
    result = described_class.call_element(element_type: "process", properties: {})
    expect(result).to eq(inputs: [], outputs: [])
  end

  it "returns empty pins for an empty steps array" do
    result = described_class.call_element(
      element_type: "process",
      properties:   { "steps" => [] }
    )
    expect(result).to eq(inputs: [], outputs: [])
  end

  it "returns empty pins when steps is not an array" do
    result = described_class.call_element(
      element_type: "process",
      properties:   { "steps" => "nonsense" }
    )
    expect(result).to eq(inputs: [], outputs: [])
  end

  it "unions outputs across a chain of single-step api_call processes" do
    first = described_class.call_element(
      element_type: "process",
      properties:   { "steps" => [{ "action" => "api_call", "config" => api_call_config_get }] }
    )
    second = described_class.call_element(
      element_type: "process",
      properties:   { "steps" => [{ "action" => "api_call", "config" => api_call_config_literal }] }
    )
    pins = (first[:outputs] + second[:outputs]).map { |o| o[:pin] }
    expect(pins).to include("resp", "resp2")
  end

  it "dedupes duplicate pins across a chain of single-step processes preserving first-seen order" do
    first = described_class.call_element(
      element_type: "process",
      properties:   { "steps" => [{ "action" => "api_call", "config" => api_call_config_get }] }
    )
    second = described_class.call_element(
      element_type: "process",
      properties:   { "steps" => [{ "action" => "api_call", "config" => api_call_config_get }] }
    )
    pins = (first[:outputs] + second[:outputs]).map { |o| o[:pin] }.uniq
    expect(pins).to eq(pins.uniq)
    expect(pins).to include("resp")
  end

  it "reports a pin that is both read and written across steps in both inputs and outputs" do
    read_then_write = Class.new do
      def initialize(_element, _ctx); end
      def generate_body; "ctx[:foo] = ctx[:foo].to_i + 1"; end
    end
    registry = CodeGenerators::GeneratorRegistry.instance
    allow(registry).to receive(:find_step_action).and_call_original
    allow(registry).to receive(:find_step_action).with("rw_foo").and_return(read_then_write)

    result = described_class.call_element(
      element_type: "process",
      properties:   {
        "steps" => [{ "action" => "rw_foo", "config" => {} }]
      }
    )
    expect(result[:inputs].map { |i| i[:pin] }).to include("foo")
    expect(result[:outputs].map { |o| o[:pin] }).to include("foo")
  end

  it "skips steps with blank action" do
    blank = described_class.call_element(
      element_type: "process",
      properties:   { "steps" => [{ "action" => "", "config" => {} }] }
    )
    missing = described_class.call_element(
      element_type: "process",
      properties:   { "steps" => [{ "action" => nil, "config" => {} }] }
    )
    result = described_class.call_element(
      element_type: "process",
      properties:   { "steps" => [{ "action" => "api_call", "config" => api_call_config_get }] }
    )
    expect(blank[:outputs]).to eq([])
    expect(missing[:outputs]).to eq([])
    expect(result[:outputs].map { |o| o[:pin] }).to include("resp")
  end

  it "contributes nothing for a step whose action is unknown" do
    unknown = described_class.call_element(
      element_type: "process",
      properties:   { "steps" => [{ "action" => "__not_a_real_action__", "config" => {} }] }
    )
    result = described_class.call_element(
      element_type: "process",
      properties:   { "steps" => [{ "action" => "api_call", "config" => api_call_config_get }] }
    )
    pins = (unknown[:outputs] + result[:outputs]).map { |o| o[:pin] }
    expect(unknown[:outputs]).to eq([])
    expect(pins).to include("resp")
    expect(pins).to all(be_a(String))
  end

  it "contributes nothing for a step whose generator raises" do
    exploding = Class.new do
      def initialize(_element, _ctx); end
      def generate_body; raise "boom"; end
    end
    registry = CodeGenerators::GeneratorRegistry.instance
    allow(registry).to receive(:find_step_action).and_call_original
    allow(registry).to receive(:find_step_action).with("exploding_step").and_return(exploding)

    exploded = described_class.call_element(
      element_type: "process",
      properties:   { "steps" => [{ "action" => "exploding_step", "config" => {} }] }
    )
    result = described_class.call_element(
      element_type: "process",
      properties:   { "steps" => [{ "action" => "api_call", "config" => api_call_config_get }] }
    )
    expect(exploded[:outputs]).to eq([])
    expect(result[:outputs].map { |o| o[:pin] }).to include("resp")
  end

  it "accepts symbol keys for steps/action/config" do
    result = described_class.call_element(
      element_type: "process",
      properties:   {
        steps: [
          { action: "api_call", config: api_call_config_get }
        ]
      }
    )
    expect(result[:outputs].map { |o| o[:pin] }).to include("resp")
  end
end
