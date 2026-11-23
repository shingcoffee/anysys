# frozen_string_literal: true

require "prism"
require_relative "metadata_dsl"
require_relative "config_schema"
require_relative "generator_error"

module CodeGenerators
  module GeneratorInterface
    extend ActiveSupport::Concern

    class InterfaceError < StandardError; end

    class_methods do
      def generator_metadata(&block)
        dsl = CodeGenerators::MetadataDSL.new
        dsl.instance_eval(&block)
        self._metadata = dsl.to_h
      end

      # Declare the generator's configuration schema. Auto-generates
      # #validate_config and exposes a machine-readable field catalog. See
      # CodeGenerators::ConfigSchema.
      def config_schema(&block)
        prefix = generator_kind == :element_type ? "flowchart_elements" : "flowchart_actions"
        schema = CodeGenerators::ConfigSchema.new(action_name: generator_name, i18n_prefix: prefix)
        schema.instance_eval(&block)
        self._config_schema = schema
      end

      # Machine-readable catalog of declared config fields (for the builder UI
      # and documentation).
      def config_fields
        _config_schema ? _config_schema.catalog : []
      end

      def generator_name
        explicit_name = _metadata[:name].to_s
        return explicit_name unless explicit_name.empty?

        name.demodulize.sub(/Generator$/, "").underscore
      end

      def generator_kind
        if name.include?("ElementTypes::Process")
          :step_action
        elsif name.include?("ElementTypes")
          :element_type
        else
          :unknown
        end
      end

      def registered_names
        [generator_name]
      end

      def sample_input
        _config_schema ? _config_schema.sample_input : {}
      end
    end

    included do
      class_attribute :_metadata, default: {}
      class_attribute :_config_schema, default: nil
    end

    def initialize(element, context)
      @element = element
      @context = context
    end

    def generate_step_method
      body = generate_body
      return nil unless body

      parsed = Prism.parse(body.to_s)
      unless parsed.success?
        raise CodeGenerators::GeneratorError,
          I18n.t("maint_core.flowcharts.generator_error", action: self.class.generator_name)
      end

      method = <<~RUBY.chomp
        def #{derive_step_name}(ctx, **)
        #{body.indent(2)}
        end
      RUBY
      CodeGenerators::SourceFormatter.call(method, max_width: CodeGenerators::SourceFormatter::STEP_WIDTH)
    end

    def generate_body
      raise InterfaceError, "#{self.class.name} must implement #generate_body"
    end

    # When a config_schema is declared, validation is derived from it. A
    # subclass may still override #validate_config for fully bespoke rules.
    def validate_config(config)
      schema = self.class._config_schema
      raise InterfaceError, "#{self.class.name} must implement #validate_config" if schema.nil?

      schema.validate_config(config, self)
    end

    def dependencies
      []
    end

    private

    # Method names generated from user-supplied labels MUST be:
    #   - non-empty
    #   - non-reserved-Ruby-word (otherwise `def end(...)` is a SyntaxError)
    #   - not starting with a digit
    # When the label parameterizes to a problematic value we fall back to
    # the generator's stable name (e.g. `decision`, `api_call`).
    def derive_step_name
      label = @element.is_a?(Hash) ? (@element["label"] || @element["name"]) : nil
      candidate = label.to_s.parameterize(separator: "_") if label.present?
      candidate = candidate.to_s.gsub(/\A\d+/, "step_\\0")
      if candidate.empty?
        self.class.generator_name
      elsif Shared::IdentifierSanitizer::RUBY_RESERVED.include?(candidate)
        "#{candidate}_step"
      else
        candidate
      end
    end
  end
end
