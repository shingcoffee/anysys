# frozen_string_literal: true

require "set"
require_relative "io_extractor/body_analyzer"

module CodeGenerators
  # IoExtractor runs a step-action generator with a supplied config hash,
  # feeds its body through BodyAnalyzer, and classifies the resulting
  # ctx reads / writes into input and output "pins".
  #
  # A pin is a single ctx key (e.g. the `:resp` in `ctx[:resp]`). Each input
  # pin is further tagged with a `source`:
  #
  #   * "config_expr"        — the pin appears literally as `ctx[:<pin>]`
  #                            inside a string value somewhere in the config
  #                            hash (meaning the user wired a ctx expression
  #                            into this field).
  #   * "generator_literal"  — the pin only appears in the generator's own
  #                            emitted Ruby source (e.g. a hardcoded
  #                            `ctx[:api_url]` fallback inside the generator).
  #
  # Contract:
  #   CodeGenerators::IoExtractor.call(action: "api_call", config: {...})
  #   # => { inputs:  [{ pin:, ctx_key:, source: }, ...],
  #   #      outputs: [{ pin:, ctx_key: }, ...] }
  #
  #   * Unknown action name         -> { inputs: [], outputs: [] }
  #   * Generator raises             -> { inputs: [], outputs: [] }
  #   * Duplicate pins are collapsed, preserving first-seen order.
  #   * In v1 `ctx_key` always equals `pin`.
  module IoExtractor
    EMPTY = { inputs: [], outputs: [] }.freeze

    # Matches `ctx[:identifier]` embedded inside a config string value.
    CTX_SYMBOL_IN_STRING = /ctx\[:([a-zA-Z_][a-zA-Z0-9_]*)\]/.freeze

    def self.call(action:, config: {})
      Extractor.new(action: action, config: config).call
    end

    def self.call_element(element_type:, properties: {})
      ElementExtractor.new(element_type: element_type, properties: properties).call
    end

    class ElementExtractor
      def initialize(element_type:, properties:)
        @element_type = element_type
        @properties = properties || {}
      end

      def call
        return extract_process_io if @element_type.to_s == "process"

        generator_class = CodeGenerators::GeneratorRegistry.instance.find_element_type(@element_type)
        return EMPTY unless generator_class

        body = build_body(generator_class)
        return EMPTY unless body

        ast = BodyAnalyzer.call(body)
        config_expr_pins = extract_config_expr_pins

        {
          inputs:  dedupe_preserving_order(ast[:reads]).map { |r| input_hash(r, config_expr_pins) },
          outputs: dedupe_preserving_order(ast[:writes]).map { |w| output_hash(w) }
        }
      end

      private

      def extract_process_io
        steps = @properties["steps"] || @properties[:steps]
        return EMPTY unless steps.is_a?(Array) && steps.any?

        inputs = []
        outputs = []

        steps.each do |step|
          next unless step.is_a?(Hash)

          action = step["action"] || step[:action]
          next if action.nil? || action.to_s.strip.empty?

          config = step["config"] || step[:config] || {}
          step_io = CodeGenerators::IoExtractor.call(action: action, config: config)

          inputs.concat(step_io[:inputs] || [])
          outputs.concat(step_io[:outputs] || [])
        end

        {
          inputs:  dedupe_hashes_by_pin(inputs),
          outputs: dedupe_hashes_by_pin(outputs)
        }
      end

      def dedupe_hashes_by_pin(entries)
        seen = Set.new
        entries.each_with_object([]) do |e, acc|
          pin = e[:pin]
          next if seen.include?(pin)

          seen << pin
          acc << e
        end
      end

      def build_body(generator_class)
        element = {
          "id"         => "__io_extract_elem_stub__",
          "label"      => "stub",
          "type"       => @element_type,
          "properties" => @properties,
          "config"     => @properties
        }
        generator_class.new(element, { config: @properties }).generate_body
      rescue StandardError
        nil
      end

      def extract_config_expr_pins
        pins = Set.new
        deep_each_string(@properties) do |value|
          value.scan(CTX_SYMBOL_IN_STRING) { |m| pins << m.first }
        end
        pins
      end

      def deep_each_string(obj, &block)
        case obj
        when String then yield(obj)
        when Hash   then obj.each_value { |v| deep_each_string(v, &block) }
        when Array  then obj.each       { |v| deep_each_string(v, &block) }
        end
      end

      def dedupe_preserving_order(entries)
        seen = Set.new
        entries.each_with_object([]) do |e, acc|
          next if seen.include?(e[:pin])

          seen << e[:pin]
          acc << e
        end
      end

      def input_hash(read, config_expr_pins)
        {
          pin:     read[:pin],
          ctx_key: read[:pin],
          source:  config_expr_pins.include?(read[:pin]) ? "config_expr" : "generator_literal"
        }
      end

      def output_hash(write)
        { pin: write[:pin], ctx_key: write[:pin] }
      end
    end

    # Internal worker class so we can keep per-call state without polluting
    # the module namespace (BodyAnalyzer already lives here).
    class Extractor
      def initialize(action:, config:)
        @action = action
        @config = config || {}
      end

      def call
        generator_class = CodeGenerators::GeneratorRegistry.instance.find_step_action(@action)
        return EMPTY unless generator_class

        body = build_body(generator_class)
        return EMPTY unless body

        ast = BodyAnalyzer.call(body)
        config_expr_pins = extract_config_expr_pins

        {
          inputs:  dedupe_preserving_order(ast[:reads]).map { |r| input_hash(r, config_expr_pins) },
          outputs: dedupe_preserving_order(ast[:writes]).map { |w| output_hash(w) }
        }
      end

      private

      # Instantiates the generator with a synthetic element + context just
      # rich enough to let it produce a body. Any exception during the
      # generator run is swallowed — a broken generator should not crash the
      # I/O extraction layer, it should simply yield empty pins.
      def build_body(generator_class)
        element = {
          "id"         => "__io_extract_stub__",
          "label"      => "stub",
          "action"     => @action,
          "properties" => @config,
          "config"     => @config
        }
        generator_class.new(element, { config: @config }).generate_body
      rescue StandardError
        nil
      end

      # Walks the config hash (deeply) and collects every pin name that
      # appears as `ctx[:<name>]` inside *any* string value. Nested hashes /
      # arrays (headers, queryParams, bodyTemplate, etc.) are all inspected.
      def extract_config_expr_pins
        pins = Set.new
        deep_each_string(@config) do |value|
          value.scan(CTX_SYMBOL_IN_STRING) { |m| pins << m.first }
        end
        pins
      end

      def deep_each_string(obj, &block)
        case obj
        when String then yield(obj)
        when Hash   then obj.each_value { |v| deep_each_string(v, &block) }
        when Array  then obj.each       { |v| deep_each_string(v, &block) }
        end
      end

      def dedupe_preserving_order(entries)
        seen = Set.new
        entries.each_with_object([]) do |e, acc|
          next if seen.include?(e[:pin])

          seen << e[:pin]
          acc << e
        end
      end

      def input_hash(read, config_expr_pins)
        {
          pin:     read[:pin],
          ctx_key: read[:pin],
          source:  config_expr_pins.include?(read[:pin]) ? "config_expr" : "generator_literal"
        }
      end

      def output_hash(write)
        { pin: write[:pin], ctx_key: write[:pin] }
      end
    end
  end
end
