# frozen_string_literal: true

module CodeGenerators
  class SourceAssembler
    def initialize(params = {}, source: nil, **attributes)
      params = params.merge(attributes)
      @source = source
      @kind = params[:kind]&.to_s || "step_action"
      @category = params[:category]&.to_s || "uncategorized"
      @file_name = params[:file_name].to_s
      @description = params[:description].to_s
      @version = params[:version].presence || "1.0.0"
      @registered_names = parse_keys(params[:registered_names])
      @methods_body = params[:methods_body].to_s
    end

    # With an on-disk source (edit) only the class body is replaced, so the
    # body is the single source of truth for metadata and declarations.
    def assemble
      return SourceDocument.new(@source).with_body(@methods_body) if @source

      [
        "# frozen_string_literal: true",
        "",
        module_open,
        class_body.indent(module_depth * 2),
        module_close
      ].join("\n") + "\n"
    end

    def class_name
      base = @file_name.to_s.underscore
      base = "#{base}_generator" unless base.end_with?("_generator")
      base.camelize
    end

    private

    def parse_keys(value)
      return [] if value.blank?

      if value.is_a?(String)
        value.split(",").map(&:strip).reject(&:blank?).map { |k| k.delete_prefix(":") }
      else
        Array(value).map(&:to_s).reject(&:blank?).map { |k| k.delete_prefix(":") }
      end
    end

    def element_type?
      @kind == "element_type"
    end

    def module_nesting
      if element_type?
        type_name = @file_name.to_s.underscore.sub(/_generator$/, "").camelize
        ["CodeGenerators", "ElementTypes", type_name]
      else
        cat_module = @category.to_s.camelize
        ["CodeGenerators", "ElementTypes", "Process", cat_module]
      end
    end

    def module_depth
      module_nesting.size
    end

    def module_open
      module_nesting.map.with_index do |mod, i|
        "#{"  " * i}module #{mod}"
      end.join("\n")
    end

    def module_close
      module_nesting.size.times.map do |i|
        "#{"  " * (module_nesting.size - 1 - i)}end"
      end.join("\n")
    end

    def class_body
      parts = []
      parts << "class #{class_name} < CodeGenerators::BaseGenerator"

      # registered_names override
      if @registered_names.any?
        names_array = @registered_names.map(&:inspect).join(", ")
        parts << ""
        parts << "  def self.registered_names"
        parts << "    [#{names_array}]"
        parts << "  end"
      end

      # metadata block
      parts << ""
      parts << "  generator_metadata do"
      parts << "    description #{@description.inspect}"
      parts << "    category    #{@category.underscore.to_sym.inspect}"
      parts << "    version     #{@version.inspect}"
      parts << "  end"

      # methods body
      if @methods_body.present?
        parts << ""
        parts << @methods_body.gsub("\r\n", "\n").indent(2)
      end

      parts << "end"
      parts.join("\n")
    end
  end
end
