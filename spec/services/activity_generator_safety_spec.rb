# frozen_string_literal: true

require "rails_helper"

# Safety / hardening coverage for ActivityGenerator and the code-generation
# helpers it relies on. Each example here pins down a behaviour that
# protects the generated source from a real failure mode (cycle, dangling
# edge, raising generator, reserved-word identifier, injection target).
RSpec.describe ActivityGenerator, "safety hardening" do
  let_it_be(:customer) { create(:customer) }
  let(:entity)   { create(:entity, customer: customer) }

  def build_flow(elements, connections, name: "Safety Flow")
    cfg = {
      "elements"    => elements,
      "connections" => connections,
      "metadata"    => { "canvas" => { "width" => 1200, "height" => 800 } }
    }.to_json
    create(:flowchart, customer: customer, name: name, configuration: cfg)
  end

  describe "structural validation" do
    it "detects cycles via the topological-order length check" do
      els = [
        { "id" => "s", "type" => "start",   "label" => "S", "properties" => {} },
        { "id" => "a", "type" => "process", "label" => "A", "properties" => { "steps" => [] } },
        { "id" => "b", "type" => "process", "label" => "B", "properties" => { "steps" => [] } },
        { "id" => "e", "type" => "end",     "label" => "E", "properties" => {} }
      ]
      conns = [
        { "id" => "c1", "from" => "s", "to" => "a" },
        { "id" => "c2", "from" => "a", "to" => "b" },
        { "id" => "c3", "from" => "b", "to" => "a" }, # cycle: a <-> b
        { "id" => "c4", "from" => "a", "to" => "e" }
      ]
      flow = build_flow(els, conns)
      gen  = described_class.new(flow)
      errors = gen.structure_errors
      expect(errors).to include(a_string_matching(/Cycle detected/))
      # The generator refuses to emit anything for a cyclic flowchart.
      expect(gen.generate).to be_nil
    end

    it "flags connections that point to unknown element ids" do
      els = [
        { "id" => "s", "type" => "start", "label" => "S", "properties" => {} },
        { "id" => "e", "type" => "end",   "label" => "E", "properties" => {} }
      ]
      conns = [
        { "id" => "c1", "from" => "s",  "to" => "e" },
        { "id" => "c2", "from" => "s",  "to" => "ghost" }
      ]
      gen = described_class.new(build_flow(els, conns))
      errors = gen.structure_errors
      expect(errors).to include(a_string_matching(/unknown element id 'ghost'/))
    end

    it "build_topological_order returns the full set for a valid linear graph" do
      els = [
        { "id" => "s", "type" => "start",   "label" => "S", "properties" => {} },
        { "id" => "p", "type" => "process", "label" => "P", "properties" => { "steps" => [] } },
        { "id" => "e", "type" => "end",     "label" => "E", "properties" => {} }
      ]
      conns = [
        { "id" => "c1", "from" => "s", "to" => "p" },
        { "id" => "c2", "from" => "p", "to" => "e" }
      ]
      gen = described_class.new(build_flow(els, conns))
      expect(gen.send(:build_topological_order)).to eq(%w[s p e])
    end
  end

  describe "reserved-word labels" do
    %w[end class def begin do return self].each do |reserved|
      it "produces parseable Ruby when an element label is the Ruby keyword '#{reserved}'" do
        els = [
          { "id" => "s", "type" => "start",   "label" => "Start", "properties" => {} },
          { "id" => "p", "type" => "process", "label" => reserved, "properties" => { "steps" => [] } },
          { "id" => "e", "type" => "end",     "label" => "End",   "properties" => {} }
        ]
        conns = [
          { "id" => "c1", "from" => "s", "to" => "p" },
          { "id" => "c2", "from" => "p", "to" => "e" }
        ]
        code = described_class.new(build_flow(els, conns, name: "Reserved #{reserved}")).generate
        expect(code).not_to be_nil
        # A safe step suffix must be appended so `def end(ctx, **)` etc. don't
        # land in the output as Ruby SyntaxErrors.
        expect(code).to include("def #{reserved}_step(ctx, **)")
        expect { RubyVM::InstructionSequence.compile(code) }.not_to raise_error
      end
    end

    it "falls back to the generator name when a label parameterizes to empty" do
      els = [
        { "id" => "s", "type" => "start",   "label" => "Start", "properties" => {} },
        { "id" => "p", "type" => "process", "label" => "!!!",    "properties" => { "steps" => [] } },
        { "id" => "e", "type" => "end",     "label" => "End",   "properties" => {} }
      ]
      conns = [
        { "id" => "c1", "from" => "s", "to" => "p" },
        { "id" => "c2", "from" => "p", "to" => "e" }
      ]
      code = described_class.new(build_flow(els, conns)).generate
      expect(code).not_to be_nil
      # An empty parameterize collapses to the generator-stable name. We
      # don't pin which one — just confirm the method definition parses.
      expect { RubyVM::InstructionSequence.compile(code) }.not_to raise_error
    end
  end

  describe "generator-rescue path" do
    it "propagates generator failures instead of emitting a success-shaped TODO body" do
      # Stub the registry to return a class that always raises.
      raiser = Class.new do
        def initialize(*); end
        def generate_body
          raise "boom"
        end
        def validate_config(_config)
          []
        end
        def self.name; "ExplodingGenerator"; end
      end
      registry = CodeGenerators::GeneratorRegistry.instance
      allow(registry).to receive(:find_step_action).and_return(raiser)

      els = [
        { "id" => "s", "type" => "start",   "label" => "S", "properties" => {} },
        { "id" => "p", "type" => "process", "label" => "P",
          "properties" => { "steps" => [{ "id" => "x", "action" => "explode" }] } },
        { "id" => "e", "type" => "end",     "label" => "E", "properties" => {} }
      ]
      conns = [
        { "id" => "c1", "from" => "s", "to" => "p" },
        { "id" => "c2", "from" => "p", "to" => "e" }
      ]
      expect { described_class.new(build_flow(els, conns)).generate }.to raise_error(RuntimeError, "boom")
    end
  end

  describe "Trojan Source-style comment safety" do
    it "strips Unicode line separators and bidi overrides from the header comment" do
      # U+2028 (LSEP) and U+202E (right-to-left override) — Trojan Source.
      malicious = "Pwned # extra‮/* */"
      els = [
        { "id" => "s", "type" => "start", "label" => "S", "properties" => {} },
        { "id" => "e", "type" => "end",   "label" => "E", "properties" => {} }
      ]
      conns = [{ "id" => "c1", "from" => "s", "to" => "e" }]
      code = described_class.new(build_flow(els, conns, name: malicious)).generate
      header_line = code.lines.find { |l| l.start_with?("# Generated from flowchart") }
      expect(header_line).not_to include(" ")
      expect(header_line).not_to include("‮")
    end

    it "keeps element labels on one sanitized comment line and never executes injected source" do
      malicious = "Safe label\nKernel.raise(\"LABEL_INJECTION\")"
      els = [
        { "id" => "s", "type" => "start", "label" => "Start", "properties" => {} },
        { "id" => "p", "type" => "process", "label" => malicious, "properties" => { "steps" => [] } },
        { "id" => "e", "type" => "end", "label" => "End", "properties" => {} }
      ]
      conns = [
        { "id" => "c1", "from" => "s", "to" => "p" },
        { "id" => "c2", "from" => "p", "to" => "e" }
      ]

      code = described_class.new(build_flow(els, conns)).generate
      expect(code).not_to match(/^Kernel\.raise/)
      expect { RubyVM::InstructionSequence.compile(code).eval }.not_to raise_error
    end
  end

  describe "generator configuration validation" do
    it "raises a structured ActivityGenerator::Error before emitting invalid element source" do
      els = [
        { "id" => "s", "type" => "start", "label" => "Start", "properties" => {} },
        {
          "id" => "e",
          "type" => "end",
          "label" => "End",
          "properties" => {
            "responseType" => "http_response",
            "httpStatus" => 200,
            "responseFormat" => "json\nKernel.raise(\"FORMAT_INJECTION\")"
          }
        }
      ]
      conns = [{ "id" => "c1", "from" => "s", "to" => "e" }]

      expect { described_class.new(build_flow(els, conns)).generate }
        .to raise_error(ActivityGenerator::Error) { |error|
          expect(error.code).to eq(:invalid_generator_config)
          expect(error.element_id).to eq("e")
          expect(error.element_type).to eq("end")
          expect(error.details.map(&:field)).to include("responseType", "responseFormat")
        }
    end

    it "rejects removed Switch elements before adversarial source can be emitted" do
      malicious_properties = {
        "sourceVariable" => "status",
        "_route_index" => "0]; Kernel.raise('SWITCH_ROUTE_INJECTION'); ctx[:_route_0",
        "_connection_match_values" => [
          {
            "branch" => "branch_0; Kernel.raise('SWITCH_BRANCH_INJECTION'); :branch_0",
            "matchValue" => "persisted"
          },
          { "branch" => "branch_1", "matchValue" => "" }
        ]
      }
      elements = [
        { "id" => "s", "type" => "start", "label" => "Start", "properties" => {} },
        { "id" => "w", "type" => "switch", "label" => "Switch",
          "properties" => malicious_properties },
        { "id" => "e", "type" => "end", "label" => "End", "properties" => {} }
      ]
      connections = [
        { "id" => "c1", "from" => "s", "to" => "w" },
        { "id" => "c2", "from" => "w", "to" => "a", "matchValue" => "active" },
        { "id" => "c3", "from" => "w", "to" => "d", "matchValue" => "" },
        { "id" => "c4", "from" => "a", "to" => "e" },
        { "id" => "c5", "from" => "d", "to" => "e" }
      ]
      elements.concat([
        { "id" => "a", "type" => "process", "label" => "Active", "properties" => { "steps" => [] } },
        { "id" => "d", "type" => "process", "label" => "Default", "properties" => { "steps" => [] } }
      ])

      expect { described_class.new(build_flow(elements, connections)).generate }
        .to raise_error(ActivityGenerator::Error) { |error|
          expect(error.code).to eq(:unsupported_structural_element)
          expect(error.details).to include("w:switch")
        }
    end
  end
end
