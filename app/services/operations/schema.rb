# frozen_string_literal: true

require "json_schemer"

module Operations
  class Schema
    SCHEMA_URI = "https://json-schema.org/draft/2020-12/schema"
    MAX_VIOLATIONS = 25
    WRAPPER_TYPES = %w[anyOf oneOf allOf if then else not].freeze
    TYPE_NAMES = %w[null string boolean integer number array object].freeze
    KEYWORD_CODES = {
      "required" => "schema.required",
      "enum" => "schema.enum",
      "const" => "schema.enum",
      "type" => "schema.type",
      "pattern" => "schema.pattern",
      "format" => "schema.format",
      "minLength" => "schema.min_length",
      "maxLength" => "schema.max_length",
      "minItems" => "schema.min_items",
      "maxItems" => "schema.max_items",
      "minimum" => "schema.minimum",
      "maximum" => "schema.maximum",
      "uniqueItems" => "schema.unique_items",
      "minProperties" => "schema.min_properties",
      "maxProperties" => "schema.max_properties",
      "additionalProperties" => "schema.unknown_property",
      "unevaluatedProperties" => "schema.unknown_property"
    }.freeze

    class << self
      def schema_root
        @schema_root ||= Rails.root.join("app/services/operations/schemas")
      end

      attr_writer :schema_root

      # Parsed schema files keyed by path and mtime, so an edited file is
      # picked up without a restart. Resolution is not cached: vocabulary
      # slots depend on the tenant in the context.
      def parsed_files
        @parsed_files ||= {}
      end

      def reset_cache!
        @parsed_files = {}
      end
    end

    def initialize(operation_class, context:)
      @operation_class = operation_class
      @context = context
    end

    def document
      @document ||= resolve_document
    end

    def validate(input)
      normalized = deep_json_copy(input)
      errors = JSONSchemer.schema(document, insert_property_defaults: @operation_class.insert_defaults?)
                          .validate(normalized).to_a
      [map_errors(errors), normalized]
    end

    private

    def resolve_document
      raw = load_json(@operation_class.schema)
      defs = {}
      @operation_class.shared_defs.each do |file|
        shared = load_json(file)
        defs.merge!(shared.fetch("$defs", {}))
      end
      defs.merge!(raw.fetch("$defs", {}))
      raw = raw.merge("$defs" => defs) if defs.any?
      resolved = resolve_slots(deep_json_copy(raw))
      resolved["$id"] = "urn:anysys:operation:#{@operation_class.key}:v#{@operation_class.version}"
      resolved["$schema"] = SCHEMA_URI
      resolved
    end

    def load_json(file)
      path = Pathname(file)
      path = root.join(file) unless path.absolute?
      key = [path.to_s, File.mtime(path).to_f]
      deep_json_copy(self.class.parsed_files[key] ||= JSON.parse(File.read(path)))
    end

    def root
      @operation_class.schema_root || self.class.schema_root
    end

    def resolve_slots(node)
      case node
      when Array
        node.map { |item| resolve_slots(item) }
      when Hash
        resolved = node.transform_values { |value| resolve_slots(value) }
        apply_vocabulary_slot!(resolved) if resolved.key?("x-vocabulary")
        apply_vocabulary_max!(resolved) if resolved.key?("x-vocabulary-max")
        resolved
      else
        node
      end
    end

    def apply_vocabulary_slot!(schema)
      source = vocabulary_source(schema["x-vocabulary"])
      unless source.is_a?(Hash)
        raise ArgumentError, "vocabulary #{schema['x-vocabulary'].inspect} must resolve to values/descriptions"
      end

      values = Array(source[:values] || source["values"]).dup
      descriptions = (source[:descriptions] || source["descriptions"] || {}).stringify_keys
      values << nil if nullable?(schema) && !values.include?(nil)
      schema["enum"] = values
      schema["x-enum-descriptions"] = descriptions
    end

    def apply_vocabulary_max!(schema)
      source = vocabulary_source(schema["x-vocabulary-max"])
      unless source.is_a?(Integer)
        raise ArgumentError, "vocabulary #{schema['x-vocabulary-max'].inspect} must resolve to an Integer"
      end

      schema["maximum"] = source
    end

    def vocabulary_source(name)
      vocabulary = @operation_class.vocabulary
      raise ArgumentError, "unknown vocabulary slot: #{name.inspect}" unless vocabulary

      vocabulary.resolve(name, @context)
    rescue ArgumentError
      raise
    rescue StandardError
      raise ArgumentError, "unknown vocabulary slot: #{name.inspect}"
    end

    def nullable?(schema)
      type = schema["type"]
      type == "null" || (type.is_a?(Array) && type.include?("null"))
    end

    def deep_json_copy(value)
      JSON.parse(JSON.generate(as_json_value(value)))
    end

    def as_json_value(value)
      case value
      when Hash then value.to_h.transform_keys(&:to_s).transform_values { |item| as_json_value(item) }
      when Array then value.map { |item| as_json_value(item) }
      else value.respond_to?(:as_json) ? value.as_json : value
      end
    end

    def map_errors(errors)
      selected = select_specific_errors(errors)
      mapped = selected.flat_map { |error| violations_for(error) }
      mapped.uniq { |violation| [violation.pointer, violation.code] }.first(MAX_VIOLATIONS)
    end

    def select_specific_errors(errors)
      leaves = errors.reject { |error| WRAPPER_TYPES.include?(error["type"]) }
      pool = leaves.presence || errors
      wrapper_related, rest = pool.partition { |error| wrapper_schema?(error) }
      return pool if wrapper_related.empty?

      deepest = wrapper_related.max_by { |error| pointer_depth(error["data_pointer"]) }
      max_depth = pointer_depth(deepest["data_pointer"])
      rest + wrapper_related.select { |error| pointer_depth(error["data_pointer"]) == max_depth }
    end

    def wrapper_schema?(error)
      pointer = error["schema_pointer"].to_s
      pointer.match?(%r{/(anyOf|oneOf|allOf|if|then|else|not)(/|$)})
    end

    def pointer_depth(pointer)
      pointer.to_s.split("/").reject(&:empty?).size
    end

    def violations_for(error)
      type = error["type"].to_s
      if type == "required"
        return required_violations(error)
      end

      [
        Violation.new(
          pointer: pointer_for(error),
          code: code_for(error),
          details: details_for(error)
        )
      ]
    end

    def required_violations(error)
      missing = Array(error.dig("details", "missing_keys"))
      missing = [nil] if missing.empty?
      missing.map do |property|
        Violation.new(
          pointer: Pointer.join(error["data_pointer"].to_s, property),
          code: "schema.required",
          details: { "property" => property }.compact
        )
      end
    end

    def pointer_for(error)
      pointer = error["data_pointer"].to_s
      return pointer unless unknown_property?(error) && pointer.empty?

      unknown_keys(error).first.then { |key| key ? Pointer.join(pointer, key) : pointer }
    end

    def code_for(error)
      type = error["type"].to_s
      return "schema.type" if TYPE_NAMES.include?(type)
      return "schema.unknown_property" if unknown_property?(error)

      KEYWORD_CODES.fetch(type, "schema.invalid")
    end

    def details_for(error)
      type = error["type"].to_s
      schema = error["schema"]
      if type == "enum" || type == "const"
        allowed = type == "const" ? [schema.is_a?(Hash) ? schema["const"] : nil] : Array(schema.is_a?(Hash) ? schema["enum"] : nil)
        return { "allowed" => allowed.compact }
      end
      if type == "type" || TYPE_NAMES.include?(type)
        expected = schema.is_a?(Hash) ? schema["type"] : type
        return { "expected" => expected.is_a?(Array) ? expected.join(", ") : (expected || type) }
      end
      if unknown_property?(error)
        unknown = unknown_keys(error).first || File.basename(error["data_pointer"].to_s)
        siblings = sibling_properties(error)
        return { "candidates" => Violation.candidates(unknown, siblings) }
      end
      if KEYWORD_CODES.key?(type)
        expected = schema.is_a?(Hash) ? schema[type] : nil
        return { "expected" => expected }.compact
      end
      {}
    end

    def unknown_property?(error)
      type = error["type"].to_s
      pointer = error["schema_pointer"].to_s
      KEYWORD_CODES[type] == "schema.unknown_property" ||
        pointer.end_with?("/additionalProperties") ||
        pointer.end_with?("/unevaluatedProperties")
    end

    def unknown_keys(error)
      data = error["data"]
      return [] unless data.is_a?(Hash)

      allowed = sibling_properties(error)
      return data.keys - allowed if allowed.any?

      token = error["data_pointer"].to_s.split("/").last
      token.present? ? [unescape(token)] : []
    end

    def sibling_properties(error)
      pointer = error["schema_pointer"].to_s.sub(%r{/(additionalProperties|unevaluatedProperties)\z}, "")
      node = walk_pointer(error["root_schema"], pointer)
      Array(node&.[]("properties")&.keys)
    end

    def walk_pointer(document, pointer)
      return document if pointer.blank?

      pointer.delete_prefix("/").split("/").reduce(document) do |node, token|
        break unless node.is_a?(Hash) || node.is_a?(Array)

        key = unescape(token)
        node.is_a?(Array) ? node[key.to_i] : node[key]
      end
    end

    def unescape(token)
      token.to_s.gsub("~1", "/").gsub("~0", "~")
    end
  end
end
