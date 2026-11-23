# frozen_string_literal: true

require "liquid"
require "erb"

module FlowchartRuntime
  # FlowchartRuntime::Template
  #
  # Thin wrapper around Liquid for flowchart template rendering.
  module Template
    class Error < StandardError; end

    ENGINES = %i[liquid].freeze
    OUTPUT_FORMATS = %w[text html].freeze

    module_function

    # @param source            [String]
    # @param variables         [Hash]
    # @param engine            [Symbol, String] :liquid
    # @param strict_variables  [Boolean] Liquid-only; undefined vars raise when true
    # @param output_format     [String] text (default) or html (escapes interpolated values)
    # @param trim_whitespace   [Boolean] strip leading/trailing whitespace from the result
    # @return [String]
    # @raise  [FlowchartRuntime::Template::Error]
    # Merge run ctx with explicit template variables so format_string merges
    # that only named {{placeholders}} still resolve from ctx keys.
    def interpolate(ctx, source, variables: {}, strict_variables: false, output_format: "text",
                    trim_whitespace: false)
      bindings = {}
      ctx.to_h.each do |key, value|
        name = key.to_s
        next if name.start_with?("_")

        bindings[name] = value
      end
      normalize_variables(variables).each { |key, value| bindings[key] = value }
      render(source, bindings, engine: :liquid, strict_variables: strict_variables,
             output_format: output_format, trim_whitespace: trim_whitespace)
    end

    def render(source, variables = {}, engine: :liquid, strict_variables: false, output_format: "text",
               trim_whitespace: false)
      eng = normalize_engine(engine)
      raise Error, "unsupported engine" unless ENGINES.include?(eng)
      raise Error, "variables must be a hash" unless variables.is_a?(Hash)

      format_name = output_format.to_s
      format_name = "text" unless OUTPUT_FORMATS.include?(format_name)
      vars = normalize_variables(variables)
      vars = escape_html_values(vars) if format_name == "html"

      result = render_liquid(source, vars, strict_variables: strict_variables)
      result = result.to_s.strip if trim_whitespace
      result
    rescue Liquid::Error => e
      raise Error, e.message
    end

    def normalize_engine(engine)
      case engine.to_s.downcase
      when "liquid" then :liquid
      else engine.to_s.downcase.to_sym
      end
    end

    def normalize_variables(variables)
      variables.each_with_object({}) do |(key, value), hash|
        hash[key.to_s] = value
      end
    end

    def render_liquid(source, variables, strict_variables:)
      template = Liquid::Template.parse(source.to_s)
      return template.render!(variables, strict_variables: true) if strict_variables

      template.render(variables)
    end

    def escape_html_values(value)
      case value
      when Hash
        value.each_with_object({}) { |(key, item), memo| memo[key] = escape_html_values(item) }
      when Array
        value.map { |item| escape_html_values(item) }
      when String
        ERB::Util.html_escape(value).to_s
      when Numeric, TrueClass, FalseClass, NilClass
        value
      else
        ERB::Util.html_escape(value.to_s).to_s
      end
    end
    private_class_method :escape_html_values
  end
end
