# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module Utility
        class TemplateRenderGenerator < BaseGenerator
          OUTPUT_FORMATS = FlowchartRuntime::Template::OUTPUT_FORMATS

          generator_metadata do
            description "Renders a Liquid template over the run ctx (plus optional variables) and stores " \
                        "the string on resultVar (default rendered). Use this to compose a receipt, SMS, " \
                        "or HTML snippet from submit data; use i18n_translate for a catalog key, and a " \
                        "template field on send_email or generate_document when that action interpolates " \
                        "one string itself. {{ name }} reads ctx[:name]. outputFormat html escapes " \
                        "interpolated values. strictVariables fails as template_render.failed when a " \
                        "referenced name is missing; trimWhitespace strips the result."
            category :utility
            version "1.5.0"
            presentation icon: "M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z",
                         color: "pink", single_use: false, privileged: false
          end

          config_schema do
            literal :template, required: true, example: "Hello {{ name }}", multiline: true, placeholder: true,
                    description: "Liquid template body, such as Hello {{ name }} or Order {{ model.number }}. " \
                                 "Required. Ctx keys are already in scope; do not wrap in extra quotes."
            mapping :variables, key: :literal, value: :literal, default: [],
                    description: "Extra bindings merged over ctx. Each key is a Liquid name (name); each " \
                                 "value is a ctx path (person) or a literal. Overrides a same-named ctx key."
            flag :strictVariables, default: false,
                 description: "When true, fail the step as template_render.failed if the template names a " \
                              "missing variable. Default false (missing names render empty)."
            enum :outputFormat, OUTPUT_FORMATS, default: "text",
                 description: "text (default) keeps interpolated values as-is. html HTML-escapes them " \
                              "before insert, for a snippet you later put in send_email."
            flag :trimWhitespace, default: false, group: :advanced,
                 description: "When true, strip leading and trailing whitespace from the rendered string. " \
                              "Default false."
            output :resultVar, default: "rendered",
                   description: "Ctx variable that receives the rendered string. Default rendered. Point " \
                                "send_email body at this name when you compose HTML first."
          end

          def generate_body
            attempt('"template_render.failed"', FlowchartRuntime::Template::Error) do
              [
                assign(:resultVar, "FlowchartRuntime::Template.interpolate(ctx, #{interpolate_args})"),
                "true"
              ]
            end
          end

          private

          def interpolate_args
            [
              read(:template),
              ("variables: #{variables_hash}" unless variables_hash == "{}"),
              ("strict_variables: #{read(:strictVariables)}" if value(:strictVariables)),
              ("output_format: #{read(:outputFormat)}" unless value(:outputFormat).to_s == "text"),
              ("trim_whitespace: #{read(:trimWhitespace)}" if value(:trimWhitespace))
            ].compact.join(", ")
          end

          def variables_hash
            pairs = mapping_rows(:variables).filter_map do |row|
              next unless row.is_a?(Hash)

              key = row["key"] || row[:key]
              next if key.to_s.empty?

              "#{key.to_s.inspect} => #{argument_expression(row['value'] || row[:value])}"
            end
            "{#{pairs.join(', ')}}"
          end

          def mapping_rows(name)
            raw = value(name)
            case raw
            when Hash then raw.map { |key, val| { "key" => key.to_s, "value" => val } }
            when Array then raw
            else []
            end
          end

          def argument_expression(raw)
            return "nil" if raw.nil? || raw.to_s.strip.empty?
            return raw.inspect if raw == true || raw == false || raw.is_a?(Numeric)

            src = raw.to_s.strip
            return input_path(src.delete_prefix("ctx.")) if src.start_with?("ctx.")
            return src if src.match?(/\Actx\[:[a-zA-Z_][a-zA-Z0-9_]*\]\z/)
            return input_path(src) if src.match?(/\A[A-Za-z_][A-Za-z0-9_]*\z/)

            src.inspect
          end

          def input_path(path)
            root, *rest = path.to_s.split(".", -1)
            return "nil" if root.to_s.empty?
            return "ctx[:#{root}]" if rest.empty? && safe_ident?(root)

            keys = rest.map { |segment| segment.match?(/\A\d+\z/) ? segment : ":#{segment}" }.join(", ")
            "FlowchartRuntime::Step.dig(ctx[:#{root}], #{keys})"
          end
        end
      end
    end
  end
end
